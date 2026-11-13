extends Button
## Pure presentation: action ownership stays with the containing controller.
var _hover:Tween
func _ready()->void:
	mouse_entered.connect(_raise);focus_entered.connect(_raise)
	mouse_exited.connect(_lower);focus_exited.connect(_lower)
	pivot_offset=size*0.5
func _raise()->void:
	if _hover:_hover.kill()
	_hover=create_tween().set_parallel(true)
	_hover.tween_property(self,"scale",Vector2.ONE*1.055,0.13).set_trans(Tween.TRANS_QUAD)
	_hover.tween_property(self,"modulate",Color(1.1,1.1,1.05),0.13)
func _lower()->void:
	if _hover:_hover.kill()
	_hover=create_tween().set_parallel(true)
	_hover.tween_property(self,"scale",Vector2.ONE,0.16)
	_hover.tween_property(self,"modulate",Color.WHITE,0.16)
