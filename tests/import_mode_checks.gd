extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func ready(viewer:GaussianSplattingViewer)->void:
	while viewer.is_loading():await process_frame
	for i in range(3):await process_frame
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");var toggle:CheckButton=ui.get_node("%ClearBeforeImport")
	var path:=Checks.fixture("user://import-source.ply",3)
	var original:=viewer.load_new_splat_from_path(path);await ready(viewer)
	original.position=Vector3(2,3,4);original.rotation=Vector3(0.1,0.2,0.3);original.scale=Vector3(1,2,3)
	var pose:=original.global_transform
	check(not toggle.button_pressed,"Clear scene before importing is unchecked by default")
	await ui._import_interactive(path);await ready(viewer)
	check(viewer.placement_active and viewer.total_splats_to_load==6 and original.global_transform.is_equal_approx(pose),"unchecked model imports append and preserve existing XYZ transforms")
	viewer.confirm_model_placement(true)
	var saved:="user://import-combined.pxrscene";check(await viewer.save_composition(saved)==OK,"combined fixture saves exact authored transforms")
	var camera:=viewer.get_camera().global_transform
	await ui._import_interactive(saved);await ready(viewer)
	check(viewer.total_splats_to_load==12 and is_instance_valid(original) and original.global_transform.is_equal_approx(pose) and viewer.get_camera().global_transform.is_equal_approx(camera),"unchecked composed-scene import adds models without changing existing models or camera")
	var ids:Dictionary={};var duplicates:=false;var exact:=0
	for record in viewer.get_model_snapshot():
		if ids.has(record.model_id):duplicates=true
		ids[record.model_id]=true
		for resident in viewer._records.values():
			var node:GaussianSplat=resident.node.get_ref()
			if node.model_id==record.model_id and node.global_transform.is_equal_approx(pose):exact+=1
	check(not duplicates and exact==2,"adding the same scene remaps identities and preserves the imported transform exactly")
	toggle.button_pressed=true
	await ui._import_interactive("user://missing-import.ply")
	check(viewer.total_splats_to_load==12 and is_instance_valid(original) and toggle.button_pressed,"invalid file admission preserves existing models and the explicit import choice")
	ui._on_file_dialog_canceled()
	check(viewer.total_splats_to_load==12,"cancelling the file picker never clears the scene")
	await ui._import_interactive(saved);await ready(viewer)
	check(viewer.total_splats_to_load==6 and not toggle.button_pressed,"checked composed-scene import replaces and restores the safe default afterward")
	toggle.button_pressed=true
	await ui._import_interactive(path);await ready(viewer)
	check(viewer.placement_active and viewer.total_splats_to_load==3 and not toggle.button_pressed,"checked model import clears once and retains object placement")
	viewer.confirm_model_placement(true)
	var before:=viewer.get_model_snapshot();var bad:="user://bad-import.pxrscene"
	var broken:=Checks.fixture("user://broken-import.ply",3)
	var invalid_payload:=FileAccess.get_file_as_string(broken).replace("0 0 0 -3","nan 0 0 -3")
	var payload:=FileAccess.open(broken,FileAccess.WRITE);payload.store_string(invalid_payload);payload.close()
	var broken_document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(saved))
	broken_document.models.back().source=ProjectSettings.globalize_path(broken);broken_document.models.back().relative_source="broken-import.ply"
	broken_document.models.back().bytes=FileAccess.get_file_as_bytes(broken).size();broken_document.models.back().sha256=FileAccess.get_sha256(broken)
	var output:=FileAccess.open("user://decode-failed-import.pxrscene",FileAccess.WRITE);output.store_string(JSON.stringify(broken_document));output.close()
	check(await viewer.add_composition("user://decode-failed-import.pxrscene")!=OK and viewer.get_model_snapshot()==before,"decoder failure rolls back only the added models and preserves resident identities, transforms and selection")
	var file:=FileAccess.open(bad,FileAccess.WRITE);file.store_string("{}");file.close()
	check(await viewer.add_composition(bad)!=OK and viewer.get_model_snapshot()==before,"invalid added composition is rejected without mutating existing content")
	scene.get_node("SceneManagerPanel").get_node("%CompositionFiles").get_node("%Open").pressed.emit()
	check(toggle.button_pressed and viewer.show_load_zone,"Scene navigator Open retains its explicit replacement intent in the shared import panel")
	ui._on_load_button_pressed()
	check(not toggle.button_pressed,"main Import opens with the safe unchecked default")
	await RenderingServer.frame_post_draw
	ui.viewer.show_load_zone=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://import-options.png")
	scene.free();await process_frame
	print("IMPORT MODES COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
