class_name GSSceneMesh
extends Node3D
## One imported scene root owns its transform; native children retain authored local poses.
const PICK_LAYER:=1<<18
var model_id:=Crypto.new().generate_random_bytes(16).hex_encode()
var file_path:=""
var import_kind:GaussianSplat.ImportKind=GaussianSplat.ImportKind.AUTO
var is_loaded:=false
var transform_locked:=false
var bounds_local:=AABB()
var vertex_count:=0
var surface_count:=0
var transparent_surfaces:=0
var fingerprints:Array=[]
var motion_shapes:Array=[]
var geometry_parts:Array=[]
var has_deformation:=false
var motion_error:Error=OK
var motion_quality:GSMeshMotionJob.Quality=GSMeshMotionJob.Quality.FAST
var motion_metrics:Dictionary={}
var _prepared_motion:Dictionary={}
var _job_quality:GSMeshMotionJob.Quality=GSMeshMotionJob.Quality.FAST
var _motion_job:GSMeshMotionJob
var _viewer:WeakRef
var _bodies:Array[StaticBody3D]=[]
var _has_bounds:=false
var _preview_transparency:Dictionary={}
func _init()->void:set_process(false)
func prepare_motion_shapes(quality:GSMeshMotionJob.Quality=GSMeshMotionJob.Quality.FAST)->bool:
	if quality!=motion_quality:
		motion_quality=quality;motion_error=OK;motion_shapes=_prepared_motion.get(quality,[])
		if not motion_shapes.is_empty():motion_metrics={"quality":quality,"cache_hit":true,"memory_hit":true,"milliseconds":0,"shapes":motion_shapes.size()}
		if _motion_job and _job_quality!=quality:_motion_job.cancel()
	if not motion_shapes.is_empty():return true
	if motion_error!=OK or has_deformation:return false
	if not _motion_job:
		_job_quality=quality;_motion_job=GSMeshMotionJob.new();motion_error=_motion_job.start(geometry_parts,quality,GSMeshMotionJob.cache_key(fingerprints,quality))
		if motion_error!=OK:_motion_job=null
		else:set_process(true)
	return false
func _process(_delta:float)->void:
	if _motion_job and _motion_job.done():
		var was_cancelled:=_motion_job.cancelled();var shapes:=_motion_job.finish();var metrics:=_motion_job.metrics;_motion_job=null;set_process(false)
		if was_cancelled or _job_quality!=motion_quality:return
		motion_shapes=shapes;motion_metrics=metrics
		if motion_shapes.is_empty():motion_error=ERR_INVALID_DATA
		else:_prepared_motion[motion_quality]=motion_shapes
func cancel_motion_shapes(wait:bool=true)->void:
	if _motion_job:
		_motion_job.cancel()
		if not wait:return
		_motion_job.finish(true);_motion_job=null
	set_process(false)
func motion_progress()->float:return 1.0 if not motion_shapes.is_empty() else (_motion_job.progress() if _motion_job else 0.0)
func _enter_tree()->void:set_notify_transform(true)
func _notification(what:int)->void:
	if what==NOTIFICATION_TRANSFORM_CHANGED and _viewer and is_instance_valid(_viewer.get_ref()):_viewer.get_ref().mesh_changed()
func initialize(content:Node3D,metadata:Array)->Error:
	fingerprints=metadata.duplicate(true)
	add_child(content)
	_scan(content,Transform3D.IDENTITY)
	if not _has_bounds:return ERR_INVALID_DATA
	is_loaded=true
	visibility_changed.connect(_sync_collisions)
	_sync_collisions()
	return OK
func _scan(node:Node,pose:Transform3D)->void:
	if node is Node3D:pose=pose*node.transform
	if node is Camera3D:node.current=false
	if node is Light3D:node.visible=false
	if node is AnimationPlayer:node.autoplay=""
	if node is MeshInstance3D and node.mesh:
		geometry_parts.append({"mesh":node.mesh,"pose":pose,"node":weakref(node)})
		has_deformation=has_deformation or node.skin!=null or node.get_blend_shape_count()>0
		var box:AABB=pose*node.mesh.get_aabb()
		bounds_local=bounds_local.merge(box) if _has_bounds else box;_has_bounds=true
		for surface in range(node.mesh.get_surface_count()):
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_VERTEX]!=null:vertex_count+=arrays[Mesh.ARRAY_VERTEX].size()
			surface_count+=1
			var material:=node.get_active_material(surface) as BaseMaterial3D
			if material and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:transparent_surfaces+=1
		var shape:ConcavePolygonShape3D=node.mesh.create_trimesh_shape()
		if shape:
			shape.backface_collision=true
			var body:=StaticBody3D.new();body.name="SceneGeometry";body.collision_layer=1|PICK_LAYER;body.collision_mask=0
			body.set_meta("scene_asset",weakref(self))
			var collision:=CollisionShape3D.new();collision.debug_color=Color.TRANSPARENT;collision.debug_fill=false;collision.shape=shape;body.add_child(collision);node.add_child(body);_bodies.append(body)
	for child in node.get_children():
		if not child is StaticBody3D:_scan(child,pose)
func assign_viewer(viewer:Node)->void:_viewer=weakref(viewer)
func _sync_collisions()->void:
	for body in _bodies:
		if is_instance_valid(body):
			# Internal triangle helpers must not cover the imported material when the
			# editor enables Visible Collision Shapes. Physics stays enabled.
			for child in body.get_children():
				if child is CollisionShape3D:child.debug_color=Color.TRANSPARENT;child.debug_fill=false
			body.collision_layer=(1|PICK_LAYER) if body.is_visible_in_tree() and not has_meta("placement_preview") else 0
	if _viewer and is_instance_valid(_viewer.get_ref()):_viewer.get_ref().mesh_changed()
func preview(enabled:bool)->void:
	if enabled:set_meta("placement_preview",true)
	else:remove_meta("placement_preview")
	# A placement preview must not write opaque depth over its own GS target.
	# Instance transparency leaves original materials/textures untouched.
	for part in geometry_parts:
		var geometry:GeometryInstance3D=part.node.get_ref()
		if not is_instance_valid(geometry):continue
		var id:=geometry.get_instance_id()
		if enabled:
			if not _preview_transparency.has(id):_preview_transparency[id]=geometry.transparency
			geometry.transparency=maxf(float(_preview_transparency[id]),0.35)
		elif _preview_transparency.has(id):geometry.transparency=_preview_transparency[id]
	if not enabled:_preview_transparency.clear()
	_sync_collisions()
func _exit_tree()->void:
	cancel_motion_shapes()
	if _viewer and is_instance_valid(_viewer.get_ref()):_viewer.get_ref().unregister_mesh(self)
