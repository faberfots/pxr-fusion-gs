class_name GSModelTransformControls
extends Control
## Godot runtime gizmo submits edits to the existing GS/native pose and undo owners.
enum Mode { SELECT,MOVE,ROTATE,SCALE,ALL }
var viewer:GaussianSplattingViewer
var layout_host:Node
var mode:Mode=Mode.ALL
var local_space:=false
var runtime:GSRuntimeTransformGizmo
var gizmo_preferences:=GSGizmoPreferences.new()
var toolbar:GSFloatingPanel
var selection_label:Label
var buttons:Array[Button]=[]
var dragging:=false
var _drag_model:WeakRef
var _initial:=Transform3D.IDENTITY
var _pivot:=Vector3.ZERO
var _center:=Vector2.ZERO
var _ends:Array[Vector2]=[]
var _anchor_model:=""
var _anchor_local:=Vector3.ZERO
var _can_draw:=false
var _group_edit:Dictionary={}
var _group_node:Dictionary={}
var _group_refs:Dictionary={}
var _pending_edit:Dictionary={}
var _finish_when_ready:=false
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	toolbar=%Toolbar;selection_label=%SelectionLabel;runtime=%RuntimeTransformGizmo;runtime.controller=self
	gizmo_preferences.load_preferences()
	gizmo_preferences.changed.connect(func():
		if dragging:finish_drag(true)
		runtime.invalidate_preferences()
	)
	toolbar.drag_changed.connect(func(active):viewer.set_camera_blocker("model_toolbar",active))
	buttons.assign([%Select,%Move,%Rotate,%Scale,%Universal])
	for i in range(buttons.size()):buttons[i].pressed.connect(set_mode.bind(i))
	buttons[mode].button_pressed=true
	%LocalSpace.toggled.connect(func(value):
		if dragging:finish_drag(true)
		local_space=value
	)
	%Frame.pressed.connect(func():
		var model:=viewer.get_selected_asset()
		if model:viewer.frame_models(viewer.selected_model_ids)
	)
	%Models.item_selected.connect(func(index):viewer.select_model_id(%Models.get_item_metadata(index)))
	%SolidEdits.toggled.connect(func(value):viewer.mesh_edit_collisions_enabled=value)
	%ShapeQuality.item_selected.connect(func(index):viewer.set_mesh_edit_shape_quality(index))
	viewer.model_registry_changed.connect(_refresh_models)
	viewer.model_clicked.connect(_on_model_clicked)
	viewer.selection_changed.connect(func(_id):
		if dragging:finish_drag(true)
		runtime.native.active=false;runtime.hide();_can_draw=false
		_refresh_models()
	)
	get_viewport().size_changed.connect(_place_toolbar)
	_refresh_models();_place_toolbar()
func _refresh_models()->void:
	var list:OptionButton=%Models
	list.clear()
	if not is_instance_valid(viewer):return
	for record in viewer.get_asset_snapshot():
		if record.status!="loaded":continue
		list.add_item(str(record.file_path).get_file())
		var index:=list.item_count-1
		list.set_item_metadata(index,record.model_id)
		list.set_item_tooltip(index,str(record.file_path))
		if record.model_id==viewer.selected_model_id:list.select(index)
	list.tooltip_text="%d selected · choose active model" % viewer.selected_model_ids.size()
func _place_toolbar()->void:
	if not is_instance_valid(toolbar):return
	%Row.columns=10 if get_viewport_rect().size.x>=850 else 4
	toolbar.reset_size()
	GSUiScale.apply(toolbar)
	if toolbar._placed or toolbar._dragging:
		toolbar._fit()
		return
	var viewport:=get_viewport_rect().size
	var toolbar_size:=GSUiScale.extent(toolbar)
	var y:=viewport.y-toolbar_size.y-38
	var spaces:Array[Vector2]=[Vector2(12,viewport.x-12)]
	if is_instance_valid(layout_host):
		for obstacle in layout_host.get_ui_obstacles():
			if obstacle.end.y<y or obstacle.position.y>y+toolbar_size.y:continue
			var next:Array[Vector2]=[]
			for space in spaces:
				if obstacle.end.x+12<=space.x or obstacle.position.x-12>=space.y:next.append(space);continue
				if obstacle.position.x-12>space.x:next.append(Vector2(space.x,obstacle.position.x-12))
				if obstacle.end.x+12<space.y:next.append(Vector2(obstacle.end.x+12,space.y))
			spaces=next
	var best:=Vector2.ZERO
	for space in spaces:
		if space.y-space.x>=toolbar_size.x and space.y-space.x>best.y-best.x:best=space
	if best.y>best.x:toolbar.position=Vector2((best.x+best.y-toolbar_size.x)*0.5,y)
	else:toolbar.position=Vector2(maxf(12,(viewport.x-toolbar_size.x)*0.5),24)
func set_mode(value:int)->void:
	if dragging:finish_drag(true)
	mode=value as Mode
	for i in range(buttons.size()):buttons[i].set_pressed_no_signal(i==value)
	queue_redraw()
func reset_toolbar_layout()->void:
	toolbar._placed=false
	var file:=ConfigFile.new();file.load(GSFloatingPanel.LAYOUT_PATH)
	if file.has_section(toolbar.layout_id):file.erase_section(toolbar.layout_id)
	file.save(GSFloatingPanel.LAYOUT_PATH)
	_place_toolbar()
func _on_model_clicked(id:String,point:Vector3)->void:
	var model:=viewer.get_selected_asset()
	if model and point.is_finite():
		_anchor_model=id
		_anchor_local=viewer.get_asset_edit_transform(model).affine_inverse()*point
func _process(_delta:float)->void:
	var model:=viewer.get_selected_asset() if is_instance_valid(viewer) else null
	if dragging and (not is_visible_in_tree() or not model or _drag_model.get_ref()!=model or not model.is_visible_in_tree() or viewer._atlas_migration or viewer.composition_busy or model.transform_locked):finish_drag(true)
	if is_instance_valid(viewer) and (viewer.placement_active or viewer.model_navigation_active):
		if dragging:finish_drag(true)
		toolbar.hide();runtime.hide();runtime.native.active=false;_can_draw=false;return
	var solid:CheckButton=get_node_or_null("%SolidEdits")
	if solid:solid.set_pressed_no_signal(viewer.mesh_edit_collisions_enabled);solid.visible=model is GSSceneMesh
	var quality:OptionButton=get_node_or_null("%ShapeQuality")
	if quality:
		quality.visible=model is GSSceneMesh and viewer.mesh_edit_collisions_enabled
		quality.select(viewer.mesh_edit_shape_quality)
		quality.disabled=dragging or viewer.camera_controller.has_movement_blocker("model_transform")
	%LocalSpace.set_pressed_no_signal(local_space);%LocalSpace.disabled=dragging
	if dragging and not _pending_edit.is_empty() and viewer.apply_asset_edits(_pending_edit):
		_pending_edit.clear()
		if _finish_when_ready:finish_drag(false)
	selection_label.text=(("Locked · " if model.transform_locked else "")+model.file_path.get_file()) if model else "Click a model"
	%Models.modulate=Color(1,0.75,0.74) if viewer.selected_model_ids.size()>1 else Color.WHITE
	selection_label.tooltip_text=selection_label.text;toolbar.visible=model!=null;_place_toolbar()
	_can_draw=is_visible_in_tree() and model!=null and model.is_visible_in_tree() and mode!=Mode.SELECT and not viewer._atlas_migration and not viewer.composition_busy and not model.transform_locked
	for selected in viewer.get_selected_assets():
		if selected.transform_locked:_can_draw=false
	var camera:=viewer.get_camera()
	if not camera:_can_draw=false
	if _can_draw:
		if not dragging:
			_pivot=viewer.get_asset_edit_transform(model)*_anchor_local if _anchor_model==model.model_id else viewer.get_asset_world_bounds(model).get_center()
			if viewer.selected_model_ids.size()>1:
				_pivot=Vector3.ZERO
				for selected in viewer.get_selected_assets():_pivot+=viewer.get_asset_world_bounds(selected).get_center()
				_pivot/=viewer.selected_model_ids.size()
		_can_draw=not camera.is_position_behind(_pivot)
	var basis:Basis=viewer.get_asset_edit_transform(model).basis.orthonormalized() if model else Basis.IDENTITY
	runtime.synchronize(camera,_pivot,basis,_can_draw,_port_mode(),local_space)
	if _can_draw:
		_center=camera.unproject_position(runtime.proxy.global_position)
		_ends.clear()
		for axis in range(3):_ends.append(runtime.axis_screen(axis))
func _port_mode()->int:
	return [0,Gizmo3D.ToolMode.MOVE,Gizmo3D.ToolMode.ROTATE,Gizmo3D.ToolMode.SCALE,Gizmo3D.ToolMode.ALL][mode]
func handle_at(point:Vector2)->int:return -1 if _can_draw and runtime.hit_test(point) else -2
func _input(event:InputEvent)->void:
	if not is_instance_valid(viewer) or not is_visible_in_tree() or viewer.placement_active:return
	if event is InputEventKey and event.keycode in [KEY_CTRL,KEY_SHIFT]:runtime.feed(event)
	if dragging:
		if event is InputEventMouseMotion:
			if not _finish_when_ready:runtime.feed(event)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:finish_drag(false);get_viewport().set_input_as_handled()
			elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:finish_drag(true);get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:finish_drag(true);get_viewport().set_input_as_handled()
		return
	if not _can_draw or get_viewport().gui_get_hovered_control()!=null or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT):
		runtime.feed(event)
		if dragging:get_viewport().set_input_as_handled()
func _unhandled_key_input(event:InputEvent)->void:
	if is_instance_valid(viewer) and viewer.placement_active:return
	if event is InputEventKey and event.pressed and not event.echo and (event.ctrl_pressed or event.meta_pressed) and event.keycode==KEY_Z:
		var focus:=get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:return
		viewer.undo_transform(event.shift_pressed);get_viewport().set_input_as_handled();return
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode>=KEY_1 and event.keycode<=KEY_5 and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		set_mode(event.keycode-KEY_1);get_viewport().set_input_as_handled()
func begin_native_drag()->bool:
	if viewer.model_navigation_active:return false
	var model:=viewer.get_selected_asset()
	if not model or not model.is_loaded or viewer._atlas_migration or viewer.composition_busy or mode==Mode.SELECT:return false
	for asset in viewer.get_selected_assets():
		if asset.transform_locked:return false
	if absf(model.global_basis.determinant())<1.0e-18:return false
	_initial=viewer.get_asset_edit_transform(model);_drag_model=weakref(model);dragging=true
	_pending_edit.clear();_finish_when_ready=false;viewer.prepare_asset_edits(viewer.selected_model_ids)
	_group_edit.clear();_group_node.clear();_group_refs.clear()
	for selected in viewer.get_selected_assets():
		_group_edit[selected.model_id]=viewer.get_asset_edit_transform(selected);_group_node[selected.model_id]=selected.global_transform
		_group_refs[selected.model_id]=weakref(selected)
	viewer.set_camera_blocker("model_transform",true)
	return true
func begin_drag(axis:int,point:Vector2)->bool:
	if mode==Mode.SELECT or not _can_draw:return false
	var kind:int=[0,Gizmo3D.TransformMode.TRANSLATE,Gizmo3D.TransformMode.ROTATE,Gizmo3D.TransformMode.SCALE,Gizmo3D.TransformMode.TRANSLATE][mode]
	runtime.native.begin_handle(axis,point,kind)
	return dragging
func update_drag(point:Vector2)->void:
	if dragging:runtime.native.update_handle(point)
func apply_native_delta(delta:Transform3D)->void:
	if not dragging:return
	var poses:Dictionary={}
	for selected in viewer.get_selected_assets():
		if _group_edit.has(selected.model_id):poses[selected.model_id]=delta*_group_edit[selected.model_id]
	_pending_edit=poses if not viewer.apply_asset_edits(poses) else {}
func finish_drag(cancelled:bool)->void:
	if not cancelled and not _pending_edit.is_empty():_finish_when_ready=true;return
	_pending_edit.clear();_finish_when_ready=false
	if cancelled and is_instance_valid(viewer):viewer.cancel_asset_edits()
	var model:Node3D=_drag_model.get_ref() if _drag_model else null
	if dragging:
		var after:Dictionary={}
		for id in _group_node:
			var selected:Node3D=_group_refs[id].get_ref()
			if not is_instance_valid(selected):continue
			if cancelled:selected.global_transform=_group_node[selected.model_id]
			after[selected.model_id]=selected.global_transform
		if not cancelled:viewer.commit_transform_edit(_group_node,after)
	_group_edit.clear();_group_node.clear();_group_refs.clear()
	dragging=false;_drag_model=null
	if is_instance_valid(runtime):runtime.native.stop();runtime.request_draw()
	if is_instance_valid(viewer):viewer.set_camera_blocker("model_transform",false)
func _notification(what:int)->void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and dragging:finish_drag(true)
func _exit_tree()->void:
	if is_instance_valid(viewer):
		finish_drag(true)
		viewer.set_camera_blocker("model_toolbar",false)
