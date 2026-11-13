extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func run() -> void:
	var camera_script := load("res://addons/advanced_control_camera3d/nodes/advanced_control_camera_3d.gd")
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var detached: Camera3D = camera_script.new()
	detached.free()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == before, "export-time camera construction and destruction leave no orphan visualization nodes")
	var active: Camera3D = camera_script.new()
	active.position = Vector3(0, 2, 5)
	root.add_child(active)
	check(is_instance_valid(active._pole_mesh_instance) and active._pole_mesh_instance.get_parent() == active, "active camera retains its pivot visualization")
	check(is_instance_valid(active._debug_mesh_instance) and active._debug_mesh_instance.get_parent() == active, "active camera retains its raycast visualization")
	active.free()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == before, "active camera teardown frees all visualization children")
	print("CAMERA LIFECYCLE COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
