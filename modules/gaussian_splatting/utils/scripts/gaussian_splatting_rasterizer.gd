@tool
class_name GaussianSplattingRasterizer
extends Resource
## GPU resources are touched only through the render-thread owner.
signal loaded
signal frame_failed(message: String, code: int)
signal pick_completed(request_id: int, world_position: Vector3)
signal model_pick_completed(request_id:int,instance_id:int,world_position:Vector3)
var config: GaussianSplattingConfig
var compute_shader_path := "res://modules/gaussian_splatting/shaders/compute"
var context: RenderingContext
var pipeline_manager: GPUPipelineManager
var shaders: Dictionary = {}
var descriptors: Dictionary = {}
var descriptor_sets: Dictionary = {}
var allocator: SplatBlockAllocator
var atlas_capacity_splats := 0
var pair_capacity := 0
var allocation_bytes := 0
var render_texture: Texture2DRD
var camera: Camera3D
var camera_projection := Projection()
var camera_transform := Projection()
var camera_push_constants := PackedByteArray()
var tile_dims := Vector2i.ZERO
var texture_size: Vector2i:
	get: return _texture_size
	set(value): resize(value)
var _texture_size := Vector2i.ZERO
var _viewport_size := Vector2i.ZERO
var is_loaded := false
var should_enable_heatmap := [false]
var render_scale := [1.0]
var model_scale := [1.0]
var should_terminate_thread: Array[bool] = [false]
var num_splats_loaded: Array[int] = [0]
var basis_override := Basis.IDENTITY
var gpu_init_complete := false
var rendering_enabled := false
var selected_instance_id := 0
var _is_busy_modifying_resources := false
var _mutex := Mutex.new()
var _snapshot: Dictionary = {}
var _stats: Dictionary = {}
var _readback_pending := false
var _last_readback_ms := 0
var _generation := 0
var _pick_request := Vector3i(-1, -1, 0)
var _pick_inflight := false
var _pick_epoch := 0
var _depth_rid := RID()
var _sampler := RID()
var _reported_overflow := false
var _allocation_plan: Dictionary = {}

func _init(output_size: Vector2i = Vector2i.ONE, output_texture: Texture2DRD = null, view_camera: Camera3D = null, custom_config: GaussianSplattingConfig = null) -> void:
	config = custom_config.duplicate(true) if custom_config else GaussianSplattingConfig.create_default()
	render_texture = output_texture if output_texture else Texture2DRD.new()
	camera = view_camera
	render_scale[0] = config.default_render_scale
	model_scale[0] = config.default_model_scale
	should_enable_heatmap[0] = config.enable_heatmap_by_default
	_viewport_size = output_size
	_texture_size = (Vector2(output_size) * float(render_scale[0])).ceil().max(Vector2.ONE)
	tile_dims = (_texture_size + Vector2i.ONE * (config.tile_size - 1)) / config.tile_size

func _sync(action: Callable) -> Variant:
	var completed := Semaphore.new()
	var result := [null]
	RenderingServer.call_on_render_thread(func():
		result[0] = action.call()
		completed.post()
	)
	completed.wait()
	return result[0]

static func memory_plan(settings: GaussianSplattingConfig, dimensions: Vector2i) -> Dictionary:
	if not settings.validate() or dimensions.x < 1 or dimensions.y < 1:
		return {"error": "Invalid GPU configuration"}
	var tiles := (dimensions + Vector2i.ONE * (settings.tile_size - 1)) / settings.tile_size
	var fixed: int = dimensions.x * dimensions.y * 16 + tiles.x * tiles.y * 8 + (settings.memory_max_instances + 1) * 64 + 512
	var budget: int = settings.memory_max_vram_budget_mb * 1048576
	var partition: int = settings.shader_radix_sort_workgroup_size * settings.shader_radix_sort_partition_division
	var per_splat := 304.0 + settings.max_duplication_factor * (24.0 + 1024.0 / partition)
	# Keep transactional resize headroom inside the declared total budget.
	var capacity := int(floor((budget * 0.8 - fixed - 1024) / per_splat))
	# Godot's portable path keeps individual storage buffers below 2 GiB.
	capacity = mini(capacity, int(2147483400.0 / maxf(240.0, settings.max_duplication_factor * 16.0)))
	# Vulkan's guaranteed per-axis dispatch count. Avoid admitting un-dispatchable atlases.
	capacity = mini(capacity, 65535 * settings.shader_projection_workgroup_size)
	capacity = mini(capacity, int(65535.0 * partition / settings.max_duplication_factor))
	if capacity < 1:
		return {"error": "Output textures and instance palette exceed the total GPU budget"}
	var pairs := int(capacity * settings.max_duplication_factor)
	var partitions := (pairs + partition - 1) / partition
	var total := fixed + capacity * 304 + pairs * 24 + partitions * 1024
	return {"splats": capacity, "pairs": pairs, "partitions": partitions, "bytes": total, "budget": budget}

func init_gpu() -> Error:
	if not RenderingServer.get_rendering_device(): return ERR_UNAVAILABLE
	if _is_busy_modifying_resources:
		return ERR_BUSY
	_is_busy_modifying_resources = true
	var result: Error = _sync(_initialize_on_render_thread)
	_is_busy_modifying_resources = false
	return result

func _initialize_on_render_thread() -> Error:
	if gpu_init_complete:
		return OK
	if not config.validate():
		return ERR_INVALID_PARAMETER
	var rd := RenderingServer.get_rendering_device()
	if not rd:
		return ERR_UNAVAILABLE
	var largest_group := maxi(config.tile_size * config.tile_size, maxi(config.shader_projection_workgroup_size, config.shader_radix_sort_workgroup_size))
	if largest_group > rd.limit_get(RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_INVOCATIONS):
		return ERR_PARAMETER_RANGE_ERROR
	var shared_bytes := config.shader_radix_sort_workgroup_size * config.shader_radix_sort_partition_division * 28 + 1024
	if shared_bytes > rd.limit_get(RenderingDevice.LIMIT_MAX_COMPUTE_SHARED_MEMORY_SIZE):
		return ERR_PARAMETER_RANGE_ERROR
	if _texture_size.x > rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D) or _texture_size.y > rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D):
		return ERR_PARAMETER_RANGE_ERROR
	_allocation_plan = memory_plan(config, _texture_size)
	if _allocation_plan.has("error"):
		return ERR_OUT_OF_MEMORY
	atlas_capacity_splats = _allocation_plan.splats
	pair_capacity = _allocation_plan.pairs
	allocation_bytes = _allocation_plan.bytes
	allocator = SplatBlockAllocator.new(atlas_capacity_splats * GSConstants.SPLAT_STRUCT_BYTES)
	context = RenderingContext.create(rd)
	for name in ["gsplat_projection", "radix_sort_upsweep", "radix_sort_spine", "radix_sort_downsweep", "gsplat_boundaries", "gsplat_render"]:
		var rid := context.load_shader(compute_shader_path.path_join(name + ".glsl"), config)
		if not rid.is_valid():
			_cleanup_on_render_thread()
			return ERR_CANT_CREATE
		shaders[name] = rid
	descriptors["splats"] = context.create_storage_buffer(atlas_capacity_splats * 240, PackedByteArray(), 0, "live_atlas")
	descriptors["culled_splats"] = context.create_storage_buffer(atlas_capacity_splats * 64, PackedByteArray(), 0, "projected_splats")
	descriptors["uniforms"] = context.create_uniform_buffer(128, PackedByteArray(), "frame_snapshot")
	descriptors["histogram"] = context.create_storage_buffer(16 + int(_allocation_plan.partitions) * 1024, PackedByteArray(), 0, "bounded_metadata")
	descriptors["sort_keys"] = context.create_storage_buffer(pair_capacity * 16, PackedByteArray(), 0, "wide_sort_keys")
	descriptors["sort_values"] = context.create_storage_buffer(pair_capacity * 8, PackedByteArray(), 0, "sort_indices")
	descriptors["grid_dimensions"] = context.create_storage_buffer(24, PackedInt32Array([0, 1, 1, 0, 1, 1]).to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT, "dispatch")
	descriptors["tile_bounds"] = context.create_storage_buffer(tile_dims.x * tile_dims.y * 8, PackedByteArray(), 0, "tile_ranges")
	descriptors["tile_splat_pos"] = context.create_storage_buffer(16, PackedByteArray(), 0, "pick_result")
	descriptors["instance_transforms"] = context.create_storage_buffer((config.memory_max_instances + 1) * 64, PackedByteArray(), 0, "instance_palette")
	descriptors["render_texture"] = context.create_texture(_texture_size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	var zero := PackedByteArray()
	zero.resize(4)
	descriptors["dummy_depth"] = context.create_texture(Vector2i.ONE, RenderingDevice.DATA_FORMAT_R32_SFLOAT, RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT, null, zero, "background_depth")
	for descriptor in descriptors.values():
		if not descriptor or not descriptor.is_valid():
			_cleanup_on_render_thread()
			return ERR_OUT_OF_MEMORY
	rd.texture_clear(descriptors.render_texture.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
	rd.buffer_clear(descriptors.splats.rid, 0, descriptors.splats.size)
	rd.buffer_clear(descriptors.instance_transforms.rid, 0, descriptors.instance_transforms.size)
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = context.deletion_queue.push(rd.sampler_create(sampler_state), "sampler")
	descriptor_sets["gsplat_projection"] = context.create_descriptor_set([descriptors.splats, descriptors.culled_splats, descriptors.histogram, descriptors.sort_keys, descriptors.sort_values, descriptors.grid_dimensions, descriptors.uniforms, descriptors.instance_transforms], shaders.gsplat_projection)
	descriptor_sets["radix_sort_upsweep"] = context.create_descriptor_set([descriptors.histogram, descriptors.sort_keys], shaders.radix_sort_upsweep)
	descriptor_sets["radix_sort_spine"] = context.create_descriptor_set([descriptors.histogram], shaders.radix_sort_spine)
	descriptor_sets["radix_sort_downsweep"] = context.create_descriptor_set([descriptors.histogram, descriptors.sort_keys, descriptors.sort_values], shaders.radix_sort_downsweep)
	descriptor_sets["gsplat_boundaries"] = context.create_descriptor_set([descriptors.histogram, descriptors.sort_keys, descriptors.tile_bounds], shaders.gsplat_boundaries)
	descriptor_sets["gsplat_render"] = _create_render_set(descriptors.dummy_depth.rid)
	pipeline_manager = GPUPipelineManager.new(context, config.enable_verbose_logging)
	var dimensions := {
		"gsplat_projection": [1, 1, 1], "radix_sort_upsweep": [], "radix_sort_spine": [1, 1, 1],
		"radix_sort_downsweep": [], "gsplat_boundaries": [], "gsplat_render": [tile_dims.x, tile_dims.y, 1]
	}
	for name in dimensions:
		if not descriptor_sets[name].is_valid() or not pipeline_manager.register_pipeline(name, dimensions[name], [descriptor_sets[name]], shaders[name], true):
			_cleanup_on_render_thread()
			return ERR_CANT_CREATE
	_generation += 1
	should_terminate_thread[0] = false
	render_texture.texture_rd_rid = descriptors.render_texture.rid
	gpu_init_complete = true
	is_loaded = true
	_stats = context.get_memory_stats()
	return OK

func _create_render_set(depth: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	var names := ["culled_splats", "sort_values", "tile_bounds", "tile_splat_pos", "render_texture", "histogram", "uniforms"]
	for i in range(names.size()):
		var uniform := RDUniform.new()
		uniform.binding = i
		uniform.uniform_type = descriptors[names[i]].type
		uniform.add_id(descriptors[names[i]].rid)
		uniforms.append(uniform)
	var sampled := RDUniform.new()
	sampled.binding = 7
	sampled.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	sampled.add_id(_sampler)
	sampled.add_id(depth)
	uniforms.append(sampled)
	_depth_rid = depth
	return context.deletion_queue.push(context.device.uniform_set_create(uniforms, shaders.gsplat_render, 0), "descriptor_set")

func cleanup() -> void:
	if not context and not gpu_init_complete:
		_is_busy_modifying_resources = false
		should_terminate_thread[0] = false
		return
	if _is_busy_modifying_resources:
		return
	_is_busy_modifying_resources = true
	_sync(_cleanup_on_render_thread)
	_is_busy_modifying_resources = false

func _cleanup_on_render_thread() -> void:
	_generation += 1
	gpu_init_complete = false
	is_loaded = false
	_readback_pending = false
	_pick_inflight = false
	_reported_overflow = false
	_pick_request = Vector3i(-1, -1, 0)
	_snapshot.clear()
	_stats.clear()
	if render_texture:
		render_texture.texture_rd_rid = RID()
	if context:
		context.cleanup()
	context = null
	pipeline_manager = null
	descriptors.clear()
	descriptor_sets.clear()
	shaders.clear()
	_depth_rid = RID()
	_sampler = RID()
	if allocator:
		allocator.reset()
	num_splats_loaded[0] = 0
	should_terminate_thread[0] = false

func clear_gpu_memory() -> void:
	if not gpu_init_complete:
		return
	_sync(func():
		_generation += 1
		_readback_pending = false
		_pick_inflight = false
		_pick_request = Vector3i(-1, -1, 0)
		context.device.texture_clear(descriptors.render_texture.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
		context.device.buffer_clear(descriptors.splats.rid, 0, descriptors.splats.size)
		context.device.buffer_clear(descriptors.instance_transforms.rid, 0, descriptors.instance_transforms.size)
	)
	allocator.reset()
	num_splats_loaded[0] = 0
	should_terminate_thread[0] = false
	_reported_overflow = false

func upload_splat_data(data: PackedByteArray, offset_bytes: int) -> Error:
	if not gpu_init_complete or offset_bytes < 0 or data.size() % GSConstants.SPLAT_STRUCT_BYTES != 0 or offset_bytes + data.size() > atlas_capacity_splats * GSConstants.SPLAT_STRUCT_BYTES:
		return ERR_PARAMETER_RANGE_ERROR
	var generation := _generation
	RenderingServer.call_on_render_thread(func():
		if generation == _generation and gpu_init_complete:
			context.device.buffer_update(descriptors.splats.rid, offset_bytes, data.size(), data)
	)
	return OK

func clear_splat_data(offset_bytes: int, size_bytes: int) -> void:
	if not gpu_init_complete or offset_bytes < 0 or offset_bytes + size_bytes > atlas_capacity_splats * GSConstants.SPLAT_STRUCT_BYTES:
		return
	var generation := _generation
	RenderingServer.call_on_render_thread(func():
		if generation == _generation and gpu_init_complete:
			context.device.buffer_clear(descriptors.splats.rid, offset_bytes, size_bytes)
	)

func update_instance_transform(instance_id: int, transform: Transform3D, active: bool = true) -> void:
	if not gpu_init_complete or instance_id < 0 or instance_id > config.memory_max_instances:
		return
	var matrix := Projection(Transform3D(basis_override.inverse(), Vector3.ZERO) * transform * Transform3D(config.source_basis(), Vector3.ZERO))
	var data := RenderingContext.pack_projection(matrix)
	if not active or absf(transform.basis.determinant()) < 0.00000001:
		data.fill(0)
	var generation := _generation
	RenderingServer.call_on_render_thread(func():
		if generation == _generation and gpu_init_complete:
			context.device.buffer_update(descriptors.instance_transforms.rid, instance_id * 64, data.size(), data)
	)

func update_camera_matrices() -> bool:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	var camera_world := camera.global_transform
	var view := Projection(camera_world.affine_inverse())
	var projection := camera.get_camera_projection()
	var constants := RenderingContext.pack_projection(view)
	constants.append_array(RenderingContext.pack_projection(projection))
	var snapshot := {"view": constants, "inverse": RenderingContext.pack_projection(projection.inverse()), "position": camera_world.origin, "population": allocator.high_water_splats() if allocator else 0, "time": Time.get_ticks_msec() * 0.001, "heatmap": float(should_enable_heatmap[0]), "model_scale": float(model_scale[0]), "enabled": rendering_enabled, "selected": selected_instance_id}
	_mutex.lock()
	_snapshot = snapshot
	_mutex.unlock()
	var changed := view != camera_transform or projection != camera_projection
	camera_transform = view
	camera_projection = projection
	camera_push_constants = constants
	return changed

func rasterize() -> void:
	RenderingServer.call_on_render_thread(render_on_render_thread.bind(RID(), false))

func render_on_render_thread(depth: RID = RID(), scene_depth_enabled: bool = false) -> void:
	if not gpu_init_complete:
		return
	_mutex.lock()
	var snapshot := _snapshot.duplicate()
	var pick := _pick_request
	var pick_epoch:=_pick_epoch
	_mutex.unlock()
	if snapshot.is_empty() or (not snapshot.get("enabled", false) and pick.z <= 0):
		return
	if depth.is_valid() and depth != _depth_rid:
		context.deletion_queue.free_rid(context.device, descriptor_sets.gsplat_render)
		descriptor_sets.gsplat_render = _create_render_set(depth)
	elif not depth.is_valid() and _depth_rid != descriptors.dummy_depth.rid:
		context.deletion_queue.free_rid(context.device, descriptor_sets.gsplat_render)
		descriptor_sets.gsplat_render = _create_render_set(descriptors.dummy_depth.rid)
	var rd := context.device
	var uniforms := PackedByteArray()
	uniforms.resize(128)
	var position: Vector3 = snapshot.position
	for i in range(4):
		uniforms.encode_float(i * 4, [position.x, position.y, position.z, snapshot.model_scale][i])
	for i in range(4):
		uniforms.encode_u32(16 + i * 4, [_texture_size.x, _texture_size.y, snapshot.population, pair_capacity][i])
	for i in range(4):
		uniforms.encode_float(32 + i * 4, [snapshot.time, snapshot.heatmap, float(scene_depth_enabled), 1.0][i])
	uniforms.encode_s32(48, pick.x)
	uniforms.encode_s32(52, pick.y)
	uniforms.encode_s32(56, pick.z)
	uniforms.encode_u32(60, snapshot.get("selected", 0))
	var inverse_data: PackedByteArray = snapshot.inverse
	for i in range(64):
		uniforms[64 + i] = inverse_data[i]
	rd.buffer_update(descriptors.uniforms.rid, 0, 128, uniforms)
	rd.buffer_clear(descriptors.histogram.rid, 0, 16)
	rd.buffer_clear(descriptors.tile_bounds.rid, 0, descriptors.tile_bounds.size)
	rd.buffer_clear(descriptors.tile_splat_pos.rid, 0, 16)
	rd.buffer_update(descriptors.grid_dimensions.rid, 0, 24, PackedInt32Array([0, 1, 1, 0, 1, 1]).to_byte_array())
	pipeline_manager.update_block_dimensions("gsplat_projection", [maxi(1, ceili(float(snapshot.population) / config.shader_projection_workgroup_size)), 1, 1])
	var list := context.compute_list_begin()
	pipeline_manager.get_pipeline("gsplat_projection").call(context, list, snapshot.view)
	context.compute_list_end()
	list = context.compute_list_begin()
	for pass_index in range(8):
		var constants := RenderingContext.create_push_constant([pass_index, pair_capacity * (pass_index % 2), pair_capacity * (1 - pass_index % 2), pair_capacity])
		pipeline_manager.get_pipeline("radix_sort_upsweep").call(context, list, constants, [], descriptors.grid_dimensions.rid, 0)
		pipeline_manager.get_pipeline("radix_sort_spine").call(context, list, constants)
		pipeline_manager.get_pipeline("radix_sort_downsweep").call(context, list, constants, [], descriptors.grid_dimensions.rid, 0)
	context.compute_list_end()
	list = context.compute_list_begin()
	pipeline_manager.get_pipeline("gsplat_boundaries").call(context, list, PackedByteArray(), [], descriptors.grid_dimensions.rid, 12)
	pipeline_manager.get_pipeline("gsplat_render").call(context, list, PackedByteArray(), [descriptor_sets.gsplat_render])
	context.compute_list_end()
	var now := Time.get_ticks_msec()
	if not _readback_pending and now - _last_readback_ms >= int(config.debug_update_interval * 1000):
		_readback_pending = true
		_last_readback_ms = now
		var generation := _generation
		var result := rd.buffer_get_data_async(descriptors.histogram.rid, _receive_stats.bind(generation), 0, 16)
		if result != OK:
			_readback_pending = false
	if pick.z > 0 and not _pick_inflight:
		_pick_inflight = true
		var generation := _generation
		var result := rd.buffer_get_data_async(descriptors.tile_splat_pos.rid, _receive_pick.bind(generation, pick.z,pick_epoch), 0, 16)
		if result != OK:
			_pick_inflight = false

func _receive_stats(bytes: PackedByteArray, generation: int) -> void:
	if generation != _generation:
		return
	_readback_pending = false
	if bytes.size() < 16:
		return
	_mutex.lock()
	_stats.merge(context.get_memory_stats(), true)
	_stats["pipeline_stats"] = pipeline_manager.get_stats()
	_stats["tile_splat_pairs"] = bytes.decode_u32(0)
	_stats["sort_overflow"] = bytes.decode_u32(4) != 0
	_stats["splats_rendered_frame"] = bytes.decode_u32(8)
	_mutex.unlock()
	if bytes.decode_u32(4) != 0 and not _reported_overflow:
		_reported_overflow = true
		call_deferred("emit_signal", "frame_failed", "Gaussian footprints exceeded the reserved tile-pair capacity. The last complete frame was preserved.", ERR_OUT_OF_MEMORY)

func _receive_pick(bytes: PackedByteArray, generation: int, request_id: int,epoch:int) -> void:
	if generation != _generation:
		return
	_pick_inflight = false
	_mutex.lock()
	if _pick_request.z != request_id or epoch!=_pick_epoch:
		_mutex.unlock()
		return
	_pick_request = Vector3i(-1, -1, 0)
	_mutex.unlock()
	var position := Vector3.INF
	var instance_id:=0
	if bytes.size() >= 16 and bytes.decode_float(12) > 0.5:
		position = Vector3(bytes.decode_float(0), bytes.decode_float(4), bytes.decode_float(8))
		instance_id=int(round(bytes.decode_float(12)))
	call_deferred("_deliver_pick",generation,epoch,request_id,instance_id,position)

func _deliver_pick(generation:int,epoch:int,request_id:int,instance_id:int,position:Vector3)->void:
	if generation!=_generation or epoch!=_pick_epoch:return
	model_pick_completed.emit(request_id,instance_id,position)
	pick_completed.emit(request_id,position)

func request_pick(screen_position: Vector2, request_id: int) -> void:
	var pixel := Vector2i(screen_position * float(render_scale[0]))
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= _texture_size.x or pixel.y >= _texture_size.y:
		pick_completed.emit(request_id, Vector3.INF)
		return
	_mutex.lock()
	_pick_epoch+=1
	_pick_request = Vector3i(pixel.x, pixel.y, request_id)
	_mutex.unlock()

func cancel_pick()->void:
	_mutex.lock()
	_pick_epoch+=1
	_pick_request=Vector3i(-1,-1,0)
	_mutex.unlock()

func get_splat_position(_screen_position: Vector2i) -> Vector3:
	# Retained compatibility entry point. Picking is asynchronous; consumers use request_pick.
	return Vector3.INF

func resize(size: Vector2i) -> Error:
	var next: Vector2i = (Vector2(size) * float(render_scale[0])).ceil().max(Vector2.ONE)
	if next == _texture_size:
		return OK
	if not gpu_init_complete:
		_texture_size = next
		_viewport_size = size
		tile_dims = (next + Vector2i.ONE * (config.tile_size - 1)) / config.tile_size
		return OK
	var additional := next.x * next.y * 16 + ((next.x + config.tile_size - 1) / config.tile_size) * ((next.y + config.tile_size - 1) / config.tile_size) * 8
	var previous := _texture_size.x * _texture_size.y * 16 + tile_dims.x * tile_dims.y * 8
	if allocation_bytes + additional > int(_allocation_plan.budget):
		return ERR_OUT_OF_MEMORY
	var result: Error = _sync(func():
		var replacement := context.create_texture(next, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
		var next_tiles := (next + Vector2i.ONE * (config.tile_size - 1)) / config.tile_size
		var ranges := context.create_storage_buffer(next_tiles.x * next_tiles.y * 8)
		if not replacement or not ranges:
			if replacement: context.deletion_queue.free_rid(context.device, replacement.rid)
			if ranges: context.deletion_queue.free_rid(context.device, ranges.rid)
			return ERR_OUT_OF_MEMORY
		context.deletion_queue.free_rid(context.device, descriptor_sets.gsplat_render)
		context.deletion_queue.free_rid(context.device, descriptor_sets.gsplat_boundaries)
		var old_texture: RenderingContext.Descriptor = descriptors.render_texture
		var old_ranges: RenderingContext.Descriptor = descriptors.tile_bounds
		descriptors.render_texture = replacement
		descriptors.tile_bounds = ranges
		descriptor_sets.gsplat_boundaries = context.create_descriptor_set([descriptors.histogram, descriptors.sort_keys, ranges], shaders.gsplat_boundaries)
		descriptor_sets.gsplat_render = _create_render_set(descriptors.dummy_depth.rid)
		pipeline_manager.update_descriptor_sets("gsplat_boundaries", [descriptor_sets.gsplat_boundaries])
		pipeline_manager.update_descriptor_sets("gsplat_render", [descriptor_sets.gsplat_render])
		pipeline_manager.update_block_dimensions("gsplat_render", [next_tiles.x, next_tiles.y, 1])
		render_texture.texture_rd_rid = replacement.rid
		context.deletion_queue.free_rid(context.device, old_texture.rid)
		context.deletion_queue.free_rid(context.device, old_ranges.rid)
		_texture_size = next
		tile_dims = next_tiles
		_mutex.lock()
		_stats.merge(context.get_memory_stats(), true)
		_mutex.unlock()
		return OK
	)
	if result == OK:
		_viewport_size = size
		allocation_bytes += additional - previous
	return result

func get_stats() -> Dictionary:
	_mutex.lock()
	var snapshot := _stats.duplicate(true)
	_mutex.unlock()
	snapshot["texture_size"] = _texture_size
	snapshot["tile_dims"] = tile_dims
	snapshot["atlas_capacity"] = atlas_capacity_splats
	snapshot["pair_capacity"] = pair_capacity
	snapshot["gpu_budget_bytes"] = int(_allocation_plan.get("budget", 0))
	snapshot["pipeline_stats"] = snapshot.get("pipeline_stats", {})
	return snapshot

static func get_render_capabilities() -> Dictionary:
	return {"opaque_depth":true,"orthographic_projection":true,"independent_model_transform3d":true,"transparent_mesh_interleaving":false,"gaussian_shadow_casting":false,"xr_multiview":false}
