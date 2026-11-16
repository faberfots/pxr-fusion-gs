class_name RenderingContext
extends RefCounted
## Rendering-device owner; all methods run on its owning render thread.
class DeletionQueue:
	var queue: Array[RID] = []
	var rid_metadata: Dictionary = {}
	func push(rid: RID, type_name: String = "unknown", size: int = 0, debug_name: String = "") -> RID:
		if rid.is_valid():
			queue.append(rid)
			rid_metadata[rid] = {"type": type_name, "size": size, "name": debug_name}
		return rid
	func free_rid(device: RenderingDevice, rid: RID) -> void:
		if queue.has(rid):
			var kind:String=rid_metadata.get(rid,{}).get("type","")
			queue.erase(rid)
			rid_metadata.erase(rid)
			# Dependencies may already have invalidated uniform sets. RD handles dependency teardown.
			if kind!="descriptor_set" or device.uniform_set_is_valid(rid):device.free_rid(rid)
	func flush(device: RenderingDevice) -> void:
		if not device:
			return
		for i in range(queue.size() - 1, -1, -1):
			var rid:RID=queue[i]
			if rid_metadata.get(rid,{}).get("type","")!="descriptor_set" or device.uniform_set_is_valid(rid):device.free_rid(rid)
		queue.clear()
		rid_metadata.clear()
	func get_tracked_memory() -> int:
		var total := 0
		for metadata in rid_metadata.values():
			total += int(metadata.size)
		return total
	func debug_print_resources() -> void:
		for metadata in rid_metadata.values():
			print(metadata)

class Descriptor:
	var rid: RID
	var type: RenderingDevice.UniformType
	var size := 0
	var debug_name := ""
	func _init(handle: RID, uniform_type: RenderingDevice.UniformType, byte_size: int = 0, label: String = ""):
		rid = handle
		type = uniform_type
		size = byte_size
		debug_name = label
	func is_valid() -> bool:
		return rid.is_valid()

var device: RenderingDevice
var deletion_queue := DeletionQueue.new()
var shader_cache: Dictionary = {}
var is_initialized := false
var max_vram_usage := 0
var owns_device := false
var specialization_constants: Array[RDPipelineSpecializationConstant] = []

static func create(rendering_device: RenderingDevice = null) -> RenderingContext:
	var context := RenderingContext.new()
	context.device = rendering_device if rendering_device else RenderingServer.create_local_rendering_device()
	context.owns_device = rendering_device == null
	context.is_initialized = context.device != null
	return context if context.is_initialized else null

func cleanup() -> void:
	if not is_initialized:
		return
	deletion_queue.flush(device)
	shader_cache.clear()
	is_initialized = false
	if owns_device:
		device.free()
	device = null

func submit() -> void:
	if owns_device and device:
		device.submit()

func compute_list_begin() -> int:
	return device.compute_list_begin() if device else -1

func compute_list_end() -> void:
	if device:
		device.compute_list_end()

func load_shader(path: String, config: GaussianSplattingConfig = null) -> RID:
	if shader_cache.has(path):
		return shader_cache[path]
	if config:
		specialization_constants = config.pipeline_constants()
	# Imported RDShaderFile works both in the editor and in a source-free PCK export.
	var resource := load(path) as RDShaderFile
	if not resource:
		push_error("Missing imported compute shader: " + path)
		return RID()
	var spirv := resource.get_spirv()
	if not spirv or not spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():
		push_error("Invalid imported compute shader: " + path)
		return RID()
	var rid := device.shader_create_from_spirv(spirv)
	if rid.is_valid():
		shader_cache[path] = deletion_queue.push(rid, "shader", 0, path.get_file())
	return rid

func create_storage_buffer(size: int, data: PackedByteArray = PackedByteArray(), usage: int = 0, label: String = "") -> Descriptor:
	if not device or size <= 0 or data.size() > size:
		return null
	var rid := device.storage_buffer_create(size, data, usage)
	if not rid.is_valid():
		return null
	deletion_queue.push(rid, "storage_buffer", size, label)
	return Descriptor.new(rid, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, size, label)

func create_uniform_buffer(size: int, data: PackedByteArray = PackedByteArray(), label: String = "") -> Descriptor:
	if not device or size <= 0 or data.size() > size:
		return null
	var rid := device.uniform_buffer_create(size, data)
	if not rid.is_valid():
		return null
	deletion_queue.push(rid, "uniform_buffer", size, label)
	return Descriptor.new(rid, RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, size, label)

func create_texture(dimensions: Vector2i, format: RenderingDevice.DataFormat, usage: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT, view: RDTextureView = null, data: PackedByteArray = PackedByteArray(), label: String = "") -> Descriptor:
	if not device or dimensions.x <= 0 or dimensions.y <= 0:
		return null
	if not device.texture_is_format_supported_for_usage(format, usage):
		return null
	var texture_format := RDTextureFormat.new()
	texture_format.format = format
	texture_format.width = dimensions.x
	texture_format.height = dimensions.y
	texture_format.usage_bits = usage
	var layers: Array[PackedByteArray] = []
	if not data.is_empty():
		layers.append(data)
	var rid := device.texture_create(texture_format, view if view else RDTextureView.new(), layers)
	if not rid.is_valid():
		return null
	var bytes_per_pixel := 16 if format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT else 4
	deletion_queue.push(rid, "texture", dimensions.x * dimensions.y * bytes_per_pixel, label)
	return Descriptor.new(rid, RenderingDevice.UNIFORM_TYPE_IMAGE, dimensions.x * dimensions.y * bytes_per_pixel, label)

func create_descriptor_set(descriptors: Array[Descriptor], shader: RID, set_index: int = 0) -> RID:
	if not device or not shader.is_valid():
		return RID()
	var uniforms: Array[RDUniform] = []
	for i in range(descriptors.size()):
		if not descriptors[i] or not descriptors[i].is_valid():
			return RID()
		var uniform := RDUniform.new()
		uniform.uniform_type = descriptors[i].type
		uniform.binding = i
		uniform.add_id(descriptors[i].rid)
		uniforms.append(uniform)
	return deletion_queue.push(device.uniform_set_create(uniforms, shader, set_index), "descriptor_set")

func create_pipeline(block_dimensions: Array, descriptor_sets: Array, shader: RID, label: String = "") -> Dictionary:
	if not device or not shader.is_valid() or descriptor_sets.is_empty():
		return {"rid": RID(), "callable": Callable()}
	var pipeline := device.compute_pipeline_create(shader, specialization_constants)
	if not pipeline.is_valid():
		return {"rid": RID(), "callable": Callable()}
	deletion_queue.push(pipeline, "compute_pipeline", 0, label)
	var invoke := func(context: RenderingContext, list: int, constants: PackedByteArray = PackedByteArray(), overrides: Array = [], indirect: RID = RID(), indirect_offset: int = 0):
		var sets: Array = descriptor_sets if overrides.is_empty() else overrides
		var rd := context.device
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		if not constants.is_empty():
			rd.compute_list_set_push_constant(list, constants, constants.size())
		for i in range(sets.size()):
			rd.compute_list_bind_uniform_set(list, sets[i], i)
		if indirect.is_valid():
			rd.compute_list_dispatch_indirect(list, indirect, indirect_offset)
		elif block_dimensions.size() == 3:
			rd.compute_list_dispatch(list, block_dimensions[0], block_dimensions[1], block_dimensions[2])
		rd.compute_list_add_barrier(list)
	return {"rid": pipeline, "callable": invoke}

static func create_push_constant(values: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(((values.size() * 4 + 15) / 16) * 16)
	for i in range(values.size()):
		if values[i] is float:
			bytes.encode_float(i * 4, values[i])
		else:
			bytes.encode_s32(i * 4, int(values[i]))
	return bytes

static func pack_projection(matrix: Projection) -> PackedByteArray:
	return PackedFloat32Array([matrix.x.x, matrix.x.y, matrix.x.z, matrix.x.w, matrix.y.x, matrix.y.y, matrix.y.z, matrix.y.w, matrix.z.x, matrix.z.y, matrix.z.z, matrix.z.w, matrix.w.x, matrix.w.y, matrix.w.z, matrix.w.w]).to_byte_array()

static func is_resource_valid(resource: Variant) -> bool:
	if resource is RID:
		return resource.is_valid()
	return resource is Object and is_instance_valid(resource) and resource.has_method("is_valid") and resource.is_valid()

static func safe_free_resource(rd: RenderingDevice, resource: Variant, queue: DeletionQueue = null) -> bool:
	if not rd or not is_resource_valid(resource):
		return false
	var rid: RID = resource if resource is RID else resource.rid
	if queue:
		queue.free_rid(rd, rid)
	else:
		rd.free_rid(rid)
	return true

func get_memory_stats() -> Dictionary:
	var tracked := deletion_queue.get_tracked_memory()
	max_vram_usage = maxi(max_vram_usage, tracked)
	return {"total": tracked, "tracked": tracked, "peak": max_vram_usage, "resource_count": deletion_queue.queue.size()}

func debug_print_resources() -> void:
	deletion_queue.debug_print_resources()
