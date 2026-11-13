class_name CameraController
extends Node
## Orchestrates camera behavior and provides a clean interface between cameras and the viewer
## 
## Responsibilities:
## - Manage active camera instance
## - Handle camera switching at runtime
## - Forward input events to active camera
## - Aggregate camera signals for viewer consumption
## - Validate camera state periodically
## 
## This decouples the viewer from specific camera implementations, allowing
## cameras to be swapped without modifying viewer code.

#region Signals
## Forwarded from active camera - viewer uses this to trigger render optimizations
signal camera_movement_changed(is_moving: bool)

## Forwarded from active camera - viewer uses this to update cursor/focus point
signal camera_focus_requested(target_position: Vector3)

## Forwarded from active camera - viewer/UI can display current mode
signal camera_mode_changed(mode_string: String)

## Emitted when camera is switched at runtime
signal camera_switched(old_camera: CameraInterface, new_camera: CameraInterface)

## Emitted when camera state validation fails
signal camera_validation_failed(camera: CameraInterface, reason: String)

#endregion

#region Configuration
## How often to validate camera state (seconds)
## Set to 0 to disable automatic validation
@export_range(0.0, 5.0, 0.1) var validation_interval : float = 1.0

## Whether to auto-reset camera on validation failure
@export var auto_reset_on_validation_failure : bool = true

## Enable debug logging
@export var enable_debug_logging : bool = false
@export var ground: Node3D
@export var home_on_ready := false
@export var safety: GSCameraSafetySettings = GSCameraSafetySettings.new()
var _safe_pose := Transform3D.IDENTITY
var _has_safe_pose := false
var _collision_sphere := SphereShape3D.new()
#endregion

#region State
## Currently active camera
var active_camera : CameraInterface = null
var _movement_blockers: Dictionary = {}

## Validation timer
var _validation_timer : float = 0.0

## Last known movement state (for change detection)
var _last_movement_state : bool = false

#endregion

#region Initialization
func _ready() -> void:
	# Auto-detect camera if not set
	if not active_camera:
		_auto_detect_camera()
	if home_on_ready: go_home.call_deferred()
	
	if enable_debug_logging:
		print("[CameraController] Initialized with camera: %s" % (active_camera.get_class() if active_camera else "None"))

## Automatically detect and set first CameraInterface child
func _auto_detect_camera() -> void:
	for child in get_children():
		if child is CameraInterface:
			set_camera(child)
			if enable_debug_logging:
				print("[CameraController] Auto-detected camera: %s" % child.get_class())
			return
	
	push_warning("[CameraController] No CameraInterface found in children")
#endregion

#region Camera Management
## Set the active camera (switches cameras at runtime)
func set_camera(new_camera: CameraInterface) -> void:
	if not new_camera:
		push_error("[CameraController] Cannot set null camera")
		return
	
	if not new_camera is CameraInterface:
		push_error("[CameraController] Camera must extend CameraInterface")
		return
	
	var old_camera := active_camera
	
	# Disconnect old camera signals
	if old_camera:
		_disconnect_camera_signals(old_camera)
		old_camera.current = false
		old_camera.enable_camera_movement = false
	
	# Set new camera
	active_camera = new_camera
	active_camera.current = true
	if is_instance_valid(ground):
		active_camera.global_transform = constrain_pose(active_camera.global_transform, active_camera.global_transform)
	_safe_pose = active_camera.global_transform
	_has_safe_pose = true
	for child in get_children():
		if child is CameraInterface:
			child.enable_camera_movement = child == active_camera and _movement_blockers.is_empty()
	
	# Connect new camera signals
	_connect_camera_signals(active_camera)
	
	# Emit switch event
	camera_switched.emit(old_camera, new_camera)
	
	if enable_debug_logging:
		print("[CameraController] Switched camera: %s -> %s" % [
			old_camera.get_class() if old_camera else "None",
			new_camera.get_class()
		])

## Get the active camera
func get_camera() -> CameraInterface:
	return active_camera

## Connect to camera's signals
func _connect_camera_signals(camera: CameraInterface) -> void:
	if not camera:
		return
	
	# Forward camera signals
	if not camera.movement_state_changed.is_connected(_on_camera_movement_changed):
		camera.movement_state_changed.connect(_on_camera_movement_changed)
	
	if not camera.focus_requested.is_connected(_on_camera_focus_requested):
		camera.focus_requested.connect(_on_camera_focus_requested)
	
	if not camera.mode_changed.is_connected(_on_camera_mode_changed):
		camera.mode_changed.connect(_on_camera_mode_changed)

## Disconnect from camera's signals
func _disconnect_camera_signals(camera: CameraInterface) -> void:
	if not camera:
		return
	
	if camera.movement_state_changed.is_connected(_on_camera_movement_changed):
		camera.movement_state_changed.disconnect(_on_camera_movement_changed)
	
	if camera.focus_requested.is_connected(_on_camera_focus_requested):
		camera.focus_requested.disconnect(_on_camera_focus_requested)
	
	if camera.mode_changed.is_connected(_on_camera_mode_changed):
		camera.mode_changed.disconnect(_on_camera_mode_changed)
#endregion

#region Signal Forwarding
func _on_camera_movement_changed(is_moving: bool) -> void:
	_last_movement_state = is_moving
	camera_movement_changed.emit(is_moving)
	
	if enable_debug_logging:
		print("[CameraController] Movement: %s" % ("Moving" if is_moving else "Stopped"))

func _on_camera_focus_requested(target_position: Vector3) -> void:
	camera_focus_requested.emit(target_position)
	
	if enable_debug_logging:
		print("[CameraController] Focus requested: %v" % target_position)

func _on_camera_mode_changed(mode_string: String) -> void:
	camera_mode_changed.emit(mode_string)
	
	if enable_debug_logging:
		print("[CameraController] Mode changed: %s" % mode_string)
#endregion

#region Camera Control API (Called by Viewer/UI)
## Enable/disable camera movement
func set_movement_enabled(enabled: bool) -> void:
	set_movement_blocker("legacy", not enabled)

func set_movement_blocker(owner_id: StringName, blocked: bool) -> void:
	if blocked:
		_movement_blockers[owner_id] = true
	else:
		_movement_blockers.erase(owner_id)
	if is_instance_valid(active_camera):
		active_camera.enable_camera_movement = _movement_blockers.is_empty()

func is_movement_blocked() -> bool:
	return not _movement_blockers.is_empty()

func reset_camera() -> void:
	if not active_camera:
		push_warning("[CameraController] No active camera to reset")
		return
	
	active_camera.reset()
	if home_on_ready: go_home()
	
	if enable_debug_logging:
		print("[CameraController] Camera reset")

## Set camera to focus on a specific position
func focus_on_position(target_position: Vector3) -> void:
	if not active_camera:
		push_warning("[CameraController] No active camera to focus")
		return
	
	active_camera.set_focused_position(target_position)
	
	if enable_debug_logging:
		print("[CameraController] Focus set: %v" % target_position)

## Update camera settings (forwarded from config)
func apply_settings(settings: Dictionary) -> void:
	if not active_camera:
		return
	
	if settings.has("mouse_sensitivity"):
		active_camera.mouse_sensitivity = settings.mouse_sensitivity
	
	if settings.has("run_speed_multiplier"):
		active_camera.run_speed_multiplier = settings.run_speed_multiplier
	
	if settings.has("acceleration"):
		active_camera.acceleration = settings.acceleration
	
	if settings.has("deceleration"):
		active_camera.deceleration = settings.deceleration
	
	if settings.has("vel_multiplier"):
		active_camera.vel_multiplier = settings.vel_multiplier
	
	if settings.has("fov"):
		active_camera.fov = settings.fov
	
	if enable_debug_logging:
		print("[CameraController] Applied %d camera settings" % settings.size())

## Get current camera state for UI display
func get_camera_state() -> Dictionary:
	if not active_camera:
		return {
			"has_camera": false,
			"is_moving": false,
			"mode": "No Camera"
		}
	
	return {
		"has_camera": true,
		"is_moving": active_camera.is_moving(),
		"mode": active_camera.get_mode_string(),
		"position": active_camera.global_position,
		"rotation_degrees": active_camera.rotation_degrees,
		"velocity": active_camera.get_velocity(),
		"fov": active_camera.fov
	}

## ============================================================================
## PUBLIC API: Set Camera Transform
## ============================================================================
## Sets the camera's global transform and resets movement state.
## This is the preferred way for external systems to position the camera.
##
## @param transform: The desired global transform for the camera
## ============================================================================
func set_camera_transform(transform: Transform3D) -> void:
	var camera := get_camera()
	if not camera:
		push_warning("[CameraController] Cannot set transform: no camera")
		return
	
	# Apply transform
	camera.global_transform = constrain_pose(camera.global_transform, transform)
	_safe_pose = camera.global_transform
	_has_safe_pose = true
	
	# Reset camera's internal state to prevent override
	if camera.has_method("reset_movement_state"):
		camera.reset_movement_state()
	
	print("[CameraController] Camera transform set to: %s" % active_camera.global_position)

func go_home() -> void:
	position_camera_at(safety.home_position, safety.home_target)

func set_protection(enabled: bool) -> void:
	safety.protected_fly = enabled
	if enabled and active_camera:
		set_camera_transform(active_camera.global_transform)

func ground_height() -> float:
	if not is_instance_valid(ground): return -INF
	if ground is CSGBox3D:
		return ground.to_global(Vector3(0, ground.size.y * 0.5, 0)).y
	return ground.global_position.y

func constrain_pose(previous: Transform3D, desired: Transform3D) -> Transform3D:
	if not safety.protected_fly or not is_instance_valid(ground): return desired
	var minimum := ground_height() + safety.radius + safety.margin
	desired.origin.y = maxf(desired.origin.y, minimum)
	if not Engine.is_in_physics_frame() or not active_camera: return desired
	var start := previous.origin
	start.y = maxf(start.y, minimum)
	var motion := desired.origin - start
	if motion.length_squared() < 0.00000001: return desired
	_collision_sphere.radius = safety.radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_sphere
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = motion
	query.margin = safety.margin
	query.collision_mask = safety.collision_mask
	query.collide_with_areas = false
	var state := active_camera.get_world_3d().direct_space_state
	var fractions := state.cast_motion(query)
	if fractions.size() == 2 and fractions[0] < 1.0:
		var safe_fraction := maxf(0.0, fractions[0] - safety.margin / maxf(motion.length(), 0.001))
		var reached := start + motion * safe_fraction
		query.transform.origin = start + motion * fractions[1]
		query.motion = Vector3.ZERO
		var hit := state.get_rest_info(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			var slide := (motion * (1.0 - safe_fraction)).slide(normal)
			query.transform.origin = reached
			query.motion = slide
			var remainder := state.cast_motion(query)
			if remainder.size() == 2: reached += slide * maxf(0, remainder[0] - 0.001)
			if active_camera is FreeLookCamera:
				active_camera.velocity = active_camera.velocity.slide(normal)
		desired.origin = reached
	desired.origin.y = maxf(desired.origin.y, minimum)
	return desired

func _physics_process(_delta: float) -> void:
	if not active_camera: return
	var desired := active_camera.global_transform
	var resolved := constrain_pose(_safe_pose if _has_safe_pose else desired, desired)
	if not resolved.origin.is_equal_approx(desired.origin):
		active_camera.global_transform = resolved
		if active_camera is FreeLookCamera:
			active_camera.velocity.y = maxf(0, active_camera.velocity.y) if resolved.origin.y <= ground_height() + safety.radius + safety.margin + 0.001 else active_camera.velocity.y
	_safe_pose = resolved
	_has_safe_pose = true


## ============================================================================
## PUBLIC API: Position Camera Looking At Target
## ============================================================================
## Convenience method to position camera at a point looking at a target.
##
## @param position: Where to place the camera
## @param look_at_target: What the camera should look at
## ============================================================================
func position_camera_at(position: Vector3, look_at_target: Vector3) -> void:
	var look_direction := (look_at_target - position).normalized()
	var up := Vector3.UP
	
	# Handle edge case where look direction is parallel to up
	if abs(look_direction.dot(up)) > 0.99:
		up = Vector3.FORWARD
	
	var basis := Basis.looking_at(look_direction, up)
	var transform := Transform3D(basis, position)
	
	set_camera_transform(transform)

#endregion

#region Validation
func _process(delta: float) -> void:
	if validation_interval > 0.0:
		_validation_timer += delta
		
		if _validation_timer >= validation_interval:
			_validation_timer = 0.0
			_validate_camera_state()

func _validate_camera_state() -> void:
	if not active_camera:
		return
	
	var is_valid := active_camera.validate_state()
	
	if not is_valid:
		var reason := "Camera validation failed"
		camera_validation_failed.emit(active_camera, reason)
		
		if enable_debug_logging:
			push_warning("[CameraController] %s" % reason)
		
		if auto_reset_on_validation_failure:
			reset_camera()
#endregion

#region Event Callbacks (Called by Viewer)
## Notify camera that content has been loaded
func on_content_loaded(bounds_center: Vector3, bounds_size: Vector3) -> void:
	if not active_camera:
		return
	
	active_camera.on_content_loaded(bounds_center, bounds_size)
	
	if enable_debug_logging:
		print("[CameraController] Notified camera of content load: center=%v, size=%v" % [bounds_center, bounds_size])

## Notify camera of viewer error
func on_viewer_error(error_message: String) -> void:
	if not active_camera:
		return
	
	active_camera.on_viewer_error(error_message)
	
	if enable_debug_logging:
		print("[CameraController] Notified camera of error: %s" % error_message)
#endregion

#region Debug Utilities
## Get detailed debug information
func get_debug_info() -> Dictionary:
	var info := {
		"has_active_camera": active_camera != null,
		"validation_enabled": validation_interval > 0.0,
		"last_movement_state": _last_movement_state
	}
	
	if active_camera:
		info["camera_debug"] = active_camera.get_debug_info()
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	print("[CameraController] === Debug Info ===")
	var info := get_debug_info()
	for key in info:
		print("  %s: %s" % [key, str(info[key])])
#endregion
