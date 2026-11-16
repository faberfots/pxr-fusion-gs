extends SceneTree
var failures:Array[String]=[]
var panel:CognitivePanel
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
func rect(control:Control)->Rect2:
	return control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size)
func contained(control:Control)->bool:
	return root.get_visible_rect().grow(1).encloses(rect(control))
func click(control:Control)->void:
	var parent:=control.get_parent()
	while parent:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await settle()
	var point:=control.get_global_transform_with_canvas()*(control.size*0.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true);await process_frame
func check_layout(label:String,ask:bool)->void:
	check(contained(panel.get_node("%Panel")) and contained(panel.get_node("%HeaderBar")) and contained(panel.close_button),label+": frame, drag handle and Close stay on screen")
	if ask:check(contained(panel.input_field) and contained(panel.analyze_button),label+": question and Ask stay on screen")
func run()->void:
	var brain:Node=root.get_node("SpatialIntelligence")
	brain.conversations=CortexConversations.new("user://layout-chats-"+CortexConversations.identity()+".json")
	SIConfig.settings().select("openai");SIConfig.settings().update_experience("connected",true)
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");ui._on_cognitive_button_pressed();panel=ui.cognitive_panel
	await settle()
	var original_size:=root.size
	print("LAYOUT logical viewport ",root.get_visible_rect()," owner ",rect(panel.draggable_container)," frame ",rect(panel.get_node("%Panel"))," header ",rect(panel.get_node("%HeaderBar")))
	check_layout("Connected assistant with Help and missing setup",true)
	var prefix:="review"
	if not OS.get_cmdline_user_args().is_empty():prefix=OS.get_cmdline_user_args()[0]
	root.get_texture().get_image().save_png("user://cortex-layout-"+prefix+"-"+str(original_size.x)+"x"+str(original_size.y)+".png")
	if not failures.is_empty():scene.free();await process_frame;print("CORTEX LAYOUT COMPLETE: ",failures.size()," failures");quit(1);return
	check(not panel.get_node("%SharingDetails").visible and panel.get_node("%SharingToggle").text.contains("sharing off"),"collapsed assistant section shows its destination and truthful sharing state")
	await click(panel.get_node("%SharingToggle"));await settle()
	check(panel.get_node("%SharingDetails").visible,"actual disclosure click exposes the saved connection and permissions")
	await click(panel.get_node("%CloudConsent"));await settle()
	check(brain.policy.cloud_enabled and panel.get_node("%SharingToggle").text.contains("sharing allowed"),"sharing summary follows the existing explicit consent owner")
	await click(panel.get_node("%CloudConsent"));await click(panel.get_node("%SharingToggle"))
	check(not brain.policy.cloud_enabled and not panel.get_node("%SharingDetails").visible,"collapsing the section neither grants permission nor changes the scene")
	var generation:int=brain._generation
	await click(panel.get_node("%GoalHelpButton"));await settle()
	check(not panel.get_node("%GoalHelpScroll").visible and brain._generation==generation,"Guide collapses with pointer input without cancelling a question or changing authority")
	root.get_texture().get_image().save_png("user://cortex-layout-collapsed-"+str(original_size.x)+"x"+str(original_size.y)+".png")
	var before_drag:=panel.draggable_container.position
	var delta:=Vector2(-24 if before_drag.x>40 else 24,-18 if before_drag.y>30 else 18)
	var start:Vector2=panel.get_node("%HeaderBar").get_global_transform_with_canvas()*Vector2(8,12)
	var down:=InputEventMouseButton.new();down.position=start;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;root.push_input(down,true)
	var motion:=InputEventMouseMotion.new();motion.position=start+delta;motion.relative=delta;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	var up:=InputEventMouseButton.new();up.position=motion.position;up.button_index=MOUSE_BUTTON_LEFT;root.push_input(up,true);await settle()
	check(panel.draggable_container.position.distance_to(before_drag+delta)<2,"the visible header still moves the compact Cortex panel with actual pointer input")
	var ticket:Dictionary=brain.conversations.begin_turn("Keep this conversation during layout changes.","fixture","Assistant")
	brain.conversations.finish_turn(ticket,"Your conversation stays available.")
	panel.input_field.text="Keep this draft too";panel.input_field.text_changed.emit(panel.input_field.text)
	var chats:Dictionary=brain.conversations.snapshot();var camera:=viewer.get_camera().global_transform
	for id in CortexPresets.ORDER:
		panel.choose_preset(id)
		for help in [false,true]:
			SIConfig.settings().update_experience(id,help);await settle()
			check_layout(id+(" Help open" if help else " Help closed"),CortexPresets.kind(id) in ["private","connected"])
		if id=="custom":
			for tab in range(3):
				panel.get_node("%WorkspaceTabs").current_tab=tab;await settle();check_layout("Advanced tab "+str(tab),tab==0)
	panel.choose_preset("connected");SIConfig.settings().update_experience("connected",true)
	root.size=Vector2i(1000,500);await settle();check_layout("Resized to a short window",true)
	panel.draggable_container._drag_to(Vector2(10000,10000));await settle();check_layout("Dragged to the window edge",true)
	panel.draggable_container.position=Vector2(10000,-10000);panel.draggable_container._save()
	panel.queue_free();ui.cognitive_panel=null;await process_frame
	ui._on_cognitive_button_pressed();panel=ui.cognitive_panel;await settle()
	check_layout("Reopened with an off-screen saved position",true)
	root.size=original_size;await settle();check_layout("Restored original window",true)
	check(brain.conversations.snapshot()==chats and panel.input_field.text=="Keep this draft too","layout changes and reopening preserve the chat history and draft")
	check(viewer.get_camera().global_transform.is_equal_approx(camera) and not brain.policy.cloud_enabled and not brain.policy.local_enabled and not brain.policy.allows_action(),"layout changes preserve the camera and never grant sharing or scene permissions")
	check(not brain.local_runtime.is_running() and not brain.segmentation.is_processing(),"layout and Help changes start no inference")
	scene.free();await process_frame
	print("CORTEX LAYOUT COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
