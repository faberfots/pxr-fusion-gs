class_name GSModelTransformControls
extends Control
## Screen handles edit the selected GaussianSplat Node3D. No parallel transform state.
enum Mode { SELECT,MOVE,ROTATE,SCALE }
const AXES:=[Vector3.RIGHT,Vector3.UP,Vector3.BACK]
const COLORS:=[Color("ff6b78"),Color("74dda4"),Color("6aaeff")]
var viewer:GaussianSplattingViewer
var mode:Mode=Mode.SELECT
var toolbar:PanelContainer
var selection_label:Label
var buttons:Array[Button]=[]
var dragging:=false
var _drag_model:WeakRef
var _initial:=Transform3D.IDENTITY
var _initial_node:=Transform3D.IDENTITY
var _pivot:=Vector3.ZERO
var _start:=Vector2.ZERO
var _center:=Vector2.ZERO
var _ends:Array[Vector2]=[]
var _axis:=-1
var _units:=0.01
var _anchor_model:=""
var _anchor_local:=Vector3.ZERO
var _can_draw:=false
func _ready()->void:
	name="ModelTransformControls"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toolbar=PanelContainer.new();add_child(toolbar)
	var style:=StyleBoxFlat.new();style.bg_color=Color("18222f");style.set_corner_radius_all(8)
	style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=6;style.content_margin_bottom=6
	toolbar.add_theme_stylebox_override("panel",style)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",6);toolbar.add_child(row)
	selection_label=Label.new();selection_label.text="Click a model";selection_label.custom_minimum_size.x=110;selection_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;row.add_child(selection_label)
	for i in range(4):
		var button:=Button.new();button.text=["Select","Move","Rotate","Scale"][i];button.toggle_mode=true
		button.pressed.connect(set_mode.bind(i));row.add_child(button);buttons.append(button)
	buttons[0].button_pressed=true
	tooltip_text="Click a model, then drag a handle. 1 Select · 2 Move · 3 Rotate · 4 Scale · Esc cancel"
	viewer.model_clicked.connect(_on_model_clicked)
	viewer.selection_changed.connect(func(_id):
		if dragging:finish_drag(true)
	)
	get_viewport().size_changed.connect(_place_toolbar)
	_place_toolbar()
func _place_toolbar()->void:
	if not is_instance_valid(toolbar):return
	toolbar.reset_size()
	toolbar.position=Vector2(maxf(8,(get_viewport_rect().size.x-toolbar.size.x)*0.5),get_viewport_rect().size.y-toolbar.size.y-30)
func set_mode(value:int)->void:
	if dragging:finish_drag(true)
	mode=value as Mode
	for i in range(buttons.size()):buttons[i].set_pressed_no_signal(i==value)
	queue_redraw()
func _on_model_clicked(id:String,point:Vector3)->void:
	var model:=viewer.get_selected_model()
	if model and point.is_finite():
		_anchor_model=id
		_anchor_local=viewer.get_model_edit_transform(model).affine_inverse()*point
func _process(_delta:float)->void:
	var model:=viewer.get_selected_model() if is_instance_valid(viewer) else null
	if dragging and (not is_visible_in_tree() or not model or not model.is_visible_in_tree() or viewer._atlas_migration):finish_drag(true)
	selection_label.text=model.file_path.get_file() if model else "Click a model"
	selection_label.tooltip_text=selection_label.text
	toolbar.visible=model!=null
	_place_toolbar()
	_can_draw=false
	queue_redraw()
	if not model or not model.is_visible_in_tree() or mode==Mode.SELECT or viewer._atlas_migration:return
	var camera:=viewer.get_camera()
	if not camera:return
	if not dragging:
		_pivot=viewer.get_model_edit_transform(model)*_anchor_local if _anchor_model==model.model_id else viewer.get_model_world_bounds(model).get_center()
	if camera.is_position_behind(_pivot):queue_redraw();return
	var visible_pivot:Vector3=viewer.get_model_edit_transform(model)*(_initial.affine_inverse()*_pivot) if dragging and mode==Mode.MOVE else _pivot
	_center=camera.unproject_position(visible_pivot)
	var distance:=maxf(0.1,-(camera.global_transform.affine_inverse()*_pivot).z)
	_units=camera.project_position(_center+Vector2.RIGHT,distance).distance_to(camera.project_position(_center,distance))
	_ends.clear()
	for axis in range(3):
		var direction:Vector3=viewer.get_model_edit_transform(model).basis[axis].normalized() if mode==Mode.SCALE else AXES[axis]
		var projected:=camera.unproject_position(visible_pivot+direction*maxf(0.1,_units*80))-_center
		var fallback:Vector2=[Vector2.RIGHT,Vector2.UP,Vector2(-0.7,0.7)][axis]
		_ends.append(_center+(projected.normalized() if projected.length()>5 else fallback.normalized())*80)
	_can_draw=true
	queue_redraw()
func _draw()->void:
	if not _can_draw:return
	if mode==Mode.ROTATE:
		for axis in range(3):
			var radius:=38.0+axis*12
			draw_arc(_center,radius,0,TAU,72,COLORS[axis],2,true)
			draw_string(ThemeDB.fallback_font,_center+Vector2(radius+4,0),["X","Y","Z"][axis],HORIZONTAL_ALIGNMENT_LEFT,-1,13,COLORS[axis])
	else:
		for axis in range(3):
			draw_line(_center,_ends[axis],Color(0,0,0,0.65),5,true)
			draw_line(_center,_ends[axis],COLORS[axis],2.5,true)
			draw_circle(_ends[axis],5,COLORS[axis],true,-1,true)
			draw_string(ThemeDB.fallback_font,_ends[axis]+Vector2(8,-5),["X","Y","Z"][axis],HORIZONTAL_ALIGNMENT_LEFT,-1,14,COLORS[axis])
	draw_circle(_center,8,Color("18222f"),true,-1,true)
	draw_arc(_center,8,0,TAU,24,Color.WHITE,1.5,true)
func handle_at(point:Vector2)->int:
	if not _can_draw:return -2
	if point.distance_to(_center)<12:return -1
	if mode==Mode.ROTATE:
		for axis in range(3):
			if absf(point.distance_to(_center)-(38+axis*12))<6:return axis
	else:
		for axis in range(3):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,_center.lerp(_ends[axis],0.2),_ends[axis]))<8:return axis
	return -2
func _input(event:InputEvent)->void:
	if not is_instance_valid(viewer) or not is_visible_in_tree():return
	if dragging:
		if event is InputEventMouseMotion:update_drag(event.position);get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:finish_drag(false);get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:finish_drag(true);get_viewport().set_input_as_handled()
		return
	if get_viewport().gui_get_hovered_control()!=null:return
	if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var hit:=handle_at(event.position)
		if hit!=-2 and begin_drag(hit,event.position):get_viewport().set_input_as_handled()
func _unhandled_key_input(event:InputEvent)->void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode>=KEY_1 and event.keycode<=KEY_4 and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		set_mode(event.keycode-KEY_1);get_viewport().set_input_as_handled()
func begin_drag(axis:int,point:Vector2)->bool:
	var model:=viewer.get_selected_model()
	if not model or not model.is_loaded or viewer._atlas_migration or mode==Mode.SELECT:return false
	if absf(model.global_basis.determinant())<0.000001:return false
	_axis=axis;_start=point;_initial=viewer.get_model_edit_transform(model);_initial_node=model.global_transform;_drag_model=weakref(model);dragging=true
	viewer.set_camera_blocker("model_transform",true)
	return true
func update_drag(point:Vector2)->void:
	var model:GaussianSplat=_drag_model.get_ref() if _drag_model else null
	if not model:return
	var delta:=point-_start
	var result:=_initial
	if mode==Mode.MOVE:
		if _axis<0:
			var camera:=viewer.get_camera()
			result.origin+=camera.global_basis.x*delta.x*_units-camera.global_basis.y*delta.y*_units
		else:result.origin+=AXES[_axis]*delta.dot((_ends[_axis]-_center).normalized())*_units
	elif mode==Mode.ROTATE:
		var angle:=(_start-_center).angle_to(point-_center)
		var axis:Vector3=AXES[_axis] if _axis>=0 else viewer.get_camera().global_basis.z
		var rotation:=Basis(axis,angle)
		if _axis<0:
			var camera:=viewer.get_camera()
			rotation=Basis(camera.global_basis.y,-delta.x*0.01)*Basis(camera.global_basis.x,-delta.y*0.01)
		result.basis=rotation*_initial.basis;result.origin=_pivot+rotation*(_initial.origin-_pivot)
	elif mode==Mode.SCALE:
		var amount:float=delta.x-delta.y if _axis<0 else delta.dot((_ends[_axis]-_center).normalized())
		var factor:=exp(clampf(amount*0.006,-4,4))
		var factors:=Vector3.ONE
		if _axis<0:factors=Vector3.ONE*factor
		else:factors[_axis]=factor
		result.basis=_initial.basis*Basis.from_scale(factors)
		result.origin=_pivot+(result.basis*_initial.basis.inverse())*(_initial.origin-_pivot)
	viewer.set_model_edit_transform(model,result)
func finish_drag(cancelled:bool)->void:
	var model:GaussianSplat=_drag_model.get_ref() if _drag_model else null
	if cancelled and is_instance_valid(model) and model.is_inside_tree():model.global_transform=_initial_node
	dragging=false;_drag_model=null
	if is_instance_valid(viewer):viewer.set_camera_blocker("model_transform",false)
func _notification(what:int)->void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and dragging:finish_drag(true)
func _exit_tree()->void:
	if is_instance_valid(viewer):finish_drag(true)
