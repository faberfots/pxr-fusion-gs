extends SceneTree
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var pipeline := SpatialPipeline.new()
	root.add_child(pipeline)
	check(pipeline.rd != null, "SpatialOS local device")
	var points := PackedVector3Array([Vector3(10000, 2, 4), Vector3(10000.02, 2, 4), Vector3(10001, 2, 4)])
	var colors := PackedColorArray([Color.RED, Color.BLUE, Color.GREEN])
	var voxels := pipeline._voxelize(points, colors, points[0], 0.1)
	check(not voxels.has("error") and voxels.points.size() == 2, "voxel occupancy and compaction ABI")
	if not voxels.has("error"):
		var combined := false
		for i in range(voxels.points.size()):
			if voxels.points[i].x < 10000.5:
				combined = absf(voxels.points[i].x - 10000.01) < 0.003 and absf(voxels.colors[i].r - 0.5) < 0.01 and absf(voxels.colors[i].b - 0.5) < 0.01
		check(combined, "large-coordinate averaged voxel position and color")
	var bytes := PackedByteArray()
	bytes.resize(points.size() * 16)
	for i in range(points.size()):
		bytes.encode_float(i * 16, points[i].x)
		bytes.encode_float(i * 16 + 4, points[i].y)
		bytes.encode_float(i * 16 + 8, points[i].z)
	var input := pipeline.rd.storage_buffer_create(bytes.size(), bytes)
	var index := SpatialIndex.new()
	index.build_index_gpu(pipeline.rd, input, points.size(), points[0], points[2], points)
	check(index.get_grid_stats().grid_dim.y == 1 and index.get_grid_stats().grid_dim.z == 1, "planar grid dimensions stay positive")
	check(index.get_neighbors_radius(points[0], 0.01) == PackedInt32Array([0]), "exact radius filtering")
	check(index.get_neighbors_radius(points[2], 0.01) == PackedInt32Array([2]), "maximum boundary indexed")
	check(index.get_neighbors_radius(points[0] - Vector3(0.02, 0, 0), 0.025).has(0), "radius centered outside bounds")
	index.cleanup_gpu_resources()
	check(points.size() == 3, "index cleanup preserves source geometry")
	index = null
	pipeline.rd.free_rid(input)
	var original := PackedVector3Array()
	original.resize(10001)
	check(pipeline._downsample_points(original, 1000.0 / 10001).size() == 1000, "strict downsample cap")
	var a := SegmentData.new()
	a.segment_id = 1
	a.add_point(Vector3.ZERO)
	a.finalize()
	check(a.average_normal == Vector3.ZERO, "missing normals remain unknown")
	var connected := PackedVector3Array()
	for i in range(512): connected.append(Vector3(i * 0.001, 0, 0))
	for i in range(512): connected.append(Vector3(10 + i * 0.001, 0, 0))
	for i in range(60): connected.append(Vector3(20 + i * 0.001, 0, 0))
	var cloud := PointCloudResource.new(connected)
	pipeline._finalize_processing(cloud)
	var graph := SpatialGraph.new()
	var result := graph.compute_connectivity(cloud)
	check(result.get("segment_count", -1) == 3 and cloud.segment_count == 3 and cloud.segments[0] != cloud.segments[1023], "connected components preserve remote small segment")
	check(result.get("segment_count", -1) == cloud.segment_count, "reported graph count matches committed graph")
	cloud.invalidate_derived()
	check(cloud.point_count == 1084, "graph invalidation preserves authoritative points")
	cloud = null
	var visualizer: MultiMeshInstance3D = load("res://modules/SpatialOS/scenes/PointVisualizer.gd").new()
	root.add_child(visualizer)
	visualizer.prepare_progressive(3)
	visualizer.append_chunk(points, colors)
	var finalized: PointCloudResource = visualizer.finalize_progressive()
	visualizer.clear_visualization()
	check(finalized.point_count == 3 and finalized.colors.size() == 3, "progressive finalization and teardown preserve geometry and colors")
	visualizer.free()
	pipeline.free()
	await process_frame
	print("SPATIAL COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
