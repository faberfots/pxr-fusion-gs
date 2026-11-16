class_name GSMeshEditGuard
extends RefCounted
## Query-only compound bodies constrain authoring; Node3D remains the pose owner.
const TOLERANCE:=0.003
var _viewer:WeakRef
var _bodies:Dictionary={}
func _init(viewer:Node)->void:_viewer=weakref(viewer)
static func blend(current:Transform3D,desired:Transform3D,weight:float)->Transform3D:
	if weight>=1.0:return desired
	if weight<=0.0:return current
	if current.basis.is_equal_approx(desired.basis):return Transform3D(current.basis,current.origin.lerp(desired.origin,weight))
	return current.interpolate_with(desired,weight)
func remove(id:String)->void:
	if _bodies.has(id):PhysicsServer3D.free_rid(_bodies[id].body);_bodies.erase(id)
func remove_model(model:GSSceneMesh)->void:
	if _bodies.has(model.model_id) and _bodies[model.model_id].model.get_ref()==model:remove(model.model_id)
func clear()->void:
	for entry in _bodies.values():PhysicsServer3D.free_rid(entry.body)
	_bodies.clear()
func prepare(ids:Array)->bool:
	var viewer:Node=_viewer.get_ref();var ready:=true;var progress:=1.0
	for id in ids:
		var model:=viewer.get_asset_by_id(id) as GSSceneMesh
		if not model or viewer.resolve_import_kind(model)==GaussianSplat.ImportKind.ENVIRONMENT:continue
		if model.has_deformation or model.motion_error!=OK:
			viewer.composition_progress.emit("Solid edits need rigid mesh geometry. Turn Solid off for this asset.");return false
		if not model.prepare_motion_shapes(viewer.mesh_edit_shape_quality):ready=false;progress=minf(progress,model.motion_progress())
	if not ready:viewer.composition_progress.emit("Preparing %s solid shapes… %d%% · Esc cancels this drag." % ["fast" if viewer.mesh_edit_shape_quality==GSMeshMotionJob.Quality.FAST else "detailed",roundi(progress*100)])
	return ready
func _configure(model:GSSceneMesh,basis:Basis)->Dictionary:
	if _bodies.has(model.model_id) and _bodies[model.model_id].model.get_ref()!=model:remove(model.model_id)
	if not _bodies.has(model.model_id):
		var body:=PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_KINEMATIC)
		PhysicsServer3D.body_set_space(body,model.get_world_3d().space)
		PhysicsServer3D.body_set_collision_layer(body,0)
		PhysicsServer3D.body_set_collision_mask(body,1|CameraController.MODEL_CAMERA_LAYER)
		_bodies[model.model_id]={"body":body,"model":weakref(model),"shapes":[],"basis":Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),"minimum":0.0,"quality":-1}
	var entry:Dictionary=_bodies[model.model_id]
	if entry.basis.is_equal_approx(basis) and entry.quality==model.motion_quality:return entry
	var points:=GSMeshMotionJob.bake_points(model.motion_shapes,basis)
	if entry.shapes.size()!=points.size():
		PhysicsServer3D.body_clear_shapes(entry.body);entry.shapes.clear()
		for vertices in points:
			var shape:=ConvexPolygonShape3D.new();shape.points=vertices;entry.shapes.append(shape)
			PhysicsServer3D.body_add_shape(entry.body,shape.get_rid())
	else:
		for index in range(points.size()):entry.shapes[index].points=points[index]
	var minimum:=INF
	for vertices in points:
		for vertex in vertices:minimum=minf(minimum,vertex.y)
	entry.basis=basis;entry.minimum=minimum;entry.quality=model.motion_quality
	return entry
func _parameters(pose:Transform3D,excluded:Array[RID])->PhysicsTestMotionParameters3D:
	var parameters:=PhysicsTestMotionParameters3D.new();parameters.from=Transform3D(Basis.IDENTITY,pose.origin)
	parameters.margin=0.001;parameters.max_collisions=16;parameters.exclude_bodies=excluded
	var ground:Node=_viewer.get_ref().camera_controller.ground
	# The controller owns the reference plane policy. Exclude the prototype CSG
	# object's physical body by its public object ID; native floors remain queried.
	if is_instance_valid(ground):parameters.exclude_objects=[ground.get_instance_id()]
	return parameters
func _depth(model:GSSceneMesh,pose:Transform3D,excluded:Array[RID],floor_height:float)->float:
	var entry:=_configure(model,pose.basis)
	var depth:=maxf(0.0,floor_height-pose.origin.y-entry.minimum) if is_finite(floor_height) else 0.0
	var query:=PhysicsShapeQueryParameters3D.new();query.transform=Transform3D(Basis.IDENTITY,pose.origin);query.margin=0.0001;query.collision_mask=1|CameraController.MODEL_CAMERA_LAYER
	var ignored:Array[RID]=excluded.duplicate()
	var ground:RID=_viewer.get_ref().camera_controller.reference_floor_rid()
	if ground.is_valid():ignored.append(ground)
	query.exclude=ignored
	var space:PhysicsDirectSpaceState3D=model.get_world_3d().direct_space_state
	for shape in entry.shapes:
		query.shape=shape
		var contacts:=space.collide_shape(query,16)
		for index in range(0,contacts.size(),2):depth=maxf(depth,contacts[index].distance_to(contacts[index+1]))
	return depth
func fraction(poses:Dictionary)->float:
	var viewer:Node=_viewer.get_ref();var excluded:Array[RID]=[]
	for id in poses:
		var model:=viewer.get_asset_by_id(id) as GSSceneMesh
		if model:
			for body in model._bodies:excluded.append(body.get_rid())
	var fraction:=1.0
	for id in poses:
		var model:=viewer.get_asset_by_id(id) as GSSceneMesh
		if not model or viewer.resolve_import_kind(model)==GaussianSplat.ImportKind.ENVIRONMENT:continue
		var current:=model.global_transform;var desired:Transform3D=poses[id]
		var entry:=_configure(model,current.basis)
		var floor_height:float=viewer.camera_controller.ground_height()
		# Existing saved overlaps/poses never pop: permit escape, never deepen a
		# below-reference-floor placement. Imported native floors use real triangles.
		if is_finite(floor_height):floor_height=minf(floor_height,current.origin.y+entry.minimum)
		var baseline:=_depth(model,current,excluded,floor_height)
		var angle:=current.basis.orthonormalized().get_rotation_quaternion().angle_to(desired.basis.orthonormalized().get_rotation_quaternion())
		var scale_change:float=(desired.basis.get_scale()-current.basis.get_scale()).length()
		var steps:=clampi(ceili(maxf(angle/deg_to_rad(3),scale_change*16)),1,64)
		var reached:=0.0
		for step in range(1,steps+1):
			var amount:=minf(float(step)/steps,fraction)
			var before:=blend(current,desired,reached);var candidate:=blend(current,desired,amount)
			var configured:=_configure(model,before.basis)
			var parameters:=_parameters(before,excluded);parameters.motion=candidate.origin-before.origin
			var motion:=PhysicsTestMotionResult3D.new()
			if parameters.motion.length_squared()>0.00000001 and PhysicsServer3D.body_test_motion(configured.body,parameters,motion):
				var safe:=motion.get_collision_safe_fraction();var unsafe:=motion.get_collision_unsafe_fraction();var full_motion:=parameters.motion
				# Refine the server's coarse fraction for a long pointer/numeric jump;
				# contact should remain close even when the intended motion is huge.
				for refinement in range(2):
					parameters.from.origin=before.origin+full_motion*safe;parameters.motion=full_motion*(unsafe-safe)
					if PhysicsServer3D.body_test_motion(configured.body,parameters,motion):
						var span:=unsafe-safe;unsafe=safe+span*motion.get_collision_unsafe_fraction();safe+=span*motion.get_collision_safe_fraction()
					else:safe=unsafe;break
				amount=lerpf(reached,amount,maxf(0.0,safe-0.000001));candidate=blend(current,desired,amount)
			var depth:=_depth(model,candidate,excluded,floor_height)
			if depth>maxf(baseline,TOLERANCE)+0.0001:
				var low:=reached;var high:=amount
				for iteration in range(12):
					var middle:float=(low+high)*0.5
					if _depth(model,blend(current,desired,middle),excluded,floor_height)<=maxf(baseline,TOLERANCE)+0.0001:low=middle
					else:high=middle
				amount=low
			reached=amount;baseline=minf(baseline,depth)
			if amount<minf(float(step)/steps,fraction)-0.000001:break
		fraction=minf(fraction,reached)
		if fraction<=0.000001:break
	return fraction
