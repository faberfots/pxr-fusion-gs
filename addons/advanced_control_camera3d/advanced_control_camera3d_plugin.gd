@tool
extends EditorPlugin

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	add_custom_type("ControlCamera3D", "Camera3D",
			preload("res://addons/advanced_control_camera3d/nodes/advanced_control_camera_3d.gd"),
			preload("res://addons/advanced_control_camera3d/advanced_control_camera3d.svg"))

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	remove_custom_type("ControlCamera3D")
