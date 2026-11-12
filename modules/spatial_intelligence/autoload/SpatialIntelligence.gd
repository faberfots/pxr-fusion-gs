extends Node
signal analysis_started
signal analysis_completed(response: String)
signal analysis_failed(error: String)
signal capture_ready(image: Image)
var policy := AIAccessPolicy.new()
var _is_analyzing := false
var _generation := 0
var _llm_client: LLMClient
var _action_controller: ActionController
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
func analyze_scene(prompt: String) -> void:
	if _is_analyzing: return
	if not policy.cloud_enabled:
		_fail("Enable cloud analysis to send this view and scene context to " + SIConfig.get_provider() + ".")
		return
	if prompt.strip_edges().is_empty() or prompt.length() > 16000:
		_fail("Enter a prompt of at most 16,000 characters.")
		return
	_generation += 1
	var generation := _generation
	_is_analyzing = true
	analysis_started.emit()
	var image: Image = await ViewportCapture.capture_scene_only(get_viewport())
	if generation != _generation or not _is_analyzing: return
	if not image:
		_fail("Viewport capture failed.")
		return
	capture_ready.emit(image)
	var context := SceneContext.get_context_payload(get_viewport().get_camera_3d())
	_llm_client.send_request(prompt, context, ViewportCapture.encode_image_to_base64(image))
func cancel_analysis() -> void:
	_generation += 1
	_llm_client.cancel()
	_is_analyzing = false
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
