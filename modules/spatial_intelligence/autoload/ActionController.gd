class_name ActionController
extends Node
var policy: AIAccessPolicy
static func get_tool_definitions() -> Array:
	var vector := {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}
	return [
		{"type": "function", "function": {"name": "move_camera", "description": "Position the viewer camera in world coordinates.", "parameters": {"type": "object", "properties": {"position": vector, "look_at": vector}, "required": ["position"], "additionalProperties": false}}},
		{"type": "function", "function": {"name": "select_object", "description": "Select a loaded model by its stable model_id from scene context.", "parameters": {"type": "object", "properties": {"model_id": {"type": "string"}}, "required": ["model_id"], "additionalProperties": false}}},
		{"type": "function", "function": {"name": "reset_view", "description": "Frame the loaded scene.", "parameters": {"type": "object", "properties": {}, "additionalProperties": false}}}
	]
static func valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)) or absf(float(component)) > 1000000.0: return false
	return true
func execute_action(tool_name: String, args: Dictionary) -> Dictionary:
	if not policy or not policy.allows_action(): return _error("Scene actions are disabled for this session role.")
	var tree := get_tree()
	var viewer: GaussianSplattingViewer
	for candidate in tree.get_nodes_in_group("gaussian_splat_viewers"):
		if candidate.get_camera() == get_viewport().get_camera_3d():
			viewer = candidate
			break
	if not viewer: return _error("No active viewer is available.")
	match tool_name:
		"move_camera":
			for key in args:
				if key not in ["position", "look_at"]: return _error("Unknown camera argument.")
			if not valid_vector(args.get("position")): return _error("position must contain three finite, bounded numbers.")
			if args.has("look_at") and not valid_vector(args.look_at): return _error("look_at must contain three finite, bounded numbers.")
			var pos := Vector3(args.position[0], args.position[1], args.position[2])
			var camera := viewer.get_camera()
			if not camera: return _error("No active camera.")
			var target := Vector3(args.look_at[0], args.look_at[1], args.look_at[2]) if args.has("look_at") else pos - camera.global_basis.z
			if pos.distance_squared_to(target) < 0.000001: return _error("Camera position and look target must differ.")
			viewer.set_camera_blocker("ai_action", true)
			viewer.camera_controller.position_camera_at(pos, target)
			viewer.set_camera_blocker("ai_action", false)
			return {"status": "success", "message": "Camera positioned.", "position": [camera.global_position.x, camera.global_position.y, camera.global_position.z]}
		"select_object":
			if args.size() != 1 or not args.get("model_id") is String: return _error("Expected a stable model_id.")
			if not viewer.select_model_id(args.model_id): return _error("Loaded model is unavailable.")
			for panel in tree.get_nodes_in_group("gs_scene_managers"):
				if panel.viewer == viewer and panel.select_model(args.model_id): return {"status": "success", "message": "Model selected.", "model_id": args.model_id}
			return {"status": "success", "message": "Model selected and highlighted.", "model_id": args.model_id}
		"reset_view":
			if not args.is_empty(): return _error("reset_view accepts no arguments.")
			if viewer.total_splats_to_load == 0: return _error("No loaded scene to frame.")
			viewer.reset_camera()
			return {"status": "success", "message": "Loaded scene framed."}
		_: return _error("Unknown tool.")
func _error(message: String) -> Dictionary:
	return {"status": "error", "message": message}
