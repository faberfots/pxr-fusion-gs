class_name CameraInterface extends Camera3D
## Abstract base class for all camera implementations in the Gaussian Splatting system
## Defines the contract that all cameras must implement for compatibility
## 
## This ensures SSOT (Single Source of Truth) for camera behavior and prevents
## tight coupling between the viewer and specific camera implementations.
##
## Any custom camera (orbit, first-person, flythrough, etc.) should extend this class
## and implement the required methods/signals.

#region Required Signals
## Emitted when camera movement state changes (started/stopped moving)
## Useful for triggering render optimizations (pause when idle)
signal movement_state_changed(is_moving: bool)

## Emitted when camera wants to focus on a specific world position
## The viewer can use this to update cursor position or trigger animations
signal focus_requested(target_position: Vector3)

## Emitted when camera mode changes (if camera supports multiple modes)
## For example: FreeLook -> Orbit -> None
signal mode_changed(new_mode: String)
#endregion

#region Required Properties
# This is the private variable that will actually store the state.
var _is_movement_enabled := true

## Whether the camera is currently enabled and accepting input.
## When false, camera should ignore all input events.
@export var enable_camera_movement : bool:
	get:
		return _is_movement_enabled
	set(value):
		# Optional: prevent running the code if the value isn't actually changing.
		if _is_movement_enabled == value:
			return
		
		# Set the private backing variable. This does NOT call the setter again.
		_is_movement_enabled = value
		
		# Now, reliably call the function to notify subclasses of the change.
		_on_movement_enabled_changed(value)

## Mouse sensitivity for rotation (0.0 - 2.0)
## Each camera implementation interprets this differently
@export_range(0.0, 2.0, 0.1) var mouse_sensitivity : float = 0.4

## Movement speed multiplier when "run" modifier is held (typically Shift)
@export_range(1.0, 10.0, 0.1) var run_speed_multiplier : float = 5.0

## Base movement acceleration (units/second²)
@export_range(1.0, 200.0, 1.0) var acceleration : float = 100.0

## Movement deceleration when no input (negative acceleration)
@export_range(-100.0, -1.0, 1.0) var deceleration : float = -50.0

## Velocity multiplier affecting final movement speed
@export_range(0.5, 50.0, 0.5) var vel_multiplier : float = 10.0
#endregion

#region Virtual Methods (Must be overridden by implementations)
## Called when movement enabled state changes
## Implementations should use this to show/hide cursor, etc.
func _on_movement_enabled_changed(enabled: bool) -> void:
	pass # Override in subclass

## Reset camera to default position and rotation
## Each implementation defines what "default" means
func reset() -> void:
	push_error("[CameraInterface] reset() must be implemented by subclass")

## Set a position for the camera to focus on
## Used when user clicks on a splat to center view
func set_focused_position(target_position: Vector3) -> void:
	push_error("[CameraInterface] set_focused_position() must be implemented by subclass")

## Get current camera mode as string (for UI display)
## Example: "Free Look", "Orbit", "Locked"
func get_mode_string() -> String:
	push_error("[CameraInterface] get_mode_string() must be implemented by subclass")
	return "Unknown"

## Validate camera state (called periodically by viewer)
## Returns true if camera is in valid state, false if needs reset
func validate_state() -> bool:
	return true # Override in subclass if validation needed
#endregion

#region Optional Callbacks
## Called when viewer finishes loading a new file
## Camera can use this to auto-frame the content
func on_content_loaded(bounds_center: Vector3, bounds_size: Vector3) -> void:
	pass # Optional override

## Called when viewer encounters an error
## Camera can use this to restore safe state
func on_viewer_error(error_message: String) -> void:
	pass # Optional override
#endregion

#region State Queries
## Returns true if camera is currently moving
func is_moving() -> bool:
	return false # Override in subclass

## Returns current camera velocity
func get_velocity() -> Vector3:
	return Vector3.ZERO # Override in subclass

## Returns camera transform as Projection for GPU
func get_camera_view_projection() -> Projection:
	return get_camera_transform()
#endregion

#region Utility Methods (Shared across all cameras)
## Clamp rotation to prevent gimbal lock
static func clamp_rotation_degrees(rotation_deg: Vector3) -> Vector3:
	return Vector3(
		clampf(rotation_deg.x, -89.0, 89.0),  # Pitch
		wrapf(rotation_deg.y, -180.0, 180.0), # Yaw
		0.0                                     # Roll (disabled)
	)

## Smooth damping for camera movement
static func smooth_damp(current: float, target: float, velocity: float, smooth_time: float, delta: float) -> Dictionary:
	smooth_time = maxf(0.0001, smooth_time)
	var omega := 2.0 / smooth_time
	var x := omega * delta
	var exp := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (velocity + omega * change) * delta
	velocity = (velocity - omega * temp) * exp
	var output := target + (change + temp) * exp
	
	return {
		"value": output,
		"velocity": velocity
	}
#endregion

#region Debug Helpers
## Get debug information about camera state (for UI/logging)
func get_debug_info() -> Dictionary:
	return {
		"type": get_class(),
		"enabled": enable_camera_movement,
		"position": global_position,
		"rotation_deg": rotation_degrees,
		"fov": fov,
		"is_moving": is_moving()
	}
#endregion
