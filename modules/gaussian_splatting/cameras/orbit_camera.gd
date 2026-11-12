class_name OrbitCamera
extends CameraInterface
## Orbit-only camera that always rotates around a focal point
## Demonstrates creating alternative camera implementations
##
## Features:
## - Always orbits (no free-look mode)
## - Auto-frames content on load
## - Smooth zoom with scroll wheel
## - Click to set new orbit center
## - Bounded pitch to prevent flipping

#region Configuration
## Distance from orbit point
@export_range(0.5, 50.0, 0.1) var orbit_distance : float = 5.0

## Minimum orbit distance (zoom limit)
@export_range(0.1, 10.0, 0.1) var min_orbit_distance : float = 0.5

## Maximum orbit distance (zoom limit)
@export_range(5.0, 100.0, 1.0) var max_orbit_distance : float = 50.0

## Zoom speed multiplier
@export_range(0.1, 2.0, 0.1) var zoom_speed : float = 0.5

## Orbit point in world space
var orbit_point : Vector3 = Vector3.ZERO

## Current spherical coordinates (theta=yaw, phi=pitch, radius=distance)
var theta : float = 0.0  # Horizontal angle (radians)
var phi : float = PI * 0.3  # Start at a safe 54-degree angle

## Whether mouse is currently held down
var is_rotating : bool = false

## Last mouse position for delta calculation
var last_mouse_pos : Vector2 = Vector2.ZERO

var _zoom_stop_timer: Timer

#endregion

#region Initialization
func _ready() -> void:
	_update_camera_from_spherical()
	_zoom_stop_timer = Timer.new()
	_zoom_stop_timer.one_shot = true
	_zoom_stop_timer.wait_time = 0.1
	_zoom_stop_timer.timeout.connect(_on_zoom_stop_timer_timeout)
	add_child(_zoom_stop_timer)

func _on_zoom_stop_timer_timeout() -> void:
	if not is_rotating:
		movement_state_changed.emit(false)

func _update_camera_from_spherical() -> void:
	# Convert spherical coordinates to Cartesian position
	var x := orbit_distance * sin(phi) * cos(theta)
	var y := orbit_distance * cos(phi)
	var z := orbit_distance * sin(phi) * sin(theta)
	
	global_position = orbit_point + Vector3(x, y, z)
	look_at(orbit_point)
#endregion

#region CameraInterface Implementation
func _on_movement_enabled_changed(enabled: bool) -> void:
	if not enabled:
		is_rotating = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func reset() -> void:
	orbit_point = Vector3.ZERO
	orbit_distance = 5.0
	theta = 0.0
	phi = PI * 0.3  # 54 degrees
	_update_camera_from_spherical()
	
	movement_state_changed.emit(false)

func set_focused_position(target_position: Vector3) -> void:
	orbit_point = target_position
	_update_camera_from_spherical()
	focus_requested.emit(target_position)

func get_mode_string() -> String:
	return "Orbit"

func is_moving() -> bool:
	return is_rotating

func get_velocity() -> Vector3:
	# Orbit camera doesn't have traditional velocity
	return Vector3.ZERO

func on_content_loaded(bounds_center: Vector3, bounds_size: Vector3) -> void:
	# Auto-frame content
	orbit_point = bounds_center
	
	# Calculate distance to fit content in view
	var max_dimension := maxf(maxf(bounds_size.x, bounds_size.y), bounds_size.z)
	orbit_distance = max_dimension / tan(deg_to_rad(fov / 2.0)) * 1.5
	orbit_distance = clampf(orbit_distance, min_orbit_distance, max_orbit_distance)
	
	# Position camera at 45-degree angle
	theta = PI * 0.25
	phi = PI * 0.3
	
	_update_camera_from_spherical()
	
	mode_changed.emit("Orbit - Auto-framed")
#endregion

#region Input Handling
func _unhandled_input(event: InputEvent) -> void:
	if not enable_camera_movement or not current:
		return
	
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			is_rotating = event.pressed
			
			if event.pressed:
				last_mouse_pos = event.position
				movement_state_changed.emit(true)
			else:
				movement_state_changed.emit(false)
		
		MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(orbit_distance - zoom_speed, min_orbit_distance)
			_update_camera_from_spherical()
			movement_state_changed.emit(true)
			_zoom_stop_timer.start() # Restart the timer

		MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(orbit_distance + zoom_speed, max_orbit_distance)
			_update_camera_from_spherical()
			movement_state_changed.emit(true)
			_zoom_stop_timer.start() # Restart the timer

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not is_rotating:
		return
	
	var delta_mouse := event.position - last_mouse_pos
	last_mouse_pos = event.position
	
	# Update spherical coordinates
	theta -= delta_mouse.x * mouse_sensitivity * 0.01
	phi -= delta_mouse.y * mouse_sensitivity * 0.01
	
	# Clamp phi to prevent flipping
	phi = clampf(phi, deg_to_rad(5.0), deg_to_rad(175.0))
	
	# Wrap theta
	theta = wrapf(theta, -PI, PI)
	
	_update_camera_from_spherical()
#endregion

#region Physics Process
func _physics_process(_delta: float) -> void:
	# Update mouse capture state
	if enable_camera_movement and current:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if is_rotating else Input.MOUSE_MODE_VISIBLE

#endregion

#region Debug Info
func get_debug_info() -> Dictionary:
	var info := super.get_debug_info()
	info.merge({
		"orbit_point": orbit_point,
		"orbit_distance": orbit_distance,
		"theta_deg": rad_to_deg(theta),
		"phi_deg": rad_to_deg(phi),
		"is_rotating": is_rotating
	})
	return info
#endregion
