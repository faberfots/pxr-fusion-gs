extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(0.2).timeout;await RenderingServer.frame_post_draw
func button(point:Vector2,pressed:bool)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func run()->void:
	var file:=ConfigFile.new();file.load(GSFloatingPanel.LAYOUT_PATH)
	if file.has_section("command_orbit_v2"):file.erase_section("command_orbit_v2");file.save(GSFloatingPanel.LAYOUT_PATH)
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	var dock:GSCommandDock=scene.get_node("ProductionUI").get_node("%MainControls")
	await settle()
	check(dock.expanded and GSUiScale.extent(dock).x>240,"fresh launcher has a real expanded layout before any preference exists")
	for expanded in [true,false]:
		dock.set_expanded(expanded);dock.position=Vector2(120,100);dock.save_layout();await settle()
		var toggle:Button=dock.get_node("%Toggle")
		var point:Vector2=toggle.get_global_transform_with_canvas()*(toggle.size*0.5)
		var before:=dock.position;var camera:=viewer.get_camera().global_transform
		button(point,true)
		var motion:=InputEventMouseMotion.new();motion.position=point+Vector2(105,55);motion.relative=Vector2(105,55);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
		button(motion.position,false);await settle()
		check(dock.position.distance_to(before+Vector2(105,55))<1,"held left drag moves the %s main control one-to-one" % ("expanded" if expanded else "compact"))
		check(dock.expanded==expanded,"a launcher drag cannot toggle expansion")
		check(viewer.get_camera().global_transform.is_equal_approx(camera),"moving the main control preserves the camera pose")
		var saved:=dock.position
		dock.position=Vector2.ZERO;dock._placed=false;dock._load_layout();await settle()
		check(dock.position.distance_to(saved)<1 and dock.expanded==expanded,"launcher position and expansion survive preference reload")
		point=toggle.get_global_transform_with_canvas()*(toggle.size*0.5)
		button(point,true);button(point,false);await settle()
		check(dock.expanded!=expanded,"ordinary left click retains the expand/collapse action")
		var clicked_position:=dock.position
		dock.position=Vector2.ZERO;dock._load_layout();await settle()
		check(dock.position.distance_to(clicked_position)<1 and dock.expanded!=expanded,"clicking after a drag persists the current compact/expanded position")
	dock.set_expanded(false);dock.position=Vector2(200,100);await settle()
	var toggle:Button=dock.get_node("%Toggle")
	var point:Vector2=toggle.get_global_transform_with_canvas()*(toggle.size*0.5)
	button(point,true)
	var motion:=InputEventMouseMotion.new();motion.position=point+Vector2(-9000,9000);motion.relative=Vector2(-9000,9000);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	dock._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT);await settle()
	var box:=GSUiScale.screen_rect(dock)
	check(box.position.x>=0 and box.end.y<=root.get_visible_rect().end.y,"dragging to an edge keeps the launcher reachable")
	check(not dock._launcher_held and not viewer.camera_controller._movement_blockers.has("floating_"+dock.layout_id),"focus loss releases the launcher gesture and its camera blocker")
	button(point,false);dock.reset_layout();dock.set_expanded(true);await settle()
	root.get_texture().get_image().save_png("user://launcher-drag-review.png")
	scene.free();await process_frame
	print("LAUNCHER DRAG CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
