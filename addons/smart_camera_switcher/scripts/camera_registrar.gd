# res://addons/smart_camera_switcher/scripts/camera_registrar.gd
@tool
extends Node
class_name CameraRegistrar

## The central, declarative authority for camera registration in a scene.
## It holds a list of CameraProfile resources and uses them to register
## the specified cameras with the global CameraManager.
## This is 100% SSOT-compliant and works for ANY Camera3D node,
## regardless of its attached script.

@export var camera_profiles: Array[CameraProfile]

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Use call_deferred to ensure the entire scene tree is ready,
	# including the CameraManager autoload.
	call_deferred("_register_all_cameras")

func _register_all_cameras() -> void:
	var camera_manager = get_node_or_null("/root/CameraManager")
	if not camera_manager:
		printerr("[CameraRegistrar] CRITICAL: CameraManager singleton not found! Cameras will not be registered.")
		return

	if camera_profiles.is_empty():
		print("[CameraRegistrar] No camera profiles are configured on this registrar.")
		return

	for profile in camera_profiles:
		if not is_instance_valid(profile):
			printerr("[CameraRegistrar] A profile in the list is invalid or null.")
			continue

		var cam_node = get_node_or_null(profile.camera_node_path)

		if not is_instance_valid(cam_node):
			printerr("[CameraRegistrar] Failed to find node for profile '%s' at path: %s" % [profile.display_name, profile.camera_node_path])
			continue
			
		if not cam_node is Camera3D:
			printerr("[CameraRegistrar] Node at path '%s' is not a Camera3D. Skipping." % profile.camera_node_path)
			continue

		# Build the metadata dictionary from the profile
		var metadata = {
			"name": profile.display_name,
			"priority": profile.priority,
			"transition_type": profile.transition_type.to_lower(),
			"transition_duration": profile.transition_duration,
			"description": "Camera configured by CameraRegistrar"
		}
		
		# Generate a unique ID from the node path to ensure stability
		var camera_id = str(cam_node.get_path()).to_lower().replace("/", "_")

		# Register with the manager
		camera_manager.register_camera(cam_node, camera_id, metadata)
		
	print("[CameraRegistrar] Finished processing %d camera profiles." % camera_profiles.size())
