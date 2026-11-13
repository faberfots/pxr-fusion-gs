@tool
# @icon("res://addons/control_camera3d/control_camera3d.svg")
## Camera node, displays from a point of view towards a pivot point and rotates around this point.
## Enhanced with floor click-to-move-pivot feature with smart interpolation and full configurability.
extends Camera3D

## Global position of pivot point
@export var pivot_pos: Vector3 = Vector3.ZERO:
	set(value):
		pivot_pos = value
		_place_pivot()
		
@export_group("Camera Control")
## Mouse button used for orbital movement
@export_enum("LEFT_BUTTON", "MIDDLE_BUTTON")
var action_mouse_button: String = "MIDDLE_BUTTON"
@export_range(0.5, 2, 0.1) var rotation_speed: float = 1.0
@export_range(0.5, 4, 0.1) var translation_speed: float = 1.0
@export_range(0.5, 2, 0.1) var zoom_speed: float = 1.0
@export var zoom_in: float = 1:
	set(value):
		if value > 0:
			zoom_in = value
@export var zoom_out: float = 10:
	set(value):
		if value > zoom_in:
			zoom_out = value

@export_group("Pivot Floor Click", "floor_click_")
## Enable click-on-floor to move pivot functionality
@export var floor_click_enabled: bool = true
## Method for floor click detection
@export_enum("Modifier Keys", "Input Map Action") var floor_click_method: String = "Modifier Keys"
## Modifier keys for floor click (when using Modifier Keys method)
@export_flags("Ctrl", "Shift", "Alt", "Meta") var floor_click_modifiers: int = 3  # Ctrl + Shift by default
## Input action name for floor click (when using Input Map Action method)
@export var floor_click_action: String = "camera_pivot_click"
## Smooth transition to new pivot position
@export var floor_click_smooth_transition: bool = true
## Transition speed for smooth pivot movement
@export_range(1.0, 20.0, 0.5) var floor_click_transition_speed: float = 8.0
## Visual feedback for floor click
@export var floor_click_visual_feedback: bool = true
## Color of visual feedback marker
@export var floor_click_marker_color: Color = Color(0.2, 0.8, 1.0, 0.8)
## Size of visual feedback marker
@export_range(0.1, 2.0, 0.1) var floor_click_marker_size: float = 0.5
## Duration of visual feedback (seconds)
@export_range(0.1, 2.0, 0.1) var floor_click_marker_duration: float = 1.0
## Maximum distance for floor click raycast
@export var floor_click_max_distance: float = 1000.0
## Physics layers for floor click detection
@export_flags_3d_physics var floor_click_collision_mask: int = 1
## Maintain camera distance after pivot move
@export var floor_click_maintain_distance: bool = true
## Audio feedback for floor click (optional)
@export var floor_click_audio_stream: AudioStream = null
## Enable drag to adjust distance after floor click
@export var floor_click_drag_distance: bool = true
## Sensitivity for drag distance adjustment
@export_range(0.001, 0.05, 0.001) var floor_click_drag_sensitivity: float = 0.01
## Minimum distance when dragging towards pivot
@export var floor_click_drag_min_distance: float = 0.5
## Maximum distance when dragging away from pivot  
@export var floor_click_drag_max_distance: float = 100.0
## Use exponential scaling for more natural feel
@export var floor_click_drag_exponential: bool = true
## Visual feedback during drag
@export var floor_click_drag_show_distance: bool = false
## Invert drag direction (pull to zoom in vs out)
@export var floor_click_drag_invert: bool = false

@export_group("Collision")
## If enabled, the camera will not go through the floor.
@export var floor_collision_enabled: bool = true
## The method to use for floor detection.
@export_enum("Clamp", "Raycast") var collision_type: String = "Raycast"
## The minimum Y position for the camera when using Clamp.
@export var floor_y_position: float = 0.0
## The offset to keep the camera above the floor.
@export var collision_offset: float = 0.1
## The physics layers the raycast should detect.
@export_flags_3d_physics var collision_mask: int = 1
## Maximum ray length for floor detection
@export var ray_length: float = 1000.0
## Debug visualization for raycast
@export var debug_raycast: bool = false

var _state: int = State.IDLE
var _cam_from_pivot_dist: float
var _pivot_transform: Transform3D
var _pole_mesh := ImmediateMesh.new()
var _pole_mesh_instance: MeshInstance3D
var _pole_mat := StandardMaterial3D.new()

# Raycast debug visualization
var _debug_mesh := ImmediateMesh.new()
var _debug_mesh_instance: MeshInstance3D
var _debug_mat := StandardMaterial3D.new()

# Track mouse state for drag detection
var _mouse_button_held := false
var _floor_click_initiated := false
var _drag_threshold := 3.0  # Pixels before drag starts

# SSOT: Single source for collision data
var _collision_data := {
	"last_hit_point": Vector3.ZERO,
	"last_hit_normal": Vector3.UP,
	"is_colliding": false,
	"distance_to_floor": INF
}


# === ENHANCED: Floor Click Feature Data (SSOT) ===
var _floor_click_data := {
	"target_pivot": Vector3.ZERO,
	"is_transitioning": false,
	"transition_progress": 0.0,
	"start_pivot": Vector3.ZERO,
	"markers": [],  # Array of active visual markers
	# NEW: Drag distance control data
	"drag_active": false,
	"drag_start_mouse_y": 0.0,
	"drag_start_distance": 0.0,
	"drag_current_distance": 0.0,
	"initial_click_pos": Vector2.ZERO,
	"clicked_world_pos": Vector3.ZERO,
	"pre_drag_cam_pos": Vector3.ZERO,
	"drag_sensitivity": 0.01,  # Configurable in export vars
}

# Visual feedback components
var _click_marker_parent: Node3D = null
var _audio_player: AudioStreamPlayer3D = null

enum State{
	IDLE,
	ROTATED,
	TRANSLATED,
	LOOKAT,
	PIVOT_TRANSITIONING,  # Smooth pivot transitions
	PIVOT_DRAG_DISTANCE,  # NEW: Dragging to adjust distance after floor click
}

const _MOUSE_SENSITIVITY = 0.002
const _WHEEL_SENSITIVITY = 0.1
const _ANGLE_GAP = PI/128

func _ready() -> void:
	_place_pivot()
	_setup_visualization()
	_setup_floor_click_components()
	
func _setup_visualization() -> void:
	# Export/editor inspection can instantiate this script without entering a tree.
	# Only create Node children when they can be owned and freed by the camera.
	_pole_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance = MeshInstance3D.new()
	# Pivot visualization
	_pole_mat.vertex_color_use_as_albedo = true
	_pole_mesh_instance.mesh = _pole_mesh
	_pole_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pole_mesh_instance)
	
	# Debug raycast visualization
	_debug_mat.vertex_color_use_as_albedo = true
	_debug_mat.no_depth_test = true
	_debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_mesh_instance.mesh = _debug_mesh
	_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_debug_mesh_instance)

# === NEW: Setup floor click visual and audio components ===
func _setup_floor_click_components() -> void:
	if not is_inside_tree():
		return
		
	# Create parent node for click markers
	_click_marker_parent = Node3D.new()
	_click_marker_parent.name = "FloorClickMarkers"
	add_child(_click_marker_parent)
	
	# Create audio player if audio stream is provided
	if floor_click_audio_stream != null:
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.stream = floor_click_audio_stream
		_audio_player.unit_size = 10.0
		_audio_player.max_distance = 100.0
		add_child(_audio_player)
	
func _place_pivot():
	if is_inside_tree() and global_position != pivot_pos:
		_pivot_transform = Transform3D(Basis(), pivot_pos)
		_pivot_transform = _pivot_transform.looking_at(global_position)
		_cam_from_pivot_dist = global_position.distance_to(pivot_pos)
		var new_cam_pos: Vector3 = _pivot_transform.basis.z * -(_cam_from_pivot_dist) + pivot_pos
		look_at_from_position(new_cam_pos, pivot_pos)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_place_pivot()
		_draw_pivot_line()
	
	if not Engine.is_editor_hint():
		# Handle floor collision
		if floor_collision_enabled:
			_handle_floor_collision()
		
		# Handle smooth pivot transitions
		if _floor_click_data.is_transitioning:
			_process_pivot_transition(delta)
		
		# NEW: Update drag distance display if enabled
		if _floor_click_data.drag_active and floor_click_drag_show_distance:
			_update_distance_display()
	
	if debug_raycast and not Engine.is_editor_hint():
		_draw_debug_raycast()

# === NEW: Update distance display during drag (optional) ===
func _update_distance_display() -> void:
	if not floor_click_drag_show_distance:
		return
	
	# This is a placeholder for distance display
	# You can implement a UI label or 3D text here
	var distance_text = "Distance: %.2fm" % _floor_click_data.drag_current_distance
	# For now, just print to debug
	if Engine.is_editor_hint() == false:
		pass  # Implement UI display here if needed

# === NEW: Get drag state information ===
func is_dragging_pivot_distance() -> bool:
	return _floor_click_data.drag_active

func get_current_pivot_distance() -> float:
	return _floor_click_data.drag_current_distance if _floor_click_data.drag_active else _cam_from_pivot_dist

# === NEW: Process smooth pivot transition ===
func _process_pivot_transition(delta: float) -> void:
	if not _floor_click_data.is_transitioning:
		return
	
	var speed = floor_click_transition_speed * delta
	_floor_click_data.transition_progress += speed
	
	if _floor_click_data.transition_progress >= 1.0:
		# Transition complete
		pivot_pos = _floor_click_data.target_pivot
		_floor_click_data.is_transitioning = false
		_floor_click_data.transition_progress = 0.0
		_state = State.IDLE
	else:
		# Smooth interpolation using ease-in-out curve
		var t = _ease_in_out_cubic(_floor_click_data.transition_progress)
		var interpolated_pos = _floor_click_data.start_pivot.lerp(_floor_click_data.target_pivot, t)
		
		# Maintain camera distance during transition
		if floor_click_maintain_distance:
			var direction = (global_position - pivot_pos).normalized()
			var new_cam_pos = interpolated_pos + direction * _cam_from_pivot_dist
			pivot_pos = interpolated_pos
			look_at_from_position(new_cam_pos, interpolated_pos)
		else:
			pivot_pos = interpolated_pos

# === NEW: Smooth easing function ===
func _ease_in_out_cubic(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	else:
		var p = 2.0 * t - 2.0
		return 1.0 + p * p * p / 2.0

# === NEW: Update visual feedback markers ===
func _update_floor_click_markers(delta: float) -> void:
	if not floor_click_visual_feedback:
		return
	
	var markers_to_remove = []
	for marker_data in _floor_click_data.markers:
		marker_data.lifetime -= delta
		
		# Fade out effect
		var alpha = clampf(marker_data.lifetime / floor_click_marker_duration, 0.0, 1.0)
		if marker_data.mesh_instance and marker_data.mesh_instance.material_override:
			marker_data.mesh_instance.material_override.albedo_color.a = alpha * floor_click_marker_color.a
		
		if marker_data.lifetime <= 0:
			markers_to_remove.append(marker_data)
	
	# Clean up expired markers
	for marker in markers_to_remove:
		if marker.mesh_instance:
			marker.mesh_instance.queue_free()
		_floor_click_data.markers.erase(marker)

func _draw_pivot_line() -> void:
	var global_tr_inv = global_transform.inverse()
	var pivot_global_pos = (global_tr_inv * _pivot_transform).origin
	_pole_mesh.clear_surfaces()
	_pole_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _pole_mat)
	_pole_mesh.surface_set_color(Color.WEB_PURPLE)
	_pole_mesh.surface_add_vertex(Vector3.ZERO)
	_pole_mesh.surface_add_vertex(pivot_global_pos)
	_pole_mesh.surface_end()

func _draw_debug_raycast() -> void:
	if not _collision_data.is_colliding:
		_debug_mesh.clear_surfaces()
		return
		
	var global_tr_inv = global_transform.inverse()
	var start_local = global_tr_inv * (global_position + Vector3.UP * ray_length)
	var hit_local = global_tr_inv * _collision_data.last_hit_point
	
	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _debug_mat)
	_debug_mesh.surface_set_color(Color.CYAN)
	_debug_mesh.surface_add_vertex(start_local)
	_debug_mesh.surface_add_vertex(hit_local)
	_debug_mesh.surface_end()
	
	# Draw hit point marker
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_POINTS, _debug_mat)
	_debug_mesh.surface_set_color(Color.RED)
	_debug_mesh.surface_add_vertex(hit_local)
	_debug_mesh.surface_end()

func _unhandled_input(event: InputEvent) -> void:
	if not current: return
	
	# === ENHANCED: Handle floor click with drag capability ===
	if floor_click_enabled:
		if _handle_floor_click_input(event):
			return  # Event was handled
	
	# Original input handling
	_handle_mouse_button(event)
	_handle_mouse_motion(event)
	_handle_mouse_wheel(event)

# === NEW: Comprehensive floor click input handler ===
func _handle_floor_click_input(event: InputEvent) -> bool:
	# Handle mouse button events
	if event is InputEventMouseButton:
		var mb_event = event as InputEventMouseButton
		
		if mb_event.button_index == MOUSE_BUTTON_LEFT:
			if mb_event.pressed and _should_handle_floor_click(event):
				# Start floor click interaction
				_floor_click_initiated = true
				_mouse_button_held = true
				_floor_click_data.initial_click_pos = mb_event.position
				_floor_click_data.drag_active = false
				
				# Perform initial floor detection
				var ray_result = _cast_ray_from_screen(mb_event.position)
				if ray_result.is_valid:
					_floor_click_data.clicked_world_pos = ray_result.position
					_floor_click_data.pre_drag_cam_pos = global_position
					
					# Set pivot immediately (no transition for drag mode)
					pivot_pos = ray_result.position
					_cam_from_pivot_dist = global_position.distance_to(pivot_pos)
					_floor_click_data.drag_start_distance = _cam_from_pivot_dist
					_floor_click_data.drag_current_distance = _cam_from_pivot_dist
					
					get_viewport().set_input_as_handled()
					return true
				else:
					# No floor hit, reset state
					_floor_click_initiated = false
					_mouse_button_held = false
					return false
			
			elif not mb_event.pressed and (_floor_click_initiated or _floor_click_data.drag_active):
				# Release - end any drag operation
				if _floor_click_data.drag_active:
					# Finalize drag distance
					_cam_from_pivot_dist = _floor_click_data.drag_current_distance
					_state = State.IDLE
				elif _floor_click_initiated and not _floor_click_data.drag_active:
					# Was just a click without drag - handle as simple pivot set
					# Optional: Add visual feedback here if needed
					pass
				
				# Reset states
				_floor_click_initiated = false
				_mouse_button_held = false
				_floor_click_data.drag_active = false
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				
				get_viewport().set_input_as_handled()
				return true
	
	# Handle mouse motion events
	elif event is InputEventMouseMotion and _floor_click_initiated:
		var mm_event = event as InputEventMouseMotion
		
		if _mouse_button_held and floor_click_drag_distance:
			# Check if we should start dragging (threshold check)
			if not _floor_click_data.drag_active:
				var click_distance = mm_event.position.distance_to(_floor_click_data.initial_click_pos)
				if click_distance > _drag_threshold:
					# Start drag mode
					_floor_click_data.drag_active = true
					_floor_click_data.drag_start_mouse_y = mm_event.position.y
					_state = State.PIVOT_DRAG_DISTANCE
					Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			
			# Process drag if active
			if _floor_click_data.drag_active:
				_process_floor_click_drag(mm_event)
				get_viewport().set_input_as_handled()
				return true
	
	return false

# === NEW: Process drag to adjust camera distance ===
func _process_floor_click_drag(event: InputEventMouseMotion) -> void:
	if not _floor_click_data.drag_active:
		return
	
	# Calculate drag delta (vertical mouse movement)
	var mouse_delta_y = event.position.y - _floor_click_data.drag_start_mouse_y
	
	# Apply inversion if needed
	if floor_click_drag_invert:
		mouse_delta_y = -mouse_delta_y
	
	# Calculate distance change
	var distance_multiplier: float
	
	if floor_click_drag_exponential:
		# Exponential scaling for more natural feel (like Google Earth)
		var exp_factor = -mouse_delta_y * floor_click_drag_sensitivity
		distance_multiplier = exp(exp_factor)
	else:
		# Linear scaling
		distance_multiplier = 1.0 - (mouse_delta_y * floor_click_drag_sensitivity)
	
	# Apply the distance change
	var new_distance = _floor_click_data.drag_start_distance * distance_multiplier
	new_distance = clampf(new_distance, floor_click_drag_min_distance, floor_click_drag_max_distance)
	_floor_click_data.drag_current_distance = new_distance
	
	# Update camera position while maintaining look-at relationship
	var direction = (global_position - pivot_pos).normalized()
	var new_cam_pos = pivot_pos + direction * new_distance
	look_at_from_position(new_cam_pos, pivot_pos)
	
	# Update internal distance tracking
	_cam_from_pivot_dist = new_distance

# === NEW: Check if floor click should be handled ===
func _should_handle_floor_click(event: InputEvent) -> bool:
	if not event is InputEventMouseButton:
		return false
	
	var mb_event = event as InputEventMouseButton
	if mb_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	
	match floor_click_method:
		"Modifier Keys":
			return _check_modifier_keys(mb_event)
		"Input Map Action":
			return _check_input_action()
	
	return false

# === NEW: Check modifier keys for floor click ===
func _check_modifier_keys(event: InputEventMouseButton) -> bool:
	var required_modifiers = floor_click_modifiers
	var has_required = true
	
	if required_modifiers & 1:  # Ctrl
		has_required = has_required and event.ctrl_pressed
	if required_modifiers & 2:  # Shift
		has_required = has_required and event.shift_pressed
	if required_modifiers & 4:  # Alt
		has_required = has_required and event.alt_pressed
	if required_modifiers & 8:  # Meta
		has_required = has_required and event.meta_pressed
	
	return has_required

# === NEW: Check input action for floor click ===
func _check_input_action() -> bool:
	if floor_click_action.is_empty():
		return false
	
	# Check if the action exists in InputMap
	if InputMap.has_action(floor_click_action):
		return Input.is_action_pressed(floor_click_action)
	else:
		push_warning("Floor click action '%s' not found in InputMap. Please add it in Project Settings > Input Map." % floor_click_action)
	
	return false

# === NEW: Handle floor click to move pivot ===
func _handle_floor_click(event: InputEvent) -> void:
	var mb_event = event as InputEventMouseButton
	var click_pos = mb_event.position
	
	# Perform raycast from camera through click position
	var ray_result = _cast_ray_from_screen(click_pos)
	
	if ray_result.is_valid:
		# Store the new pivot target
		_floor_click_data.target_pivot = ray_result.position
		
		if floor_click_smooth_transition:
			# Start smooth transition
			_floor_click_data.start_pivot = pivot_pos
			_floor_click_data.is_transitioning = true
			_floor_click_data.transition_progress = 0.0
			_state = State.PIVOT_TRANSITIONING
		else:
			# Instant pivot move
			pivot_pos = ray_result.position
			
			# Maintain camera distance if enabled
			if floor_click_maintain_distance:
				var direction = (global_position - pivot_pos).normalized()
				var new_cam_pos = pivot_pos + direction * _cam_from_pivot_dist
				look_at_from_position(new_cam_pos, pivot_pos)
		
		# Visual feedback
		if floor_click_visual_feedback:
			_create_click_marker(ray_result.position)
		
		# Audio feedback
		if _audio_player and floor_click_audio_stream:
			_audio_player.global_position = ray_result.position
			_audio_player.play()
		
		# Mark event as handled
		get_viewport().set_input_as_handled()

# === NEW: Cast ray from screen position ===
func _cast_ray_from_screen(screen_pos: Vector2) -> Dictionary:
	var viewport = get_viewport()
	if not viewport:
		return {"is_valid": false}
	
	# Get ray origin and direction from camera with high precision
	var from = project_ray_origin(screen_pos)
	var ray_direction = project_ray_normal(screen_pos)
	
	# Ensure normalized direction for consistent results
	ray_direction = ray_direction.normalized()
	var to = from + ray_direction * floor_click_max_distance
	
	# Perform raycast
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return {"is_valid": false}
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = floor_click_collision_mask
	query.exclude = [self]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	# Enhanced precision settings
	query.hit_from_inside = false  # More precise for floor clicking
	query.hit_back_faces = true
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return {"is_valid": false}
	
	return {
		"is_valid": true,
		"position": result.position,
		"normal": result.normal,
		"collider": result.collider,
		"distance": from.distance_to(result.position)  # Added for reference
	}

# === NEW: Create visual marker at click position ===
func _create_click_marker(position: Vector3) -> void:
	if not _click_marker_parent:
		return
	
	# Create marker mesh instance
	var marker = MeshInstance3D.new()
	marker.name = "ClickMarker"
	
	# Create sphere mesh for marker
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radial_segments = 16
	sphere_mesh.rings = 8
	sphere_mesh.radius = floor_click_marker_size
	sphere_mesh.height = floor_click_marker_size * 2.0
	marker.mesh = sphere_mesh
	
	# Create material with transparency
	var marker_mat = StandardMaterial3D.new()
	marker_mat.albedo_color = floor_click_marker_color
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.vertex_color_use_as_albedo = false
	marker.material_override = marker_mat
	
	# Position marker
	marker.global_position = position + Vector3.UP * 0.01  # Slight offset to avoid z-fighting
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add to scene
	_click_marker_parent.add_child(marker)
	
	# Add to tracking array
	_floor_click_data.markers.append({
		"mesh_instance": marker,
		"lifetime": floor_click_marker_duration
	})
	
	# Create ripple effect (optional enhancement)
	_create_ripple_effect(position)

# === NEW: Create ripple effect for enhanced visual feedback ===
func _create_ripple_effect(position: Vector3) -> void:
	# Create a torus for ripple effect
	var ripple = MeshInstance3D.new()
	ripple.name = "RippleEffect"
	
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = floor_click_marker_size * 0.8
	torus_mesh.outer_radius = floor_click_marker_size * 1.2
	torus_mesh.rings = 3
	torus_mesh.ring_segments = 12
	ripple.mesh = torus_mesh
	
	var ripple_mat = StandardMaterial3D.new()
	ripple_mat.albedo_color = Color(floor_click_marker_color.r, floor_click_marker_color.g, floor_click_marker_color.b, 0.3)
	ripple_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ripple_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ripple.material_override = ripple_mat
	
	ripple.global_position = position + Vector3.UP * 0.005
	ripple.rotation.x = -PI/2  # Flat on ground
	ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	_click_marker_parent.add_child(ripple)
	
	# Animate ripple expansion and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ripple, "scale", Vector3(3, 3, 1), floor_click_marker_duration)
	tween.tween_property(ripple.material_override, "albedo_color:a", 0.0, floor_click_marker_duration)
	tween.chain().tween_callback(ripple.queue_free)

func _handle_mouse_button(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	
	# Skip if in pivot transition or drag mode
	if _state == State.PIVOT_TRANSITIONING or _state == State.PIVOT_DRAG_DISTANCE:
		return
	
	# Skip if floor click is active
	if _floor_click_initiated:
		return
		
	var mb_event := event as InputEventMouseButton
	var target_button := MOUSE_BUTTON_MIDDLE if action_mouse_button == "MIDDLE_BUTTON" else MOUSE_BUTTON_LEFT
	
	if mb_event.button_index == target_button:
		if mb_event.pressed:
			_state = State.TRANSLATED if mb_event.shift_pressed else State.ROTATED
		else:
			_state = State.IDLE

func _handle_mouse_motion(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
		
	var mm_event := event as InputEventMouseMotion
	
	match _state:
		State.IDLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			pivot_pos = _pivot_transform.origin
		State.ROTATED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			_rotate_camera(mm_event.relative)
		State.TRANSLATED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			_translate_camera(mm_event.relative)
		State.PIVOT_TRANSITIONING:
			# Allow look around during transition if needed
			pass
		State.PIVOT_DRAG_DISTANCE:
			# Handled by _process_floor_click_drag
			pass

func _rotate_camera(relative: Vector2) -> void:
	var euler_angles = _pivot_transform.basis.get_euler()
	euler_angles.x += relative.y * _MOUSE_SENSITIVITY * rotation_speed
	euler_angles.x = clampf(euler_angles.x, -PI/2 + _ANGLE_GAP, PI/2 - _ANGLE_GAP)
	euler_angles.y -= relative.x * _MOUSE_SENSITIVITY * rotation_speed
	_pivot_transform.basis = Basis.from_euler(euler_angles)
	
	_cam_from_pivot_dist = global_position.distance_to(pivot_pos)
	var new_cam_pos: Vector3 = _pivot_transform.basis.z * -(_cam_from_pivot_dist) + pivot_pos
	if global_position != pivot_pos:
		look_at_from_position(new_cam_pos, pivot_pos)

func _translate_camera(relative: Vector2) -> void:
	var translation = Vector3(
		-relative.x * _MOUSE_SENSITIVITY * translation_speed,
		relative.y * _MOUSE_SENSITIVITY * translation_speed, 
		0
	)
	_pivot_transform = _pivot_transform.translated_local(translation)
	global_transform = global_transform.translated_local(translation)

func _handle_mouse_wheel(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
		
	var mb_event := event as InputEventMouseButton
	var distance_to_pivot := global_position.distance_to(pivot_pos)
	
	if mb_event.button_index == MOUSE_BUTTON_WHEEL_UP and distance_to_pivot > zoom_in:
		translate_object_local(Vector3.FORWARD * _WHEEL_SENSITIVITY * zoom_speed)
	elif mb_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and distance_to_pivot < zoom_out:
		translate_object_local(Vector3.FORWARD * -_WHEEL_SENSITIVITY * zoom_speed)

## MECE collision handling system
func _handle_floor_collision() -> void:
	if not floor_collision_enabled:
		return
		
	match collision_type:
		"Clamp":
			_apply_clamp_collision()
		"Raycast":
			_apply_raycast_collision()

func _apply_clamp_collision() -> void:
	var target_y := floor_y_position + collision_offset
	if global_position.y < target_y:
		var new_pos := global_position
		new_pos.y = target_y
		global_position = new_pos

func _apply_raycast_collision() -> void:
	var collision_info := _perform_floor_raycast()
	
	if collision_info.is_colliding:
		_collision_data = collision_info
		var target_y = collision_info.last_hit_point.y + collision_offset
		
		if global_position.y < target_y:
			var new_pos := global_position
			new_pos.y = target_y
			global_position = new_pos
			
			# Ensure pivot stays in sync
			if _state == State.IDLE:
				pivot_pos.y = max(pivot_pos.y, target_y)

## Performs comprehensive floor detection raycast
func _perform_floor_raycast() -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return _get_empty_collision_data()
	
	# CRITICAL FIX: Cast ray DOWNWARD from above the camera
	var ray_start := global_position + Vector3.UP * ray_length
	var ray_end := global_position - Vector3.UP * ray_length
	
	var query := PhysicsRayQueryParameters3D.new()
	query.from = ray_start
	query.to = ray_end
	query.collision_mask = collision_mask
	query.exclude = [self]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	query.hit_back_faces = true  # Important for CSG
	
	var result := space_state.intersect_ray(query)
	
	if result.is_empty():
		return _get_empty_collision_data()
	
	return {
		"last_hit_point": result.position,
		"last_hit_normal": result.normal,
		"is_colliding": true,
		"distance_to_floor": global_position.y - result.position.y
	}

func _get_empty_collision_data() -> Dictionary:
	return {
		"last_hit_point": Vector3.ZERO,
		"last_hit_normal": Vector3.UP,
		"is_colliding": false,
		"distance_to_floor": INF
	}

## Public API for external queries
func get_floor_distance() -> float:
	if floor_collision_enabled and collision_type == "Raycast":
		var info := _perform_floor_raycast()
		return info.distance_to_floor
	elif floor_collision_enabled and collision_type == "Clamp":
		return global_position.y - floor_y_position
	return INF

func is_near_floor(threshold: float = 1.0) -> bool:
	return get_floor_distance() < threshold

# === NEW: Public API for floor click feature ===
## Programmatically set pivot to a world position (with optional smooth transition)
func set_pivot_to_position(world_pos: Vector3, smooth: bool = true, maintain_distance: bool = true) -> void:
	# Cancel any ongoing drag operation
	if _floor_click_data.drag_active:
		_floor_click_data.drag_active = false
		_state = State.IDLE
	
	_floor_click_data.target_pivot = world_pos
	
	if smooth and floor_click_smooth_transition and not _floor_click_data.drag_active:
		_floor_click_data.start_pivot = pivot_pos
		_floor_click_data.is_transitioning = true
		_floor_click_data.transition_progress = 0.0
		_state = State.PIVOT_TRANSITIONING
	else:
		pivot_pos = world_pos
		if maintain_distance or floor_click_maintain_distance:
			var direction = (global_position - pivot_pos).normalized()
			var new_cam_pos = pivot_pos + direction * _cam_from_pivot_dist
			look_at_from_position(new_cam_pos, pivot_pos)

## Set camera distance from pivot programmatically
func set_pivot_distance(distance: float, smooth: bool = false) -> void:
	distance = clampf(distance, floor_click_drag_min_distance, floor_click_drag_max_distance)
	
	if smooth:
		# Could implement smooth distance transition here
		_cam_from_pivot_dist = distance
	else:
		_cam_from_pivot_dist = distance
		var direction = (global_position - pivot_pos).normalized()
		var new_cam_pos = pivot_pos + direction * distance
		look_at_from_position(new_cam_pos, pivot_pos)

## Cancel any ongoing floor click operation
func cancel_floor_click_operation() -> void:
	_floor_click_initiated = false
	_mouse_button_held = false
	_floor_click_data.drag_active = false
	_floor_click_data.is_transitioning = false
	if _state == State.PIVOT_DRAG_DISTANCE or _state == State.PIVOT_TRANSITIONING:
		_state = State.IDLE
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Configure drag sensitivity at runtime
func set_drag_sensitivity(sensitivity: float) -> void:
	floor_click_drag_sensitivity = clampf(sensitivity, 0.001, 0.05)
	_floor_click_data.drag_sensitivity = floor_click_drag_sensitivity

## Check if a world position is visible and clickable
func is_position_clickable(world_pos: Vector3) -> bool:
	if not is_position_in_frustum(world_pos):
		return false
	
	# Additional raycast check to ensure no obstacles
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return false
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = global_position
	query.to = world_pos
	query.collision_mask = floor_click_collision_mask
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	return result.is_empty() or result.position.distance_to(world_pos) < 0.1

# === HELPER: Simplified place_pivot for drag mode ===
func _place_pivot_instant(new_pivot_pos: Vector3) -> void:
	"""Instantly places pivot without transition for responsive drag control"""
	pivot_pos = new_pivot_pos
	_pivot_transform = Transform3D(Basis(), new_pivot_pos)
	if global_position != new_pivot_pos:
		_pivot_transform = _pivot_transform.looking_at(global_position)
		_cam_from_pivot_dist = global_position.distance_to(new_pivot_pos)


## Check if pivot is currently transitioning
func is_pivot_transitioning() -> bool:
	return _floor_click_data.is_transitioning

## Cancel ongoing pivot transition
func cancel_pivot_transition() -> void:
	_floor_click_data.is_transitioning = false
	_floor_click_data.transition_progress = 0.0
	_state = State.IDLE

## Get current pivot transition progress (0.0 to 1.0)
func get_pivot_transition_progress() -> float:
	return _floor_click_data.transition_progress if _floor_click_data.is_transitioning else 0.0

func _on_start_button_pressed() -> void:
	pass # Replace with function body.

func _on_stop_button_pressed() -> void:
	pass # Replace with function body.

func _on_clear_button_pressed() -> void:
	pass # Replace with function body.
