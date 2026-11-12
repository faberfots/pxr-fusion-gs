class_name NativeMLBridge
extends RefCounted
## Optional native delivery boundary. Never activates a missing extension automatically.
const MANIFEST_PATH := "res://rust/spatial_ml/models/manifest.json"
static func artifact_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK or not parser.data is Dictionary:return {}
	return parser.data
static func availability() -> Dictionary:
	var registered := ClassDB.class_exists("MobileSamSegmenter")
	var manifest := artifact_manifest()
	var supported := OS.get_name()=="Windows" and OS.has_feature("x86_64")
	var present := manifest.has("artifacts")
	if present:
		for key in ["encoder","decoder","windows_runtime"]:
			if not manifest.artifacts.has(key) or not FileAccess.file_exists(str(manifest.artifacts[key].get("path",""))):present=false
	var available := registered and supported and present and ClassDB.class_has_method("MobileSamSegmenter","load_model_with_runtime")
	return {"available":available,"native_registered":registered,"platform_supported":supported,"reason":"Native artifacts are present; initialization verifies their hashes." if available else "The verified Windows x86_64 native package is required."}
static func load_default_segmenter() -> Object:
	if not availability().available:return null
	var artifacts:Dictionary = artifact_manifest().artifacts
	var paths := {}
	for key in ["encoder","decoder","windows_runtime"]:
		if not artifacts.has(key):return null
		var artifact:Dictionary = artifacts[key]
		paths[key] = materialize_model(artifact.path,artifact.sha256)
		if paths[key].is_empty():return null
	var segmenter:Object = ClassDB.instantiate("MobileSamSegmenter")
	if not segmenter or not segmenter.has_method("load_model_with_runtime"):return null
	return segmenter if segmenter.call("load_model_with_runtime",paths.encoder,paths.decoder,paths.windows_runtime) else null
static func materialize_model(source: String, expected_sha256: String) -> String:
	if expected_sha256.length() != 64 or not FileAccess.file_exists(source): return ""
	if FileAccess.get_sha256(source).to_lower() != expected_sha256.to_lower(): return ""
	var directory := "user://verified_models"
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return ""
	var destination := directory.path_join(expected_sha256.to_lower() + "." + source.get_extension())
	if FileAccess.file_exists(destination) and FileAccess.get_sha256(destination) == expected_sha256.to_lower():
		return ProjectSettings.globalize_path(destination)
	var input := FileAccess.open(source, FileAccess.READ)
	var temporary := destination + ".%d.tmp" % Time.get_ticks_usec()
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if not input or not output: return ""
	while input.get_position() < input.get_length(): output.store_buffer(input.get_buffer(1048576))
	output.close()
	if FileAccess.get_sha256(temporary).to_lower() != expected_sha256.to_lower():
		DirAccess.remove_absolute(temporary)
		return ""
	if FileAccess.file_exists(destination):
		if DirAccess.remove_absolute(destination) != OK:
			DirAccess.remove_absolute(temporary)
			return ""
	if DirAccess.rename_absolute(temporary, destination) != OK:
		DirAccess.remove_absolute(temporary)
		return ""
	return ProjectSettings.globalize_path(destination)
