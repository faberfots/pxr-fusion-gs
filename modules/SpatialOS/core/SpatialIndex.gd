## ═══════════════════════════════════════════════════════════════════════════
## SPATIAL INDEX - GPU-accelerated Spatial Hash Grid
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Implements the "Spatial Index" required for Foundation 2.
##   Organizes millions of points into a 3D grid on the GPU for O(1) adjacency checks.
##
## ARCHITECTURE:
##   Uses a Linear Spatial Hash (Flat Grid) approach.
##   - Construction: compute shader (spatial_index.glsl)
##   - Data structure: 
##       1. Grid Table: cell_id -> {start_index, count}
##       2. Sorted Indices: 0..N -> original_point_index
##
## USAGE:
##   var index = SpatialIndex.new()
##   index.build_index_gpu(rd, points_buffer, count, bounds_min, bounds_max)
##
##   # Query (CPU side)
##   var nearby_indices = index.get_neighbors_radius(position, 0.5)
##
## GODOT VERSION: 4.5.1+
## ═══════════════════════════════════════════════════════════════════════════

class_name SpatialIndex
extends RefCounted

const Config = preload("res://modules/SpatialOS/core/spatial_config.gd")

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL STATE
# ═══════════════════════════════════════════════════════════════════════════

var _rd: RenderingDevice
var _point_count: int = 0
var _bounds_min: Vector3
var _bounds_max: Vector3
var _grid_dim: Vector3i
var _cell_size: float = Config.INDEX_GRID_CELL_SIZE

# GPU Buffers
var _grid_table_buffer: RID # Stores count/offset per cell
var _sorted_indices_buffer: RID # Stores reordered point indices

# CPU Mirrors (downloaded only on demand for CPU queries)
var _grid_table_cpu: PackedInt32Array = PackedInt32Array()
var _sorted_indices_cpu: PackedInt32Array = PackedInt32Array()
var _cpu_synced: bool = false
var _cpu_points := PackedVector3Array()
var _uniform_sets: Array[RID] = []

# Shader Resources
var _pipeline_rid: RID
var _shader_rid: RID

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

## Cleanup GPU resources to prevent memory leaks
## Called automatically before rebuilding index, or manually when done
func cleanup_gpu_resources() -> void:
	if not _rd:
		return
	
	for uniform_set in _uniform_sets:
		if _rd.uniform_set_is_valid(uniform_set): _rd.free_rid(uniform_set)
	_uniform_sets.clear()
	_point_count = 0
	_cpu_points = PackedVector3Array()
	_grid_table_cpu = PackedInt32Array()
	_sorted_indices_cpu = PackedInt32Array()
	_cpu_synced = false
	# Free buffers
	if _grid_table_buffer.is_valid():
		_rd.free_rid(_grid_table_buffer)
		_grid_table_buffer = RID()
	
	if _sorted_indices_buffer.is_valid():
		_rd.free_rid(_sorted_indices_buffer)
		_sorted_indices_buffer = RID()
	
	if _point_cell_ids_buffer.is_valid():
		_rd.free_rid(_point_cell_ids_buffer)
		_point_cell_ids_buffer = RID()
	
	if _write_counters_buffer.is_valid():
		_rd.free_rid(_write_counters_buffer)
		_write_counters_buffer = RID()
	
	# Free shader resources
	if _pipeline_rid.is_valid():
		_rd.free_rid(_pipeline_rid)
		_pipeline_rid = RID()
	
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
		_shader_rid = RID()

## Build the spatial index on the GPU
## @param rd: RenderingDevice instance
## @param points_buffer_rid: RID of the buffer containing point data (InputPoints)
## @param count: Number of points
## @param bounds_min: AABB min
## @param bounds_max: AABB max
func build_index_gpu(rd: RenderingDevice, points_buffer_rid: RID, count: int, bounds_min: Vector3, bounds_max: Vector3, cpu_points: PackedVector3Array = PackedVector3Array()) -> void:
	print("SpatialIndex: Building GPU index for %d points..." % count)
	var start_time = Time.get_ticks_usec()
	
	# Cleanup any previous resources to prevent memory leaks
	cleanup_gpu_resources()
	
	_rd = rd
	_point_count = count
	_bounds_min = bounds_min
	_bounds_max = bounds_max
	_cpu_synced = false # Invalidate CPU cache
	
	if count <= 0 or not rd or not points_buffer_rid.is_valid():
		_point_count = 0
		return
	_cpu_points = cpu_points
	if _cpu_points.size() != count:
		var raw := rd.buffer_get_data(points_buffer_rid)
		_cpu_points.resize(count)
		for i in range(count): _cpu_points[i] = Vector3(raw.decode_float(i * 16), raw.decode_float(i * 16 + 4), raw.decode_float(i * 16 + 8))
	# Include exact maximum-boundary points and expand cell size before imposing limits.
	var size := bounds_max - bounds_min
	_cell_size = maxf(Config.INDEX_GRID_CELL_SIZE, size[size.max_axis_index()] / maxf(1.0, Config.INDEX_MAX_GRID_DIM - 1.0))
	_grid_dim = Vector3i((size / _cell_size).floor()) + Vector3i.ONE
	_grid_dim = _grid_dim.max(Vector3i.ONE)

	var total_cells := _grid_dim.x * _grid_dim.y * _grid_dim.z
	# 2. Allocate Buffers
	_allocate_buffers(total_cells, count)
	
	# 3. Compile/Load Shader
	_compile_shader()
	
	# 4. Dispatch Steps
	# Step 0: Quantize (Assign Cell IDs)
	_dispatch_stage(0, points_buffer_rid, count)
	
	# Step 1: Count (Histogram)
	_dispatch_stage(1, points_buffer_rid, count)
	
	# Step 2: Prefix Sum (CPU Fallback for MVP simplicity)
	# For <1M cells, reading back and scanning on CPU is fast enough (~1ms)
	# and safer than implementing robust parallel scan in GLSL for first iteration.
	_calculate_prefix_sum_cpu(total_cells)
	
	# Step 3: Reorder (Bucket Sort)
	_dispatch_stage(3, points_buffer_rid, count)
	
	var duration = (Time.get_ticks_usec() - start_time) / 1000.0
	print("SpatialIndex: Build complete in %.2f ms" % duration)

## Retrieve neighbor indices within radius (CPU query)
## Used for graph construction and segmentation
## @return: Array of point indices
func get_neighbors_radius(point: Vector3, radius: float) -> PackedInt32Array:
	if _point_count == 0 or not point.is_finite() or not is_finite(radius) or radius < 0.0:
		return PackedInt32Array()
	
	ensure_cpu_sync()
	
	var result = PackedInt32Array()
	
	# Calculate cell range (cast to int for range())
	var cells_dim: int = int(ceil(radius / _cell_size))
	var center_cell := Vector3i(((point - _bounds_min) / _cell_size).floor())
	
	# Iterate cells in bounding box of radius
	for z in range(maxi(0, center_cell.z - cells_dim), mini(_grid_dim.z, center_cell.z + cells_dim + 1)):
		for y in range(maxi(0, center_cell.y - cells_dim), mini(_grid_dim.y, center_cell.y + cells_dim + 1)):
			for x in range(maxi(0, center_cell.x - cells_dim), mini(_grid_dim.x, center_cell.x + cells_dim + 1)):
				
				# Check grid bounds
				if x < 0 or x >= _grid_dim.x or y < 0 or y >= _grid_dim.y or z < 0 or z >= _grid_dim.z:
					continue
				
				var cell_id = _get_linear_cell_id(Vector3i(x, y, z))
				var start = _grid_table_cpu[cell_id]
				var count = _grid_table_cpu[cell_id + 1] - start # Next start - current start = count
				
				# Iterate points in cell
				for i in range(count):
					var sorted_idx = start + i
					var original_idx = _sorted_indices_cpu[sorted_idx]
					
					# Note: For exact radius check, we would need actual position access
					# Since this class doesn't store points on CPU, we assume the caller
					# will perform the precise distance check.
					# This returns CANDIDATE neighbors (broad phase).
					if _cpu_points[original_idx].distance_squared_to(point) <= radius * radius:
						result.append(original_idx)
	
	return result

## Get simple grid statistics for debugging
func get_grid_stats() -> Dictionary:
	return {
		"point_count": _point_count,
		"grid_dim": _grid_dim,
		"total_cells": _grid_dim.x * _grid_dim.y * _grid_dim.z,
		"cell_size": _cell_size,
		"bounds_min": _bounds_min,
		"bounds_max": _bounds_max
	}

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL HELPERS
# ═══════════════════════════════════════════════════════════════════════════

var _point_cell_ids_buffer: RID
var _write_counters_buffer: RID

func _allocate_buffers(total_cells: int, total_points: int) -> void:
	# B1: Cell IDs per point
	var ids_bytes = total_points * 4
	_point_cell_ids_buffer = _rd.storage_buffer_create(ids_bytes)
	
	# B2: Grid Table (Start Offsets) - Note: One extra for simplified count calc
	var table_bytes = (total_cells + 1) * 4
	var zero_data = PackedByteArray()
	zero_data.resize(table_bytes)
	_grid_table_buffer = _rd.storage_buffer_create(table_bytes, zero_data)
	
	# B3: Sorted Indices
	_sorted_indices_buffer = _rd.storage_buffer_create(ids_bytes)
	
	# B4: Write Counters (for atomic reorder)
	_write_counters_buffer = _rd.storage_buffer_create(table_bytes, zero_data)

func _compile_shader() -> void:
	var shader_file = load(Config.SPATIAL_INDEX_SHADER_PATH)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)

func _dispatch_stage(stage: int, points_buffer_rid: RID, count: int) -> void:
	# Push Constants
	var params = PackedByteArray()
	params.resize(48) # 3 vec3 (12) + 2 float/uint (4) aligned
	
	params.encode_float(0, _bounds_min.x)
	params.encode_float(4, _bounds_min.y)
	params.encode_float(8, _bounds_min.z)
	params.encode_float(12, _cell_size)
	
	params.encode_float(16, _bounds_max.x)
	params.encode_float(20, _bounds_max.y)
	params.encode_float(24, _bounds_max.z)
	params.encode_u32(28, count)
	
	params.encode_u32(32, _grid_dim.x)
	params.encode_u32(36, _grid_dim.y)
	params.encode_u32(40, _grid_dim.z)
	params.encode_u32(44, stage)

	# Uniforms
	var uniforms = [
		_create_uniform(0, points_buffer_rid),
		_create_uniform(1, _point_cell_ids_buffer),
		_create_uniform(2, _grid_table_buffer),
		_create_uniform(3, _sorted_indices_buffer),
		_create_uniform(4, _write_counters_buffer)
	]
	
	var uniform_set = _rd.uniform_set_create(uniforms, _shader_rid, 0)
	_uniform_sets.append(uniform_set)
	
	# Dispatch
	var compute_list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, params, params.size())
	
	var groups = ceil(count / float(Config.SPATIAL_MAX_WORKGROUP_SIZE))
	_rd.compute_list_dispatch(compute_list, int(groups), 1, 1)
	_rd.compute_list_end()
	
	# Barrier is handled automatically in Godot 4.5+
	# _rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

func _calculate_prefix_sum_cpu(total_cells: int) -> void:
	_rd.submit()
	_rd.sync()
	# 1. Read Counts
	var bytes = _rd.buffer_get_data(_grid_table_buffer)
	var counts = bytes.to_int32_array()
	
	# 2. Prefix Sum (Scan)
	var offsets = PackedInt32Array()
	offsets.resize(total_cells + 1)
	
	var current_offset = 0
	for i in range(total_cells):
		var count = counts[i]
		offsets[i] = current_offset # Store START index
		current_offset += count
	
	offsets[total_cells] = current_offset # Total count
	
	# 3. Write Offsets back to GridTable
	var offsets_bytes = offsets.to_byte_array()
	_rd.buffer_update(_grid_table_buffer, 0, offsets_bytes.size(), offsets_bytes)
	
	# 4. Also write to WriteCounters (B4) to serve as initial write positions
	# Because counters are atomicAdd'ed, they need to start at the base offset
	_rd.buffer_update(_write_counters_buffer, 0, offsets_bytes.size(), offsets_bytes)

func _create_uniform(binding: int, buffer_rid: RID) -> RDUniform:
	var u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buffer_rid)
	return u

## Ensure CPU buffers are synced with GPU data
## Must be called before accessing _grid_table_cpu or _sorted_indices_cpu directly
func ensure_cpu_sync() -> void:
	if _cpu_synced: return
	
	_rd.submit()
	_rd.sync()
	
	var table_bytes = _rd.buffer_get_data(_grid_table_buffer)
	_grid_table_cpu = table_bytes.to_int32_array()
	
	var indices_bytes = _rd.buffer_get_data(_sorted_indices_buffer)
	_sorted_indices_cpu = indices_bytes.to_int32_array()
	
	_cpu_synced = true

# Coordinate Helpers
func _get_cell_coord(pos: Vector3) -> Vector3i:
	var local = pos - _bounds_min
	var coord = Vector3i(local / _cell_size)
	coord = coord.clamp(Vector3i(0,0,0), _grid_dim - Vector3i(1,1,1))
	return coord

func _get_linear_cell_id(coord: Vector3i) -> int:
	return coord.x + (coord.y * _grid_dim.x) + (coord.z * _grid_dim.x * _grid_dim.y)

func _is_point_in_bounds(pos: Vector3) -> bool:
	return pos.x >= _bounds_min.x and pos.x <= _bounds_max.x and \
		   pos.y >= _bounds_min.y and pos.y <= _bounds_max.y and \
		   pos.z >= _bounds_min.z and pos.z <= _bounds_max.z

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or not is_instance_valid(_rd): return
	for uniform_set in _uniform_sets:
		if _rd.uniform_set_is_valid(uniform_set): _rd.free_rid(uniform_set)
	for rid in [_grid_table_buffer, _sorted_indices_buffer, _point_cell_ids_buffer, _write_counters_buffer, _pipeline_rid, _shader_rid]:
		if rid.is_valid(): _rd.free_rid(rid)
