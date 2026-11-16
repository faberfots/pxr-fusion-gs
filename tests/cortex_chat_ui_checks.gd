extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func click(control:Control)->void:
	var parent:=control.get_parent()
	while parent:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await process_frame;await process_frame
	var point:=control.get_global_transform_with_canvas()*(control.size*0.5)
	var move:=InputEventMouseMotion.new();move.position=point;root.push_input(move,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true);await process_frame
func select_chat(panel:CognitivePanel,id:String)->void:
	var picker:OptionButton=panel.get_node("%ChatSelector")
	for i in range(picker.item_count):
		if picker.get_item_metadata(i)==id:picker.select(i);picker.item_selected.emit(i);break
	await process_frame
func shot(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://"+name+".png")
func run()->void:
	var brain:Node=root.get_node("SpatialIntelligence");brain.conversations=CortexConversations.new("user://chat-ui-"+CortexConversations.identity()+".json")
	SIConfig.settings().update_experience("pick",false)
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=160
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://chat-ui.ply",1))
	while viewer.is_loading():await process_frame
	var pose:=model.global_transform;var camera:=viewer.get_camera().global_transform
	var ui=scene.get_node("ProductionUI");ui._on_cognitive_button_pressed();var panel:CognitivePanel=ui.cognitive_panel
	await create_timer(0.3).timeout
	await click(panel.get_node("%OpenChats"))
	check(panel.get_node("%WorkspaceTabs").current_tab==0 and SIConfig.settings().experience().preset=="scene" and not brain.local_runtime.is_running(),"Chats shortcut opens a useful private conversation without launching inference")
	var first:String=brain.conversations.active().id
	panel.input_field.text="A question I will finish later"
	await click(panel.get_node("%NewChat"));var second:String=brain.conversations.active().id
	check(first!=second and panel.input_field.text.is_empty() and panel.get_node("%ChatSelector").item_count==2,"actual New click creates a separate empty topic")
	await select_chat(panel,first)
	check(panel.input_field.text=="A question I will finish later","switching back restores the unsent draft")
	await click(panel.get_node("%RenameChat"))
	check(panel.get_node("%RenameChatDialog").visible,"Rename opens the authored dialog")
	panel.get_node("%ChatName").text="Motorcycle ideas";panel.get_node("%RenameChatDialog").confirmed.emit();panel.get_node("%RenameChatDialog").hide()
	check(brain.conversations.active().title=="Motorcycle ideas","chat names are editable without changing the questions")
	var ticket:Dictionary=brain.conversations.begin_turn("[b]Is the motorcycle selected?[/b]","fixture","Private assistant")
	brain.conversations.finish_turn(ticket,"You can select it in Scene navigator, then ask about its position and scale.")
	check(panel.chat_feed.get_parsed_text().contains("[b]Is the motorcycle") and panel.chat_feed.get_parsed_text().contains("Scene navigator"),"chat transcript shows separate speakers and displays user markup as plain text")
	await shot("cortex-chats")
	var button:Button=panel.analyze_button
	var bounds:=root.get_visible_rect()
	check(bounds.encloses(Rect2(button.get_global_transform_with_canvas()*Vector2.ZERO,button.size*0.67)) and panel.chat_feed.size.y>=140,"composer stays visible and history keeps its own scroll area at this resolution")
	await select_chat(panel,second)
	check(not panel.chat_feed.get_parsed_text().contains("motorcycle"),"other topics do not appear in a separate chat")
	await click(panel.get_node("%DeleteChat"))
	check(panel.get_node("%DeleteChatDialog").visible and brain.conversations.snapshot().chats.size()==2,"Delete asks before removing saved local history")
	panel.get_node("%DeleteChatDialog").canceled.emit();panel.get_node("%DeleteChatDialog").hide()
	check(brain.conversations.snapshot().chats.size()==2,"cancelling Delete preserves all chats")
	await click(panel.get_node("%DeleteChat"));panel.get_node("%DeleteChatDialog").confirmed.emit();panel.get_node("%DeleteChatDialog").hide()
	check(brain.conversations.snapshot().chats.size()==1 and brain.conversations.active().id==first,"confirmed Delete removes only the chosen chat")
	panel.input_field.text="Draft survives closing";panel.hide_panel();panel.show_panel()
	check(panel.input_field.text=="Draft survives closing" and brain.conversations.active().turns.size()==1,"closing and reopening keeps chat history and unsent text")
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		CortexAssets.qualification_root=args[0]
		brain.new_chat();panel.input_field.text="Remember the code word cobalt. Reply with cobalt.";await click(panel.analyze_button)
		var deadline:=Time.get_ticks_msec()+120000
		while brain._is_analyzing and Time.get_ticks_msec()<deadline:await process_frame
		check(brain.conversations.active().turns.back().state=="complete","actual chat Ask completes bundled private Qwen inference")
		panel.input_field.text="Which code word did I ask you to remember?";await click(panel.analyze_button)
		deadline=Time.get_ticks_msec()+90000
		while brain._is_analyzing and Time.get_ticks_msec()<deadline:await process_frame
		var turn:Dictionary=brain.conversations.active().turns.back()
		check(turn.state=="complete" and turn.answer.to_lower().contains("cobalt"),"real private follow-up remembers its chat's earlier answer")
		await shot("cortex-chats-private");brain.local_runtime.stop()
	check(model.global_transform.is_equal_approx(pose) and viewer.get_camera().global_transform.is_equal_approx(camera) and not brain.policy.cloud_enabled and not brain.policy.allows_action(),"chat controls preserve GS transforms, camera and read-only permission defaults")
	scene.free();await process_frame
	print("CORTEX CHAT UI COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
