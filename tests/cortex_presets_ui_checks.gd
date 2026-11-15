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
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true);await process_frame
func choose(panel:CognitivePanel,id:String)->void:
	var selector:OptionButton=panel.get_node("%GoalPicker")
	for index in range(selector.item_count):
		if selector.get_item_metadata(index)==id:selector.select(index);selector.item_selected.emit(index);break
	await process_frame;await process_frame
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():CortexAssets.qualification_root=args[0]
	var brain:Node=root.get_node("SpatialIntelligence")
	SIConfig.settings().update_experience("pick",false)
	var before:=SIConfig.settings().snapshot()
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=160
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");ui._on_cognitive_button_pressed();var panel:CognitivePanel=ui.cognitive_panel
	await create_timer(0.3).timeout
	check(panel.get_node("%WorkspaceTabs").current_tab==1 and not panel.get_node("%WorkspaceTabs").tabs_visible,"opening Cortex presents the ready-to-use click-selection preset without technical setup tabs")
	check(not brain.segmentation.is_processing() and not brain.local_runtime.is_running(),"opening or choosing a preset starts no inference")
	await click(panel.get_node("%GoalHelpButton"))
	check(panel.get_node("%GoalHelpScroll").visible and panel.get_node("%GoalHelp").text.contains("Capture") and panel.get_node("%GoalHelp").text.contains("no account"),"actual Help click displays natural-language steps, privacy and capability limits")
	await click(panel.get_node("%GoalHelpButton"))
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://preset-ui.ply",1))
	while viewer.is_loading():await process_frame
	model.position=Vector3(0,1,0);viewer.camera_controller.position_camera_at(Vector3(0,1,3),Vector3(0,1,0));await create_timer(0.3).timeout
	var pose:=model.global_transform;var camera:=viewer.get_camera().global_transform
	await click(panel.get_node("%CaptureButton"));await create_timer(0.2).timeout
	check(not panel._capture.is_empty(),"default preset captures the scene through the existing clean-capture action")
	await choose(panel,"find")
	check(panel.get_node("%ConceptPrompt").visible and panel.get_node("%SnapshotCanvas").box_mode and panel._request_vision_settings().engine=="sam3","description preset configures SAM3 and its optional box without asking for a model path")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("user://presets-find.png")
	await choose(panel,"scene")
	check(panel.get_node("%WorkspaceTabs").current_tab==0 and not panel.get_node("%AskConnection").visible and not panel.get_node("%ActionConsent").visible,"private assistant preset removes provider setup and scene-command switches from the guided path")
	await click(panel.get_node("%ExampleQuestion"))
	check(not panel.input_field.text.is_empty() and not brain._is_analyzing and not brain.local_runtime.is_running(),"example question fills the input without sending data or starting a model")
	await choose(panel,"selection");viewer.select_model_id("")
	panel.input_field.text="Explain the selected model.";await click(panel.analyze_button)
	check(panel.chat_feed.get_parsed_text().contains("Select a model") and not brain.local_runtime.is_running(),"selected-model guide explains missing selection before loading a model")
	await choose(panel,"connected")
	check(panel.get_node("%AskConnection").visible and panel.get_node("%GoalSummary").text.contains("choose") and not brain.policy.cloud_enabled,"connected preset keeps destination selection visible and does not grant cloud consent")
	await click(panel.get_node("%SetupShortcut"))
	check(panel.get_node("%WorkspaceTabs").tabs_visible and panel.get_node("%WorkspaceTabs").current_tab==2,"Advanced keeps all original Ask, Select and Setup controls reachable")
	check(SIConfig.settings().snapshot()==before and model.global_transform.is_equal_approx(pose) and viewer.get_camera().global_transform.is_equal_approx(camera),"all preset changes preserve saved settings, camera and model transforms")
	await choose(panel,"pick");brain.policy.configuration_enabled=false
	await click(panel.get_node("%SetupShortcut"))
	check(panel.get_node("%WorkspaceTabs").current_tab==2 and SIConfig.settings().experience().preset=="pick","managed users can inspect Advanced without changing their permitted preset")
	brain.policy.configuration_enabled=true
	await choose(panel,"pick");await click(panel.get_node("%GoalHelpButton"))
	check(panel.get_node("%WorkspaceTabs").current_tab==1,"reselecting the same goal restores its guided workspace after inspecting Advanced")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("user://presets-default-help.png")
	await click(panel.get_node("%GoalHelpButton"));await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("user://presets-default.png")
	panel.hide_panel();panel.show_panel()
	check(SIConfig.settings().experience().preset=="pick" and panel.get_node("%WorkspaceTabs").current_tab==1,"reopening retains the selected goal")
	scene.free();await process_frame
	print("CORTEX PRESETS UI COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
