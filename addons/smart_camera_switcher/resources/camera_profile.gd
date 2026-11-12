# res://addons/smart_camera_switcher/resources/camera_profile.gd
@tool
extends Resource
class_name CameraProfile

## A data resource that describes how a Camera3D node should be registered.
## This decouples the configuration from the camera node itself, allowing
## any camera (scripted or not) to be part of the system.

@export var camera_node_path: NodePath:
	set(value):
		camera_node_path = value
		if Engine.is_editor_hint():
			notify_property_list_changed()

@export var display_name: String = "New Camera":
	set(value):
		display_name = value
		if Engine.is_editor_hint():
			_update_resource_name()

@export_group("Behavior")
@export var priority: int = 0
@export_enum("Instant", "Smooth", "Fade") var transition_type: String = "Smooth"
@export var transition_duration: float = 0.5

func _update_resource_name():
	# Helper to make profiles easier to identify in the FileSystem dock
	var sanitized_name = display_name.to_lower().replace(" ", "_")
	if resource_path and not resource_path.get_file().begins_with(sanitized_name):
		var dir = resource_path.get_base_dir()
		ResourceSaver.save(self, dir.path_join(sanitized_name + ".tres"))
		print("Updated resource path for profile: " + display_name)
