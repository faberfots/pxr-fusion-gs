class_name GSMeshMotionJob
extends RefCounted
## Native QuickHull for ordinary edits; the existing detailed decomposition for Drive.
enum Quality { FAST, DETAILED }
const CACHE_VERSION:=2
const CACHE_DIRECTORY:="user://mesh-motion-v2"
var _thread:Thread
var _parts:Array=[]
var _quality:Quality=Quality.FAST
var _cache_key:=""
var _cancelled:=false
var _mutex:=Mutex.new()
var _completed:=0
var metrics:Dictionary={}
func start(parts:Array,quality:Quality=Quality.FAST,cache_key:String="")->Error:
	_parts=parts.duplicate();_quality=quality;_cache_key=cache_key;_thread=Thread.new()
	return _thread.start(_prepare)
func cancel()->void:
	_mutex.lock();_cancelled=true;_mutex.unlock()
func cancelled()->bool:
	_mutex.lock();var value:=_cancelled;_mutex.unlock();return value
func done()->bool:return _thread!=null and not _thread.is_alive()
func progress()->float:
	_mutex.lock();var value:=float(_completed)/maxi(_parts.size(),1);_mutex.unlock();return value
func finish(cancelled:bool=false)->Array:
	if cancelled:cancel()
	var result:Variant=_thread.wait_to_finish() if _thread and _thread.is_started() else []
	_thread=null;_parts.clear()
	return result if result is Array and not cancelled and not self.cancelled() else []
func _prepare()->Array:
	var started:=Time.get_ticks_msec();var result:=_read_cache()
	if not result.is_empty():
		metrics={"quality":_quality,"cache_hit":true,"milliseconds":Time.get_ticks_msec()-started,"shapes":result.size()};return result
	var settings:=MeshConvexDecompositionSettings.new();var reused:Dictionary={}
	settings.max_convex_hulls=16;settings.max_concavity=0.0025;settings.max_num_vertices_per_convex_hull=64;settings.resolution=100000
	for part in _parts:
		if cancelled():return []
		var mesh:Mesh=part.mesh;var id:=mesh.get_instance_id()
		if not reused.has(id):
			var shapes:Array=[]
			if _quality==Quality.FAST:
				# simplify=true invokes V-HACD again. QuickHull is clean=true, simplify=false.
				var shape:=mesh.create_convex_shape(true,false)
				if shape:shapes.append({"shape":shape,"pose":Transform3D.IDENTITY})
			else:
				var temporary:=MeshInstance3D.new();temporary.mesh=mesh
				temporary.create_multiple_convex_collisions(settings)
				for body in temporary.get_children():
					for collision in body.get_children():
						if collision is CollisionShape3D and collision.shape is ConvexPolygonShape3D:shapes.append({"shape":collision.shape,"pose":body.transform*collision.transform})
				temporary.free()
			reused[id]=shapes
		for shape in reused[id]:result.append({"shape":shape.shape,"pose":part.pose*shape.pose})
		_mutex.lock();_completed+=1;_mutex.unlock()
	if cancelled():return []
	_write_cache(result)
	metrics={"quality":_quality,"cache_hit":false,"milliseconds":Time.get_ticks_msec()-started,"shapes":result.size()}
	return result
static func cache_key(fingerprints:Array,quality:Quality)->String:
	if fingerprints.is_empty():return ""
	var sources:Array=[]
	for source in fingerprints:
		if not source is Dictionary or not source.get("sha256") is String or source.sha256.length()!=64:return ""
		sources.append([source.sha256,source.get("bytes",0)])
	return JSON.stringify([CACHE_VERSION,Engine.get_version_info().hex,quality,sources]).sha256_text()
static func _digest(bytes:PackedByteArray)->PackedByteArray:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish()
func _read_cache()->Array:
	if _cache_key.is_empty() or cancelled():return []
	var file:=FileAccess.open(CACHE_DIRECTORY.path_join(_cache_key+".bin"),FileAccess.READ)
	if not file or file.get_length()<40 or file.get_length()>64*1024*1024:return []
	var digest:=file.get_buffer(32);var bytes:=file.get_buffer(file.get_length()-32);file.close()
	if digest!=_digest(bytes):return []
	# Never deserialize objects/scripts from a cache. Geometry is plain value data.
	var data:Variant=bytes_to_var(bytes)
	if not data is Dictionary or data.get("key")!=_cache_key or not data.get("parts") is Array:return []
	if data.parts.is_empty() or data.parts.size()>16384:return []
	var result:Array=[];var total:=0
	for part in data.parts:
		if not part is Dictionary or not part.get("points") is PackedVector3Array or not part.get("pose") is Transform3D:return []
		if not part.pose.is_finite() or part.points.size()<3:return []
		total+=part.points.size()
		if total>1000000:return []
		for point in part.points:
			if not point.is_finite():return []
		var shape:=ConvexPolygonShape3D.new();shape.points=part.points;result.append({"shape":shape,"pose":part.pose})
	return result
func _write_cache(shapes:Array)->void:
	if _cache_key.is_empty() or shapes.is_empty() or cancelled():return
	var data:Array=[]
	for part in shapes:data.append({"points":part.shape.points,"pose":part.pose})
	var bytes:=var_to_bytes({"key":_cache_key,"parts":data})
	if bytes.size()>64*1024*1024-32:return
	var directory:=ProjectSettings.globalize_path(CACHE_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return
	var target:=directory.path_join(_cache_key+".bin")
	var temporary:=target+".%d-%d.tmp" % [get_instance_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if not file:return
	file.store_buffer(_digest(bytes));file.store_buffer(bytes);file.flush();var valid:=file.get_error()==OK;file.close()
	if not valid or cancelled() or DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary)
static func bake_points(parts:Array,basis:Basis)->Array[PackedVector3Array]:
	var result:Array[PackedVector3Array]=[]
	for part in parts:
		var points:PackedVector3Array=part.shape.points
		var pose:Transform3D=Transform3D(basis,Vector3.ZERO)*part.pose
		for i in range(points.size()):points[i]=pose*points[i]
		result.append(points)
	return result
