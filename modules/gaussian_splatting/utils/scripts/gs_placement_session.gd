class_name GSPlacementSession
extends RefCounted
## One pending import transaction. Live geometry/transform/residency stay viewer-owned.
enum Anchor { BASE_CENTRE, ORIGIN }
var viewer:Node
var model:Node3D
var anchor:Anchor=Anchor.BASE_CENTRE
var cursor:=Vector2.ZERO
var target:=Vector3.INF
var surface:="Reference floor"
var ready:=false
var previous_initial_framing:=false
var was_rendering:=false
var initial_node:=Transform3D.IDENTITY
var _initial_edit:=Transform3D.IDENTITY
var _initial_bounds:=AABB()
var _base:=Vector3.INF
var _base_surface:=""
var _base_cursor:=Vector2.INF
var _base_pose:=Transform3D.IDENTITY
var _base_lens:Array=[]
var _gs:=Vector3.INF
var _gs_cursor:=Vector2.INF
var _gs_pose:=Transform3D.IDENTITY
var _gs_lens:Array=[]
var _gs_time:=0
var _waiting:=false
var _request_id:=-1
var _request_cursor:=Vector2.INF
var _request_pose:=Transform3D.IDENTITY
var _request_lens:Array=[]
var _request_time:=0
var _confirm:=false
var _resolved:=false
var _force_pick:=false
var _confirm_cursor:=Vector2.INF
var _confirm_pose:=Transform3D.IDENTITY
var _confirm_lens:Array=[]

func _init(owner:Node)->void:
	viewer=owner
func lens(camera:Camera3D)->Array:
	return [camera.projection,camera.fov,camera.size,camera.near,camera.far,camera.frustum_offset,camera.h_offset,camera.v_offset,viewer.get_viewport().get_visible_rect().size,viewer.get_viewport().size]
func set_cursor(point:Vector2)->void:
	if cursor.distance_to(point)>3 and _confirm:_confirm=false;_resolved=false
	cursor=point
func set_anchor(value:int)->void:
	anchor=clampi(value,0,1) as Anchor
	_confirm=false;_resolved=false
func invalidate_pick()->void:
	_waiting=false;_gs=Vector3.INF;_request_id=-1
	if _confirm:_resolved=false;_force_pick=true
func request_confirmation()->void:
	var camera:Camera3D=viewer.get_camera()
	if not camera:return
	_confirm_cursor=cursor;_confirm_pose=camera.global_transform;_confirm_lens=lens(camera)
	if _waiting:viewer.rasterizer.cancel_pick();_waiting=false;_request_id=-1
	_confirm=true;_resolved=false;_force_pick=true
func needs_gs_pick()->bool:
	if model.import_kind==GaussianSplat.ImportKind.ENVIRONMENT:return false
	for record in viewer._records.values():
		var node:GaussianSplat=record.node.get_ref()
		if is_instance_valid(node) and node!=model and record.status=="loaded" and node.is_visible_in_tree():return true
	return false
func matches(camera:Camera3D,point:Vector2,pose:Transform3D,shape:Array)->bool:
	return cursor.distance_to(point)<1 and camera.global_transform.is_equal_approx(pose) and lens(camera)==shape
func physics_update()->void:
	if model.import_kind==GaussianSplat.ImportKind.ENVIRONMENT:_base=Vector3.INF;return
	var camera:Camera3D=viewer.get_camera()
	if not camera or not viewer.get_viewport().get_visible_rect().has_point(cursor):_base=Vector3.INF;return
	var origin:=camera.project_ray_origin(cursor)
	var direction:=camera.project_ray_normal(cursor)
	_base=Vector3.INF;_base_surface=""
	var query:=PhysicsRayQueryParameters3D.create(origin,origin+direction*camera.far)
	var hit:Dictionary=viewer.get_world_3d().direct_space_state.intersect_ray(query)
	# The guide floor deliberately does not occlude GS rendering. It is a fallback,
	# not a blocker in front of scanned surfaces or ordinary geometry below it.
	if not hit.is_empty() and hit.collider==viewer.camera_controller.ground:
		var excluded:Array[RID]=[hit.rid]
		query.exclude=excluded
		hit=viewer.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_base=hit.position
		_base_surface="Scene geometry"
	if not _base.is_finite():
		var height:float=viewer.camera_controller.ground_height()
		if not is_finite(height):height=0.0
		if absf(direction.y)>0.00001:
			var distance:float=(height-origin.y)/direction.y
			if distance>=0 and distance<=camera.far:_base=origin+direction*distance;_base_surface="Reference floor"
	_base_cursor=cursor;_base_pose=camera.global_transform;_base_lens=lens(camera)
func accept_pick(request_id:int,instance_id:int,point:Vector3)->void:
	if not _waiting or request_id!=_request_id:return
	_waiting=false
	var camera:Camera3D=viewer.get_camera()
	if not camera or not matches(camera,_request_cursor,_request_pose,_request_lens):
		_confirm=false;_resolved=false;return
	_gs=point if instance_id>0 and point.is_finite() else Vector3.INF
	_gs_cursor=_request_cursor;_gs_pose=_request_pose;_gs_lens=_request_lens;_gs_time=Time.get_ticks_msec()
	if _confirm:_resolved=true
func update()->void:
	if not is_instance_valid(model):viewer.cancel_model_placement();return
	var record:Dictionary=viewer._records.get(model.get_instance_id(),{})
	if model is GaussianSplat and (record.is_empty() or record.status=="failed"):viewer.cancel_model_placement();return
	if model.is_loaded and not ready:
		ready=true;initial_node=model.global_transform
		_initial_edit=viewer.get_asset_edit_transform(model);_initial_bounds=viewer.get_asset_world_bounds(model)
		if model.import_kind==GaussianSplat.ImportKind.AUTO:model.import_kind=viewer.resolve_import_kind(model)
	if ready and viewer.resolve_import_kind(model)==GaussianSplat.ImportKind.ENVIRONMENT:
		viewer.finish_environment_import();return
	var camera:Camera3D=viewer.get_camera()
	if not camera:return
	if _confirm and not matches(camera,_confirm_cursor,_confirm_pose,_confirm_lens):_confirm=false;_resolved=false
	var now:=Time.get_ticks_msec()
	target=_base if matches(camera,_base_cursor,_base_pose,_base_lens) else Vector3.INF
	surface=_base_surface
	if _gs.is_finite() and now-_gs_time<600 and matches(camera,_gs_cursor,_gs_pose,_gs_lens):
		var origin:=camera.project_ray_origin(cursor)
		if _base_surface=="Reference floor" or not target.is_finite() or origin.distance_to(_gs)<origin.distance_to(target)+0.01:target=_gs;surface="GS surface"
	var needs_pick:=needs_gs_pick()
	if _waiting and now-_request_time>5000:_waiting=false;viewer.rasterizer.cancel_pick()
	if needs_pick and viewer.get_viewport().get_visible_rect().has_point(cursor) and not _waiting and (_force_pick or now-_request_time>=100):
		_force_pick=false;_waiting=true;_request_cursor=cursor;_request_pose=camera.global_transform;_request_lens=lens(camera);_request_time=now
		_request_id=viewer.request_placement_pick(cursor)
	if not needs_pick:_resolved=true
	if ready and target.is_finite():
		var contact:=_initial_bounds.get_center()
		contact.y=_initial_bounds.position.y
		if anchor==Anchor.ORIGIN:contact=_initial_edit.origin
		var pose:=_initial_edit;pose.origin+=target-contact
		viewer.set_asset_edit_transform(model,pose)
	if _confirm and _resolved and ready and target.is_finite():viewer.confirm_model_placement()
func snapshot()->Dictionary:
	var valid:=target.is_finite()
	var bounds:AABB=viewer.get_asset_world_bounds(model) if ready and is_instance_valid(model) else AABB()
	return {"active":true,"kind":int(model.import_kind),"ready":ready,"valid":valid,"target":target,"surface":surface,"anchor":int(anchor),"bounds":bounds,"name":model.file_path.get_file() if is_instance_valid(model) else "Model","status":"Loading model…" if not ready else ("Point at a surface or reference floor" if not valid else ("Resolving surface…" if _confirm else "Click to place · Enter confirms · Esc cancels"))}
