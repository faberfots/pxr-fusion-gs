extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(0.2).timeout;await RenderingServer.frame_post_draw
func ready(viewer:GaussianSplattingViewer)->bool:
	for i in range(240):
		await process_frame
		if viewer.placement_active and viewer.get_placement_state().ready:return true
	return false
func button(point:Vector2,pressed:bool)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	var ui=scene.get_node("ProductionUI")
	var path:=Checks.fixture("user://route-model.ply",3)
	ui.file_dialog.file_selected.emit(path)
	check(viewer.placement_active and await ready(viewer),"the normal file picker enters placement mode for PLY models")
	await settle()
	check(not ui.transform_controls.toolbar.visible,"the transform toolbar yields pointer ownership to placement")
	var files:Control=scene.get_node("SceneManagerPanel").get_node("%CompositionFiles")
	check(files.get_node("%Save").disabled,"Scene Navigator cannot save an unfinished placement")
	var dock:GSCommandDock=ui.get_node("%MainControls")
	dock.set_expanded(false);dock.position=Vector2(300,100);dock.save_layout();await settle()
	var toggle:Button=dock.get_node("%Toggle")
	var point:Vector2=toggle.get_global_transform_with_canvas()*(toggle.size*0.5)
	var start:=dock.position
	button(point,true)
	var motion:=InputEventMouseMotion.new();motion.position=point+Vector2(-80,60);motion.relative=Vector2(-80,60);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	button(motion.position,false);await settle()
	check(dock.position.distance_to(start+Vector2(-80,60))<1 and viewer.placement_active and not viewer._placement.model.visible,"dragging the main control during placement moves UI without dropping the model")
	ui.get_node("%PlacementHUD").get_node("%Original").pressed.emit();await settle()
	check(not viewer.placement_active and viewer.total_splats_to_load==3,"Keep original retains the established import workflow")
	var binary:="user://route-model.gsres"
	check(PlyConverter.convert_ply_to_gsres(Checks.fixture("user://binary-source.ply",2),binary)==OK,"binary GSRES fixture is valid")
	await ui._on_files_dropped(PackedStringArray([binary]))
	check(viewer.placement_active and await ready(viewer),"dropped GSRES models use the same placement flow")
	ui.get_node("%PlacementHUD").get_node("%Cancel").pressed.emit();await settle()
	check(not viewer.placement_active and viewer.total_splats_to_load==3,"the authored Cancel control preserves existing models")
	ui._rebuild_recent_files_list()
	var recent:Button
	for child in ui.recent_files_list.get_children():
		if child is Button and child.tooltip_text==path:recent=child
	check(recent!=null,"the original model remains available in recent files")
	if recent:
		recent.pressed.emit()
		check(viewer.placement_active and await ready(viewer),"recent PLY imports also enter placement")
		viewer.confirm_model_placement(true)
	var document:="user://routes-combined.pxrscene"
	check(await viewer.save_composition(document)==OK,"confirmed imports can save a combined scene")
	ui.file_dialog.file_selected.emit(document)
	while viewer.composition_busy:await process_frame
	check(not viewer.placement_active and viewer.total_splats_to_load==12,"unchecked Import adds .pxrscene in its saved layout without entering model placement")
	await ui._on_files_dropped(PackedStringArray([document]))
	check(not viewer.placement_active and viewer.total_splats_to_load==18,"dropped .pxrscene files use the same additive Import choice")
	viewer.begin_model_placement(path)
	check(await ready(viewer),"clear fixture is fully pending")
	ui._on_clear_scene_pressed();await settle()
	check(not viewer.placement_active and viewer.total_splats_to_load==0 and viewer.get_model_snapshot().is_empty(),"Clear cancels pending placement and clears the owned scene")
	scene.free();await process_frame
	print("PLACEMENT ROUTES COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
