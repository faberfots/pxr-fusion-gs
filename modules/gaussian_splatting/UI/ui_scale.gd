class_name GSUiScale
extends RefCounted
## One owner for application HUD density. World and camera coordinates stay unscaled.
const FACTOR:float=0.67
static func apply(control:Control)->void:
	control.scale=Vector2.ONE*FACTOR
static func extent(control:Control)->Vector2:
	return control.size*control.scale.abs()
static func screen_rect(control:Control)->Rect2:
	return control.get_global_transform()*Rect2(Vector2.ZERO,control.size)
