@tool
class_name GaussianSplat
extends Node3D
signal loaded
@export var model_id := ""
@export var cast_gaussian_shadows := true
@export var receive_gaussian_shadows := false
@export_file("*.ply", "*.gsres") var file_path := "":
	set(value):
		if file_path == value:
			return
		file_path = value
		revision += 1
		_cached_ply_file = null
		if is_inside_tree() and not Engine.is_editor_hint():
			call_deferred("_notify_viewer_of_change")
@export var viewer_path: NodePath
var splat_count := 0
var buffer_offset := 0
var is_loaded := false
var revision := 0
var _cached_ply_file: PlyFile
var _viewer_ref: WeakRef

func _enter_tree() -> void:
	add_to_group("gaussian_splats")
	if model_id.is_empty():
		model_id = Crypto.new().generate_random_bytes(16).hex_encode()
	if not Engine.is_editor_hint():
		call_deferred("_notify_viewer_of_change")

func _exit_tree() -> void:
	if _viewer_ref:
		var viewer = _viewer_ref.get_ref()
		if is_instance_valid(viewer):
			viewer.unregister_splat(self)
	_viewer_ref = null
	remove_from_group("gaussian_splats")

func assign_viewer(viewer: Node) -> void:
	_viewer_ref = weakref(viewer)

func _notify_viewer_of_change() -> void:
	if not is_inside_tree():
		return
	var viewer: Node = _viewer_ref.get_ref() if _viewer_ref else null
	if not is_instance_valid(viewer) and not viewer_path.is_empty():
		viewer = get_node_or_null(viewer_path)
	if not is_instance_valid(viewer):
		var ancestor := get_parent()
		while ancestor:
			if ancestor.has_method("register_splat"):
				viewer = ancestor
				break
			ancestor = ancestor.get_parent()
	if is_instance_valid(viewer) and viewer.has_method("register_splat"):
		assign_viewer(viewer)
		viewer.register_splat(self)

func get_ply_file() -> PlyFile:
	if not _cached_ply_file and not file_path.is_empty():
		var ply := PlyFile.new()
		if ply.parse(file_path) == OK:
			_cached_ply_file = ply
	return _cached_ply_file
