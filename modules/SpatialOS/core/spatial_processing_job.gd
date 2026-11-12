class_name SpatialProcessingJob
extends RefCounted
## Exclusive worker ownership of CPU preparation and its local RenderingDevice.
var thread := Thread.new()
var mutex := Mutex.new()
var done := false
var cancelled := false
var result: Dictionary = {}
var input: Dictionary
var graph_mode := -1
var flip_geometry := false
var voxel_size := -1.0
var force_voxelization := false
var edge_threshold := -1.0
func start() -> Error: return thread.start(_run)
func cancel() -> void:
	mutex.lock()
	cancelled = true
	mutex.unlock()
func is_cancelled() -> bool:
	mutex.lock()
	var value := cancelled
	mutex.unlock()
	return value
func snapshot() -> Dictionary:
	mutex.lock()
	var state := {"done":done,"cancelled":cancelled}
	mutex.unlock()
	return state
func join() -> void:
	if thread.is_started():thread.wait_to_finish()
func _run() -> void:
	var engine = load("res://modules/SpatialOS/core/spatial_pipeline.gd").new()
	engine.cancellation_check = is_cancelled
	engine._ready()
	var outcome := {}
	engine.processing_completed.connect(func(resource): outcome.resource = resource)
	engine.processing_failed.connect(func(message): outcome.error = message)
	if not engine.rd:
		outcome.error = "Spatial processing requires a compute-capable rendering backend."
	elif flip_geometry:
		var points:PackedVector3Array=input.points
		for i in range(points.size()):
			if i%4096==0 and is_cancelled():break
			points[i].y=-points[i].y
		var cloud:=PointCloudResource.new(points,input.colors)
		cloud.voxel_size=input.voxel_size
		cloud.metadata=input.metadata
		cloud.invalidate_derived()
		cloud.metadata["manually_flipped"]=true
		engine._finalize_processing(cloud)
	elif graph_mode != -1:
		var cloud := PointCloudResource.new(input.points,input.colors)
		cloud.voxel_size = input.get("voxel_size",0.0)
		cloud.normals=input.get("normals",PackedVector3Array())
		cloud.curvature=input.get("curvature",PackedFloat32Array())
		engine._finalize_processing(cloud)
		if not is_cancelled():
			var graph := SpatialGraph.new()
			graph.edge_threshold_override = edge_threshold
			graph.cancellation_check = is_cancelled
			if graph_mode==-2:
				var started:=Time.get_ticks_msec()
				graph.compute_geometric_features(cloud)
				outcome.stats={"point_count":cloud.point_count,"processing_time":(Time.get_ticks_msec()-started)/1000.0}
			else:outcome.stats = graph.compute_segmentation(cloud,graph_mode)
			if outcome.stats.has("error"):outcome.error = str(outcome.stats.error)
	else:
		var direct := not force_voxelization and (SpatialConfig.USE_DIRECT_RENDERING or int(input.count) >= SpatialConfig.AUTO_DIRECT_RENDER_THRESHOLD)
		if direct:
			engine._process_direct_rendering(input.get("source_file",""),input.points,input.colors,input.get("has_colors",false),input.get("is_gaussian_splatting",false) and not input.get("coordinates_corrected",false))
		else:
			engine._finish_voxelized(input,voxel_size)
	if outcome.has("resource"):
		var cloud: PointCloudResource = outcome.resource
		if cloud.metadata.has("spatial_index"):
			var index: SpatialIndex = cloud.metadata.spatial_index
			if is_cancelled():
				index.cleanup_gpu_resources()
				cloud.metadata.erase("spatial_index")
			else:
				index.ensure_cpu_sync()
				index.detach_gpu_keep_cpu()
	# No RenderingDevice or GPU RID crosses the worker boundary.
	if engine.rd:
		for shader in [engine.shader_rid,engine.compactor_shader_rid]:
			if shader.is_valid():engine.rd.free_rid(shader)
		engine.rd.free()
		engine.rd = null
	engine.free()
	mutex.lock()
	result = outcome
	done = true
	mutex.unlock()
