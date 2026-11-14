extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	for i in range(3):await physics_frame
	await create_timer(0.25).timeout;await RenderingServer.frame_post_draw
func move(point:Vector2)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
func click(point:Vector2)->void:
	move(point)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func wait_ready(viewer:GaussianSplattingViewer)->bool:
	for i in range(240):
		await process_frame
		if viewer.placement_active and viewer.get_placement_state().ready:return true
	return false
func wait_placed(viewer:GaussianSplattingViewer)->bool:
	for i in range(240):
		await process_frame
		if not viewer.placement_active:return true
	print("PLACEMENT TIMEOUT ",viewer.get_placement_state())
	return false
func contact(viewer:GaussianSplattingViewer,node:GaussianSplat)->Vector3:
	var bounds:=viewer.get_model_world_bounds(node);var base:=bounds.get_center();base.y=bounds.position.y;return base
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI")
	ui.get_node("%MainControls").set_expanded(false)
	var lab:Node3D=load("res://tests/scenes/placement_lab.tscn").instantiate();root.add_child(lab)
	var source:=viewer.load_new_splat_from_path(Checks.fixture("user://placement-surface.ply",1))
	source.position=Vector3(-1,1.4,0);source.scale=Vector3.ONE*5
	while viewer.is_loading():await process_frame
	viewer.camera_controller.position_camera_at(Vector3(0,3,5),Vector3(0,0.6,0))
	await settle()
	var source_pose:=source.global_transform
	var source_id:=source.model_id
	var camera_pose:=viewer.get_camera().global_transform
	var surface_point:=Vector3(-1,1.4,0)
	var pixel:=viewer.get_camera().unproject_position(surface_point)
	var path:=Checks.fixture("user://placement-model.ply",3)
	check(viewer.begin_model_placement(path,pixel)==OK,"an individual import begins one viewer-owned placement transaction")
	var pending:GaussianSplat=viewer._placement.model
	check(await wait_ready(viewer),"the complete model loads before placement can commit")
	await settle()
	for i in range(180):
		if viewer.get_placement_state().surface=="GS surface":break
		await process_frame
	var state:=viewer.get_placement_state()
	print("GS PLACEMENT TARGET ",state)
	check(state.valid and state.surface=="GS surface" and state.target.distance_to(surface_point)<0.12,"actual GPU picking locates the existing GS surface above the reference floor")
	check(pending.is_loaded and not pending.visible and viewer.total_splats_to_load==4,"pending import is fully resident and hidden from its own placement picks")
	var hud:Control=ui.get_node("%PlacementHUD")
	check(not GSUiScale.screen_rect(hud.get_node("%Panel")).has_point(viewer.get_camera().unproject_position(state.target)),"placement controls keep the chosen marker visible and clickable")
	check(source.global_transform.is_equal_approx(source_pose) and viewer.get_camera().global_transform.is_equal_approx(camera_pose),"placement preview preserves the existing model and camera view")
	check(await viewer.save_composition("user://pending-placement.pxrscene")==ERR_BUSY,"saving cannot capture an unfinished hidden placement")
	root.get_texture().get_image().save_png("user://placement-preview.png")
	click(pixel)
	check(await wait_placed(viewer),"left click confirms placement after resolving its current surface")
	check(pending.visible and contact(viewer,pending).distance_to(surface_point)<0.12,"base-centre anchor lands on the chosen GS point")
	check(pending.global_basis.is_equal_approx(Basis.IDENTITY) and viewer.get_selected_model()==pending,"placement preserves orientation/scale and activates the existing transform controls")
	var placed_pose:=pending.global_transform;var placed_id:=pending.model_id
	check(await viewer.save_composition("user://placed-scene.pxrscene")==OK,"confirmed placement participates in the existing scene document")
	pending.position.y+=2
	check(await viewer.import_path("user://placed-scene.pxrscene")==OK,"saved scene reopening restores rather than re-enters placement mode")
	await settle()
	check(not viewer.placement_active and viewer.get_selected_model().global_transform.is_equal_approx(placed_pose) and viewer.selected_model_id==placed_id,"composition round trip preserves the exact placed model matrix")
	var platform_point:=Vector3(1.5,0.95,0)
	viewer.set_scene_mode(GaussianSplattingViewer.SceneMode.ENVIRONMENT_MODE,false)
	pixel=viewer.get_camera().unproject_position(platform_point)
	check(viewer.begin_model_placement(Checks.fixture("user://platform-model.ply",1),pixel)==OK,"next model can target ordinary colliding scene geometry")
	check(await wait_ready(viewer),"platform model loads completely")
	viewer.set_placement_anchor(GSPlacementSession.Anchor.ORIGIN)
	await settle()
	state=viewer.get_placement_state();print("PLATFORM TARGET ",state)
	check(state.valid and state.surface=="Scene geometry" and state.target.distance_to(platform_point)<0.03,"physics hit selects the platform top rather than the lower floor")
	pending=viewer._placement.model
	ui.get_node("%PlacementHUD").get_node("%Place").pressed.emit()
	check(await wait_placed(viewer) and viewer.get_model_edit_transform(pending).origin.distance_to(platform_point)<0.03,"HUD confirmation retains the last scene cursor and honors the origin anchor")
	check(viewer.current_scene_mode==GaussianSplattingViewer.SceneMode.ENVIRONMENT_MODE,"appending a placed model preserves an explicitly chosen scene mode")
	viewer.select_model_id(source_id);source=viewer.get_selected_model()
	var below_point:=Vector3(-1,-0.3,0);source.global_position=below_point
	await settle();pixel=viewer.get_camera().unproject_position(below_point)
	check(viewer.begin_model_placement(path,pixel)==OK and await wait_ready(viewer),"a visible scan below the reference grid remains a placement target")
	await settle()
	for i in range(180):
		if viewer.get_placement_state().surface=="GS surface":break
		await process_frame
	state=viewer.get_placement_state()
	check(state.surface=="GS surface" and state.target.distance_to(below_point)<0.12,"the non-occluding reference grid cannot override a visible GS hit")
	pending=viewer._placement.model;click(pixel)
	check(await wait_placed(viewer) and contact(viewer,pending).distance_to(below_point)<0.12,"confirmed placement follows the scanned surface below the guide floor")
	var population:=viewer.total_splats_to_load;var records:=viewer.get_model_snapshot().size()
	check(viewer.begin_model_placement(Checks.fixture("user://cancel-placement.ply",40000),pixel)==OK,"a loading placement can be cancelled")
	viewer.cancel_model_placement();await settle()
	check(not viewer.placement_active and not viewer.is_loading() and viewer.total_splats_to_load==population and viewer.get_model_snapshot().size()==records,"cancelling a worker releases only the pending model and its atlas allocation")
	for model in viewer.managed_splats:model.hide()
	viewer.rasterizer.basis_override=Basis(Vector3.UP,0.45);viewer.rasterizer.model_scale[0]=1.3
	var floor_point:=Vector3(-2,0,-1)
	pixel=viewer.get_camera().unproject_position(floor_point)
	check(viewer.begin_model_placement(path,pixel)==OK,"placement accepts the existing renderer basis and scale overrides")
	check(await wait_ready(viewer),"basis-override model loads")
	viewer.set_placement_anchor(GSPlacementSession.Anchor.ORIGIN);await settle()
	pending=viewer._placement.model
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true;root.push_input(enter,true)
	check(await wait_placed(viewer) and viewer.get_model_edit_transform(pending).origin.distance_to(floor_point)<0.03,"Enter confirms floor placement in rendered world coordinates under renderer overrides")
	check(pending.global_basis.is_equal_approx(Basis.IDENTITY),"renderer-aware placement retains the imported Node3D basis")
	check(viewer.begin_model_placement(path,pixel)==OK,"original-position import remains available")
	check(await wait_ready(viewer),"original-position model loads")
	var original:=viewer._placement.initial_node;pending=viewer._placement.model
	ui.get_node("%PlacementHUD").get_node("%Original").pressed.emit();await settle()
	check(not viewer.placement_active and pending.visible and pending.global_transform.is_equal_approx(original),"Keep original completes the import with its authored transform")
	check(viewer.begin_model_placement(path,pixel)==OK,"view-change cancellation begins a separate placement")
	check(await wait_ready(viewer),"view-change fixture loads")
	await settle();viewer.request_model_placement()
	viewer.camera_controller.position_camera_at(Vector3(0.4,3,5),Vector3(0,0.6,0))
	await settle()
	check(viewer.placement_active and not viewer._placement._confirm and not viewer._placement.model.visible,"changing the view invalidates an uncommitted confirmation instead of placing at a stale point")
	var upward:=Transform3D(Basis.IDENTITY,Vector3(0,3,5)).looking_at(Vector3(0,4,5),Vector3.FORWARD)
	viewer.camera_controller.set_camera_transform(upward)
	pixel=root.get_visible_rect().get_center();move(pixel);await settle();click(pixel);await settle()
	check(viewer.placement_active and not viewer.get_placement_state().valid and not viewer._placement.model.visible,"sky clicks without a valid surface keep the model pending")
	viewer.cancel_model_placement()
	viewer.camera_controller.position_camera_at(Vector3(0,3,5),Vector3(0,0.6,0))
	pixel=viewer.get_camera().unproject_position(floor_point)
	check(viewer.begin_model_placement(path,pixel)==OK,"Escape cancellation starts from a ready placement")
	check(await wait_ready(viewer),"Escape fixture loads")
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true)
	await settle();check(not viewer.placement_active,"Escape cancels without claiming unrelated camera controls")
	viewer.begin_model_placement(path,pixel)
	scene.free();lab.free()
	for i in range(5):await process_frame
	check(true,"viewer teardown cancels pending placement work without orphaned UI or GPU ownership")
	print("PLACEMENT CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
