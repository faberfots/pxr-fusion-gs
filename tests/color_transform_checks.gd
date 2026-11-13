extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle(seconds:float=0.1)->void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	scene.get_node("DemoUIController").show_ui=false
	root.add_child(scene)
	scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI")
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://controls-a.ply",1))
	var front:=viewer.load_new_splat_from_path(Checks.fixture("user://controls-b.ply",1))
	front.position.z=0.5
	for i in range(60):await process_frame
	while viewer.is_loading():await process_frame
	check(model.is_loaded and front.is_loaded,"both full models are loaded into the shared atlas")
	viewer.camera_controller.position_camera_at(Vector3(0,0,2),Vector3.ZERO)
	await settle(1.3)
	var atlas:RID=viewer.rasterizer.descriptors.splats.rid
	var pose:=model.global_transform
	viewer.get_camera().fov=63
	viewer.rasterizer.model_scale[0]=1.3
	viewer.rasterizer.should_enable_heatmap[0]=0.25
	ui.color_panel.show_panel()
	check(ui.color_panel.apply_profile("Warm daylight"),"color preset applies through the visible panel")
	await settle()
	check(is_equal_approx(viewer.get_camera().fov,63),"color edits preserve the user's current camera field of view")
	check(is_equal_approx(viewer.rasterizer.model_scale[0],1.3) and is_equal_approx(viewer.rasterizer.should_enable_heatmap[0],0.25),"color edits preserve existing live renderer controls")
	viewer.rasterizer.model_scale[0]=1.0;viewer.rasterizer.should_enable_heatmap[0]=0.0
	check(viewer.rasterizer.descriptors.splats.rid==atlas and model.global_transform==pose and viewer.total_splats_to_load==2,"color adjustments preserve atlas residency and model transforms")
	var grade:=GSColorSettings.snapshot(viewer.config)
	ui.color_panel.compare.button_pressed=true
	check(viewer.rendered_material.get_shader_parameter("temperature")==0.0 and GSColorSettings.snapshot(viewer.config)==grade,"original comparison leaves the authoritative grade unchanged")
	ui.color_panel.compare.button_pressed=false
	check(is_equal_approx(viewer.rendered_material.get_shader_parameter("temperature"),0.3),"ending comparison restores the chosen grade")
	var path:="user://color-persistence-test.cfg"
	check(GSColorSettings.save_preferences(viewer.config,path)==OK,"color preferences save without project settings mutation")
	var reopened:=GaussianSplattingConfig.create_default()
	check(GSColorSettings.load_preferences(reopened,path) and GSColorSettings.snapshot(reopened)==grade,"reopened preferences restore all color values")
	for quality in [GaussianSplattingConfig.QualityPreset.LOW,GaussianSplattingConfig.QualityPreset.HIGH]:reopened.apply_preset(quality)
	check(GSColorSettings.snapshot(reopened)==grade,"quality changes preserve the independently chosen color grade")
	var duplicate:=reopened.duplicate(true) as GaussianSplattingConfig
	check(duplicate.current_preset==reopened.current_preset and duplicate.color_settings_edited,"configuration snapshots retain quality and color ownership")
	check(not GSColorSettings.apply(viewer.config,{"post_exposure":NAN}) and GSColorSettings.snapshot(viewer.config)==grade,"invalid color input cannot corrupt the live configuration")
	ui.color_panel.apply_profile("Natural")
	ui.color_panel.hide_panel()
	viewer.select_model_id("")
	await settle()
	var pixel:=Vector2(root.size)*0.5
	viewer._selection_pick_request=2001
	viewer.rasterizer.request_pick(pixel,2001)
	await settle(0.3)
	check(viewer.get_selected_model()==front,"pixel picking selects the visible foreground model despite overlapping bounds")
	viewer.select_model_id("")
	var click_point:=viewer.get_camera().unproject_position(viewer.get_model_world_bounds(front).get_center())
	var click_motion:=InputEventMouseMotion.new();click_motion.position=click_point;root.push_input(click_motion,true)
	await process_frame
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=click_point;click.pressed=true;root.push_input(click,true)
	click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=click_point;root.push_input(click,true)
	await settle(0.3)
	check(viewer.get_selected_model()==front,"left-click selection works with stretched viewport input coordinates")
	var picks:Array[int]=[]
	viewer.rasterizer.model_pick_completed.connect(func(id,_instance,_point):picks.append(id))
	viewer.rasterizer.request_pick(pixel,3001)
	viewer.rasterizer.cancel_pick()
	await settle(0.2)
	viewer.rasterizer.request_pick(pixel,3002)
	await settle(0.3)
	check(not picks.has(3001) and picks.has(3002),"cancelled pick cannot select or focus a stale model over the next request")
	var panel:SceneManagerPanel=scene.get_node("SceneManagerPanel")
	check(panel.selected_node==front and panel.pos_x.editable,"direct picking synchronizes existing Scene Manager controls")
	var gizmo:GSModelTransformControls=ui.transform_controls
	gizmo.set_mode(GSModelTransformControls.Mode.MOVE)
	await settle()
	var original:=front.global_transform
	for axis in range(3):
		var start:Vector2=gizmo._ends[axis]
		gizmo.begin_drag(axis,start);gizmo.update_drag(start+(gizmo._ends[axis]-gizmo._center).normalized()*25);gizmo.finish_drag(false)
		check(not front.global_position.is_equal_approx(original.origin),"axis %s movement updates the existing Node3D" % axis)
		front.global_transform=original;await settle()
	for axis in range(3):
		gizmo.set_mode(GSModelTransformControls.Mode.ROTATE);await settle()
		var start:=gizmo._center+Vector2(50,0)
		gizmo.begin_drag(axis,start);gizmo.update_drag(gizmo._center+Vector2(0,50));gizmo.finish_drag(false)
		check(not front.global_basis.is_equal_approx(original.basis),"axis %s rotation updates the existing Node3D" % axis)
		front.global_transform=original;await settle()
	gizmo.set_mode(GSModelTransformControls.Mode.SCALE);await settle()
	for axis in [-1,0,1,2]:
		gizmo.begin_drag(axis,gizmo._center);gizmo.update_drag(gizmo._center+Vector2(30,-15));gizmo.finish_drag(false)
		check(not front.scale.is_equal_approx(Vector3.ONE),"scale handle %s supports uniform or individual XYZ scaling" % axis)
		front.global_transform=original;await settle()
	gizmo.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	gizmo.begin_drag(-1,gizmo._center);gizmo.update_drag(gizmo._center+Vector2(20,10));gizmo.finish_drag(true)
	check(front.global_transform.is_equal_approx(original) and not viewer.camera_controller.is_movement_blocked(),"cancel restores the exact transform and releases only the manipulation blocker")
	check(model.global_transform.is_equal_approx(pose),"all edits preserve the other model's independent transform")
	# Exercise input routing through the viewport, including the camera's handlers.
	gizmo.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	var handle:Vector2=gizmo._ends[0]
	var motion:=InputEventMouseMotion.new();motion.position=handle;root.push_input(motion,true)
	await process_frame
	var camera_pose:=viewer.get_camera().global_transform
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=handle;root.push_input(press,true)
	check(gizmo.dragging,"left mouse press on a handle starts direct manipulation")
	motion=InputEventMouseMotion.new();motion.position=handle+Vector2(25,0);motion.relative=Vector2(25,0);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=motion.position;root.push_input(release,true)
	await settle()
	check(not gizmo.dragging and not front.global_transform.is_equal_approx(original),"mouse drag and release commit the model transform")
	check(viewer.get_camera().global_transform.is_equal_approx(camera_pose),"direct model manipulation cannot orbit or move the camera")
	front.global_transform=original
	viewer.rasterizer.basis_override=Basis(Vector3.UP,0.4);await settle()
	gizmo.begin_drag(0,gizmo._ends[0]);gizmo.update_drag(gizmo._ends[0]+Vector2(20,0));gizmo.finish_drag(true)
	check(front.global_transform.is_equal_approx(original),"manipulation and cancellation respect the renderer basis override")
	viewer.rasterizer.basis_override=Basis.IDENTITY
	ui.color_panel.show_panel();await settle()
	root.get_texture().get_image().save_png("user://color-controls-review.png")
	print("UI COORDINATES window ",root.size," visible ",root.get_visible_rect()," panel ",ui.color_panel.get_global_rect()," gizmo ",gizmo._center," canvas ",gizmo.get_global_transform_with_canvas()," raster ",viewer.rasterizer._texture_size)
	check(ui.color_panel.position.y>=0 and ui.color_panel.get_global_rect().end.y<=root.get_visible_rect().size.y,"color panel stays within the viewport")
	ui.color_panel.hide_panel()
	gizmo.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	root.get_texture().get_image().save_png("user://transform-controls-review.png")
	scene.free();await process_frame
	print("COLOR TRANSFORM COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
