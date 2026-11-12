class_name NativeMLBridge
extends RefCounted
## Optional native delivery boundary. Never activates a missing extension automatically.
static func availability() -> Dictionary:
	return {"available": ClassDB.class_exists("MobileSamSegmenter"), "reason": "Build/install the optional native extension and supply verified MobileSAM models and ONNX Runtime."}
static func materialize_model(source: String, expected_sha256: String) -> String:
	if expected_sha256.length() != 64 or not FileAccess.file_exists(source): return ""
	if FileAccess.get_sha256(source).to_lower() != expected_sha256.to_lower(): return ""
	var directory := "user://verified_models"
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return ""
	var destination := directory.path_join(expected_sha256.to_lower() + ".onnx")
	if FileAccess.file_exists(destination) and FileAccess.get_sha256(destination) == expected_sha256.to_lower():
		return ProjectSettings.globalize_path(destination)
	var input := FileAccess.open(source, FileAccess.READ)
	var output := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	if not input or not output: return ""
	while input.get_position() < input.get_length(): output.store_buffer(input.get_buffer(1048576))
	output.close()
	if FileAccess.get_sha256(destination + ".tmp").to_lower() != expected_sha256.to_lower():
		DirAccess.remove_absolute(destination + ".tmp")
		return ""
	if DirAccess.rename_absolute(destination + ".tmp", destination) != OK: return ""
	return ProjectSettings.globalize_path(destination)
