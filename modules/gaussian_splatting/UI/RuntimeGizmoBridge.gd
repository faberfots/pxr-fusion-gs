extends "res://addons/Gizmo3DScript/gizmo3D.gd"
## Godot's port handles geometry/rays; only the existing controller writes model poses.
var host:Control
var active:=false
var redraw_requested:=true
var start_proxy:=Transform3D.IDENTITY
var _ignore_end:=false
var _pointer_offset:=Vector2.ZERO
func _ready()->void:
	super._ready()
	set_process_unhandled_input(false)
	transform_begin.connect(_begin)
	transform_end.connect(_end)
func _process(delta:float)->void:
	if not active:
		return
	if not redraw_requested:return
	redraw_requested=false
	super._process(delta)
	%ScaleCenter.visible=(mode & ToolMode.SCALE)!=0 and scale_axes==AxisMode.ALL
	%MoveCenter.visible=mode==ToolMode.MOVE and move_axes==AxisMode.ALL
	%ScaleCenter.scale=Vector3.ONE*_gizmo_scale
	%MoveCenter.scale=Vector3.ONE*_gizmo_scale
	%ScaleCenter.material_override.albedo_color=Color(0.9,0.9,0.9,opacity)
func _unhandled_input(_event:InputEvent)->void:pass
func feed(event:InputEvent)->void:
	if event is InputEventKey:
		if event.keycode==KEY_CTRL:_snapping=event.pressed
		elif event.keycode==KEY_SHIFT:_shift_snap=event.pressed
		return
	if not active:return
	host.request_draw()
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		_pointer_offset=Vector2.ZERO
		_snapping=event.ctrl_pressed;_shift_snap=event.shift_pressed
		if center_hit(event.position):
			begin_handle(-1,event.position,TransformMode.SCALE if mode & ToolMode.SCALE else TransformMode.TRANSLATE)
			return
	if event is InputEventMouseMotion and _editing and _pointer_offset!=Vector2.ZERO:
		var shifted:=event.duplicate() as InputEventMouseMotion;shifted.position+=_pointer_offset
		super._unhandled_input(shifted);return
	super._unhandled_input(event)
func center_hit(point:Vector2)->bool:
	var available:bool=(mode==ToolMode.MOVE and move_axes==AxisMode.ALL) or ((mode & ToolMode.SCALE)!=0 and scale_axes==AxisMode.ALL)
	return active and available and point.distance_to(_point_to_screen(global_position))<maxf(6.0,size*0.12)
func _calculate_spatial_bounds(_parent:Node3D,_omit_top_level:=false,_bounds_orientation:=Transform3D.IDENTITY)->AABB:
	if not host or not host.proxy:return AABB()
	return host.proxy.global_transform.affine_inverse()*host.selection_bounds
func _begin(_kind:int)->void:
	start_proxy=host.proxy.global_transform
	if not host.controller.begin_native_drag():stop()
func _end(_kind:int)->void:
	if not _ignore_end:host.controller.finish_drag(false)
func _transform_gizmo_apply(_node:Node3D,pose:Transform3D,_local:bool)->void:
	if pose.is_finite() and absf(pose.basis.determinant())>1.0e-18:
		host.controller.apply_native_delta(pose*start_proxy.affine_inverse())
func _edit_scale(value:Vector3)->Vector3:
	# Preserve positive drag scaling; do not sweep physical shapes through a
	# singular zero scale. Authored mirrored matrices/undo remain untouched.
	return value.max(Vector3.ONE*-0.999)
func stop()->void:
	_ignore_end=true;_editing=false;_edit.mode=TransformMode.NONE;_ignore_end=false
	_pointer_offset=Vector2.ZERO
	_select_gizmo_highlight_axis(-1)
func begin_handle(axis:int,point:Vector2,kind:int)->void:
	_pointer_offset=Vector2.ZERO
	if kind==TransformMode.SCALE:
		if axis<0:_pointer_offset=_point_to_screen(global_position)-point+Vector2(1,-1).normalized()*size*0.8
		elif point.distance_to(_point_to_screen(global_position))<1:_pointer_offset=_point_to_screen(global_position+global_basis[axis].normalized()*_gizmo_scale*GIZMO_SCALE_OFFSET)-point
	_compute_edit(point+_pointer_offset)
	_edit.mode=kind as TransformMode
	_edit.plane=([TransformPlane.X,TransformPlane.Y,TransformPlane.Z][axis] if axis>=0 else TransformPlane.VIEW) as TransformPlane
	_edit.mouse_pos=point+_pointer_offset;_edit.initial_click_vector=Vector3.ZERO;_edit.previous_rotation_vector=Vector3.ZERO
	_edit.accumulated_rotation_angle=0;_edit.display_rotation_angle=0;_edit.gizmo_initiated=false
	_editing=true;_begin(kind)
	host.request_draw()
func update_handle(point:Vector2)->void:
	_edit.mouse_pos=point+_pointer_offset
	_update_transform(false)
	host.request_draw()
func _on_focus_exited()->void:
	if host and host.controller and host.controller.dragging:host.controller.finish_drag(true)
	super._on_focus_exited()
