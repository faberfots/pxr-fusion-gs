extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(0.25).timeout;await RenderingServer.frame_post_draw
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	root.add_child(scene)
	scene.get_node("DemoUIController").set_process(false)
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	var controller:=viewer.camera_controller
	var ui=scene.get_node("ProductionUI")
	var dock:GSCommandDock=ui.get_node("%MainControls")
	dock.set_expanded(true);dock.reset_layout()
	await settle()
	check(controller.get_camera().global_position.distance_to(Vector3(6,3.5,8))<0.01,"empty scene opens at the elevated authored home view")
	root.get_texture().get_image().save_png("user://studio-home.png")
	controller.position_camera_at(Vector3(0,-5,5),Vector3.ZERO)
	check(controller.get_camera().global_position.y>=controller.safety.radius,"external camera positioning obeys floor protection")
	controller.set_protection(false)
	controller.position_camera_at(Vector3(0,-2,5),Vector3.ZERO)
	check(controller.get_camera().global_position.y<0,"explicit unrestricted flight remains available")
	controller.set_protection(true)
	check(controller.get_camera().global_position.y>0,"reenabling protection immediately recovers above the floor")
	var wall:Node=load("res://tests/scenes/camera_collision_lab.tscn").instantiate();root.add_child(wall)
	for i in range(4):await physics_frame
	var previous:=Transform3D(Basis.IDENTITY,Vector3(0,1,4))
	var desired:=Transform3D(Basis.IDENTITY,Vector3(0,1,1))
	var resolved:=controller.constrain_pose(previous,desired)
	print("SWEEP WALL ",resolved.origin)
	check(resolved.origin.z>3.2,"camera volume sweep prevents high-speed travel through physical geometry")
	wall.free()
	ui._on_camera_mode(true)
	var orbit:=controller.get_camera() as OrbitCamera
	orbit.orbit_point=Vector3.ZERO;orbit.phi=PI*0.9;orbit._update_camera_from_spherical()
	check(orbit.global_position.y>=controller.safety.radius,"orbit camera uses the same floor protection owner")
	ui._on_camera_mode(false);controller.go_home()
	var a:=viewer.load_new_splat_from_path(Checks.fixture("user://studio-a.ply",1))
	var b:=viewer.load_new_splat_from_path(Checks.fixture("user://studio-b.ply",1))
	a.position.y=1;b.position=Vector3(1.5,1,0)
	for i in range(30):await process_frame
	while viewer.is_loading():await process_frame
	viewer.select_model_ids([a.model_id,b.model_id])
	check(viewer.get_selected_models().size()==2 and viewer.get_selected_model()==b,"multi-selection and active model share one viewer-owned registry")
	var tools:GSModelTransformControls=ui.transform_controls
	viewer.frame_models([])
	tools.set_mode(GSModelTransformControls.Mode.MOVE)
	await settle()
	var before_a:=a.global_transform;var before_b:=b.global_transform
	tools.begin_drag(-1,tools._center);tools.update_drag(tools._center+Vector2(35,15));tools.finish_drag(false)
	check(not a.global_transform.is_equal_approx(before_a) and not b.global_transform.is_equal_approx(before_b),"one group drag edits both selected Node3D transforms")
	check(viewer.undo_transform() and a.global_transform.is_equal_approx(before_a) and b.global_transform.is_equal_approx(before_b),"one undo transaction restores the complete selected group")
	check(viewer.undo_transform(true) and not a.global_transform.is_equal_approx(before_a),"group transform redo restores the committed edit")
	var cancel_a:=a.global_transform;var cancel_b:=b.global_transform
	tools.begin_drag(-1,tools._center);tools.update_drag(tools._center+Vector2(40,10))
	viewer.select_model_id(a.model_id)
	check(not tools.dragging and a.global_transform.is_equal_approx(cancel_a) and b.global_transform.is_equal_approx(cancel_b),"selection changes cancel the entire original drag group atomically")
	viewer.select_model_ids([a.model_id,b.model_id])
	dock.get_node("%ColorButton").pressed.emit()
	await settle()
	root.get_texture().get_image().save_png("user://studio-image.png")
	ui.color_panel.hide_panel()
	dock.get_node("%CameraButton").pressed.emit();await settle()
	root.get_texture().get_image().save_png("user://studio-camera.png")
	dock.get_node("%SettingsButton").pressed.emit();await settle()
	root.get_texture().get_image().save_png("user://studio-system.png")
	dock.get_node("%LightingButton").pressed.emit();await settle()
	root.get_texture().get_image().save_png("user://studio-light.png")
	ui.get_node("%LightingPanel").hide()
	dock.get_node("%SceneManagerButton").pressed.emit()
	await settle()
	root.get_texture().get_image().save_png("user://studio-models.png")
	var navigator:SceneManagerPanel=ui.scene_manager_panel
	navigator.pos_x.value+=0.5
	check(viewer.undo_transform(),"numeric model editing participates in the same transform undo owner")
	navigator.get_node("%ScaleZ").value=1.7
	check(is_equal_approx(viewer.get_selected_model().scale.z,1.7),"authored inspector preserves independent XYZ model scaling")
	viewer.select_model_id(a.model_id)
	var numeric_before:=a.global_transform
	navigator._begin_numeric_edit();navigator.pos_z.value+=1.0
	viewer.select_model_id(b.model_id)
	check(viewer.undo_transform() and a.global_transform.is_equal_approx(numeric_before),"switching selection commits numeric undo to the originally edited model")
	check(ui.scene_manager_panel.visible,"scene navigator remains accessible from the command dock")
	ui.scene_manager_panel.hide_panel()
	dock.get_node("%CognitiveButton").pressed.emit();await settle()
	root.get_texture().get_image().save_png("user://studio-assist.png")
	var intelligence:Node=root.get_node("SpatialIntelligence")
	check(not intelligence.policy.cloud_enabled and not intelligence.policy.allows_action(),"opening assistant preserves default-denied cloud and action capabilities")
	ui.cognitive_panel.hide_panel()
	ui._toggle_diagnostics();await settle()
	root.get_texture().get_image().save_png("user://studio-diagnostics.png")
	ui._toggle_diagnostics()
	dock.set_expanded(false)
	check(not dock.get_node("%Actions").visible,"command dock collapses to its compact launcher")
	dock.set_expanded(true)
	dock.position=Vector2(-9000,9000);dock._fit()
	check(dock.position.x>=0 and dock.position.y+dock.size.y<=root.get_visible_rect().size.y,"floating dock remains recoverable inside logical viewport bounds")
	dock.reset_layout()
	viewer.select_model_id(a.model_id);var survivor:=a.global_transform
	navigator.pos_y.value+=0.2
	viewer.select_model_id(b.model_id);navigator.pos_x.value+=0.3
	viewer.select_model_ids([a.model_id,b.model_id]);navigator._on_delete_pressed(b)
	for i in range(5):await process_frame
	check(viewer.selected_model_ids==[a.model_id],"deleting the active model preserves the surviving selected model")
	check(viewer.undo_transform() and a.global_transform.is_equal_approx(survivor),"deleted-model history cannot block undo for surviving models")
	viewer._clear_scene_and_reset_atlas()
	check(not viewer.undo_transform() and not viewer.undo_transform(true),"clearing the scene releases transform history")
	scene.queue_free();for i in range(5):await process_frame
	print("STUDIO CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
