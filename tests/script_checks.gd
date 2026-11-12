extends SceneTree
var invalid: Array[String] = []
func _initialize() -> void:
	scan("res://modules")
	scan("res://tests")
	print("SCRIPT CHECKS COMPLETE: ", invalid.size(), " invalid scripts")
	quit(0 if invalid.is_empty() else 1)
func scan(folder: String) -> void:
	var directory := DirAccess.open(folder)
	for file in directory.get_files():
		if not file.ends_with(".gd"): continue
		var path := folder.path_join(file)
		var script := load(path) as Script
		if not script or not script.can_instantiate():
			invalid.append(path)
			printerr("INVALID SCRIPT ", path)
	for child in directory.get_directories(): scan(folder.path_join(child))
