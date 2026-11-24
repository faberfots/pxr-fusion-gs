class_name GSRuntimeTransformGizmo
extends Control
## A separate transparent World3D keeps editor handles out of GS depth/picking/captures.
var controller:GSModelTransformControls
var _last_state:Array=[]
var render_requests:=0
var _frame_pending:=false
var _preference_revision:=-1
var selection_bounds:=AABB()
@onready var camera:Camera3D=%GizmoCamera
@onready var proxy:Node3D=%GizmoPivot
@onready var native:Node3D=%NativeGizmo
func _ready()->void:
	native.host=self
	native.select(proxy)
	%GizmoImage.texture=%GizmoViewport.get_texture()
func synchronize(source:Camera3D,pivot:Vector3,basis:Basis,enabled:bool,tool_mode:int,local:bool)->void:
	visible=enabled;native.active=enabled
	if not enabled:_last_state.clear();%GizmoViewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;return
	%GizmoViewport.size=Vector2i(get_viewport().get_visible_rect().size)
	var preferences:=controller.gizmo_preferences
	if _preference_revision!=preferences.revision:
		_preference_revision=preferences.revision
		var config:=preferences.values
		native.size=float(config.size)*GSUiScale.FACTOR;native.opacity=config.opacity
		native.colors.assign([config.color_x,config.color_y,config.color_z]);native._set_colors()
		native.selection_box_color=config.bounds_color;native.show_selection_box=config.show_bounds
		native.show_axes=config.show_axes;native.show_transform_plane=config.show_planes
		native.show_rotation_line=config.show_rotation_line;native.show_rotation_arc=config.show_rotation_arc
		for key in ["translate_snap","rotate_snap","scale_snap","move_axes","rotation_axes","scale_axes"]:native.set(key,config[key])
	var bounds:=AABB()
	if preferences.values.show_bounds:
		var first:=true
		for asset in controller.viewer.get_selected_assets():
			var current:=controller.viewer.get_asset_world_bounds(asset)
			bounds=current if first else bounds.merge(current);first=false
	selection_bounds=bounds
	var fields:=["projection","fov","size","near","far","keep_aspect","frustum_offset","h_offset","v_offset"]
	var lens:Array=[]
	for field in fields:lens.append(source.get(field))
	var pose:=Transform3D(basis,pivot)
	if controller.dragging:
		var model:=controller.viewer.get_selected_asset()
		if model:pose=(controller.viewer.get_asset_edit_transform(model)*controller._initial.affine_inverse())*native.start_proxy
	var state:Array=[source.global_transform,lens,pose,tool_mode,local,size,preferences.revision,bounds]
	if state==_last_state:return
	_last_state=state
	camera.global_transform=source.global_transform
	for index in range(fields.size()):camera.set(fields[index],lens[index])
	proxy.global_transform=pose
	native.mode=tool_mode;native.use_local_space=local
	native._update_transform_gizmo()
	request_draw()
func invalidate_preferences()->void:
	_last_state.clear();_preference_revision=-1
func request_draw()->void:
	native.redraw_requested=true;render_requests+=1
	%GizmoViewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	if not _frame_pending:
		_frame_pending=true
		RenderingServer.frame_post_draw.connect(_frame_drawn,CONNECT_ONE_SHOT)
func _frame_drawn()->void:
	%GizmoViewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_frame_pending=false
func feed(event:InputEvent)->void:native.feed(event)
func hit_test(point:Vector2)->bool:return native.center_hit(point) or (native.active and native._transform_gizmo_select(point,true))
func axis_screen(axis:int)->Vector2:
	var tip:Vector3=native.global_position+native.global_basis[axis].normalized()*native._gizmo_scale*(native.GIZMO_ARROW_OFFSET+native.GIZMO_ARROW_SIZE*0.5)
	return camera.unproject_position(tip)
