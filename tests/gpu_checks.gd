extends SceneTree
var failed := false
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var settings := GaussianSplattingConfig.create_default()
	settings.memory_max_vram_budget_mb = 32
	settings.max_duplication_factor = 12.0 # Keep fixture capacity independent of user quality presets.
	var rasterizer := GaussianSplattingRasterizer.new(Vector2i(64, 64), null, null, settings)
	var result := rasterizer.init_gpu()
	print("GPU INITIALIZATION: ", result)
	if result == OK:
		for count in [1, 255, 256, 1023, 1024, 1025, 4099]:
			var valid: bool = rasterizer._sync(test_sort.bind(rasterizer, count))
			print("SORT ", count, ": ", valid)
			failed = failed or not valid
		var compositing: bool = rasterizer._sync(test_compositing.bind(rasterizer))
		print("LINEAR COMPOSITING / PIXEL TERMINATION: ", compositing)
		failed = failed or not compositing
		var overflow_safe: bool = rasterizer._sync(test_overflow.bind(rasterizer))
		print("PROJECTION OVERFLOW BOUND: ", overflow_safe)
		failed = failed or not overflow_safe
		var radiance: bool = rasterizer._sync(test_radiance.bind(rasterizer))
		print("LOCAL SH RADIANCE / OFF-AXIS FOOTPRINT: ", radiance)
		failed = failed or not radiance
		var reservations: bool = rasterizer._sync(test_projection_reservations.bind(rasterizer))
		print("MULTI-WORKGROUP PROJECTION RESERVATIONS: ", reservations)
		failed = failed or not reservations
		rasterizer.clear_gpu_memory()
		rasterizer.cleanup()
		result = rasterizer.init_gpu()
		print("GPU REINITIALIZATION: ", result)
		rasterizer.cleanup()
	for variant in [[8, 64, 1, 262145], [32, 128, 2, 1025]]:
		settings.tile_size = variant[0]
		settings.shader_radix_sort_workgroup_size = variant[1]
		settings.shader_projection_workgroup_size = variant[1]
		settings.shader_radix_sort_partition_division = variant[2]
		var specialized := GaussianSplattingRasterizer.new(Vector2i(64, 64), null, null, settings)
		var initialized := specialized.init_gpu()
		var valid: bool = initialized == OK and specialized._sync(test_sort.bind(specialized, variant[3]))
		print("SPECIALIZED SORT ", variant, ": ", valid)
		failed = failed or not valid
		var projection: bool = initialized == OK and specialized._sync(test_projection_reservations.bind(specialized)) and specialized._sync(test_radiance.bind(specialized)) and specialized._sync(test_overflow.bind(specialized))
		print("SPECIALIZED PROJECTION ", variant[1], ": ", projection)
		failed = failed or not projection
		specialized.cleanup()
	quit(0 if result == OK and not failed else 1)

func test_sort(rasterizer: GaussianSplattingRasterizer, count: int) -> bool:
	var rd := rasterizer.context.device
	var capacity := rasterizer.pair_capacity
	var keys := PackedByteArray()
	var values := PackedByteArray()
	keys.resize(count * 8)
	values.resize(count * 4)
	var expected: Array = []
	for i in range(count):
		var depth := (i * 31) % 257
		var tile: int = [0, 1, 65536, 99999][(i * 7) % 4]
		keys.encode_u32(i * 8, depth)
		keys.encode_u32(i * 8 + 4, tile)
		values.encode_u32(i * 4, i)
		expected.append([tile, depth, i])
	expected.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	rd.buffer_update(rasterizer.descriptors.sort_keys.rid, 0, keys.size(), keys)
	rd.buffer_update(rasterizer.descriptors.sort_values.rid, 0, values.size(), values)
	rd.buffer_update(rasterizer.descriptors.histogram.rid, 0, 16, PackedInt32Array([count, 0, 0, 0]).to_byte_array())
	var block_size := rasterizer.config.shader_radix_sort_workgroup_size * rasterizer.config.shader_radix_sort_partition_division
	rd.buffer_update(rasterizer.descriptors.grid_dimensions.rid, 0, 24, PackedInt32Array([ceili(float(count) / block_size), 1, 1, ceili(float(count) / rasterizer.config.shader_projection_workgroup_size), 1, 1]).to_byte_array())
	var list := rasterizer.context.compute_list_begin()
	for pass_index in range(8):
		var push := RenderingContext.create_push_constant([pass_index, capacity * (pass_index % 2), capacity * (1 - pass_index % 2), capacity])
		for stage in ["radix_sort_upsweep", "radix_sort_spine", "radix_sort_downsweep"]:
			if stage == "radix_sort_spine":
				rasterizer.pipeline_manager.get_pipeline(stage).call(rasterizer.context, list, push)
			else:
				rasterizer.pipeline_manager.get_pipeline(stage).call(rasterizer.context, list, push, [], rasterizer.descriptors.grid_dimensions.rid, 0)
	rasterizer.context.compute_list_end()
	var result := rd.buffer_get_data(rasterizer.descriptors.sort_values.rid, 0, count * 4)
	for i in range(count):
		if result.decode_u32(i * 4) != expected[i][2]:
			print("MISMATCH ", i, " actual ", result.decode_u32(i * 4), " expected ", expected[i])
			return false
	rd.buffer_clear(rasterizer.descriptors.tile_bounds.rid, 0, rasterizer.descriptors.tile_bounds.size)
	list = rasterizer.context.compute_list_begin()
	rasterizer.pipeline_manager.get_pipeline("gsplat_boundaries").call(rasterizer.context, list, PackedByteArray(), [], rasterizer.descriptors.grid_dimensions.rid, 12)
	rasterizer.context.compute_list_end()
	var ranges := rd.buffer_get_data(rasterizer.descriptors.tile_bounds.rid, 0, 16).to_int32_array()
	var zeros := 0
	var ones := 0
	for entry in expected:
		if entry[0] == 0: zeros += 1
		if entry[0] == 1: ones += 1
	if zeros > 0 and (ranges[0] != 0 or ranges[1] != zeros): return false
	if ones > 0 and (ranges[2] != zeros or ranges[3] != zeros + ones): return false
	return true

func test_compositing(rasterizer: GaussianSplattingRasterizer) -> bool:
	var rd := rasterizer.context.device
	var data := PackedByteArray()
	data.resize(129 * 64)
	for i in range(129):
		var offset := i * 64
		data.encode_float(offset, 0.0 if i < 128 else 15.0)
		data.encode_float(offset + 4, 0.0 if i < 128 else 15.0)
		data.encode_float(offset + 8, 64.0)
		data.encode_float(offset + 16, 1.0 if i < 128 else 0.0)
		data.encode_float(offset + 24, 0.0 if i < 128 else 1.0)
		data.encode_float(offset + 28, 0.5)
		data.encode_float(offset + 44, 5.0)
		data.encode_float(offset + 48, 64.0)
	rd.buffer_update(rasterizer.descriptors.culled_splats.rid, 0, data.size(), data)
	var values := PackedInt32Array()
	for i in range(129): values.append(i)
	rd.buffer_update(rasterizer.descriptors.sort_values.rid, 0, values.size() * 4, values.to_byte_array())
	rd.buffer_update(rasterizer.descriptors.histogram.rid, 0, 16, PackedInt32Array([129, 0, 129, 0]).to_byte_array())
	rd.buffer_clear(rasterizer.descriptors.tile_bounds.rid, 0, rasterizer.descriptors.tile_bounds.size)
	rd.buffer_update(rasterizer.descriptors.tile_bounds.rid, 0, 8, PackedInt32Array([0, 129]).to_byte_array())
	var uniforms := PackedByteArray()
	uniforms.resize(128)
	uniforms.encode_u32(16, 64)
	uniforms.encode_u32(20, 64)
	uniforms.encode_u32(48, 15)
	uniforms.encode_u32(52, 15)
	uniforms.encode_u32(56, 1)
	rd.buffer_update(rasterizer.descriptors.uniforms.rid, 0, 128, uniforms)
	var list := rasterizer.context.compute_list_begin()
	rasterizer.pipeline_manager.get_pipeline("gsplat_render").call(rasterizer.context, list)
	rasterizer.context.compute_list_end()
	var image := rd.texture_get_data(rasterizer.descriptors.render_texture.rid, 0)
	var pixel := (15 * 64 + 15) * 16
	return absf(image.decode_float(pixel + 8) - 0.5) < 0.001 and absf(image.decode_float(pixel + 12) - 0.5) < 0.001 and image.decode_float(12) > 0.99

func test_overflow(rasterizer: GaussianSplattingRasterizer) -> bool:
	var rd := rasterizer.context.device
	var splat := PackedByteArray()
	splat.resize(240)
	splat.encode_float(8, -1.0)
	splat.encode_float(12, -2.0)
	for offset in [16, 28, 36]: splat.encode_float(offset, 1.0)
	splat.encode_float(40, 0.9)
	splat.encode_float(44, 1.0)
	rd.buffer_update(rasterizer.descriptors.splats.rid, 0, 240, splat)
	rd.buffer_update(rasterizer.descriptors.instance_transforms.rid, 64, 64, RenderingContext.pack_projection(Projection.IDENTITY))
	var uniforms := PackedByteArray()
	uniforms.resize(128)
	uniforms.encode_float(12, 1.0)
	uniforms.encode_u32(16, 64)
	uniforms.encode_u32(20, 64)
	uniforms.encode_u32(24, 1)
	uniforms.encode_u32(28, 1) # Only one pair admitted; this footprint needs many tiles.
	uniforms.encode_float(32, 5.0)
	rd.buffer_update(rasterizer.descriptors.uniforms.rid, 0, 128, uniforms)
	rd.buffer_clear(rasterizer.descriptors.histogram.rid, 0, 16)
	var push := RenderingContext.pack_projection(Projection.IDENTITY)
	push.append_array(RenderingContext.pack_projection(Projection.create_perspective(75.0, 1.0, 0.05, 10.0)))
	var list := rasterizer.context.compute_list_begin()
	rasterizer.pipeline_manager.get_pipeline("gsplat_projection").call(rasterizer.context, list, push)
	rasterizer.context.compute_list_end()
	var meta := rd.buffer_get_data(rasterizer.descriptors.histogram.rid, 0, 16).to_int32_array()
	return meta[0] == 0 and meta[1] == 1

func test_radiance(rasterizer: GaussianSplattingRasterizer) -> bool:
	var rd := rasterizer.context.device
	var splat := PackedByteArray()
	splat.resize(240)
	splat.encode_float(12, -2.0)
	for offset in [16, 28, 36]: splat.encode_float(offset, 0.0025)
	splat.encode_float(40, 0.9)
	splat.encode_float(44, 1.0)
	splat.encode_float(72, 1.0) # degree-one Z radiance coefficient, red channel
	rd.buffer_update(rasterizer.descriptors.splats.rid, 0, 240, splat)
	var uniforms := PackedByteArray()
	uniforms.resize(128)
	uniforms.encode_float(12, 1.0)
	uniforms.encode_u32(16, 64)
	uniforms.encode_u32(20, 64)
	uniforms.encode_u32(24, 1)
	uniforms.encode_u32(28, rasterizer.pair_capacity)
	uniforms.encode_float(32, 5.0)
	rd.buffer_update(rasterizer.descriptors.uniforms.rid, 0, 128, uniforms)
	var push := RenderingContext.pack_projection(Projection.IDENTITY)
	push.append_array(RenderingContext.pack_projection(Projection.create_perspective(75.0, 1.0, 0.05, 10.0)))
	for angle in [0.0, PI]:
		var model := Transform3D(Basis(Vector3.UP, angle), Vector3(0, 0, -1))
		rd.buffer_update(rasterizer.descriptors.instance_transforms.rid, 64, 64, RenderingContext.pack_projection(Projection(model)))
		rd.buffer_clear(rasterizer.descriptors.histogram.rid, 0, 16)
		var list := rasterizer.context.compute_list_begin()
		rasterizer.pipeline_manager.get_pipeline("gsplat_projection").call(rasterizer.context, list, push)
		rasterizer.context.compute_list_end()
		var color := rd.buffer_get_data(rasterizer.descriptors.culled_splats.rid, 16, 16).to_float32_array()
		var local_direction := model.basis.inverse() * Vector3.FORWARD
		var expected := 0.5 + 0.4886025119 * local_direction.z
		if absf(color[0] - expected) > 0.0001: return false
	for tiny in [true, false]:
		for offset in [16, 28, 36]: splat.encode_float(offset, 0.00000000000001 if tiny else 4.0)
		rd.buffer_update(rasterizer.descriptors.splats.rid, 0, 240, splat)
		var model := Transform3D(Basis.IDENTITY, Vector3(0 if tiny else 3, 0, -1))
		rd.buffer_update(rasterizer.descriptors.instance_transforms.rid, 64, 64, RenderingContext.pack_projection(Projection(model)))
		rd.buffer_clear(rasterizer.descriptors.histogram.rid, 0, 16)
		var list := rasterizer.context.compute_list_begin()
		rasterizer.pipeline_manager.get_pipeline("gsplat_projection").call(rasterizer.context, list, push)
		rasterizer.context.compute_list_end()
		var meta := rd.buffer_get_data(rasterizer.descriptors.histogram.rid, 0, 16).to_int32_array()
		if meta[2] != 1: return false # tiny footprint and off-screen mean with visible footprint
	# A small, distant off-axis Gaussian just past the near plane must not inflate
	# into a full-screen sheet through an unbounded perspective Jacobian.
	for offset in [16, 28, 36]: splat.encode_float(offset, 0.04)
	rd.buffer_update(rasterizer.descriptors.splats.rid, 0, 240, splat)
	rd.buffer_update(rasterizer.descriptors.instance_transforms.rid, 64, 64, RenderingContext.pack_projection(Projection(Transform3D(Basis.IDENTITY, Vector3(30, 0, -0.051)))))
	rd.buffer_clear(rasterizer.descriptors.histogram.rid, 0, 16)
	var list := rasterizer.context.compute_list_begin()
	rasterizer.pipeline_manager.get_pipeline("gsplat_projection").call(rasterizer.context, list, push)
	rasterizer.context.compute_list_end()
	return rd.buffer_get_data(rasterizer.descriptors.histogram.rid, 0, 16).decode_u32(8) == 0

func test_projection_reservations(rasterizer: GaussianSplattingRasterizer) -> bool:
	var rd := rasterizer.context.device
	var population := 513
	var splats := PackedByteArray()
	splats.resize(population * 240)
	var expected := 0
	for id in range(population):
		var base := id * 240
		splats.encode_float(base + 8, -1.0)
		splats.encode_float(base + 12, -2.0)
		for offset in [16,28,36]: splats.encode_float(base + offset,0.000001)
		splats.encode_float(base + 40, 0.0 if id % 7 == 0 else 0.9)
		splats.encode_float(base + 44,1.0)
		if id % 7 != 0: expected += 1
	rd.buffer_update(rasterizer.descriptors.splats.rid,0,splats.size(),splats)
	rd.buffer_update(rasterizer.descriptors.instance_transforms.rid,64,64,RenderingContext.pack_projection(Projection.IDENTITY))
	var uniforms := PackedByteArray()
	uniforms.resize(128)
	uniforms.encode_float(12,1.0)
	uniforms.encode_u32(16,64)
	uniforms.encode_u32(20,64)
	uniforms.encode_u32(24,population)
	uniforms.encode_u32(28,rasterizer.pair_capacity)
	uniforms.encode_float(32,5.0)
	rd.buffer_update(rasterizer.descriptors.uniforms.rid,0,128,uniforms)
	rd.buffer_clear(rasterizer.descriptors.histogram.rid,0,16)
	rd.buffer_update(rasterizer.descriptors.grid_dimensions.rid,0,24,PackedInt32Array([0,1,1,0,1,1]).to_byte_array())
	var push := RenderingContext.pack_projection(Projection.IDENTITY)
	push.append_array(RenderingContext.pack_projection(Projection.create_perspective(75.0,1.0,0.05,10.0)))
	rasterizer.pipeline_manager.update_block_dimensions("gsplat_projection",[ceili(float(population)/rasterizer.config.shader_projection_workgroup_size),1,1])
	var list := rasterizer.context.compute_list_begin()
	rasterizer.pipeline_manager.get_pipeline("gsplat_projection").call(rasterizer.context,list,push)
	rasterizer.context.compute_list_end()
	var meta := rd.buffer_get_data(rasterizer.descriptors.histogram.rid,0,16).to_int32_array()
	if meta[0] != expected*4 or meta[1] != 0 or meta[2] != expected:return false
	var indices := rd.buffer_get_data(rasterizer.descriptors.sort_values.rid,0,meta[0]*4).to_int32_array()
	var keys := rd.buffer_get_data(rasterizer.descriptors.sort_keys.rid,0,meta[0]*8)
	var counts := PackedInt32Array()
	counts.resize(population)
	for i in range(indices.size()):
		var id := indices[i]
		if id < 0 or id >= population or id % 7 == 0 or keys.decode_u32(i*8) != 0x3f800000:return false
		counts[id] += 1
	for id in range(population):
		if counts[id] != (0 if id % 7 == 0 else 4):return false
	return true
