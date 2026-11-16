extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(0.35).timeout;await RenderingServer.frame_post_draw
func document(path:String)->Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
func write(path:String,value:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value,"\t",true,true))
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI")
	viewer.position.x=0.37
	var source_a:=Checks.fixture("user://composition-a.ply",3)
	var source_b:=Checks.fixture("user://composition-b.ply",2)
	var a:=viewer.load_new_splat_from_path(source_a)
	var b:=viewer.load_new_splat_from_path(source_b)
	var c:=viewer.load_new_splat_from_path(source_a)
	while viewer.is_loading():await process_frame
	var models:=[a,b,c];var poses:Array[Transform3D]=[];var ids:Array[String]=[]
	for i in range(3):
		models[i].transform=Transform3D(Basis.from_euler(Vector3(0.11+i*0.1,0.31,-0.17)).scaled(Vector3(-0.8 if i==2 else 0.8,1.1+i*0.1,0.9)),Vector3(i*0.7-0.7,1,0.15*i))
		poses.append(models[i].global_transform);ids.append(models[i].model_id)
	b.hide();a.cast_gaussian_shadows=false;c.receive_gaussian_shadows=true
	viewer.select_model_ids([ids[0],ids[2]])
	ui.color_panel.apply_profile("Warm daylight")
	viewer.rasterizer.basis_override=Basis(Vector3.UP,0.17)
	viewer.config.default_model_scale=1.2;viewer.config.default_render_scale=0.75
	await settle()
	ui._on_camera_mode(true)
	viewer.camera_controller.position_camera_at(Vector3(4,3,7),Vector3(0,1,0))
	viewer.get_camera().fov=67
	await settle()
	var expected_view:=GSComposition.view(viewer)
	var path:="user://composition-test.pxrscene"
	check(await viewer.save_composition(path)==OK,"scene saves complete models without flattening or rewriting PLY data")
	var saved:=document(path)
	check(saved.models.size()==3 and saved.models[0].sha256.length()==64,"saved document contains all identities and source fingerprints")
	# Overwriting must atomically replace the document, not delete the old one first.
	check(await viewer.save_composition(path)==OK,"saving over an existing composition succeeds")
	for node in models:node.position=Vector3(8,5,4)
	ui.color_panel.apply_profile("Natural");ui._on_camera_mode(false);viewer.camera_controller.go_home()
	check(await viewer.import_path(path)==OK,"the standard import dispatcher recognizes .pxrscene")
	await settle()
	check(viewer.total_splats_to_load==8 and viewer.get_model_snapshot().size()==3,"reopen restores the exact population, including repeated instances of one source")
	for i in range(3):
		viewer.select_model_id(ids[i]);var node:=viewer.get_selected_model()
		check(node!=null and node.global_transform.is_equal_approx(poses[i]),"model %d retains its full world matrix, including nonuniform/reflected scale" % i)
		if not node:continue
		if i==1:check(not node.visible,"hidden models remain hidden after reopen")
		if i==0:check(not node.cast_gaussian_shadows,"model casting choice is preserved")
		if i==2:check(node.receive_gaussian_shadows,"model receiving choice is preserved")
	var actual_view:=GSComposition.view(viewer)
	for key in expected_view:
		if actual_view[key]!=expected_view[key]:print("VIEW DIFFERENCE ",key," expected ",expected_view[key]," actual ",actual_view[key])
	check(actual_view==expected_view,"camera mode/pose/lens, image grade and renderer settings round-trip exactly")
	viewer.select_model_ids(saved.selection)
	var original:=viewer.get_selected_model();var original_pose:=original.global_transform
	var bad:=saved.duplicate(true);bad.models[0].transform=[1,2]
	write("user://invalid-transform.pxrscene",bad)
	check(await viewer.open_composition("user://invalid-transform.pxrscene")!=OK and viewer.get_selected_model()==original,"malformed scene is rejected before changing live nodes")
	bad=saved.duplicate(true);bad.models[0].source="C:/missing-source.ply";bad.models[0].relative_source="missing-source.ply"
	write("user://missing-source.pxrscene",bad)
	check(await viewer.open_composition("user://missing-source.pxrscene")!=OK and original.global_transform.is_equal_approx(original_pose),"missing original leaves the current composition intact")
	var source:=FileAccess.open(source_b,FileAccess.READ_WRITE);source.seek_end();source.store_8(0);source.close()
	check(await viewer.open_composition(path)!=OK and viewer.total_splats_to_load==8,"changed source fingerprint is rejected before replacing the atlas")
	var unchanged_document:=FileAccess.get_sha256(path)
	check(await viewer.save_composition(path)!=OK and FileAccess.get_sha256(path)==unchanged_document,"save rejects a source changed since import rather than recording data different from the resident model")
	Checks.fixture(source_b,2)
	# A valid header/fingerprint with an invalid payload fails only during decoding.
	var broken:=Checks.fixture("user://composition-broken.ply",2)
	var text:=FileAccess.get_file_as_string(broken).replace("0 0 0 -3","nan 0 0 -3")
	var bytes:=text.to_utf8_buffer()
	var output:=FileAccess.open(broken,FileAccess.WRITE);output.store_buffer(bytes);output.close()
	bad=saved.duplicate(true)
	bad.models[1].source=ProjectSettings.globalize_path(broken);bad.models[1].relative_source="composition-broken.ply"
	bad.models[1].bytes=bytes.size();bad.models[1].sha256=FileAccess.get_sha256(broken)
	write("user://decode-failure.pxrscene",bad)
	# Remove an old source to prove rollback uses resident data, not source reloading.
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(source_b))==OK and not FileAccess.file_exists(source_b),"original source can be removed after completed file operations")
	check(await viewer.open_composition("user://decode-failure.pxrscene")!=OK,"a decoder failure rejects the incomplete composition")
	check(viewer.last_error.contains("previous composition was restored"),"decoder failure exercises resident checkpoint rollback after replacement began")
	check(viewer.get_selected_model()==original and original.global_transform.is_equal_approx(original_pose) and viewer.total_splats_to_load==8,"failed open restores original node identities, selection, transforms and resident atlas even with an old source missing")
	check(not viewer.composition_busy and not viewer.camera_controller.is_movement_blocked(),"scene operation releases only its own input blocker")
	var saved_hash:=FileAccess.get_sha256(path)
	var failed_save:=await viewer.save_composition(path)
	print("SAVE FAILURE CHECK result ",failed_save," source exists ",FileAccess.file_exists(source_b)," original hash ",saved_hash," after ",FileAccess.get_sha256(path))
	check(failed_save!=OK and FileAccess.get_sha256(path)==saved_hash,"failed save preserves the previous composition file byte-for-byte")
	Checks.fixture(source_b,2)
	var picker:FileDialog=ui.file_dialog
	check("*.pxrscene" in str(picker.filters),"the existing Import file picker exposes the .pxrscene extension")
	ui.get_node("%ClearBeforeImport").button_pressed=true
	picker.file_selected.emit(path)
	while viewer.composition_busy:await process_frame
	check(viewer.total_splats_to_load==8 and viewer.get_selected_model().model_id==saved.selection.back(),"checked Import picker restores a composition without duplicating models")
	ui.get_node("%ClearBeforeImport").button_pressed=true
	await ui._on_files_dropped(PackedStringArray([path]))
	check(viewer.total_splats_to_load==8,"checked drag-and-drop uses the same replacement scene dispatcher")
	ui._rebuild_recent_files_list()
	var recent:Button
	for child in ui.recent_files_list.get_children():
		if child is Button and child.tooltip_text==path:recent=child
	check(recent!=null,"opened compositions appear in the existing recent-files list")
	if recent:
		ui.get_node("%ClearBeforeImport").button_pressed=true
		recent.pressed.emit()
		while viewer.composition_busy:await process_frame
		check(viewer.total_splats_to_load==8,"recent-file button reopens a composition through the same dispatcher")
	ui._on_scene_manager_pressed();await settle()
	var files:Control=ui.scene_manager_panel.get_node("%CompositionFiles")
	var dialog:FileDialog=files.get_node("%SaveDialog");dialog.use_native_dialog=false
	files.get_node("%Save").pressed.emit();await process_frame
	check(viewer.camera_controller.is_movement_blocked(),"Save Scene dialog owns its independent camera blocker")
	dialog.hide();dialog.file_selected.emit("user://composition-ui-save")
	while viewer.composition_busy:await process_frame
	check(FileAccess.file_exists("user://composition-ui-save.pxrscene"),"authored Save Scene control adds the extension and saves the complete composition")
	ui.scene_manager_panel.hide_panel()
	# Existing PLY import remains append, never an implicit replace.
	check(await viewer.import_path(Checks.fixture("user://composition-append.ply",1))==OK,"PLY still imports through the same dispatcher")
	while viewer.is_loading():await process_frame
	check(viewer.total_splats_to_load==9,"ordinary import preserves the composed scene and appends its complete model")
	ui._on_scene_manager_pressed();await settle()
	root.get_texture().get_image().save_png("user://composition-ui.png")
	viewer._clear_scene_and_reset_atlas();await settle()
	check(await viewer.save_composition("user://empty-composition.pxrscene")==OK and await viewer.import_path("user://empty-composition.pxrscene")==OK and viewer.total_splats_to_load==0,"an empty saved composition restores the empty view without stale models")
	scene.free();await process_frame
	print("COMPOSITION CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
