class_name CortexAssets
extends RefCounted
## Portable project/package paths. User credentials and preferences never travel with assets.
static var qualification_root:="" # Isolated test harness only; never persisted or exposed to LLM tools.
static func root()->String:
	if not qualification_root.is_empty():return qualification_root
	if OS.has_feature("editor"):return ProjectSettings.globalize_path("res://resources/cortex").simplify_path()
	return OS.get_executable_path().get_base_dir().path_join("resources/cortex")
static func resolve(relative:String)->String:
	if relative.is_absolute_path() or ".." in relative.split("/") or "\\" in relative:return ""
	return root().path_join(relative)
static func catalog()->Dictionary:
	var file:=FileAccess.open(resolve("catalog.json"),FileAccess.READ)
	if not file or file.get_length()>1048576:return {}
	var parser:=JSON.new();var error:=parser.parse(file.get_as_text());file.close()
	return parser.data if error==OK and parser.data is Dictionary else {}
static func sam3_directory(value:String)->String:
	if value!="bundle://sam3" and not value.is_empty():return value
	var relative:String=catalog().get("sam3",{}).get("directory","")
	return resolve(relative) if not relative.is_empty() else ""
static func mobile_artifacts()->Dictionary:
	var metadata:=catalog()
	var output:Dictionary={}
	for name in ["encoder","decoder","windows_runtime"]:
		if not metadata.get("mobile_sam",{}).has(name):return {}
		var artifact:Dictionary=metadata.mobile_sam[name].duplicate()
		artifact.path=resolve(artifact.path)
		if not FileAccess.file_exists(artifact.path):return {}
		for dependency in artifact.get("dependencies",[]):dependency.path=resolve(dependency.path)
		output[name]=artifact
	return output
