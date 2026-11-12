extends SceneTree
var failures: Array[String] = []
var completed: PointCloudResource
var failure := ""
var chunks := 0
var last_chunk:=PackedVector3Array()
func _initialize() -> void: call_deferred("run")
func check(value:bool,label:String) -> void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run() -> void:
	var pipeline := SpatialPipeline.new()
	root.add_child(pipeline)
	pipeline.processing_completed.connect(func(resource):completed=resource)
	pipeline.processing_failed.connect(func(message):failure=message)
	var visualizer = load("res://modules/SpatialOS/scenes/PointVisualizer.gd").new()
	root.add_child(visualizer)
	pipeline.loading_prepared.connect(func(total):visualizer.prepare_progressive(total))
	pipeline.chunk_loaded.connect(func(points,colors):visualizer.append_chunk(points,colors);chunks+=1;last_chunk=points)
	var args := OS.get_cmdline_user_args()
	var expected:=int(args[1]) if args.size()>1 else 2000000
	if args.is_empty():quit(1);return
	var start := Time.get_ticks_msec()
	var previous := start
	var frames := 0
	var worst_gap := 0
	pipeline.ingest_and_process(args[0])
	while completed==null and failure.is_empty() and Time.get_ticks_msec()-start<120000:
		await process_frame
		var now := Time.get_ticks_msec()
		worst_gap=maxi(worst_gap,now-previous)
		previous=now;frames+=1
	check(completed!=null and failure.is_empty(),"multi-million-point async ingest completes")
	if completed:
		check(completed.point_count==expected and completed.colors.size()==expected,"full spatial source population and colors preserved")
		var index: SpatialIndex = completed.metadata.spatial_index
		check(index._rd==null and not index.get_neighbors_radius(Vector3.ZERO,0.005).is_empty(),"published spatial index is queryable without worker GPU ownership")
		visualizer.visualize(completed)
		while visualizer._populating:
			await process_frame
			var now := Time.get_ticks_msec()
			worst_gap=maxi(worst_gap,now-previous);previous=now;frames+=1
		check(visualizer.multimesh.instance_count==expected,"full final visualization completes")
	check((frames>50 and chunks>100 and worst_gap<250) if expected>=1000000 else frames>2,"UI heartbeat remains responsive through loading, processing and visualization")
	print("SPATIAL ASYNC TIMING ms ",Time.get_ticks_msec()-start," frames ",frames," max_gap_ms ",worst_gap," chunks ",chunks)
	var preserved:=completed
	completed=null
	check(pipeline.flip_scan_async(preserved),"large worker operation can start after visualization")
	for i in range(2):await process_frame
	pipeline.cancel_loading()
	var cancelled_at:=Time.get_ticks_msec()
	while pipeline.is_loading_async() and Time.get_ticks_msec()-cancelled_at<5000:await process_frame
	check(not pipeline.is_loading_async() and completed==null and preserved.point_count==expected,"cancelling worker processing preserves the previously completed geometry")
	failure=""
	var coordinate_fixture:String=load("res://tests/core_checks.gd").fixture("user://spatial-gs-coordinates.ply",1)
	var text:=FileAccess.get_file_as_string(coordinate_fixture)
	var rows:=text.strip_edges().split("\n")
	var values:=rows[-1].split(" ")
	values[0]="1";values[1]="2";values[2]="3"
	rows[-1]=" ".join(values)
	var source:=FileAccess.open(coordinate_fixture,FileAccess.WRITE)
	source.store_string("\n".join(rows)+"\n");source.close()
	completed=null;failure=""
	pipeline.ingest_and_process(coordinate_fixture)
	while pipeline.is_loading_async():await process_frame
	check(completed!=null and completed.points[0].is_equal_approx(Vector3(-1,-2,3)) and last_chunk[0].is_equal_approx(completed.points[0]),"progressive Gaussian coordinates match the final resource exactly once")
	var points := PackedVector3Array()
	for i in range(100):points.append(Vector3(i%10,1,i/10))
	var resource := PointCloudResource.new(points,PackedColorArray())
	var stats:Dictionary = await pipeline.compute_graph_async(resource,0)
	check(not stats.has("error") and resource.segments.size()==points.size(),"worker graph analysis commits derived labels")
	var old_labels := resource.segments.duplicate()
	var geometry:Dictionary=await pipeline.compute_geometry_async(resource)
	check(not geometry.has("error") and resource.normals.size()==100 and resource.segments==old_labels,"worker geometry analysis preserves existing segment labels")
	completed=null
	var original_points:=resource.points
	check(pipeline.flip_scan_async(resource),"manual flip starts through the spatial worker")
	while pipeline.is_loading_async():await process_frame
	check(completed!=null and completed.point_count==100 and completed.points[3].is_equal_approx(Vector3(original_points[3].x,-original_points[3].y,original_points[3].z)),"manual flip preserves points and rebuilds a queryable index")
	check(resource.points[3].y==1.0,"worker flip cannot mutate the original authoritative geometry")

	pipeline.compute_graph_async(resource,0)
	# Start the coroutine through a separate continuation, then invalidate the source.
	# Completion must never attach labels computed from the previous geometry revision.
	resource.set("points",PackedVector3Array([Vector3(100,100,100)]))
	while pipeline.is_loading_async():await process_frame
	check(resource.point_count==1 and resource.segments.is_empty(),"stale worker graph result cannot overwrite newer geometry")
	visualizer.free()
	pipeline.free()
	print("SPATIAL ASYNC COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
