class_name SceneContext
extends Node
static func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
static func get_context_payload(camera: Camera3D) -> Dictionary:
	var payload := {"schema_version": 1, "frame": Engine.get_process_frames(), "timestamp": Time.get_datetime_string_from_system(), "visible_objects": [], "semantics": "Models are assets; names do not prove object identity."}
	if not is_instance_valid(camera): return payload
	payload.camera = {"position": vec(camera.global_position), "rotation_degrees": vec(camera.global_rotation_degrees), "fov": camera.fov, "projection": camera.projection}
	var tree := Engine.get_main_loop() as SceneTree
	for viewer in tree.get_nodes_in_group("gaussian_splat_viewers"):
		if viewer.get_camera() != camera: continue
		for item in viewer.get_model_snapshot():
			if item.status != "loaded" or not item.visible: continue
			var transform: Transform3D = item.transform
			var bounds: AABB = transform * item.bounds
			var outside := false
			for plane in camera.get_frustum():
				var all_outside := true
				for i in range(8):
					if not plane.is_point_over(bounds.get_endpoint(i)):
						all_outside = false
						break
				if all_outside:
					outside = true
					break
			if outside: continue
			payload.visible_objects.append({"model_id": item.model_id, "name": item.name, "bounds_world": {"min": vec(bounds.position), "max": vec(bounds.end)}, "splat_count": item.splat_count})
	payload.spatial_graph = []
	for provider in tree.get_nodes_in_group("spatial_context_providers"):
		if provider.has_method("get_context_snapshot"):
			payload.spatial_graph.append(provider.get_context_snapshot())
	return payload
static func get_context_as_text() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	return JSON.stringify(get_context_payload(tree.root.get_camera_3d()), "\t") if tree else "{}"
