class_name GSModelNavigation
extends RefCounted
## Optional geometry-shaped walking. The imported Node3D remains the live pose owner.
enum State { IDLE, PREPARING, WALKING }
var state:State=State.IDLE
var model_id:=""
var speed:=3.0
var status:=""
var _viewer:WeakRef
var _model:WeakRef
var _body:CharacterBody3D
var _before:=Transform3D.IDENTITY
var _keys:Dictionary={}
var _jump:=false
var _orbit:=false
var _offset:=Vector3(0,2,4)
var _basis:=Basis.IDENTITY
var _ignored_ground:=RID()
func _init(viewer:Node)->void:_viewer=weakref(viewer)
func start(model:GSSceneMesh)->Error:
	if state!=State.IDLE:return ERR_BUSY
	if not is_instance_valid(model) or not model.is_loaded or not model.is_visible_in_tree() or model.transform_locked or model.has_deformation:return ERR_UNAVAILABLE
	if absf(model.global_basis.determinant())<0.000001:return ERR_INVALID_DATA
	_model=weakref(model);model_id=model.model_id;_before=model.global_transform;_basis=model.global_basis
	state=State.PREPARING;status="Preparing shape collisions… Esc cancels"
	var viewer:Node=_viewer.get_ref();viewer.set_camera_blocker("model_navigation",true)
	var camera:CameraInterface=viewer.camera_controller.get_node_or_null("FreeLookCamera")
	if camera and camera!=viewer.get_camera():
		var camera_pose:Transform3D=viewer.get_camera().global_transform
		viewer.camera_controller.set_camera(camera);viewer.camera_controller.set_camera_transform(camera_pose)
	var bounds:AABB=viewer.get_asset_world_bounds(model)
	speed=clampf(bounds.size.y*1.5,0.25,20.0)
	_offset=viewer.get_camera().global_position-bounds.get_center()
	var height:=maxf(bounds.size.y,0.3)
	if _offset.length()<height or _offset.length()>height*8:_offset=Vector3(0,height*0.7,height*2.5)
	if model.prepare_motion_shapes(GSMeshMotionJob.Quality.DETAILED):_activate(model.motion_shapes);return OK
	if model.motion_error!=OK:stop(false);status="Shape preparation could not start.";return model.motion_error
	return OK
func pump()->void:
	if state==State.IDLE:return
	var model:GSSceneMesh=_model.get_ref() if _model else null
	if not is_instance_valid(model) or not model.is_visible_in_tree() or model.transform_locked:stop();return
	var viewer:Node=_viewer.get_ref()
	if not is_instance_valid(viewer) or viewer._closing:return
	if viewer.selected_model_id!=model_id or viewer.placement_active or viewer.composition_busy or viewer._atlas_migration:stop();return
	if state==State.PREPARING:
		status="Preparing shape collisions… %d%% · Esc cancels" % roundi(model.motion_progress()*100)
		if model.motion_error!=OK:stop(false);status="This model has no usable solid collision geometry.";return
		if model.prepare_motion_shapes(GSMeshMotionJob.Quality.DETAILED):_activate(model.motion_shapes)
func _activate(shapes:Array)->void:
	var viewer:Node=_viewer.get_ref();var model:GSSceneMesh=_model.get_ref()
	if not is_instance_valid(viewer) or not is_instance_valid(model):stop(false);return
	_body=CharacterBody3D.new();_body.name="DrivenModelBody";_body.collision_layer=0;_body.collision_mask=1|CameraController.MODEL_CAMERA_LAYER
	_body.floor_snap_length=0.25;_body.safe_margin=0.01;_body.max_slides=6
	for points in GSMeshMotionJob.bake_points(shapes,_basis):
		var shape:=ConvexPolygonShape3D.new();shape.points=points
		var collision:=CollisionShape3D.new();collision.debug_color=Color.TRANSPARENT;collision.debug_fill=false;collision.shape=shape;_body.add_child(collision)
	viewer.add_child(_body);_body.top_level=true;_body.global_transform=Transform3D(Basis.IDENTITY,model.global_position)
	for body in model._bodies:_body.add_collision_exception_with(body)
	viewer.camera_controller.set_model_camera_collision(true)
	state=State.WALKING;status="WASD move · Shift faster · Space jump · Right-drag look · Esc exits"
func handle(event:InputEvent)->bool:
	if state==State.IDLE:return false
	var viewer:Node=_viewer.get_ref()
	if event is InputEventKey:
		if event.pressed and event.keycode==KEY_ESCAPE:stop();return true
		var focus:Control=viewer.get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit or viewer.camera_controller.is_movement_blocked_by_others("model_navigation"):
			_keys.clear();_jump=false;return false
		var key:Key=event.physical_keycode if event.physical_keycode else event.keycode
		if key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE]:
			_keys[key]=event.pressed
			if key==KEY_SPACE and event.pressed and not event.echo:_jump=true
			return true
	if state!=State.WALKING:return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if event.pressed and (viewer.get_viewport().gui_get_hovered_control()!=null or viewer.camera_controller.is_movement_blocked_by_others("model_navigation")):return false
		_orbit=event.pressed;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if _orbit else Input.MOUSE_MODE_VISIBLE;return true
	if event is InputEventMouseMotion and _orbit:
		_offset=Basis(Vector3.UP,-event.relative.x*0.005)*_offset
		var right:=Vector3.UP.cross(_offset).normalized()
		var candidate:=Basis(right,-event.relative.y*0.005)*_offset
		if absf(candidate.normalized().y)<0.9:_offset=candidate
		return true
	return false
func step(delta:float)->void:
	if state!=State.WALKING or not is_instance_valid(_body):return
	var viewer:Node=_viewer.get_ref();var model:GSSceneMesh=_model.get_ref()
	if not is_instance_valid(viewer) or not is_instance_valid(model):stop(false);return
	var controller:CameraController=viewer.camera_controller
	var ignored:RID=controller.reference_floor_rid() if controller.uses_mesh_floor() else RID()
	if ignored!=_ignored_ground:
		if _ignored_ground.is_valid():PhysicsServer3D.body_remove_collision_exception(_body.get_rid(),_ignored_ground)
		if ignored.is_valid():PhysicsServer3D.body_add_collision_exception(_body.get_rid(),ignored)
		_ignored_ground=ignored
	var focus:Control=viewer.get_viewport().gui_get_focus_owner()
	var input:=Vector2.ZERO
	if focus is LineEdit or focus is TextEdit or controller.is_movement_blocked_by_others("model_navigation"):
		release_input()
	else:
		input=Vector2(float(_keys.get(KEY_D,false))-float(_keys.get(KEY_A,false)),float(_keys.get(KEY_W,false))-float(_keys.get(KEY_S,false))).limit_length()
	var forward:Vector3=-viewer.get_camera().global_basis.z;forward.y=0;forward=forward.normalized()
	var right:=forward.cross(Vector3.UP)
	var direction:=right*input.x+forward*input.y
	var amount:=speed*(2.0 if _keys.get(KEY_SHIFT,false) else 1.0)
	_body.velocity.x=direction.x*amount;_body.velocity.z=direction.z*amount
	if not _body.is_on_floor():_body.velocity.y-=float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))*delta
	elif _jump:_body.velocity.y=4.0
	else:_body.velocity.y=0.0
	_jump=false;_body.move_and_slide()
	var pose:=Transform3D(_basis,_body.global_position)
	if not model.global_transform.is_equal_approx(pose):model.global_transform=pose
	var target:AABB=viewer.get_asset_world_bounds(model)
	viewer.camera_controller.follow_model_at(target.get_center()+_offset,target.get_center())
func release_input()->void:
	_keys.clear();_jump=false;_orbit=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func stop(commit:bool=true)->void:
	if state==State.IDLE:return
	var viewer:Node=_viewer.get_ref();var model:GSSceneMesh=_model.get_ref() if _model else null
	if state==State.PREPARING and is_instance_valid(model):model.cancel_motion_shapes(false)
	release_input()
	if is_instance_valid(_body):_body.queue_free()
	_body=null;_ignored_ground=RID()
	if is_instance_valid(viewer):
		viewer.camera_controller.set_model_camera_collision(false)
		if state==State.WALKING and not viewer._closing:viewer.camera_controller.set_camera_transform(viewer.get_camera().global_transform)
		viewer.set_camera_blocker("model_navigation",false)
		if commit and is_instance_valid(model) and not viewer._closing:viewer.commit_transform_edit({model_id:_before},{model_id:model.global_transform})
	state=State.IDLE;model_id="";_model=null;status="Edit mode · transforms remain on the imported model"
func snapshot()->Dictionary:
	return {"active":state!=State.IDLE,"preparing":state==State.PREPARING,"walking":state==State.WALKING,"model_id":model_id,"speed":speed,"status":status}
