extends SceneTree
var failures: Array[String] = []
func check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)
	print("PASS " if condition else "FAIL ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(GaussianSplattingRasterizer.scene_msaa_mode(Viewport.MSAA_2X,"llvmpipe (LLVM 20)")==Viewport.MSAA_4X and GaussianSplattingRasterizer.scene_msaa_mode(Viewport.MSAA_8X,"llvmpipe (LLVM 21)")==Viewport.MSAA_4X,"software Vulkan selects native 4x depth rather than an unsupported sample count")
	check(GaussianSplattingRasterizer.scene_msaa_mode(Viewport.MSAA_DISABLED,"llvmpipe")==Viewport.MSAA_DISABLED and GaussianSplattingRasterizer.scene_msaa_mode(Viewport.MSAA_2X,"NVIDIA GeForce RTX")==Viewport.MSAA_2X,"scene depth policy preserves disabled AA and existing hardware GPU settings")
	var allocator := SplatBlockAllocator.new(2400)
	var a := allocator.allocate(720)
	var b := allocator.allocate(1680)
	check(a == 0 and b == 720 and allocator.allocate(240) == -1, "allocator admission")
	allocator.free_block(a, 720)
	allocator.free_block(b, 1680)
	check(allocator.allocate(2400) == 0, "allocator coalescing")
	allocator.reset()
	check(allocator.high_water_splats() == 0, "allocator reset high water")
	var settings := GaussianSplattingConfig.create_default()
	settings.memory_max_vram_budget_mb = 32
	var plan := GaussianSplattingRasterizer.memory_plan(settings, Vector2i(128, 128))
	check(not plan.has("error") and plan.bytes <= plan.budget, "complete GPU budget")
	var invalid := "user://unterminated.ply"
	var file := FileAccess.open(invalid, FileAccess.WRITE)
	file.store_string("ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\n")
	file.close()
	var document := PLYDocument.new()
	check(document.parse(invalid) != OK, "unterminated PLY rejected")
	file = FileAccess.open("user://typed.ply", FileAccess.WRITE)
	file.store_string("ply\nformat binary_big_endian 1.0\nelement vertex 1\nproperty float x\nproperty short y\nproperty double z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n")
	var payload := StreamPeerBuffer.new()
	payload.big_endian = true
	payload.put_float(1.25)
	payload.put_16(-2)
	payload.put_double(3.5)
	for value in [255, 128, 0]: payload.put_u8(value)
	file.store_buffer(payload.data_array)
	file.close()
	var typed := PLYLoader.load_ply("user://typed.ply")
	check(not typed.has("error") and typed.points[0] == Vector3(1.25, -2, 3.5) and typed.colors[0].r == 1.0, "mixed scalar big-endian PLY")
	var source := fixture("user://valid.ply", 3)
	var ply := PlyFile.new()
	check(ply.parse(source) == OK and ply.size == 3, "ASCII Gaussian schema")
	check(ply.parse(source, 50000000, 1) == OK, "source file size is not an admission gate")
	var thin_values := PackedFloat32Array([0, 0, 0, -4.06825018, -31.00940132, -32.05010986, 1, 0, 0, 0, -5.14226532, 0, 0, 0])
	var thin := PlyFile.pack_chunk(thin_values, 14, ply.document.gaussian_mapping(), 1)
	check(not thin.has("error") and thin.count == 1, "valid thin Bali Gaussians retain full source population")
	var high := GaussianSplattingConfig.new()
	high.apply_preset(GaussianSplattingConfig.QualityPreset.HIGH)
	var large_plan := GaussianSplattingRasterizer.memory_plan(high, Vector2i(1142, 648))
	check(large_plan.splats >= 7739833 + 219953 and large_plan.bytes <= large_plan.budget, "High atlas fits Bali plus another full-resolution model")
	var resource := PlyConverter.parse_ply_to_resource(source)
	check(resource != null and resource.is_valid() and resource.data.size() == 720, "Gaussian CPU conversion")
	if resource:
		check(resource.save_binary("user://roundtrip.gsres") == OK, "binary save")
		var restored := GaussianSplatResource.load_binary("user://roundtrip.gsres")
		check(restored != null and restored.data == resource.data, "binary checksum round trip")
		var corrupt := FileAccess.open("user://roundtrip.gsres", FileAccess.READ_WRITE)
		corrupt.seek(128)
		corrupt.store_8(255)
		corrupt.close()
		check(GaussianSplatResource.load_binary("user://roundtrip.gsres") == null, "binary corruption rejected")
	var spatial := PLYLoader.load_ply(source)
	check(spatial.get("count", 0) == 3 and spatial.points[2].x == 2.0, "shared SpatialOS decoding")
	check(not ActionController.valid_vector([0, 1]) and not ActionController.valid_vector([0, "1", 2]) and not ActionController.valid_vector([INF, 0, 0]) and ActionController.valid_vector([0, 1.5, -2]), "AI vector validation")
	var policy := AIAccessPolicy.new()
	check(not policy.cloud_enabled and not policy.allows_action(), "AI default read-only policy")
	var controller := ActionController.new()
	controller.policy = policy
	root.add_child(controller)
	check(controller.execute_action("move_camera", {"position": [0, 1, 2]}).status == "error", "denied AI action")
	controller.free()
	check(not LLMClient.parse_response("openai", {"choices": []}).error.is_empty(), "malformed provider response")
	var reply := {"choices": [{"message": {"tool_calls": [{"function": {"name": "reset_view", "arguments": "{}"}}, {"function": {"name": "reset_view", "arguments": "{}"}}]}}]}
	check(LLMClient.parse_response("openai", reply).calls.size() == 2, "multiple provider tools decoded")
	var data := PointCloudResource.new(PackedVector3Array([Vector3.ONE, Vector3(2, 3, 4)]))
	check(data.point_count == 2 and data.aabb.position == Vector3.ONE, "derived point count and bounds")
	data.segments = PackedInt32Array([1, 1])
	data.points = PackedVector3Array([Vector3.ZERO])
	check(data.point_count == 1 and data.segments.is_empty() and data.aabb.size == Vector3.ZERO, "geometry invalidates derived graph")
	data.points[0] = Vector3(4, 5, 6)
	check(data.aabb.position == Vector3(4, 5, 6), "indexed geometry edit invalidates bounds")
	var detached := data.points
	detached[0] = Vector3.ZERO
	check(data.points[0] == Vector3(4, 5, 6), "retained geometry snapshot cannot mutate source")
	var large_source := fixture("user://cancel.ply", 1000)
	var job := GSLoadJob.new()
	job.path = large_source
	job.expected_count = 1000
	job.chunk_size = 100
	check(job.start() == OK, "CPU worker start")
	await create_timer(0.05).timeout
	job.cancel()
	job.join()
	check(job.result().cancelled and job.result().done, "bounded worker cancellation joins")
	var sample_job := GSLoadJob.new()
	sample_job.path = fixture("user://samples.ply", 16000)
	sample_job.expected_count = 16000
	sample_job.start()
	while not sample_job.result().done or not sample_job.result().empty:
		sample_job.take_chunk()
		await process_frame
	sample_job.join()
	var samples: PackedVector3Array = sample_job.result().samples
	check(samples.size() <= 8192 and samples[-1].x > 15990, "bounded floor samples span the complete source")
	var async_loader := AsyncPLYLoader.new()
	root.add_child(async_loader)
	check(async_loader.load_ply_async(large_source), "SpatialOS async start")
	async_loader.cancel()
	check(not async_loader.is_loading(), "SpatialOS async cancellation joins")
	async_loader.free()
	var unavailable := GaussianSplattingRasterizer.new(Vector2i.ONE)
	var first_failure := unavailable.init_gpu()
	var second_failure := unavailable.init_gpu()
	check(first_failure != OK and second_failure != ERR_BUSY and not unavailable._is_busy_modifying_resources, "failed initialization releases lock")
	unavailable.cleanup()
	print("CHECKS COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

static func fixture(path: String, count: int) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("ply\nformat ascii 1.0\nelement vertex %d\n" % count)
	for property in ["x", "y", "z", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3", "opacity", "f_dc_0", "f_dc_1", "f_dc_2"]:
		file.store_string("property float " + property + "\n")
	file.store_string("end_header\n")
	for i in range(count): file.store_string("%s 0 0 -3 -3 -3 1 0 0 0 2 1 0 0\n" % i)
	file.close()
	return path
