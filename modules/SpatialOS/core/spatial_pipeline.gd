class_name SpatialPipeline
extends Node

# The API to the outside world
signal processing_started
signal processing_completed(resource: PointCloudResource)  # Renamed for consistency
signal processing_failed(error_message: String)  # NEW

# ═══════════════════════════════════════════════════════════════
# ASYNC LOADING SIGNALS (NEW)
# ═══════════════════════════════════════════════════════════════

## Emitted during async loading with real progress
signal loading_progress(percent: float, points_loaded: int, total_points: int)

## Emitted when a chunk is ready for progressive rendering
signal loading_prepared(total_points: int)
signal chunk_loaded(points: PackedVector3Array, colors: PackedColorArray)

const Config = preload("res://modules/SpatialOS/core/spatial_config.gd")

var _resources: Array[WeakRef] = []
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

var compactor_shader_rid: RID
var compactor_pipeline_rid: RID

# ═══════════════════════════════════════════════════════════════
# ASYNC LOADER STATE (NEW)
# ═══════════════════════════════════════════════════════════════

## Internal async loader instance (created on demand)
var _async_loader: AsyncPLYLoader = null

## Stores parameters for async processing continuation
var _pending_voxel_size: float = -1.0
var _pending_force_voxelization: bool = false

func _ready():
	# WOOOAOOW Factor: Initialize local RD for background processing
	rd = RenderingServer.create_local_rendering_device()
	if rd: _compile_shaders()

func _compile_shaders():
	var shader_file = load(Config.VOXELIZER_SHADER)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	
	# Compile compactor if enabled
	if Config.USE_GPU_COMPACTION:
		var compactor_file = load(Config.COMPACTOR_SHADER)
		var compactor_spirv: RDShaderSPIRV = compactor_file.get_spirv()
		compactor_shader_rid = rd.shader_create_from_spirv(compactor_spirv)

# ═══════════════════════════════════════════════════════════════
# GRAPH INTELLIGENCE API (FOUNDATION 2)
# ═══════════════════════════════════════════════════════════════

## Compute segmentation for a resource using specified mode
## @param resource: The point cloud resource
## @param mode: Segmentation mode (0=Connectivity, 1=ColorCluster, 2=DepthEdges)
## @param edge_threshold: Optional runtime override for edge threshold (-1 to use config default)
func compute_graph(resource: PointCloudResource, mode: int = 0, edge_threshold: float = -1.0) -> Dictionary:
	var graph = SpatialGraph.new()
	graph.edge_threshold_override = edge_threshold
	return graph.compute_segmentation(resource, mode)

func ingest_and_process(file_path: String, voxel_size: float = -1.0, force_voxelization: bool = false):
	emit_signal("processing_started")
	
	# ═══════════════════════════════════════════════════════════════
	# ASYNC VS SYNC LOADING DECISION
	# ═══════════════════════════════════════════════════════════════
	
	# Check file size to determine loading strategy
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		emit_signal("processing_failed", "Failed to open PLY file. Check path and permissions.")
		return
	
	var file_size_mb = file.get_length() / (1024.0 * 1024.0)
	file.close()
	
	# Use async loading for large files when enabled
	var use_async = Config.USE_ASYNC_LOADING and file_size_mb >= Config.ASYNC_MIN_FILE_SIZE_MB
	
	if use_async:
		print("SpatialOS: Using ASYNC loading for %.1f MB file" % file_size_mb)
		
		# Store parameters for continuation after async load
		_pending_voxel_size = voxel_size
		_pending_force_voxelization = force_voxelization
		
		# Create async loader if needed
		if not _async_loader:
			_async_loader = AsyncPLYLoader.new()
			add_child(_async_loader)
			
			# Connect signals (one-time setup)
			_async_loader.loading_prepared.connect(func(total): loading_prepared.emit(total))
			_async_loader.progress_updated.connect(_on_async_progress)
			_async_loader.chunk_ready.connect(_on_async_chunk)
			_async_loader.loading_completed.connect(_on_async_completed)
			_async_loader.loading_failed.connect(_on_async_failed)
			_async_loader.loading_cancelled.connect(_on_async_cancelled)
		
		# Start async loading
		_async_loader.load_ply_async(file_path)
		return
	
	# ═══════════════════════════════════════════════════════════════
	# SYNC LOADING (Original path - unchanged)
	# ═══════════════════════════════════════════════════════════════
	
	print("SpatialOS: Using SYNC loading for %.1f MB file" % file_size_mb)
	
	# 1. Load (CPU)
	var raw_data = PLYLoader.load_ply(file_path)
	if raw_data.is_empty() or raw_data.has("error"):
		emit_signal("processing_failed", "Failed to load PLY file. Check format and path.")
		return
	
	var raw_points = raw_data["points"] as PackedVector3Array
	var raw_colors = raw_data["colors"] as PackedColorArray
	var count = raw_data["count"] as int
	var has_colors = raw_data.get("has_colors", false)
	
	if count == 0:
		emit_signal("processing_failed", "PLY file contains no vertex data.")
		return
	
	print("SpatialOS: Processing ", count, " points (Colors: ", has_colors, ")")
	
	# SMART DECISION: Direct render vs Voxelization
	var use_direct = Config.USE_DIRECT_RENDERING and not force_voxelization
	var is_large_scan = count >= Config.AUTO_DIRECT_RENDER_THRESHOLD
	var is_gaussian_splatting = raw_data.get("is_gaussian_splatting", false)
	
	if use_direct or is_large_scan:
		print("SpatialOS: Using DIRECT RENDERING mode (", count, " points)")
		
		# Pass GS detection to direct rendering for coordinate transform
		_process_direct_rendering(file_path, raw_points, raw_colors, has_colors, is_gaussian_splatting)
		return
	
	print("SpatialOS: Using VOXELIZATION mode")
	
# 2. Calculate Bounds (CPU)
	var min_b = Vector3(INF, INF, INF)
	var max_b = Vector3(-INF, -INF, -INF)
	for p in raw_points:
		min_b = min_b.min(p)
		max_b = max_b.max(p)
	
	print("SpatialOS: Bounds: ", min_b, " to ", max_b)
	
	# 2.5. Smart voxel size calculation (if not manually specified)
	if voxel_size <= 0:
		voxel_size = _calculate_optimal_voxel_size(min_b, max_b, count)
	else:
		print("SpatialOS: Using manual voxel size: %.2fcm" % (voxel_size * 100))
	
	_finish_voxelized(raw_data, voxel_size)

## Direct rendering path - bypass voxelization for maximum detail
## Used for large scans or when detail preservation is critical
func _process_direct_rendering(file_path: String, points: PackedVector3Array, colors: PackedColorArray, has_colors: bool, is_gaussian_splatting: bool = false):
	var count = points.size()
	
	# ═══════════════════════════════════════════════════════════════
	# COORDINATE SYSTEM CORRECTION
	# ═══════════════════════════════════════════════════════════════
	
	# Apply coordinate transform if needed
	if Config.AUTO_FLIP_GAUSSIAN_SPLATTING and is_gaussian_splatting:
		points = _apply_coordinate_transform(points, "gs_basis")
		print("SpatialOS: Gaussian Splatting coordinate system corrected (Y-flipped)")
	
	# Calculate bounds AFTER transformation
	var min_b = Vector3(INF, INF, INF)
	var max_b = Vector3(-INF, -INF, -INF)
	for p in points:
		min_b = min_b.min(p)
		max_b = max_b.max(p)
	
	print("SpatialOS: Bounds: ", min_b, " to ", max_b)
	
	# Downsample if too many points (for performance)
	var final_points = points
	var final_colors = colors
	
	if count > Config.DIRECT_RENDER_MAX_POINTS:
		print("SpatialOS: Downsampling from ", count, " to ", Config.DIRECT_RENDER_MAX_POINTS, " points")
		var ratio = float(Config.DIRECT_RENDER_MAX_POINTS) / count
		final_points = _downsample_points(points, ratio)
		final_colors = _downsample_points(colors, ratio) if colors.size() > 0 else PackedColorArray()
		count = final_points.size()
	
	# Create resource directly (no voxelization)
	var resource = PointCloudResource.new(final_points, final_colors)
	resource.voxel_size = 0.0  # Indicates no voxelization
	resource.metadata["source_file"] = file_path
	resource.metadata["processed_date"] = Time.get_datetime_string_from_system()
	resource.metadata["has_native_colors"] = has_colors
	resource.metadata["rendering_mode"] = "direct"
	
	print("SpatialOS: Direct rendering complete - ", count, " points preserved")
	
	_finalize_processing(resource)

## Downsample point cloud by ratio (uniform sampling)
## Returns every Nth point where N = 1/ratio
func _downsample_points(points_or_colors, ratio: float):
	var length: int = points_or_colors.size()
	var target := clampi(int(floor(length * ratio)), 0, length)
	var result = PackedVector3Array() if points_or_colors is PackedVector3Array else PackedColorArray()
	result.resize(target)
	for i in range(target): result[i] = points_or_colors[int(i * float(length) / target)]
	return result

func _apply_coordinate_transform(points: PackedVector3Array, transform_type: String = "y_flip") -> PackedVector3Array:
	if transform_type == "none":
		return points
	
	var transformed = PackedVector3Array()
	transformed.resize(points.size())
	
	match transform_type:
		"gs_basis":
			var basis := GaussianSplattingConfig.new().source_basis()
			for i in range(points.size()): transformed[i] = basis * points[i]
		"y_flip":
			# Flip Y-axis (most common for Gaussian Splatting)
			# Converts Y-down to Y-up
			print("SpatialOS: Applying Y-flip coordinate transform (GS → Godot)")
			for i in range(points.size()):
				var p = points[i]
				transformed[i] = Vector3(p.x, -p.y, p.z)
		
		"z_up_to_y_up":
			# Rotate Z-up to Y-up (common for CAD/GIS data)
			# X stays X, Z becomes Y, Y becomes -Z
			print("SpatialOS: Applying Z-up → Y-up coordinate transform")
			for i in range(points.size()):
				var p = points[i]
				transformed[i] = Vector3(p.x, p.z, -p.y)
		
		"full_flip":
			# Flip all axes (rare, but useful for debugging)
			print("SpatialOS: Applying full axis flip")
			for i in range(points.size()):
				var p = points[i]
				transformed[i] = Vector3(-p.x, -p.y, -p.z)
		
		_:
			push_warning("Unknown coordinate transform: ", transform_type)
			return points
	
	return transformed

## Calculate optimal voxel size based on point cloud density and bounds
## Returns a voxel size that targets ~100k-500k voxels for optimal performance
func _calculate_optimal_voxel_size(bounds_min: Vector3, bounds_max: Vector3, point_count: int) -> float:
	var size = bounds_max - bounds_min
	var volume = size.x * size.y * size.z
	
	if volume <= 0:
		return Config.DEFAULT_VOXEL_SIZE
	
	# Calculate point density (points per cubic meter)
	var density = point_count / volume
	
	# Target: 200k voxels for good balance between detail and performance
	var target_voxel_count = 200000
	
	# Calculate voxel size that would give us target count
	# voxel_count = volume / (voxel_size^3)
	# voxel_size = (volume / target_voxel_count)^(1/3)
	var optimal_size = pow(volume / target_voxel_count, 1.0/3.0)
	
	# Clamp to reasonable bounds (5mm to 50cm)
	optimal_size = clamp(optimal_size, 0.005, 0.5)
	
	print("SpatialOS: Adaptive voxel size: %.2fcm (density: %.1f pts/m³)" % [optimal_size * 100, density])
	
	return optimal_size

# ═══════════════════════════════════════════════════════════════
# ASYNC LOADING CALLBACKS (NEW)
# ═══════════════════════════════════════════════════════════════

## Called when async loading progress updates
## Re-emits the signal for UI consumption
func _on_async_progress(percent: float, points_loaded: int, total_points: int) -> void:
	loading_progress.emit(percent, points_loaded, total_points)

## Called when a chunk is ready during async loading
## Re-emits for progressive rendering in UI
func _on_async_chunk(points: PackedVector3Array, colors: PackedColorArray) -> void:
	chunk_loaded.emit(points, colors)

## Called when async loading completes successfully
## Continues with the normal processing pipeline (direct render or voxelization)
func _on_async_completed(raw_data: Dictionary) -> void:
	var raw_points = raw_data["points"] as PackedVector3Array
	var raw_colors = raw_data["colors"] as PackedColorArray
	var count = raw_data["count"] as int
	var has_colors = raw_data.get("has_colors", false)
	var is_gaussian_splatting = raw_data.get("is_gaussian_splatting", false)
	
	if count == 0:
		emit_signal("processing_failed", "PLY file contains no vertex data.")
		return
	
	print("SpatialOS: Async load complete. Processing ", count, " points (Colors: ", has_colors, ")")
	
	# SMART DECISION: Direct render vs Voxelization
	var use_direct = Config.USE_DIRECT_RENDERING and not _pending_force_voxelization
	var is_large_scan = count >= Config.AUTO_DIRECT_RENDER_THRESHOLD
	
	if use_direct or is_large_scan:
		print("SpatialOS: Using DIRECT RENDERING mode (", count, " points)")
		
		# Pass GS detection to direct rendering for coordinate transform
		# Need the original file path - stored in metadata if available
		var file_path = raw_data.get("source_file", "")
		_process_direct_rendering(file_path, raw_points, raw_colors, has_colors, is_gaussian_splatting)
		return
	
	# For voxelization, we need to continue with the GPU pipeline
	# This is the more complex path that uses the existing voxelization code
	print("SpatialOS: Using VOXELIZATION mode (from async data)")
	_process_voxelization_from_data(raw_data, _pending_voxel_size)

## Called when async loading fails
func _on_async_failed(error_message: String) -> void:
	emit_signal("processing_failed", error_message)

## Called when async loading is cancelled by user
func _on_async_cancelled() -> void:
	emit_signal("processing_failed", "Loading cancelled by user.")

## Public method to cancel current async loading
## Call this from UI when user clicks Cancel button
func cancel_loading() -> void:
	if _async_loader and _async_loader.is_loading():
		_async_loader.cancel()
		print("SpatialOS: Cancel request sent to async loader")

## Check if currently loading asynchronously
func is_loading_async() -> bool:
	return _async_loader and _async_loader.is_loading()

## Process voxelization from already-loaded data (used by async path)
## This is a simplified version that skips the PLYLoader step
func _process_voxelization_from_data(raw_data: Dictionary, voxel_size: float) -> void:
	_finish_voxelized(raw_data, voxel_size)

func _finalize_processing(resource: PointCloudResource) -> void:
	print("SpatialOS: Finalizing resource (Indexing)...")
	
	# ─────────────────────────────────────────────────────────────────
	# BUILD SPATIAL INDEX (FOUNDATION 1 -> 2 BRIDGE)
	# ─────────────────────────────────────────────────────────────────
	# If we have GPU points available, we build the index now
	# Note: Currently resource stores points on CPU memory.
	# To build index on GPU, we upload them briefly.
	
	var points = resource.points # Corrected: direct property access
	var count = resource.point_count
	
	if count > 0:
		# Calculate bounds (CPU) - reuse if already computed elsewhere?
		# For safety/simplicity, recount here or ask resource
		var min_b = Vector3(INF, INF, INF)
		var max_b = Vector3(-INF, -INF, -INF)
		for p in points:
			min_b = min_b.min(p)
			max_b = max_b.max(p)
		
		# Upload points for indexing shader
		# We need a packed InputPoint struct (vec4 aligned)
		var input_bytes = PackedByteArray()
		input_bytes.resize(count * 16)
		
		for i in range(count):
			var p = points[i]
			var offset = i * 16
			input_bytes.encode_float(offset, p.x)
			input_bytes.encode_float(offset + 4, p.y)
			input_bytes.encode_float(offset + 8, p.z)
			# Padding/Data (0.0)
		
		var points_buffer = rd.storage_buffer_create(input_bytes.size(), input_bytes)
		
		# Instantiate and Build Index
		var spatial_index = SpatialIndex.new()
		spatial_index.build_index_gpu(rd, points_buffer, count, min_b, max_b, points)
		
		# Store Index in Resource Metadata (Access for Foundation 2)
		resource.metadata["spatial_index"] = spatial_index
		
		# Cleanup upload buffer
		rd.free_rid(points_buffer)
	
	_resources.append(weakref(resource))
	emit_signal("processing_completed", resource)

func _finish_voxelized(data: Dictionary, size: float) -> void:
	if not rd:
		processing_failed.emit("Voxelization requires a compute-capable rendering backend.")
		return
	var points: PackedVector3Array = data.points
	var colors: PackedColorArray = data.colors
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	if size <= 0.0: size = _calculate_optimal_voxel_size(bounds.position, bounds.end, points.size())
	if not is_finite(size) or size <= 0.0:
		processing_failed.emit("Invalid voxel size.")
		return
	var unpacked := _voxelize(points, colors, bounds.position, size)
	if unpacked.has("error"):
		processing_failed.emit(unpacked.error)
		return
	var resource := PointCloudResource.new(unpacked.points, unpacked.colors)
	resource.voxel_size = size
	resource.metadata.source_file = data.get("source_file", "")
	resource.metadata.has_native_colors = data.get("has_colors", false)
	_finalize_processing(resource)

func _voxelize(points: PackedVector3Array, colors: PackedColorArray, minimum: Vector3, size: float) -> Dictionary:
	var capacity := mini(Config.GRID_SIZE, maxi(16, points.size() * 2))
	var bytes := PackedByteArray()
	bytes.resize(points.size() * 16)
	for i in range(points.size()):
		bytes.encode_float(i * 16, points[i].x)
		bytes.encode_float(i * 16 + 4, points[i].y)
		bytes.encode_float(i * 16 + 8, points[i].z)
		bytes.encode_u32(i * 16 + 12, colors[i].to_rgba32() if i < colors.size() else 0xffffffff)
	var input := rd.storage_buffer_create(bytes.size(), bytes)
	var grid := rd.storage_buffer_create(16 + capacity * 48)
	rd.buffer_clear(grid, 0, 16 + capacity * 48)
	var output_capacity := mini(capacity, points.size())
	var output := rd.storage_buffer_create(16 + output_capacity * 32)
	rd.buffer_clear(output, 0, 16 + output_capacity * 32)
	var sets: Array[RID] = []
	var pipelines: Array[RID] = []
	for stage in range(2):
		var shader: RID = shader_rid if stage == 0 else compactor_shader_rid
		var uniforms: Array[RDUniform] = []
		for i in range(2):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = i
			uniform.add_id([input, grid][i] if stage == 0 else [grid, output][i])
			uniforms.append(uniform)
		var set_rid := rd.uniform_set_create(uniforms, shader, 0)
		var pipeline := rd.compute_pipeline_create(shader)
		sets.append(set_rid)
		pipelines.append(pipeline)
		var push := PackedByteArray()
		push.resize(32)
		push.encode_float(0, minimum.x)
		push.encode_float(4, minimum.y)
		push.encode_float(8, minimum.z)
		push.encode_float(12, size)
		push.encode_u32(16, points.size() if stage == 0 else capacity)
		push.encode_u32(20, capacity if stage == 0 else output_capacity)
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		rd.compute_list_bind_uniform_set(list, set_rid, 0)
		rd.compute_list_set_push_constant(list, push, push.size())
		rd.compute_list_dispatch(list, ceili(float(points.size() if stage == 0 else capacity) / 256.0), 1, 1)
		rd.compute_list_end()
	rd.submit()
	rd.sync()
	var overflow := rd.buffer_get_data(grid, 0, 4).decode_u32(0) != 0
	var packed := rd.buffer_get_data(output)
	var count := mini(packed.decode_u32(0), output_capacity)
	var result_points := PackedVector3Array()
	var result_colors := PackedColorArray()
	result_points.resize(count)
	result_colors.resize(count)
	for i in range(count):
		var offset := 16 + i * 32
		result_points[i] = Vector3(packed.decode_float(offset), packed.decode_float(offset + 4), packed.decode_float(offset + 8))
		result_colors[i] = Color(packed.decode_float(offset + 16), packed.decode_float(offset + 20), packed.decode_float(offset + 24), packed.decode_float(offset + 28))
	for set_rid in sets: rd.free_rid(set_rid)
	for pipeline in pipelines: rd.free_rid(pipeline)
	for buffer in [input, grid, output]: rd.free_rid(buffer)
	return {"error": "Voxel hash capacity exceeded; no partial result was committed."} if overflow else {"points": result_points, "colors": result_colors}

func _exit_tree() -> void:
	if _async_loader: _async_loader.cancel()
	for reference in _resources:
		var resource = reference.get_ref()
		if resource: resource.invalidate_derived()
	if rd:
		for shader in [shader_rid, compactor_shader_rid]:
			if shader.is_valid(): rd.free_rid(shader)
		rd.free()
		rd = null
