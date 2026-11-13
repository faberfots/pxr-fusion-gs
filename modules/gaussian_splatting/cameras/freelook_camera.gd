class_name FreeLookCamera
extends CameraInterface
## Free-look camera with orbit mode support
## Refactored from original camera.gd to implement CameraInterface
## 
## Features:
## - Free-look rotation (right-click drag)
## - Orbit mode (left-click drag around a focal point)
## - WASD movement with Shift to run
## - Scroll wheel to zoom in orbit mode
## - Smooth transitions between modes

#region Camera Modes
enum RotationMode { 
	FREE_LOOK, ## Right-click: rotate camera freely
	ORBIT,     ## Left-click: orbit around a point
	NONE       ## No rotation active
}
#endregion

#region State Variables
## Current rotation mode
var rotation_mode := RotationMode.NONE

## Point to orbit around in world space
var orbit_position := -Vector3.FORWARD * 2.0

## Target orbit position (for smooth transitions)
var target_orbit_position := Vector3.ZERO

## Time spent in orbit mode (for interpolation)
var orbit_time := 0.0

## Movement direction from keyboard input
var direction := Vector3.ZERO

## Current velocity
var velocity := Vector3.ZERO

## Keyboard state tracking
var _w := false
var _s := false
var _a := false
var _d := false
var _q := false
var _e := false
var _shift := false
var _alt := false

## Internal movement tracking for signal emission
var _was_moving := false

var _left_mouse_down_time := 0.0

#endregion

#region Child Nodes
## Orbit target node (for smooth transitions)
@onready var target : Node3D = $Target if has_node("Target") else null

## Visual cursor at orbit position
@onready var cursor : Node3D = $Cursor if has_node("Cursor") else null

## Timer for switching to orbit mode
@onready var orbit_swap_timer : Timer = $OrbitSwapTimer if has_node("OrbitSwapTimer") else null
#endregion

#region Initialization
func _ready() -> void:
	# REMOVED: super._ready()  # Don't call this!
	
	# Setup orbit swap timer if it exists
	if orbit_swap_timer:
		orbit_swap_timer.timeout.connect(_on_orbit_swap_timeout)
	
	if cursor: cursor.top_level = true
	# Initialize target node
	if target:
		target.top_level = true
		target.global_transform = global_transform
		target.position = target_orbit_position


## Called when orbit swap timer expires
func _on_orbit_swap_timeout() -> void:
	if not enable_camera_movement or not current:
		return
	
	target.global_transform = global_transform
	target.look_at_from_position(global_position, orbit_position)
	
	# Skip interpolation if camera already facing orbit position
	var dot_product := 1.0 - global_basis.get_rotation_quaternion().dot(target.global_basis.get_rotation_quaternion())
	orbit_time = 0.0 if dot_product > 1e-5 else 1.0
	rotation_mode = RotationMode.ORBIT
	
	mode_changed.emit(get_mode_string())
#endregion

#region CameraInterface Implementation
func _on_movement_enabled_changed(enabled: bool) -> void:
	if not enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		rotation_mode = RotationMode.NONE
		velocity = Vector3.ZERO
		_w = false
		_s = false
		_a = false
		_d = false
		_q = false
		_e = false
		_shift = false
		_alt = false
		direction = Vector3.ZERO

func reset() -> void:
	position = Vector3.ZERO
	rotation = Vector3.UP * -PI
	target_orbit_position = Vector3.ZERO
	orbit_position = -Vector3.FORWARD * 2.0
	rotation_mode = RotationMode.NONE
	velocity = Vector3.ZERO
	
	if target:
		target.position = target_orbit_position
	
	if cursor:
		cursor.set_alpha(0.0)
		cursor.update_position(orbit_position)
	var controller := get_parent() as CameraController
	if controller and controller.home_on_ready: controller.go_home()

func set_focused_position(target_position: Vector3) -> void:
	if not enable_camera_movement or not current:
		return
	
	orbit_position = target_position
	
	if target:
		target.global_position = target_position + global_basis.z * 2.0
	
	if cursor:
		cursor.update_position(orbit_position)
	
	focus_requested.emit(target_position)

func get_mode_string() -> String:
	match rotation_mode:
		RotationMode.FREE_LOOK:
			return "Free Look"
		RotationMode.ORBIT:
			return "Orbit"
		RotationMode.NONE:
			return "Idle"
		_:
			return "Unknown"

func is_moving() -> bool:
	return not velocity.is_zero_approx() or rotation_mode != RotationMode.NONE

func get_velocity() -> Vector3:
	return velocity
#endregion

#region Input Handling
func _unhandled_input(event: InputEvent) -> void:
	# THIS IS THE CRITICAL GUARD. If the camera is disabled, do nothing.
	if not enable_camera_movement or not current:
		return
	
	# Mouse motion for rotation
	if event is InputEventMouseMotion and rotation_mode != RotationMode.NONE:
		_handle_mouse_motion(event)
	
	# Mouse button for rotation mode control
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	
	# Keyboard for movement
	elif event is InputEventKey:
		_handle_keyboard(event)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var offset : Vector2 = -event.relative * mouse_sensitivity
	
	match rotation_mode:
		RotationMode.FREE_LOOK:
			rotation_degrees += Vector3(offset.y, offset.x, 0.0)
			rotation_degrees = CameraInterface.clamp_rotation_degrees(rotation_degrees)
		
		RotationMode.ORBIT:
			if not target:
				return
			
			var pitch : float = target.rotation_degrees.x - offset.y
			var rotated_pos : Vector3 = target.global_position - orbit_position
			
			# Apply pitch rotation if within bounds
			if pitch >= -80.0 and pitch <= 70.0:
				rotated_pos = rotated_pos.rotated(target.global_basis.x, deg_to_rad(-offset.y))
			
			# Apply yaw rotation
			rotated_pos = rotated_pos.rotated(target.global_basis.y, deg_to_rad(-offset.x) * cos(deg_to_rad(pitch)))
			rotated_pos += orbit_position
			
			target.look_at_from_position(rotated_pos, orbit_position)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Don't start the timer here, just record the time
				_left_mouse_down_time = Time.get_ticks_msec()
				# The orbit_swap_timer can still be used for the drag-to-orbit logic
				if orbit_swap_timer:
					orbit_swap_timer.start()
			else:
				if orbit_swap_timer:
					orbit_swap_timer.stop()
				
				# If the mouse was held for a very short time, it's a click.
				# Handle the click logic here (e.g., splat picking).
				# This logic is currently in the viewer, which is good.
				# The key is to stop the timer and reset state.
				if (Time.get_ticks_msec() - _left_mouse_down_time) < 100: # 100ms threshold for a click
					pass # It was a click, not a drag.
				
				rotation_mode = RotationMode.NONE
				mode_changed.emit(get_mode_string())
		
		MOUSE_BUTTON_RIGHT:
			rotation_mode = RotationMode.FREE_LOOK if event.pressed else RotationMode.NONE
			mode_changed.emit(get_mode_string())
		
		MOUSE_BUTTON_WHEEL_UP:
			if target and orbit_position.distance_to(target.global_position) > 0.75:
				target.position += (orbit_position - target.position).normalized() * 0.25
			if cursor:
				cursor.update_position(orbit_position)
		
		MOUSE_BUTTON_WHEEL_DOWN:
			if target:
				target.position -= (orbit_position - target.position).normalized() * 0.25
			if cursor:
				cursor.update_position(orbit_position)

func _handle_keyboard(event: InputEventKey) -> void:
	match event.keycode:
		KEY_A: _a = event.pressed
		KEY_D: _d = event.pressed
		KEY_Q: _q = event.pressed
		KEY_E: _e = event.pressed
		KEY_W: _w = event.pressed
		KEY_S: _s = event.pressed
		KEY_SHIFT: _shift = event.pressed
		KEY_ALT: _alt = event.pressed
#endregion


##region Movement Update
func _process(delta: float) -> void:
	_update_movement_signal()

func _physics_process(delta: float) -> void:
	var previous := global_transform
	_update_movement(delta)
	var controller := get_parent() as CameraController
	if controller:
		var resolved := controller.constrain_pose(previous, global_transform)
		if not resolved.origin.is_equal_approx(global_position):
			global_transform = resolved
			if velocity.y < 0 and global_position.y <= controller.ground_height() + controller.safety.radius + controller.safety.margin + 0.001: velocity.y = 0
			if target: target.global_position = global_position
	# Only manage the mouse if the camera is actually enabled.
	if enable_camera_movement and current:
		# Update mouse capture state
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if rotation_mode != RotationMode.NONE else Input.MOUSE_MODE_VISIBLE
	
	# Update cursor position in orbit mode
	if rotation_mode == RotationMode.ORBIT and cursor:
		cursor.update_position(orbit_position)

func _update_movement(delta: float) -> void:
	if not enable_camera_movement or not current:
		return
	if rotation_mode != RotationMode.ORBIT:
		# Standard free movement
		direction = Vector3(
			(_d as float) - (_a as float),
			(_e as float) - (_q as float),
			(_s as float) - (_w as float)
		)
		
		# Apply acceleration and deceleration
		var offset := (direction.normalized() * acceleration + velocity.normalized() * deceleration) * vel_multiplier * delta
		
		# Calculate speed multiplier
		var speed_multi := 1.0
		if _shift: speed_multi *= run_speed_multiplier
		if _alt: speed_multi *= 1.0 / run_speed_multiplier
		
		# Update velocity
		if direction == Vector3.ZERO and offset.length_squared() > velocity.length_squared():
			velocity = Vector3.ZERO
		else:
			velocity = (velocity + offset).clampf(-vel_multiplier, vel_multiplier)
			translate(velocity * delta * speed_multi)
		
		# Update target position
		if not velocity.is_zero_approx() and target:
			target.global_position = global_position
	
	else:
		# Orbit mode - smooth interpolation to target
		orbit_time += delta
		
		if not target:
			return
		
		# Calculate target position maintaining current distance
		var target_pos_same_radius := orbit_position + (target.global_position - orbit_position).normalized() * (orbit_position - global_position).length()
		
		# Smooth transition (faster at higher FPS)
		var t := 1.0 - pow(1.0 - orbit_time * lerpf(1.0, 0.1, minf(Engine.get_frames_per_second() / 180.0, 1.0)), 3) if orbit_time < 0.4 else 1.0
		
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(target.global_basis.get_rotation_quaternion(), t))
		global_position = global_position.slerp(target_pos_same_radius, t)
	
	# Smooth camera distance transition
	if target and global_position.distance_squared_to(target.global_position) > 1e-6:
		global_position = global_position.lerp(target.global_position, minf(delta * 5.0, 1.0))

func _update_movement_signal() -> void:
	var is_currently_moving := is_moving()
	
	if is_currently_moving != _was_moving:
		movement_state_changed.emit(is_currently_moving)
		_was_moving = is_currently_moving
		
## ============================================================================
## PUBLIC API: Reset Movement State
## ============================================================================
## Resets all internal movement state to allow external positioning.
## Call this after programmatically setting camera position to prevent
## the movement system from overriding the new position.
##
## Used by GaussianSplattingViewer for initial camera positioning.
## ============================================================================
func reset_movement_state() -> void:
	# Reset velocity to stop any ongoing movement
	velocity = Vector3.ZERO
	direction = Vector3.ZERO
	
	# Reset orbit state
	orbit_time = 0.0
	rotation_mode = RotationMode.NONE
	
	# Sync target node to current camera position
	if target:
		target.global_position = global_position
		target.global_basis = global_basis
	
	# Reset movement tracking
	_was_moving = false
	
	if Engine.is_editor_hint():
		return
	
	if OS.is_debug_build():
		print("[FreeLookCamera] Movement state reset. Position: %s" % global_position)

#endregion

#region Optional Callbacks
func on_content_loaded(bounds_center: Vector3, bounds_size: Vector3) -> void:
	# Auto-frame content by positioning camera to see entire bounds
	var max_dimension := maxf(maxf(bounds_size.x, bounds_size.y), bounds_size.z)
	var distance := max_dimension / tan(deg_to_rad(fov / 2.0)) * 1.5
	
	position = bounds_center + Vector3(0, 0, distance)
	look_at(bounds_center)
	
	orbit_position = bounds_center
	if target:
		target.global_position = global_position
#endregion
