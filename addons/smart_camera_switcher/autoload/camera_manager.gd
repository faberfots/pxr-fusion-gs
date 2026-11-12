# camera_manager.gd
extends Node

## Smart Camera Switcher - Enhanced Camera Management with View Interpolation
## Core functionality: Register cameras and switch between them with smooth transitions

# Camera storage with metadata support
var cameras: Dictionary = {}  # camera_id -> Camera3D
var camera_metadata: Dictionary = {}  # camera_id -> metadata dict
var active_camera: Camera3D = null
var active_camera_id: String = ""

# --- UPGRADE: HYBRID AUTHORITY MODEL ---
# This map tracks registered nodes by their unique instance ID to prevent duplicates
# and establish a clear authority hierarchy (Registrar > Helper).
var _node_id_to_camera_id_map: Dictionary = {}
# ----------------------------------------

# Settings cache
var settings_cache: Dictionary = {}

# Transition system
var transition_active: bool = false
var transition_tween: Tween = null
var transition_data := {
	"from_pos": Vector3.ZERO,
	"from_rot": Vector3.ZERO,
	"from_fov": 75.0,
	"to_pos": Vector3.ZERO,
	"to_rot": Vector3.ZERO,
	"to_fov": 75.0,
	"progress": 0.0,
	"duration": 0.5,
	"target_camera": null,
	"transition_mode": "smooth"  # "smooth", "instant", "teleport"
}

# Camera state preservation
var camera_states: Dictionary = {}  # camera_id -> saved state

# Signals for UI updates
signal camera_registered(camera: Camera3D, camera_id: String)
signal camera_unregistered(camera_id: String)
signal camera_switched(from_camera: Camera3D, to_camera: Camera3D)
signal camera_switch_started(target_camera: Camera3D)
signal camera_switch_completed(active_camera: Camera3D)
signal camera_list_changed
signal active_camera_changed(camera: Camera3D)
signal transition_progress(progress: float)

func _ready():
	"""Initialize camera manager with proper timing"""
	print("[CameraManager] Starting enhanced camera manager...")
	
	# Load settings
	_load_settings()
	
	# Wait for scene to be fully ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Auto-discover cameras if enabled
	if settings_cache.get("auto_register", true):
		discover_cameras()
	
	# [NEW] Auto-instantiate UI if enabled (Plug & Play feature)
	if settings_cache.get("auto_instantiate_ui", true):
		_auto_instantiate_selector_ui()
	
	print("[CameraManager] Enhanced camera manager ready!")

func _load_settings():
	"""Load settings from project settings"""
	settings_cache = {
		"activation_key": ProjectSettings.get_setting("smart_camera_switcher/activation_key", "mouse_right"),
		"ui_style": ProjectSettings.get_setting("smart_camera_switcher/ui_style", "buttons"),
		"transition_duration": ProjectSettings.get_setting("smart_camera_switcher/transition_duration", 0.5),
		"auto_hide_delay": ProjectSettings.get_setting("smart_camera_switcher/auto_hide_delay", 3.0),
		"enable_shortcuts": ProjectSettings.get_setting("smart_camera_switcher/enable_keyboard_shortcuts", true),
		"auto_register": ProjectSettings.get_setting("smart_camera_switcher/auto_register_cameras", true),
		"auto_instantiate_ui": ProjectSettings.get_setting("smart_camera_switcher/auto_instantiate_ui", true),  # [NEW] Plug & Play
		"transition_mode": ProjectSettings.get_setting("smart_camera_switcher/transition_mode", "smooth"),
		"preserve_view_on_switch": ProjectSettings.get_setting("smart_camera_switcher/preserve_view_on_switch", true)
	}

func register_camera(camera: Camera3D, camera_id: String, metadata: Dictionary = {}) -> bool:
	"""
	Register a camera with the manager
	Args:
		camera: Camera3D node to register
		camera_id: Unique identifier for the camera
		metadata: Optional metadata dictionary
	Returns:
		bool: True if registration successful
	"""
	if not is_instance_valid(camera):
		push_error("[CameraManager] Invalid camera provided for registration")
		return false
	
	if camera_id.is_empty():
		camera_id = camera.name.to_lower().replace(" ", "_")
	
	# --- UPGRADE: HYBRID AUTHORITY MODEL ---
	# Check if this specific node INSTANCE is already registered.
	var node_instance_id = camera.get_instance_id()
	if _node_id_to_camera_id_map.has(node_instance_id):
		var existing_id = _node_id_to_camera_id_map[node_instance_id]
		print("[CameraManager] Node '%s' is already registered with ID '%s'. Ignoring new request." % [camera.name, existing_id])
		return false # Indicate that no NEW registration occurred.
		
	# Also check for a genuine ID clash from a DIFFERENT node.
	if cameras.has(camera_id):
		printerr("[CameraManager] CRITICAL ID CLASH: A different camera is already using the ID '%s'. Registration failed." % camera_id)
		return false
	# ----------------------------------------
	
	# Store camera and metadata
	cameras[camera_id] = camera
	camera_metadata[camera_id] = _build_default_metadata(camera, metadata)
	
	# --- UPGRADE: HYBRID AUTHORITY MODEL ---
	# Add the node to our new tracking map.
	_node_id_to_camera_id_map[node_instance_id] = camera_id
	# ----------------------------------------
	
	# Initialize camera state
	_save_camera_state(camera_id)
	
	print("[CameraManager] Registered camera: %s (Name: %s)" % [camera_id, camera.name])
	
	# Set as active if it's the first camera or currently active in scene
	if active_camera == null or camera.current:
		set_active_camera(camera_id, false)  # No transition for first camera
	
	# Emit signals
	camera_registered.emit(camera, camera_id)
	camera_list_changed.emit()
	
	return true

func unregister_camera(camera_id: String) -> bool:
	"""
	Unregister a camera from the manager
	Args:
		camera_id: ID of camera to unregister
	Returns:
		bool: True if unregistration successful
	"""
	if camera_id not in cameras:
		print("[CameraManager] Camera not found for unregistration: %s" % camera_id)
		return false
	
	var camera = cameras[camera_id]
	
	# --- UPGRADE: HYBRID AUTHORITY MODEL ---
	# Clean up the node instance from our tracking map as well.
	if is_instance_valid(camera):
		var node_instance_id = camera.get_instance_id()
		if _node_id_to_camera_id_map.has(node_instance_id):
			_node_id_to_camera_id_map.erase(node_instance_id)
	# ----------------------------------------
	
	# If this was the active camera, switch to another one
	if camera_id == active_camera_id:
		var remaining_cameras = cameras.keys()
		remaining_cameras.erase(camera_id)
		if not remaining_cameras.is_empty():
			set_active_camera(remaining_cameras[0], false)
		else:
			active_camera = null
			active_camera_id = ""
	
	# Remove from storage
	cameras.erase(camera_id)
	camera_metadata.erase(camera_id)
	camera_states.erase(camera_id)
	
	print("[CameraManager] Unregistered camera: %s" % camera_id)
	
	# Emit signals
	camera_unregistered.emit(camera_id)
	camera_list_changed.emit()
	
	return true

# --- UPGRADE: HYBRID AUTHORITY MODEL ---
## New public function to check if a specific node instance is registered.
## This is used by helper scripts to "ask for permission" before acting.
func is_node_registered(camera_node: Camera3D) -> bool:
	if not is_instance_valid(camera_node):
		return false
	return _node_id_to_camera_id_map.has(camera_node.get_instance_id())
# ----------------------------------------

func set_active_camera(camera_id: String, use_transition: bool = true) -> bool:
	"""
	Enhanced camera switching with smooth view transitions
	Args:
		camera_id: ID of camera to activate
		use_transition: Whether to use smooth transition
	Returns:
		bool: True if switch successful
	"""
	if camera_id not in cameras:
		push_error("[CameraManager] Camera not found: %s" % camera_id)
		return false
	
	var new_camera = cameras[camera_id]
	
	# Critical fix: Validate old_camera before using it
	var old_camera = active_camera
	if old_camera and not is_instance_valid(old_camera):
		print("[CameraManager] Previous active camera was freed, resetting reference")
		old_camera = null
		active_camera = null
		active_camera_id = ""
	
	if old_camera == new_camera: # Don't switch to the camera that is already active
		return true
	
	# Cancel any ongoing transition
	if transition_tween and transition_tween.is_valid():
		transition_tween.kill()
	
	# Start transition
	camera_switch_started.emit(new_camera)
	
	# Save current camera state before switching
	if active_camera and is_instance_valid(active_camera):
		_save_camera_state(active_camera_id)
	
	# Determine transition behavior
	var should_interpolate = use_transition and old_camera != null and is_instance_valid(old_camera) and settings_cache.get("preserve_view_on_switch", true)
	
	if should_interpolate:
		# Perform smooth transition from current view to new camera
		_perform_view_transition(old_camera, new_camera, camera_id)
	else:
		# Instant switch (original behavior)
		_instant_camera_switch(old_camera, new_camera, camera_id)
	
	return true

func _perform_view_transition(from_camera: Camera3D, to_camera: Camera3D, to_camera_id: String):
	"""
	Perform smooth view transition between cameras
	"""
	print("[CameraManager] Starting smooth transition to camera: %s" % to_camera_id)
	
	# Store transition data
	transition_data.from_pos = from_camera.global_position
	transition_data.from_rot = from_camera.global_rotation
	transition_data.from_fov = from_camera.fov if from_camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 75.0
	
	# Get target state (either saved state or current position)
	var target_state = camera_states.get(to_camera_id, {})
	transition_data.to_pos = target_state.get("position", to_camera.global_position)
	transition_data.to_rot = target_state.get("rotation", to_camera.global_rotation)
	transition_data.to_fov = target_state.get("fov", to_camera.fov if to_camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 75.0)
	
	transition_data.target_camera = to_camera
	transition_data.duration = settings_cache.get("transition_duration", 0.5)
	transition_data.progress = 0.0
	
	# Deactivate old camera
	from_camera.current = false
	
	# Position new camera at current view initially
	to_camera.global_position = from_camera.global_position
	to_camera.global_rotation = from_camera.global_rotation
	if to_camera.projection == Camera3D.PROJECTION_PERSPECTIVE and from_camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		to_camera.fov = from_camera.fov
	
	# Activate new camera
	to_camera.make_current()
	active_camera = to_camera
	active_camera_id = to_camera_id
	
	# Create and start transition tween
	transition_active = true
	transition_tween = create_tween()
	transition_tween.set_ease(Tween.EASE_IN_OUT)
	transition_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Animate the transition
	transition_tween.tween_method(_update_camera_transition, 0.0, 1.0, transition_data.duration)
	transition_tween.finished.connect(_on_transition_complete)

func _update_camera_transition(progress: float):
	"""
	Update camera position/rotation during transition
	"""
	if not is_instance_valid(transition_data.target_camera):
		return
	
	transition_data.progress = progress
	var cam = transition_data.target_camera
	
	# Interpolate position
	cam.global_position = transition_data.from_pos.lerp(transition_data.to_pos, progress)
	
	# Interpolate rotation (using quaternions for smooth rotation)
	var from_quat = Quaternion.from_euler(transition_data.from_rot)
	var to_quat = Quaternion.from_euler(transition_data.to_rot)
	var interpolated_quat = from_quat.slerp(to_quat, progress)
	cam.quaternion = interpolated_quat
	
	# Interpolate FOV if perspective camera
	if cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		cam.fov = lerp(transition_data.from_fov, transition_data.to_fov, progress)
	
	# Emit progress signal
	transition_progress.emit(progress)

func _on_transition_complete():
	"""
	Handle transition completion
	"""
	transition_active = false
	print("[CameraManager] Transition complete to camera: %s" % active_camera_id)
	
	# Emit completion signals
	camera_switch_completed.emit(active_camera)
	active_camera_changed.emit(active_camera)

func _instant_camera_switch(from_camera: Camera3D, to_camera: Camera3D, to_camera_id: String):
	"""
	Instant camera switch (original behavior) with scene tree safety
	"""
	# Deactivate current camera (handle null from_camera)
	if from_camera != null and is_instance_valid(from_camera) and from_camera.is_inside_tree():
		from_camera.current = false
	
	# Check if target camera is still valid and in tree
	if not is_instance_valid(to_camera) or not to_camera.is_inside_tree():
		print("[CameraManager] Warning: Target camera not in tree during switch")
		# Still update our references even if camera isn't in tree
		active_camera = to_camera if is_instance_valid(to_camera) else null
		active_camera_id = to_camera_id
		return
	
	# Restore saved state if available
	if to_camera_id in camera_states:
		var state = camera_states[to_camera_id]
		to_camera.global_position = state.get("position", to_camera.global_position)
		to_camera.global_rotation = state.get("rotation", to_camera.global_rotation)
		if to_camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
			to_camera.fov = state.get("fov", to_camera.fov)
	
	# Activate new camera
	to_camera.make_current()
	active_camera = to_camera
	active_camera_id = to_camera_id
	
	print("[CameraManager] Switched to camera: %s (instant)" % to_camera_id)
	
	# Emit signals (check for null from_camera)
	if from_camera != null and from_camera != to_camera:
		camera_switched.emit(from_camera, to_camera)
	active_camera_changed.emit(to_camera)
	camera_switch_completed.emit(to_camera)

func _save_camera_state(camera_id: String):
	"""
	Save current state of a camera with scene tree safety
	"""
	if camera_id not in cameras:
		return
	
	var camera = cameras[camera_id]
	if not is_instance_valid(camera):
		return
	
	# Check if camera is still in the scene tree
	if not camera.is_inside_tree():
		return
	
	camera_states[camera_id] = {
		"position": camera.global_position,
		"rotation": camera.global_rotation,
		"fov": camera.fov if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 75.0,
		"timestamp": Time.get_ticks_msec()
	}

func cycle_cameras(direction: int = 1) -> bool:
	"""
	Cycle through cameras with smooth transitions
	Args:
		direction: 1 for next, -1 for previous
	Returns:
		bool: True if cycling successful
	"""
	var camera_ids = cameras.keys()
	camera_ids.sort() # Ensure consistent order
	if camera_ids.is_empty():
		return false
	
	var current_index = 0
	if active_camera_id in camera_ids:
		current_index = camera_ids.find(active_camera_id)
	
	# Calculate next index with wrapping
	var next_index = (current_index + direction) % camera_ids.size()
	if next_index < 0:
		next_index = camera_ids.size() - 1
	
	return set_active_camera(camera_ids[next_index])

func auto_register_cameras_in_scene(scene_root: Node = null) -> int:
	"""
	Auto-register all Camera3D nodes in a scene
	Args:
		scene_root: Root node to search (current scene if null)
	Returns:
		int: Number of cameras registered
	"""
	if not scene_root:
		scene_root = get_tree().current_scene
	
	if not scene_root:
		print("[CameraManager] No scene root available for auto-registration")
		return 0
	
	var found_cameras = _find_all_cameras(scene_root)
	var registered_count = 0
	
	for camera in found_cameras:
		var camera_id = camera.name.to_lower().replace(" ", "_")
		if register_camera(camera, camera_id):
			registered_count += 1
	
	print("[CameraManager] Auto-registered %d cameras" % registered_count)
	return registered_count

func discover_cameras():
	"""Find all cameras in current scene and register them"""
	# Clean up any invalid references first
	_cleanup_invalid_cameras()
	
	var scene_root = get_tree().current_scene
	if not scene_root:
		print("[CameraManager] No current scene for camera discovery")
		return
	
	auto_register_cameras_in_scene(scene_root)

func _cleanup_invalid_cameras():
	"""Remove any invalid camera references from storage"""
	var to_remove = []
	
	for camera_id in cameras:
		if not is_instance_valid(cameras[camera_id]):
			to_remove.append(camera_id)
			print("[CameraManager] Cleaning up invalid camera: %s" % camera_id)
	
	for camera_id in to_remove:
		unregister_camera(camera_id) # Use the proper unregister function to ensure full cleanup
	
	# Clean up active camera reference if invalid
	if active_camera and not is_instance_valid(active_camera):
		active_camera = null
		active_camera_id = ""
		print("[CameraManager] Cleaned up invalid active camera reference")
	
	if not to_remove.is_empty():
		camera_list_changed.emit()

func _find_all_cameras(node: Node) -> Array[Camera3D]:
	"""Recursively find all Camera3D nodes"""
	var found_cameras: Array[Camera3D] = []
	
	if node is Camera3D:
		found_cameras.append(node)
	
	for child in node.get_children():
		found_cameras.append_array(_find_all_cameras(child))
	
	return found_cameras

func _build_default_metadata(camera: Camera3D, provided_metadata: Dictionary) -> Dictionary:
	"""Build complete metadata with defaults"""
	var metadata = {
		"name": camera.name.capitalize(),
		"description": "Camera: " + camera.name,
		"icon": "res://addons/smart_camera_switcher/icons/camera_default.svg",
		"priority": 0,
		"transition_type": "smooth",
		"transition_duration": settings_cache.get("transition_duration", 0.5),
		"camera_type": "default",
		"node_path": str(camera.get_path()),
		"auto_registered": false,
		"preserve_state": true  # Whether to preserve camera state between switches
	}
	
	# Merge with provided metadata
	for key in provided_metadata:
		metadata[key] = provided_metadata[key]
	
	return metadata

# Enhanced API methods
func set_transition_mode(mode: String):
	"""
	Set the transition mode for camera switches
	Args:
		mode: "smooth", "instant", or "teleport"
	"""
	if mode in ["smooth", "instant", "teleport"]:
		settings_cache["transition_mode"] = mode
		print("[CameraManager] Transition mode set to: %s" % mode)

func set_transition_duration(duration: float):
	"""
	Set the duration for smooth transitions
	Args:
		duration: Time in seconds for transition
	"""
	settings_cache["transition_duration"] = max(0.1, duration)
	print("[CameraManager] Transition duration set to: %.2f seconds" % duration)

func set_preserve_view_on_switch(preserve: bool):
	"""
	Toggle whether to preserve current view when switching cameras
	Args:
		preserve: If true, new camera starts from current view
	"""
	settings_cache["preserve_view_on_switch"] = preserve
	print("[CameraManager] Preserve view on switch: %s" % preserve)

func reset_camera_state(camera_id: String):
	"""
	Reset a camera to its original state
	Args:
		camera_id: ID of camera to reset
	"""
	if camera_id in camera_states:
		camera_states.erase(camera_id)
		print("[CameraManager] Reset state for camera: %s" % camera_id)

func save_all_camera_states():
	"""
	Save the current state of all registered cameras
	"""
	for camera_id in cameras:
		_save_camera_state(camera_id)
	print("[CameraManager] Saved states for all cameras")

# Getter methods for API compatibility
func get_registered_cameras() -> Dictionary:
	"""Get all registered cameras"""
	return cameras.duplicate()

func get_camera_metadata(camera_id: String) -> Dictionary:
	"""Get metadata for a specific camera"""
	return camera_metadata.get(camera_id, {})

func get_active_camera() -> Camera3D:
	"""Get currently active camera"""
	return active_camera

func get_active_camera_id() -> String:
	"""Get ID of currently active camera"""
	return active_camera_id

func get_camera_list() -> Dictionary:
	"""Alias for get_registered_cameras for UI compatibility"""
	# The UI expects a dictionary of id -> {node, metadata}
	# This script stores them separately, so we must build the expected structure.
	var list = {}
	for id in cameras:
		list[id] = {
			"node": cameras[id],
			"metadata": camera_metadata.get(id, {})
		}
	return list

func get_settings() -> Dictionary:
	"""Get current settings"""
	return settings_cache.duplicate()

func is_transitioning() -> bool:
	"""Check if a transition is currently active"""
	return transition_active

func get_transition_progress() -> float:
	"""Get current transition progress (0.0 to 1.0)"""
	return transition_data.progress if transition_active else 0.0

# Utility methods
func is_camera_registered(camera_id: String) -> bool:
	"""Check if a camera is registered"""
	return camera_id in cameras

func get_camera_count() -> int:
	"""Get number of registered cameras"""
	return cameras.size()

func clear_all_cameras():
	"""Clear all registered cameras (for cleanup)"""
	var keys_to_unregister = cameras.keys()
	for key in keys_to_unregister:
		unregister_camera(key)

func unregister_all_cameras() -> void:
	"""Unregister all cameras and reset state - with safety checks"""
	print("[CameraManager] Unregistering all cameras...")
	
	# Check if we're still in the tree
	if not is_inside_tree():
		print("[CameraManager] Not in tree, performing quick cleanup")
		# Just clear the dictionaries without trying to access node properties
		cameras.clear()
		camera_metadata.clear()
		camera_states.clear()
		_node_id_to_camera_id_map.clear()
		active_camera = null
		active_camera_id = ""
		return
	
	# Normal unregistration process
	clear_all_cameras()

func set_camera_transform(camera_id: String, position: Vector3, rotation: Vector3, fov: float) -> void:
	"""
	Smartly and safely sets the position, rotation, and field of view for a specific registered camera
	"""
	# Input Validation
	if not camera_id or camera_id.is_empty():
		printerr("[CameraManager] ERROR: set_camera_transform() called with an empty camera_id.")
		return

	if not position is Vector3:
		printerr("[CameraManager] ERROR: Invalid 'position' data for camera '%s'. Expected Vector3." % camera_id)
		return

	if not rotation is Vector3:
		printerr("[CameraManager] ERROR: Invalid 'rotation' data for camera '%s'. Expected Vector3." % camera_id)
		return

	# Find the Camera
	if not cameras.has(camera_id):
		printerr("[CameraManager] ERROR: Cannot set transform. Camera with ID '%s' is not registered." % camera_id)
		return

	# Validate the Camera Node
	var camera_node = cameras[camera_id]
	if not is_instance_valid(camera_node):
		printerr("[CameraManager] ERROR: Camera node for ID '%s' is invalid (likely freed). Cannot set transform." % camera_id)
		unregister_camera(camera_id) # Use unregister to clean up properly
		return

	# Apply the Transform
	print("[CameraManager] Applying transform to camera '%s'..." % camera_id)
	camera_node.global_position = position
	camera_node.rotation = rotation
	if camera_node.projection == Camera3D.PROJECTION_PERSPECTIVE:
		camera_node.fov = fov
	
	# Update saved state
	_save_camera_state(camera_id)
	
	print("[CameraManager] ✔ Successfully updated transform for camera: %s" % camera_node.name)


# =============================================================================
# [NEW] PLUG & PLAY: Auto UI Instantiation
# =============================================================================
# This function automatically creates the camera selector UI and adds it to
# the scene tree. Users don't need to manually add the scene to their project.
# =============================================================================
var _selector_ui_instance: Node = null

func _auto_instantiate_selector_ui() -> void:
	"""Auto-instantiate the Camera Selector UI for plug & play operation"""
	
	# Prevent duplicate instantiation
	if is_instance_valid(_selector_ui_instance):
		print("[CameraManager] Selector UI already instantiated, skipping")
		return
	
	# Check if UI scene exists
	const UI_SCENE_PATH = "res://addons/smart_camera_switcher/scenes/camera_selector_ui.tscn"
	if not FileAccess.file_exists(UI_SCENE_PATH):
		push_warning("[CameraManager] Camera selector UI scene not found at: %s" % UI_SCENE_PATH)
		return
	
	# Load and instantiate the UI scene
	var ui_scene = load(UI_SCENE_PATH)
	if not ui_scene:
		push_error("[CameraManager] Failed to load camera selector UI scene")
		return
	
	_selector_ui_instance = ui_scene.instantiate()
	if not _selector_ui_instance:
		push_error("[CameraManager] Failed to instantiate camera selector UI")
		return
	
	# Add to scene tree (use a CanvasLayer for proper UI layering)
	# We add it to the root viewport to ensure it's always accessible
	var root = get_tree().root
	if root:
		root.call_deferred("add_child", _selector_ui_instance)
		print("[CameraManager] ✔ Auto-instantiated Camera Selector UI (Plug & Play)")
	else:
		push_warning("[CameraManager] No root viewport found for UI instantiation")
		_selector_ui_instance.queue_free()
		_selector_ui_instance = null

func get_selector_ui() -> Node:
	"""Get the auto-instantiated selector UI instance"""
	return _selector_ui_instance

func destroy_selector_ui() -> void:
	"""Manually destroy the auto-instantiated UI (for cleanup)"""
	if is_instance_valid(_selector_ui_instance):
		_selector_ui_instance.queue_free()
		_selector_ui_instance = null
		print("[CameraManager] Selector UI destroyed")
