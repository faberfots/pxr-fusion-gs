@tool
extends Camera3D
class_name SmartCameraNode

## Smart Camera Switcher - Fixed Camera Registration Helper
## Attach this script to any Camera3D node for automatic registration with proper error handling

# Camera metadata that can be configured in the inspector
@export_group("Smart Camera Settings")
@export var camera_display_name: String = ""
@export_multiline var camera_description: String = ""
@export var camera_icon: Texture2D
@export var camera_priority: int = 0
@export var transition_type: TransitionType = TransitionType.SMOOTH
@export var transition_duration: float = 0.5
@export var auto_register: bool = true

@export_group("Camera Type")
@export var camera_type: CameraType = CameraType.DEFAULT

# Enums for editor dropdowns
enum TransitionType {
	INSTANT,
	SMOOTH,
	FADE
}

enum CameraType {
	DEFAULT,
	MAIN,
	SECONDARY,
	DEBUG,
	CINEMATIC,
	UI_OVERLAY
}

# Internal state
var is_registered: bool = false
var camera_id: String = ""
var camera_manager: Node = null

# Signal for registration events
signal camera_registered_successfully(camera_id: String)
signal camera_registration_failed(error: String)

func _ready():
	"""Initialize the smart camera node with proper timing"""
	if Engine.is_editor_hint():
		return
	
	print("[SmartCameraNode] Initializing smart camera: %s" % name)
	
	# Auto-register if enabled
	if auto_register:
		_delayed_register()

func _delayed_register():
	"""Register camera with proper timing to avoid race conditions"""
	# Wait for scene tree to be fully ready
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame  # Extra wait for complex scenes
	
	# Wait for CameraManager to be available
	var max_attempts = 10
	var attempt = 0
	
	while attempt < max_attempts:
		camera_manager = get_node_or_null("/root/CameraManager")
		if camera_manager:
			break
		
		print("[SmartCameraNode] Waiting for CameraManager... (attempt %d)" % (attempt + 1))
		await get_tree().create_timer(0.1).timeout
		attempt += 1
	
	if not camera_manager:
		var error_msg = "CameraManager not available after %d attempts - ensure plugin is enabled" % max_attempts
		push_error("[SmartCameraNode] " + error_msg)
		camera_registration_failed.emit(error_msg)
		return
	
	# Now register
	register_camera()

func register_camera(custom_id: String = "", force_register: bool = false) -> bool:
	"""
	Register this camera with the CameraManager
	Args:
		custom_id: Custom ID to use (auto-generated if empty)
		force_register: Re-register even if already registered
	Returns:
		bool: True if registration successful
	"""
	if is_registered and not force_register:
		print("[SmartCameraNode] Camera '%s' already registered" % camera_id)
		return true
	
	# Ensure camera manager is available
	if not camera_manager:
		camera_manager = get_node_or_null("/root/CameraManager")
		if not camera_manager:
			var error_msg = "CameraManager not available - ensure plugin is enabled"
			push_error("[SmartCameraNode] " + error_msg)
			camera_registration_failed.emit(error_msg)
			return false

	# UPGRADE: Ask for permission before registering. If another system (like
	# CameraRegistrar) has already handled this node, we gracefully do nothing.
	if camera_manager.is_node_registered(self) and not force_register:
		print("[SmartCameraNode] Skipping auto-registration for '%s'; it has already been registered by a higher-authority system." % name)
		# For this script's state, the camera IS in the system, so we consider it a success.
		is_registered = true 
		return true
	
	# Generate camera ID
	if custom_id.is_empty():
		camera_id = _generate_camera_id()
	else:
		camera_id = custom_id
	
	# Build metadata
	var metadata = _build_camera_metadata()
	
	# Register with CameraManager using the correct API
	var success = camera_manager.register_camera(self, camera_id, metadata)
	
	if success:
		is_registered = true
		camera_registered_successfully.emit(camera_id)
		print("[SmartCameraNode] Successfully registered camera '%s'" % camera_id)
	else:
		# UPGRADE: The error message is now more informative, accounting for potential ID clashes
		# or race conditions if force_register isn't used.
		var error_msg = "Failed to register camera '%s'. The ID might already be in use by another node." % camera_id
		#push_error("[SmartCameraNode] " + error_msg) # This can be noisy, so it's safe to comment out.
		camera_registration_failed.emit(error_msg)
	
	return success

func unregister_camera() -> bool:
	"""
	Unregister this camera from the CameraManager
	Returns:
		bool: True if unregistration successful
	"""
	if not is_registered:
		print("[SmartCameraNode] Camera '%s' not registered" % name)
		return true
	
	if not camera_manager:
		camera_manager = get_node_or_null("/root/CameraManager")
		if not camera_manager:
			push_error("[SmartCameraNode] CameraManager not available")
			return false
	
	var success = camera_manager.unregister_camera(camera_id)
	
	if success:
		is_registered = false
		print("[SmartCameraNode] Successfully unregistered camera '%s'" % camera_id)
	
	return success

func _build_camera_metadata() -> Dictionary:
	"""Build metadata dictionary for camera registration"""
	var metadata = {}
	
	# Display name
	if camera_display_name.is_empty():
		metadata["name"] = name.capitalize()
	else:
		metadata["name"] = camera_display_name
	
	# Description
	if camera_description.is_empty():
		metadata["description"] = "Camera: " + metadata["name"]
	else:
		metadata["description"] = camera_description
	
	# Icon
	metadata["icon"] = _get_icon_path()
	
	# Priority
	metadata["priority"] = camera_priority
	
	# Transition settings
	metadata["transition_type"] = _transition_type_to_string()
	metadata["transition_duration"] = max(0.1, transition_duration)  # Ensure minimum duration
	
	# Camera type for styling
	metadata["camera_type"] = _camera_type_to_string()
	
	# Additional metadata
	metadata["node_path"] = str(get_path())
	metadata["auto_registered"] = auto_register
	metadata["scene_file"] = get_scene_file_path()
	
	return metadata

func _generate_camera_id() -> String:
	"""Generate a unique camera ID"""
	var base_id = name.to_lower().replace(" ", "_")
	
	# Remove invalid characters
	base_id = base_id.replace("@", "").replace("#", "").replace("$", "")
	
	# Add camera type prefix if not default
	if camera_type != CameraType.DEFAULT:
		var type_prefix = _camera_type_to_string().to_lower()
		base_id = type_prefix + "_" + base_id
	
	# Ensure uniqueness by adding node path hash if needed
	if camera_manager and camera_manager.is_camera_registered(base_id):
		var path_hash = str(get_path()).hash()
		var hash_str = str(abs(path_hash))
		# Take first 6 characters using substr instead of slice
		if hash_str.length() > 6:
			hash_str = hash_str.substr(0, 6)
		base_id += "_" + hash_str
	
	return base_id

func _transition_type_to_string() -> String:
	"""Convert transition type enum to string"""
	match transition_type:
		TransitionType.INSTANT:
			return "instant"
		TransitionType.SMOOTH:
			return "smooth"
		TransitionType.FADE:
			return "fade"
		_:
			return "smooth"

func _camera_type_to_string() -> String:
	"""Convert camera type enum to string"""
	match camera_type:
		CameraType.DEFAULT:
			return "default"
		CameraType.MAIN:
			return "main"
		CameraType.SECONDARY:
			return "secondary"
		CameraType.DEBUG:
			return "debug"
		CameraType.CINEMATIC:
			return "cinematic"
		CameraType.UI_OVERLAY:
			return "ui_overlay"
		_:
			return "default"

func _get_icon_path() -> String:
	"""Get path for camera icon with fallback"""
	if camera_icon and camera_icon.resource_path:
		return camera_icon.resource_path
	else:
		return _get_default_icon_path()

func _get_default_icon_path() -> String:
	"""Get default icon path based on camera type with fallback"""
	var base_path = "res://addons/smart_camera_switcher/icons/"
	var icon_file = ""
	
	match camera_type:
		CameraType.MAIN:
			icon_file = "camera_main.svg"
		CameraType.SECONDARY:
			icon_file = "camera_secondary.svg"
		CameraType.DEBUG:
			icon_file = "camera_debug.svg"
		CameraType.CINEMATIC:
			icon_file = "camera_cinematic.svg"
		CameraType.UI_OVERLAY:
			icon_file = "camera_ui.svg"
		_:
			icon_file = "camera_default.svg"
	
	var full_path = base_path + icon_file
	
	# Check if file exists, use fallback if not
	if not FileAccess.file_exists(full_path):
		# Try without extension
		var fallback_path = base_path + "camera_default"
		if FileAccess.file_exists(fallback_path + ".png"):
			return fallback_path + ".png"
		elif FileAccess.file_exists(fallback_path + ".svg"):
			return fallback_path + ".svg"
		else:
			# Return empty string if no icon available
			return ""
	
	return full_path

# ============================================================================
# CONVENIENCE METHODS
# ============================================================================

func set_as_active() -> bool:
	"""Set this camera as the active camera"""
	if not is_registered:
		push_error("[SmartCameraNode] Camera must be registered before setting as active")
		return false
	
	if not camera_manager:
		push_error("[SmartCameraNode] CameraManager not available")
		return false
	
	return camera_manager.set_active_camera(camera_id)

func is_active_camera() -> bool:
	"""Check if this is the currently active camera"""
	if not is_registered or not camera_manager:
		return false
	
	return camera_manager.get_active_camera() == self

func update_metadata() -> bool:
	"""Update camera metadata in the system"""
	if not is_registered:
		print("[SmartCameraNode] Camera not registered, cannot update metadata")
		return false
	
	# Re-register with updated metadata
	return register_camera(camera_id, true)

func get_camera_info() -> Dictionary:
	"""Get current camera information"""
	return {
		"id": camera_id,
		"name": camera_display_name if not camera_display_name.is_empty() else name,
		"is_registered": is_registered,
		"is_active": is_active_camera(),
		"metadata": _build_camera_metadata()
	}

# ============================================================================
# EDITOR INTEGRATION (TOOL MODE)
# ============================================================================

func _get_configuration_warnings() -> PackedStringArray:
	"""Provide configuration warnings in the editor"""
	var warnings = PackedStringArray()
	
	if camera_display_name.is_empty():
		warnings.append("Consider setting a display name for better identification in the camera selector")
	
	if transition_duration <= 0.0:
		warnings.append("Transition duration should be greater than 0")
	
	if transition_duration > 5.0:
		warnings.append("Very long transition duration may feel unresponsive")
	
	# Check for duplicate names in the scene
	if Engine.is_editor_hint() and get_parent():
		var siblings = get_parent().get_children()
		var similar_names = 0
		for sibling in siblings:
			if sibling != self and sibling is Camera3D and sibling.name == name:
				similar_names += 1
		
		if similar_names > 0:
			warnings.append("Multiple cameras with the same name may cause ID conflicts")
	
	return warnings

func _validate_property(property: Dictionary):
	"""Validate properties in the editor"""
	match property.name:
		"transition_duration":
			property.hint_string = "0.1,5.0,0.1"
		"camera_priority":
			property.hint_string = "-100,100,1"

# ============================================================================
# STATIC UTILITY FUNCTIONS
# ============================================================================

static func register_camera_node(camera: Camera3D, camera_id: String = "", metadata: Dictionary = {}) -> bool:
	"""
	Static helper to register any Camera3D node
	Args:
		camera: Camera3D node to register
		camera_id: Custom ID (auto-generated if empty)
		metadata: Additional metadata
	Returns:
		bool: True if registration successful
	"""
	var camera_manager = camera.get_node_or_null("/root/CameraManager")
	if not camera_manager:
		push_error("[SmartCameraNode] CameraManager not available")
		return false
	
	# Generate ID if not provided
	if camera_id.is_empty():
		camera_id = camera.name.to_lower().replace(" ", "_")
	
	# Default metadata
	var default_metadata = {
		"name": camera.name.capitalize(),
		"description": "Camera: " + camera.name,
		"icon": "",
		"priority": 0,
		"transition_type": "smooth",
		"transition_duration": 0.5,
		"camera_type": "default",
		"node_path": str(camera.get_path()),
		"auto_registered": false
	}
	
	# Merge with provided metadata
	for key in metadata:
		default_metadata[key] = metadata[key]
	
	return camera_manager.register_camera(camera, camera_id, default_metadata)

static func auto_register_scene_cameras(scene_root: Node = null) -> int:
	"""
	Auto-register all Camera3D nodes in a scene
	Args:
		scene_root: Root node to search (current scene if null)
	Returns:
		int: Number of cameras registered
	"""
	if not scene_root:
		scene_root = Engine.get_main_loop().current_scene
	
	if not scene_root:
		push_error("[SmartCameraNode] No scene root available")
		return 0
	
	var camera_manager = scene_root.get_node_or_null("/root/CameraManager")
	if not camera_manager:
		push_error("[SmartCameraNode] CameraManager not available")
		return 0
	
	return camera_manager.auto_register_cameras_in_scene(scene_root)

# ============================================================================
# SIGNALS AND CALLBACKS
# ============================================================================

func _on_tree_exiting():
	"""Clean up when node is removed from tree"""
	if is_registered:
		unregister_camera()

func _notification(what):
	"""Handle node notifications"""
	match what:
		NOTIFICATION_PREDELETE:
			if is_registered:
				unregister_camera()
		NOTIFICATION_SCENE_INSTANTIATED:
			# Scene has been instantiated, safe to register
			if auto_register and not Engine.is_editor_hint():
				_delayed_register()

# ============================================================================
# PROPERTY CHANGE HANDLING
# ============================================================================

func _on_property_changed():
	"""Handle property changes in editor"""
	if Engine.is_editor_hint():
		notify_property_list_changed()
		update_configuration_warnings()

# Connect property changes if in editor
func _init():
	if Engine.is_editor_hint():
		# This will trigger configuration warnings updates
		set_notify_transform(true)
