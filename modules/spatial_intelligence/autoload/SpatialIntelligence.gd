extends Node
signal analysis_started
signal analysis_completed(response: String)
signal analysis_failed(error: String)
signal capture_ready(image: Image)
signal segmentation_capture_ready(capture:Dictionary)
signal diagnostics_ready(result:Dictionary)
signal configuration_changed
var policy := AIAccessPolicy.new()
var segmentation:CortexSegmentationService
var connection_probe:CortexConnectionProbe
var local_runtime:CortexLocalRuntime
var _is_analyzing := false
var _generation := 0
var _llm_client: LLMClient
var _action_controller: ActionController
var _probe_client:LLMClient
var _probe_kind:=""
var _connection:=""
var _experience_id:=""
func _ready() -> void:
	SIConfig.setup_default_settings()
	_llm_client = LLMClient.new()
	_llm_client.policy = policy
	add_child(_llm_client)
	_llm_client.response_received.connect(_complete)
	_llm_client.tool_calls_received.connect(_on_tool_calls)
	_llm_client.error_occurred.connect(_fail)
	_action_controller = ActionController.new()
	_action_controller.policy = policy
	add_child(_action_controller)
	segmentation=CortexSegmentationService.new();add_child(segmentation)
	local_runtime=CortexLocalRuntime.new();local_runtime.policy=policy;add_child(local_runtime)
	connection_probe=CortexConnectionProbe.new();connection_probe.policy=policy;add_child(connection_probe)
	connection_probe.completed.connect(func(result):diagnostics_ready.emit(result))
	_probe_client=LLMClient.new();_probe_client.policy=policy;add_child(_probe_client)
	_probe_client.response_received.connect(_probe_text)
	_probe_client.tool_calls_received.connect(_probe_tools)
	_probe_client.error_occurred.connect(func(error):diagnostics_ready.emit({"error":error,"kind":_probe_kind}))
	_connection=_connection_identity()
	_experience_id=SIConfig.settings().experience().preset
	SIConfig.settings().changed.connect(_settings_changed)
	SIConfig.settings().experience_changed.connect(_experience_changed)
func select_preset(id:String)->Error:
	if not policy.configuration_enabled:return ERR_UNAUTHORIZED
	if id==SIConfig.settings().experience().preset:_settings_changed(0);return OK
	return SIConfig.settings().update_experience(id,SIConfig.settings().experience().help_open)
func _experience_changed()->void:
	var id:String=SIConfig.settings().experience().preset
	if id==_experience_id:return
	_experience_id=id;_settings_changed(0)
func analyze_privately(prompt:String)->void:
	# This explicit human action starts only the bundled, fixed loopback assistant.
	if _is_analyzing:return
	if CortexPresets.kind(SIConfig.settings().experience().preset)!="private":_fail("Choose a private assistant preset first.");return
	if prompt.strip_edges().is_empty() or prompt.length()>16000:_fail("Enter a question first.");return
	if SIConfig.settings().analysis_profile().scope=="selected":
		var found:=false
		for viewer in get_tree().get_nodes_in_group("gaussian_splat_viewers"):
			if viewer.get_camera()==get_viewport().get_camera_3d() and not viewer.selected_model_ids.is_empty():found=true
		if not found:_fail("Select a model in the scene or Scene navigator first.");return
	if not local_runtime.is_running() and not local_runtime.is_starting():
		local_runtime.stop() # Release an exited owned host before a user-requested retry.
		var error:=local_runtime.start_bundled()
		if error!=OK:_fail("The private assistant could not start: "+error_string(error));return
	policy.local_enabled=true
	_generation+=1;var generation:=_generation
	_is_analyzing=true;analysis_started.emit()
	while local_runtime.is_starting():
		await get_tree().process_frame
		if generation!=_generation:return
	if generation!=_generation:return
	_is_analyzing=false
	if not local_runtime.is_running() or not local_runtime.message.begins_with("Ready"):_fail(local_runtime.message);return
	analyze_scene(prompt)
func analyze_scene(prompt: String) -> void:
	if _is_analyzing: return
	var profile:=SIConfig.settings().analysis_profile()
	if not policy.allows_connection(profile):
		_fail("Enable transmission to "+profile.name+" before requesting analysis.")
		return
	if prompt.strip_edges().is_empty() or prompt.length() > 16000:
		_fail("Enter a prompt of at most 16,000 characters.")
		return
	_generation += 1
	var generation := _generation
	_is_analyzing = true
	analysis_started.emit()
	var image:Image
	if profile.include_image:image=await ViewportCapture.capture_scene_only(get_viewport())
	if generation != _generation or not _is_analyzing: return
	if profile.include_image and not image:
		_fail("Viewport capture failed.")
		return
	if image:capture_ready.emit(image)
	var context := SceneContext.get_context_payload(get_viewport().get_camera_3d())
	if profile.scope=="selected":
		var selected:Array=[]
		for viewer in get_tree().get_nodes_in_group("gaussian_splat_viewers"):
			if viewer.get_camera()==get_viewport().get_camera_3d():selected=viewer.selected_model_ids
		var visible:Array=[]
		for item in context.visible_objects:
			if item.model_id in selected:visible.append(item)
		context.visible_objects=visible
	_llm_client.send_request(prompt,context,ViewportCapture.encode_image_to_base64(image) if image else "",profile)
func cancel_analysis() -> void:
	_generation += 1
	_llm_client.cancel()
	_is_analyzing = false
func _connection_identity()->String:
	var profile:=SIConfig.settings().analysis_profile();return str(profile.id)+"|"+str(profile.endpoint)
func _settings_changed(_revision:int)->void:
	cancel_analysis();connection_probe.cancel();_probe_client.cancel();segmentation.cancel()
	var identity:=_connection_identity()
	if identity!=_connection:policy.cloud_enabled=false;policy.local_enabled=false;_connection=identity
	configuration_changed.emit()
func configure_profile(profile:Dictionary,secret:String="")->Error:
	if not policy.configuration_enabled:return ERR_UNAUTHORIZED
	var next:=SIConfig.settings().snapshot()
	for i in range(next.profiles.size()):
		if next.profiles[i].id==profile.get("id"):next.profiles[i]=profile.duplicate(true)
	if not CortexSettings.validate(next).is_empty():return ERR_INVALID_DATA
	var previous:=""
	if not secret.is_empty():
		previous=CortexCredentials.resolve(profile)
		var stored:=CortexCredentials.store(profile,secret)
		if stored!=OK:return stored
	var result:=SIConfig.settings().commit(next)
	if result!=OK and not secret.is_empty():
		if previous.is_empty():CortexCredentials.forget(profile)
		else:CortexCredentials.store(profile,previous)
	return result
func set_action_consent(enabled:bool)->void:
	if policy.configuration_enabled:policy.role=AIAccessPolicy.Role.OPERATOR if enabled else AIAccessPolicy.Role.ANALYST
	policy.actions_enabled=enabled and policy.role==AIAccessPolicy.Role.OPERATOR
func test_connection(kind:String)->void:
	_probe_client.cancel();connection_probe.cancel();_probe_kind=kind
	var profile:=SIConfig.settings().active()
	if kind=="models":connection_probe.discover(profile);return
	profile.include_image=false
	if kind!="tools":profile.tools=false
	if kind=="tools" and (not policy.allows_action() or not profile.tools):diagnostics_ready.emit({"error":"Authorize AI scene commands and declare tool capability before this test."});return
	var prompt:="Reply with exactly: cortex-ready"
	var encoded:=""
	if kind=="vision":
		if not profile.vision:diagnostics_ready.emit({"error":"Declare vision capability for this model first."});return
		var image:=Image.create(64,64,false,Image.FORMAT_RGB8);image.fill(Color.RED)
		encoded=ViewportCapture.encode_image_to_base64(image);prompt="What is the dominant color in this synthetic test image? Reply with one color word."
	if kind=="tools":prompt="For this synthetic protocol test, call reset_view once. The test harness will validate the call without executing it."
	_probe_client.send_request(prompt,{"synthetic_capability_test":true},encoded,profile)
func _probe_text(text:String)->void:
	if _probe_kind=="tools":diagnostics_ready.emit({"error":"The model returned text rather than a tool call.","kind":_probe_kind});return
	if _probe_kind=="vision" and not text.to_lower().contains("red"):diagnostics_ready.emit({"error":"The model did not identify the synthetic red image.","kind":_probe_kind});return
	diagnostics_ready.emit({"status":("Vision" if _probe_kind=="vision" else "Text")+" inference verified with synthetic input.","kind":_probe_kind,"metrics":_probe_client.last_result.duplicate()})
func _probe_tools(calls:Array)->void:
	if calls.size()!=1 or calls[0].name!="reset_view" or not calls[0].args.is_empty():diagnostics_ready.emit({"error":"Tool test returned an unexpected command or arguments."});return
	diagnostics_ready.emit({"status":"Tool call schema verified; the command was not executed.","kind":_probe_kind,"metrics":_probe_client.last_result.duplicate()})
func capture_segmentation()->void:
	cancel_analysis()
	var generation:=_generation
	var viewport:=get_viewport();var viewer:GaussianSplattingViewer
	for candidate in get_tree().get_nodes_in_group("gaussian_splat_viewers"):
		if candidate.get_camera()==viewport.get_camera_3d():viewer=candidate;break
	if not viewer or viewer.is_loading() or viewer.composition_busy or viewer.placement_active:segmentation_capture_ready.emit({"error":"Finish the current scene operation before capturing."});return
	viewer.set_camera_blocker("cortex_capture",true)
	var image:=await ViewportCapture.capture_scene_only(viewport)
	if is_instance_valid(viewer):viewer.set_camera_blocker("cortex_capture",false)
	if generation!=_generation or not is_instance_valid(viewer):return
	if not image:segmentation_capture_ready.emit({"error":"Scene capture failed."});return
	image.convert(Image.FORMAT_RGB8)
	segmentation_capture_ready.emit({"image":image,"id":Crypto.new().generate_random_bytes(12).hex_encode(),"signature":scene_signature(viewer),"viewport_size":Vector2(viewport.size)})
func scene_signature(viewer:GaussianSplattingViewer)->String:
	if not is_instance_valid(viewer) or not viewer.get_camera():return ""
	var camera:=viewer.get_camera()
	return (str(viewer.get_model_snapshot())+str(camera.global_transform)+str([camera.fov,camera.projection,camera.size,camera.keep_aspect,camera.frustum_offset,viewer.get_viewport().size])+str(viewer.get("_generation"))).sha256_text()
func get_debug_context() -> String:
	return SceneContext.get_context_as_text()
func _complete(response: String) -> void:
	_is_analyzing = false
	analysis_completed.emit(response)
func _fail(message: String) -> void:
	_is_analyzing = false
	analysis_failed.emit(message)
func _on_tool_calls(calls: Array) -> void:
	var feedback: Array[String] = []
	for call in calls:
		var result := _action_controller.execute_action(call.name, call.args)
		feedback.append(JSON.stringify(result))
	_complete("\n".join(feedback))
