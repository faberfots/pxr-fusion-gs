extends MeshInstance3D
## Visual cursor for camera orbit/focus points
## Now decoupled from specific camera implementations
## Works with any CameraInterface-based camera

const MAX_ALPHA := 0.35

@onready var fade_tween : Tween
@onready var material : StandardMaterial3D = get_surface_override_material(0)

## Set cursor opacity directly
func set_alpha(alpha : float) -> void:
	if not material:
		push_warning("[Cursor] Material not initialized")
		return
	
	material.albedo_color.a = clampf(alpha, 0.0, MAX_ALPHA)

## Update cursor position with animation
func update_position(new_position : Vector3) -> void:
	if not material:
		return
	
	# If invisible, teleport immediately
	if material.albedo_color.a == 0:
		global_position = new_position
		return
	
	# If already at position, do nothing
	if global_position.is_equal_approx(new_position):
		return
	
	var displacement := new_position - global_position
	var direction := displacement.normalized()
	
	# Orient cursor toward movement direction
	var up_cross := Vector3.UP.cross(direction)
	if not up_cross.is_zero_approx():
		global_basis = Basis.IDENTITY.rotated(up_cross.normalized(), acos(Vector3.UP.dot(direction)))
	
	# Animate movement with squash & stretch
	var move_tween := create_tween().set_parallel()
	move_tween.tween_property(self, 'global_position', new_position, 0.2)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_CIRC)
	
	# Squash and stretch for visual feedback
	if mesh is CapsuleMesh:
		var distance := displacement.length()
		move_tween.tween_property(self, 'mesh:height', distance * 0.3, 0.05)
		move_tween.tween_property(self, 'mesh:radius', 0.025 / (1.0 + distance * 0.9), 0.05)
		move_tween.tween_property(self, 'mesh:height', 0.05, 0.05).set_delay(0.075)
		move_tween.tween_property(self, 'mesh:radius', 0.025, 0.05).set_delay(0.075)
	
	# Fade in/out animation
	_animate_fade()

## Animate cursor fade in and auto-fade out
func _animate_fade() -> void:
	if fade_tween:
		fade_tween.kill()
	
	if not material:
		return
	
	fade_tween = create_tween().set_parallel()
	fade_tween.tween_property(self, 'material:albedo_color:a', MAX_ALPHA, 0.25)
	fade_tween.tween_property(self, 'material:albedo_color:a', 0.0, 0.5).set_delay(2.0)

func _ready() -> void:
	if not material:
		material = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1, 0.8, 0.2, 0)
		set_surface_override_material(0, material)
