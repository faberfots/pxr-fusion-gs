class_name GSCameraSafetySettings
extends Resource
## Navigation policy only. The referenced stage collider owns ground placement.
@export var protected_fly := true
@export_range(0.05, 1.0, 0.01) var radius := 0.2
@export_range(0.005, 0.2, 0.005) var margin := 0.025
@export_flags_3d_physics var collision_mask := 1
@export var home_position := Vector3(6, 3.5, 8)
@export var home_target := Vector3(0, 0.5, 0)
