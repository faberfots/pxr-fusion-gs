extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
func pointer(point:Vector2,pressed:bool)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func click(control:Control)->void:
	var point:Vector2=control.get_global_transform_with_canvas()*(control.size*0.5)
	pointer(point,true);pointer(point,false)
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI")
	var viewer:GaussianSplattingViewer=ui.viewer
	var dock:GSCommandDock=ui.get_node("%MainControls")
	dock.set_expanded(true);dock.reset_layout();await settle()
	check(GSUiScale.screen_rect(dock).size.is_equal_approx(dock.size*0.67),"visible command rig is 33 percent smaller")
	root.get_texture().get_image().save_png("user://ui-scale-orbit.png")
	click(dock.get_node("%ColorButton"));await settle()
	check(ui.color_panel.visible and not dock.get_node("%Actions").visible,"scaled Image button receives pointer clicks and collapses the rig")
	var panel:GSColorAdjustmentPanel=ui.color_panel
	panel.reset_layout();await settle()
	var handle:Control=panel.drag_handle
	var start:Vector2=handle.get_global_transform_with_canvas()*Vector2(65,14)
	var before:=panel.position
	pointer(start,true)
	var motion:=InputEventMouseMotion.new();motion.position=start+Vector2(-65,-25);motion.relative=Vector2(-65,-25);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	await process_frame
	pointer(motion.position,false);await settle()
	check(panel.position.distance_to(before+Vector2(-65,-25))<2,"scaled floating panel drag follows the pointer without amplified movement")
	var saved:=panel.position
	panel.position=Vector2.ZERO;panel._load_layout()
	check(panel.position.distance_to(saved)<1,"reopening restores the scaled panel's normalized saved position")
	var slider:Range=panel.sliders["post_exposure"]
	var old_exposure:=viewer.config.post_exposure
	var point:Vector2=slider.get_global_transform_with_canvas()*(slider.size*Vector2(0.65,0.5))
	pointer(point,true);pointer(point,false);await settle()
	check(not is_equal_approx(viewer.config.post_exposure,old_exposure),"scaled exposure slider updates the authoritative color settings through pointer input")
	click(panel.preset);await settle()
	var popup:=panel.preset.get_popup()
	print("SCALED PRESET POPUP factor ",popup.content_scale_factor," size ",popup.size," position ",popup.position)
	check(popup.visible and is_equal_approx(popup.content_scale_factor,GSUiScale.FACTOR),"scaled preset menu opens at its button and inherits HUD density")
	root.get_texture().get_image().save_png("user://ui-scale-preset.png")
	popup.hide();panel.apply_profile("Natural");panel.hide_panel()
	ui._on_scene_manager_pressed();await settle()
	var navigator:DraggableContainer=ui.scene_manager_panel.draggable_container
	navigator.reset_layout();await settle()
	var nav_before:=navigator.position
	var nav_start:Vector2=navigator.drag_handle.get_global_transform_with_canvas()*Vector2(65,14)
	pointer(nav_start,true)
	motion=InputEventMouseMotion.new();motion.position=nav_start+Vector2(35,20);motion.relative=Vector2(35,20);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	pointer(motion.position,false);await settle()
	check(navigator.position.distance_to(nav_before+Vector2(35,20))<2,"scaled scene navigator drag follows the same pointer coordinates")
	check(GSUiScale.screen_rect(navigator).size.is_equal_approx(navigator.size*0.67),"scene navigator follows the shared HUD density")
	ui.scene_manager_panel.hide_panel()
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://ui-scale.ply",1));model.position.y=1
	for i in range(40):await process_frame
	viewer.select_model_id(model.model_id);viewer.frame_models([])
	var tools:GSModelTransformControls=ui.transform_controls;tools.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	check(tools._center.distance_to(viewer.get_camera().unproject_position(viewer.get_model_world_bounds(model).get_center()))<1,"smaller transform handles stay attached to the model's projected 3D pivot")
	check(GSUiScale.screen_rect(tools.toolbar).size.is_equal_approx(tools.toolbar.size*0.67),"model toolbar follows the same shared scale")
	tools.reset_toolbar_layout();await settle()
	var toolbar_before:=tools.toolbar.position
	var grip:Control=tools.get_node("%DragGrip")
	var toolbar_start:Vector2=grip.get_global_transform_with_canvas()*(grip.size*0.5)
	var camera_before:=viewer.get_camera().global_transform
	pointer(toolbar_start,true)
	motion=InputEventMouseMotion.new();motion.position=toolbar_start+Vector2(45,-70);motion.relative=Vector2(45,-70);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	pointer(motion.position,false);await settle()
	check(tools.toolbar.position.distance_to(toolbar_before+Vector2(45,-70))<2,"model toolbar moves one-to-one using its authored drag grip")
	var toolbar_saved:=tools.toolbar.position
	tools._place_toolbar();await settle()
	check(tools.toolbar.position.is_equal_approx(toolbar_saved),"automatic placement no longer overrides the user's toolbar position")
	tools.toolbar.position=Vector2.ZERO;tools.toolbar._load_layout()
	check(tools.toolbar.position.distance_to(toolbar_saved)<1,"model toolbar position restores from saved layout")
	check(viewer.get_camera().global_transform.is_equal_approx(camera_before),"dragging model controls does not move the camera")
	tools.reset_toolbar_layout();await settle()
	check(not tools.toolbar._placed and tools.toolbar.position.distance_to(toolbar_saved)>10,"reset layout returns model controls to automatic placement")
	ui.load_zone_panel.show();ui.status_label.show();await settle()
	check(GSUiScale.screen_rect(ui.load_zone_panel).get_center().distance_to(root.get_visible_rect().get_center())<2,"scaled load dialog remains centered")
	var strip:=GSUiScale.screen_rect(ui.status_label.get_parent())
	check(absf(strip.get_center().x-root.get_visible_rect().get_center().x)<2 and strip.end.y<=root.get_visible_rect().end.y+1,"scaled status strip stays centered on the lower viewport edge")
	ui.load_zone_panel.hide();ui.status_label.hide()
	dock.set_expanded(true);dock.reset_layout();await settle()
	var right:=GSUiScale.screen_rect(dock).end.x
	dock.set_expanded(false)
	check(absf(GSUiScale.screen_rect(dock).end.x-right)<1,"collapsing the scaled rig preserves its right screen edge")
	scene.free();await process_frame
	print("UI SCALE CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
