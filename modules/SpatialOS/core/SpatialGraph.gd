class_name SpatialGraph
extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## SPATIAL GRAPH - GPU-Accelerated Topological Understanding (Foundation 2)
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Transforms unstructured point clouds into structured objects (Segments).
##   Uses GPU compute shaders for parallel label propagation.
##
## ALGORITHM (GPU Label Propagation):
##   1. Initialize: labels[i] = i (each point is its own component)
##   2. Iterate: Each point adopts minimum label of connected neighbors
##   3. Converge: Repeat until no labels change
##   4. Compact: Remap labels to contiguous IDs, filter noise
##
## PERFORMANCE:
##   - 227K points: ~10-50ms (vs minutes on CPU)
##   - 1M points: ~50-200ms
##
## ═══════════════════════════════════════════════════════════════════════════

const Config = preload("res://modules/SpatialOS/core/spatial_config.gd")

# Shader path
const SEGMENTATION_SHADER_PATH = "res://modules/SpatialOS/shaders/graph_segmentation.glsl"
const GEOMETRIC_SHADER_PATH = "res://modules/SpatialOS/shaders/geometric_analysis.glsl"

# GPU Resources
var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID
var _next_labels_buffer: RID
var _labels_buffer: RID
var _changed_buffer: RID
var _points_buffer: RID  # Copy of input points for GPU access
var _normals_buffer: RID # Normals for geometric segmentation
var _colors_buffer: RID  # Colors for multi-modal edge detection

# Runtime override for edge threshold (set before calling compute_segmentation)
# If > 0, uses this value instead of Config.EDGE_THRESHOLD
var edge_threshold_override: float = -1.0
## Main entry point - dispatches to appropriate segmentation algorithm
## @param resource: PointCloudResource with spatial_index in metadata
## @param mode: Segmentation mode (0=Connectivity, 1=ColorCluster, 2=DepthEdges)
## @return: Dictionary with stats { "segment_count": int, "processing_time": float }
func compute_segmentation(resource: PointCloudResource, mode: int = 0) -> Dictionary:
	match mode:
		Config.SegmentationMode.CONNECTIVITY:
			return compute_connectivity(resource)
		Config.SegmentationMode.COLOR_CLUSTER:
			return compute_color_clustering(resource)
		Config.SegmentationMode.DEPTH_EDGES:
			return compute_depth_edges(resource)
		_:
			printerr("SpatialGraph: Unknown segmentation mode: %d" % mode)
			return { "status": "failed", "error": "unknown_mode" }

## Compute connectivity using GPU Label Propagation
## @param resource: PointCloudResource with spatial_index in metadata
## @return: Dictionary with stats { "segment_count": int, "processing_time": float }
func compute_connectivity(resource: PointCloudResource) -> Dictionary:
	print("SpatialGraph: Starting GPU connectivity analysis...")
	var start_time = Time.get_ticks_msec()
	
	# Validate inputs
	if not "spatial_index" in resource.metadata:
		printerr("SpatialGraph: Missing Spatial Index! Cannot build graph.")
		return { "status": "failed", "error": "missing_index" }
	
	var index: SpatialIndex = resource.metadata["spatial_index"]
	var point_count = resource.point_count
	
	# Get the RenderingDevice from the index (reuse for efficiency)
	_rd = index._rd
	
	# Calculate connectivity radius
	var radius: float
	if Config.GRAPH_AUTO_RADIUS:
		var volume = resource.aabb.get_volume()
		radius = Config.calculate_auto_radius(point_count, volume)
		print("SpatialGraph: Auto-calculated radius = %.3fm" % radius)
	else:
		radius = Config.GRAPH_CONNECTIVITY_RADIUS
	
	# Compile shader
	_compile_shader()
	
	# Create buffers
	_create_buffers(resource, point_count)
	
	# Run iterative label propagation
	var iterations = _run_label_propagation(resource, index, point_count, radius)
	
	if iterations < 0:
		_cleanup()
		return {"status": "failed", "error": "connectivity_did_not_converge", "iterations": -iterations}
	# Read results back to CPU
	var labels = _read_labels(point_count)
	
	# Compact and filter segments
	var result = _compact_labels(labels, point_count)
	
	# Cleanup GPU resources
	_cleanup()
	
	var duration = Time.get_ticks_msec() - start_time
	print("SpatialGraph: GPU segmentation complete. Found %d objects in %.2f s (%d iterations)" % 
		  [result["segment_count"], duration / 1000.0, iterations])
	
	# Update resource with segment labels
	resource.segments = result["segments"]
	resource.segment_count = result["segment_count"]
	resource.metadata["graph_built"] = true
	
	# Post-processing: Merge small segments into neighbors
	var merged_count = _merge_small_segments(resource)
	if merged_count > 0:
		# Recount unique segments after merge
		var unique_segments: Dictionary = {}
		for seg_id in resource.segments:
			if seg_id > 0:
				unique_segments[seg_id] = true
		resource.segment_count = unique_segments.size()
	
	# Compute segment metadata (centroid, bbox, point_count)
	_compute_segment_metadata(resource)
	
	# Infer spatial relationships between segments
	_infer_relationships(resource)
	
	return {
		"segment_count": resource.segment_count,
		"processing_time": duration / 1000.0,
		"iterations": iterations
	}

func _compile_shader() -> void:
	var shader_file = load(SEGMENTATION_SHADER_PATH)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)

func _create_buffers(resource: PointCloudResource, point_count: int) -> void:
	var owned_points := resource.points
	# Labels buffer: Initialize labels[i] = i
	var labels = PackedInt32Array()
	labels.resize(point_count)
	for i in range(point_count):
		labels[i] = i
	var labels_bytes = labels.to_byte_array()
	_labels_buffer = _rd.storage_buffer_create(labels_bytes.size(), labels_bytes)
	_next_labels_buffer = _rd.storage_buffer_create(labels_bytes.size(), labels_bytes)
	
	# Changed flag buffer (single uint32)
	var changed_bytes = PackedByteArray()
	changed_bytes.resize(4)
	changed_bytes.encode_u32(0, 0)
	_changed_buffer = _rd.storage_buffer_create(4, changed_bytes)
	
	# Points buffer (copy to GPU in shader-compatible format)
	var points_bytes = PackedByteArray()
	points_bytes.resize(point_count * 16)  # vec4 per point (x, y, z, pad)
	for i in range(point_count):
		var p = owned_points[i]
		points_bytes.encode_float(i * 16, p.x)
		points_bytes.encode_float(i * 16 + 4, p.y)
		points_bytes.encode_float(i * 16 + 8, p.z)
		points_bytes.encode_float(i * 16 + 12, 0.0)
	_points_buffer = _rd.storage_buffer_create(points_bytes.size(), points_bytes)
	
	# Normals buffer (Geometric Connectivity 2.5) - Binding 5
	# Create empty buffer if no normals, or populate if available
	var normals_bytes = PackedByteArray()
	normals_bytes.resize(point_count * 16) # vec4 per normal (x, y, z, curv)
	
	if resource.normals.size() == point_count:
		for i in range(point_count):
			var n = resource.normals[i]
			normals_bytes.encode_float(i * 16, n.x)
			normals_bytes.encode_float(i * 16 + 4, n.y)
			normals_bytes.encode_float(i * 16 + 8, n.z)
			# Include curvature in w component if available
			var curv = resource.curvature[i] if resource.curvature.size() > i else 0.0
			normals_bytes.encode_float(i * 16 + 12, curv)
	
	_normals_buffer = _rd.storage_buffer_create(normals_bytes.size(), normals_bytes)
	
	# Colors buffer (Foundation 2.6 Multi-Modal Edge) - Binding 6
	var colors_bytes = PackedByteArray()
	colors_bytes.resize(point_count * 16) # vec4 per color (r, g, b, a)
	
	if resource.colors.size() == point_count:
		for i in range(point_count):
			var c = resource.colors[i]
			colors_bytes.encode_float(i * 16, c.r)
			colors_bytes.encode_float(i * 16 + 4, c.g)
			colors_bytes.encode_float(i * 16 + 8, c.b)
			colors_bytes.encode_float(i * 16 + 12, c.a)
	else:
		# Default to gray if no colors
		for i in range(point_count):
			colors_bytes.encode_float(i * 16, 0.5)
			colors_bytes.encode_float(i * 16 + 4, 0.5)
			colors_bytes.encode_float(i * 16 + 8, 0.5)
			colors_bytes.encode_float(i * 16 + 12, 1.0)
	
	_colors_buffer = _rd.storage_buffer_create(colors_bytes.size(), colors_bytes)


func _run_label_propagation(resource: PointCloudResource, index: SpatialIndex, point_count: int, radius: float) -> int:
	var max_iterations := maxi(128, ceili(log(maxi(2, point_count)) / log(2.0)) * 16)
	var converged := false
	var iterations = 0
	
	# Get index GPU resources
	var grid_table_buffer = index._grid_table_buffer
	var sorted_indices_buffer = index._sorted_indices_buffer
	var bounds_min = index._bounds_min
	var bounds_max = index._bounds_max
	var cell_size = index._cell_size
	var grid_dim = index._grid_dim
	
	# Push constants - Extended for Multi-Modal Edge Segmentation (Foundation 2.6)
	# GLSL std430 layout:
	#   0-11: vec3 bounds_min
	#   12-15: float cell_size
	#   16-27: vec3 bounds_max
	#   28-31: uint point_count
	#   32-43: uvec3 grid_dim
	#   44-47: float radius_sq
	#   48-51: float w_spatial
	#   52-55: float w_normal
	#   56-59: float w_color
	#   60-63: float w_curvature
	#   64-67: float w_height
	#   68-71: float edge_threshold
	#   72-75: float height_edge_min
	#   76-79: uint use_normals
	#   80-95: PADDING (to 96 bytes, multiple of 16)
	# Total: 80 bytes (no padding needed, struct ends on 4-byte boundary)
	
	var params = PackedByteArray()
	params.resize(80)  # Exactly 80 bytes as required by shader
	
	# bounds_min (vec3) + cell_size
	params.encode_float(0, bounds_min.x)
	params.encode_float(4, bounds_min.y)
	params.encode_float(8, bounds_min.z)
	params.encode_float(12, cell_size)
	
	# bounds_max (vec3) + point_count
	params.encode_float(16, bounds_max.x)
	params.encode_float(20, bounds_max.y)
	params.encode_float(24, bounds_max.z)
	params.encode_u32(28, point_count)
	
	# grid_dim (uvec3) + radius_sq
	params.encode_u32(32, grid_dim.x)
	params.encode_u32(36, grid_dim.y)
	params.encode_u32(40, grid_dim.z)
	params.encode_float(44, radius * radius)
	
	# Edge weights (Foundation 2.6 Multi-Modal)
	params.encode_float(48, Config.EDGE_WEIGHT_SPATIAL)
	params.encode_float(52, Config.EDGE_WEIGHT_NORMAL)
	params.encode_float(56, Config.EDGE_WEIGHT_COLOR)
	params.encode_float(60, Config.EDGE_WEIGHT_CURVATURE)
	params.encode_float(64, Config.EDGE_WEIGHT_HEIGHT)
	
	# Use runtime override if set, else config default
	var effective_threshold = edge_threshold_override if edge_threshold_override > 0 else Config.EDGE_THRESHOLD
	params.encode_float(68, effective_threshold)
	params.encode_float(72, Config.HEIGHT_EDGE_MIN)
	
	# use_normals flag
	var use_normals: int = 0
	if resource.normals.size() == point_count and _normals_buffer.is_valid():
		use_normals = 1
		print("SpatialGraph: Multi-modal edge segmentation enabled (normals + colors + curvature)")
	params.encode_u32(76, use_normals)
	
	# Struct ends at byte 80 (4-byte aligned on uint)
	
	# Create uniforms - Added colors buffer at binding 6
	var uniforms = [
		_create_uniform(0, _points_buffer),
		_create_uniform(1, grid_table_buffer),
		_create_uniform(2, sorted_indices_buffer),
		_create_uniform(3, _labels_buffer),
		_create_uniform(4, _changed_buffer),
		_create_uniform(5, _normals_buffer),
		_create_uniform(6, _colors_buffer),
		_create_uniform(7, _next_labels_buffer)
	]
	var sets: Array[RID] = [_rd.uniform_set_create(uniforms, _shader_rid, 0)]
	uniforms[3] = _create_uniform(3, _next_labels_buffer)
	uniforms[7] = _create_uniform(7, _labels_buffer)
	sets.append(_rd.uniform_set_create(uniforms, _shader_rid, 0))
	
	var groups = int(ceil(point_count / 256.0))
	
	# Iterative propagation
	while iterations < max_iterations:
		iterations += 1
		
		# Clear changed flag
		var zero_bytes = PackedByteArray()
		zero_bytes.resize(4)
		zero_bytes.encode_u32(0, 0)
		_rd.buffer_update(_changed_buffer, 0, 4, zero_bytes)
		
		# Dispatch shader
		var compute_list = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
		_rd.compute_list_bind_uniform_set(compute_list, sets[(iterations - 1) % 2], 0)
		_rd.compute_list_set_push_constant(compute_list, params, params.size())
		_rd.compute_list_dispatch(compute_list, groups, 1, 1)
		_rd.compute_list_end()
		
		# Sync and check convergence
		_rd.submit()
		_rd.sync()
		
		var changed_bytes = _rd.buffer_get_data(_changed_buffer)
		var changed = changed_bytes.decode_u32(0)
		
		var previous := _labels_buffer
		_labels_buffer = _next_labels_buffer
		_next_labels_buffer = previous
		if changed == 0:
			converged = true
			print("SpatialGraph: Converged after %d iterations" % iterations)
			break
	
	if iterations >= max_iterations:
		push_warning("SpatialGraph: Hit max iterations (%d) - may not be fully converged" % max_iterations)
	
	for set_rid in sets: _rd.free_rid(set_rid)
	return iterations if converged else -iterations

func _read_labels(point_count: int) -> PackedInt32Array:
	var bytes = _rd.buffer_get_data(_labels_buffer)
	return bytes.to_int32_array()

func _compact_labels(labels: PackedInt32Array, point_count: int) -> Dictionary:
	# Count points per label and remap to contiguous IDs
	var label_counts: Dictionary = {}  # raw_label -> count
	
	for i in range(point_count):
		var lbl = labels[i]
		if lbl in label_counts:
			label_counts[lbl] += 1
		else:
			label_counts[lbl] = 1
	
	# Filter by min cluster size and create remap
	var min_cluster = Config.GRAPH_MIN_CLUSTER_SIZE
	var remap: Dictionary = {}  # raw_label -> new_segment_id
	var next_id = 1
	
	for lbl in label_counts:
		if label_counts[lbl] >= min_cluster:
			remap[lbl] = next_id
			next_id += 1
		else:
			remap[lbl] = 0  # Noise
	
	# Apply remap
	var segments = PackedInt32Array()
	segments.resize(point_count)
	for i in range(point_count):
		segments[i] = remap[labels[i]]
	
	return {
		"segments": segments,
		"segment_count": next_id - 1
	}

func _create_uniform(binding: int, buffer_rid: RID) -> RDUniform:
	var u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buffer_rid)
	return u

func _cleanup() -> void:
	if _next_labels_buffer.is_valid():
		_rd.free_rid(_next_labels_buffer)
		_next_labels_buffer = RID()
	if _labels_buffer.is_valid():
		_rd.free_rid(_labels_buffer)
	if _changed_buffer.is_valid():
		_rd.free_rid(_changed_buffer)
	if _points_buffer.is_valid():
		_rd.free_rid(_points_buffer)
	if _normals_buffer.is_valid():
		_rd.free_rid(_normals_buffer)
	if _colors_buffer.is_valid():
		_rd.free_rid(_colors_buffer)
	if _pipeline_rid.is_valid():
		_rd.free_rid(_pipeline_rid)
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)

# ═══════════════════════════════════════════════════════════════════════════
# SEGMENT METADATA COMPUTATION (Foundation 2)
# ═══════════════════════════════════════════════════════════════════════════

## Post-processing: Merge small segments into nearest neighbors
## This consolidates over-segmented fragments into coherent objects
func _merge_small_segments(resource: PointCloudResource) -> int:
	var owned_points := resource.points
	var minimum := Config.GRAPH_MIN_CLUSTER_SIZE * 2
	var counts: Dictionary = {}
	for segment in resource.segments: counts[segment] = counts.get(segment, 0) + 1
	var index: SpatialIndex = resource.metadata.get("spatial_index")
	if not index: return 0
	var radius := Config.GRAPH_CONNECTIVITY_RADIUS
	var targets: Dictionary = {}
	var distances: Dictionary = {}
	for i in range(resource.point_count):
		var segment := resource.segments[i]
		if segment <= 0 or counts[segment] >= minimum: continue
		for neighbor in index.get_neighbors_radius(owned_points[i], radius):
			var other := resource.segments[neighbor]
			if other == segment or other <= 0 or counts[other] < minimum: continue
			var distance := owned_points[i].distance_squared_to(owned_points[neighbor])
			if distance < distances.get(segment, INF):
				distances[segment] = distance
				targets[segment] = other
	for i in range(resource.point_count):
		if targets.has(resource.segments[i]): resource.segments[i] = targets[resource.segments[i]]
	return targets.size()

## Compute metadata (centroid, bbox, average_normal) for each segment
## Called after segmentation to build node attributes for scene graph
func _compute_segment_metadata(resource: PointCloudResource) -> void:
	print("SpatialGraph: Computing segment metadata...")
	
	var points = resource.points
	var segments = resource.segments
	var normals = resource.normals
	var point_count = resource.point_count
	var has_normals = normals.size() == point_count
	
	# Create SegmentData for each unique segment ID
	var segment_map: Dictionary = {}  # segment_id -> SegmentData
	
	for i in range(point_count):
		var seg_id = segments[i]
		if seg_id <= 0:
			continue  # Skip noise points
		
		# Create SegmentData if not exists
		if not seg_id in segment_map:
			var seg_data = SegmentData.new()
			seg_data.segment_id = seg_id
			segment_map[seg_id] = seg_data
		
		# Add point (with normal if available)
		if has_normals:
			segment_map[seg_id].add_point_with_normal(points[i], normals[i])
		else:
			segment_map[seg_id].add_point(points[i])
	
	# Finalize all segments (compute centroid/bbox/avg_normal)
	for seg_id in segment_map:
		segment_map[seg_id].finalize()
	
	# Store in resource
	resource.segments_metadata = segment_map
	
	# Infer semantic labels (floor, person, object)
	_infer_semantics(resource)
	
	print("SpatialGraph: Computed metadata for %d segments" % segment_map.size())

## Infer semantic labels for segments using geometric heuristics
## Classifies segments as: "floor", "person", "wall", "object"
func _infer_semantics(resource: PointCloudResource) -> void:
	for segment in resource.segments_metadata.values():
		segment.semantic_label = "unknown"
		segment.confidence = 0.0
		segment.evidence = {"source": "geometry_heuristic", "calibrated_probability": false, "normal_observations": segment.normal_count}
		if segment.normal_count == 0: continue
		var alignment: float = absf(segment.average_normal.y)
		if alignment > 0.8: segment.semantic_label = "horizontal_surface_candidate"
		elif alignment < 0.3: segment.semantic_label = "vertical_surface_candidate"
		segment.evidence["absolute_up_alignment"] = alignment

## Infer spatial relationships between segments
## Called after metadata computation to build edges for scene graph
func _infer_relationships(resource: PointCloudResource) -> void:
	if resource.segments_metadata.is_empty():
		print("SpatialGraph: No segments to infer relationships from")
		return
	
	print("SpatialGraph: Inferring spatial relationships...")
	
	# Use static inference method from SpatialRelationship class
	var relationships = SpatialRelationship.infer_all(resource.segments_metadata)
	
	# Store in resource
	resource.relationships = relationships
	
	print("SpatialGraph: Found %d relationships" % relationships.size())

# ═══════════════════════════════════════════════════════════════════════════
# COLOR-BASED CLUSTERING (K-Means on RGB)
# ═══════════════════════════════════════════════════════════════════════════

## Segment by color similarity using K-means clustering
## Groups points with similar colors together
func compute_color_clustering(resource: PointCloudResource) -> Dictionary:
	print("SpatialGraph: Starting color-based clustering (K-means)...")
	var start_time = Time.get_ticks_msec()
	
	var point_count = resource.point_count
	var k = mini(Config.COLOR_CLUSTER_K, point_count)
	if k == 0: return {"status": "failed", "error": "empty_cloud"}
	var max_iter = Config.COLOR_CLUSTER_MAX_ITER
	
	if resource.colors.size() != point_count:
		printerr("SpatialGraph: No color data available for color clustering!")
		return { "status": "failed", "error": "no_colors" }
	
	# Initialize K centroids randomly (sample from existing colors)
	var centroids: Array[Color] = []
	var step = int(point_count / k)
	for i in range(k):
		centroids.append(resource.colors[i * step])
	
	# K-means iteration
	var labels = PackedInt32Array()
	labels.resize(point_count)
	
	for iteration in range(max_iter):
		var changed = false
		
		# Assignment step: Assign each point to nearest centroid
		for i in range(point_count):
			var color = resource.colors[i]
			var min_dist = INF
			var best_label = 0
			
			for c_idx in range(k):
				var centroid = centroids[c_idx]
				var dist = _color_distance_sq(color, centroid)
				if dist < min_dist:
					min_dist = dist
					best_label = c_idx + 1  # 1-indexed labels
			
			if labels[i] != best_label:
				labels[i] = best_label
				changed = true
		
		if not changed:
			print("SpatialGraph: K-means converged after %d iterations" % (iteration + 1))
			break
		
		# Update step: Recalculate centroids
		var sums: Array[Vector3] = []
		var counts: Array[int] = []
		for c_idx in range(k):
			sums.append(Vector3.ZERO)
			counts.append(0)
		
		for i in range(point_count):
			var lbl = labels[i] - 1  # 0-indexed for array
			if lbl >= 0 and lbl < k:
				var c = resource.colors[i]
				sums[lbl] += Vector3(c.r, c.g, c.b)
				counts[lbl] += 1
		
		for c_idx in range(k):
			if counts[c_idx] > 0:
				var avg = sums[c_idx] / counts[c_idx]
				centroids[c_idx] = Color(avg.x, avg.y, avg.z)
	
	# Update resource
	resource.segments = labels
	resource.segment_count = k
	resource.metadata["graph_built"] = true
	
	# Compute segment metadata and relationships
	_compute_segment_metadata(resource)
	_infer_relationships(resource)
	
	var duration = Time.get_ticks_msec() - start_time
	print("SpatialGraph: Color clustering complete. %d clusters in %.2f s" % [k, duration / 1000.0])
	
	return {
		"segment_count": k,
		"processing_time": duration / 1000.0
	}

func _color_distance_sq(a: Color, b: Color) -> float:
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return dr*dr + dg*dg + db*db

# ═══════════════════════════════════════════════════════════════════════════
# DEPTH DISCONTINUITY (Edge Detection)
# ═══════════════════════════════════════════════════════════════════════════

## Detect edges based on depth/distance discontinuities
## Points on edges (depth jumps) are labeled differently
## NOTE: Uses sampling for large datasets to stay responsive
func compute_depth_edges(resource: PointCloudResource) -> Dictionary:
	print("SpatialGraph: Starting depth edge detection...")
	var start_time = Time.get_ticks_msec()
	
	if not "spatial_index" in resource.metadata:
		printerr("SpatialGraph: Missing Spatial Index for edge detection!")
		return { "status": "failed", "error": "missing_index" }
	
	var index: SpatialIndex = resource.metadata["spatial_index"]
	var point_count = resource.point_count
	var points = resource.points
	var threshold = Config.DEPTH_EDGE_THRESHOLD
	
	# Ensure CPU sync for neighbor queries
	index.ensure_cpu_sync()
	
	var labels = PackedInt32Array()
	labels.resize(point_count)
	labels.fill(1)  # Default: interior (1)
	
	var edge_count = 0
	var sample_radius = 0.1  # Query radius for neighbors
	
	# SAMPLING: For large datasets, only process a subset
	var max_checks = 20000  # Max points to analyze
	var stride = max(1, int(point_count / max_checks))
	var checked = 0
	
	print("SpatialGraph: Depth edges - analyzing 1/%d points (stride)" % stride)
	
	# Check sampled points for depth discontinuity
	for i in range(0, point_count, stride):
		var pos = points[i]
		var neighbors = index.get_neighbors_radius(pos, sample_radius)
		
		if neighbors.size() < 3:
			labels[i] = 2  # Edge (sparse region)
			edge_count += 1
			continue
		
		# Calculate local depth variance
		var depths = PackedFloat32Array()
		for n_idx in neighbors:
			if n_idx != i and n_idx >= 0 and n_idx < point_count:
				depths.append(points[n_idx].y)  # Use Y as "depth" proxy
		
		if depths.size() > 2:
			var mean = 0.0
			for d in depths:
				mean += d
			mean /= depths.size()
			
			var variance = 0.0
			for d in depths:
				variance += (d - mean) * (d - mean)
			variance /= depths.size()
			
			# High variance = edge
			if sqrt(variance) > threshold:
				labels[i] = 2  # Edge
				edge_count += 1
		
		checked += 1
	
	# Update resource
	resource.segments = labels
	resource.segment_count = 2  # Interior (1) and Edge (2)
	resource.metadata["graph_built"] = true
	
	# Compute segment metadata and relationships
	_compute_segment_metadata(resource)
	_infer_relationships(resource)
	
	var duration = Time.get_ticks_msec() - start_time
	print("SpatialGraph: Edge detection complete. %d edge points found (checked %d) in %.2f s" % [edge_count, checked, duration / 1000.0])
	
	return {
		"segment_count": 2,
		"processing_time": duration / 1000.0,
		"edge_count": edge_count
	}
# ═══════════════════════════════════════════════════════════════════════════
# GEOMETRIC INTELLIGENCE (Covariance Analysis)
# ═══════════════════════════════════════════════════════════════════════════

## Compute geometric features (Normals, Curvature) using GPU Covariance Analysis
## @param resource: PointCloudResource with spatial_index in metadata
func compute_geometric_features(resource: PointCloudResource) -> void:
	var owned_points := resource.points
	print("SpatialGraph: Starting Geometric Analysis (Normals + Curvature)...")
	var start_time = Time.get_ticks_msec()
	
	if not "spatial_index" in resource.metadata:
		printerr("SpatialGraph: Missing Spatial Index for geometric analysis!")
		return
	
	var index: SpatialIndex = resource.metadata["spatial_index"]
	var point_count = resource.point_count
	
	# Reuse RD from index
	_rd = index._rd
	
	# Compile Shader
	var shader_file = load(GEOMETRIC_SHADER_PATH)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	var shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	var pipeline_rid = _rd.compute_pipeline_create(shader_rid)
	
	# Prepare Buffers
	# 1. Input Points - Convert to vec4 format
	var points_bytes = PackedByteArray()
	points_bytes.resize(point_count * 16)
	for i in range(point_count):
		var p = owned_points[i]
		points_bytes.encode_float(i * 16, p.x)
		points_bytes.encode_float(i * 16 + 4, p.y)
		points_bytes.encode_float(i * 16 + 8, p.z)
		points_bytes.encode_float(i * 16 + 12, 0.0)
	var input_buffer = _rd.storage_buffer_create(points_bytes.size(), points_bytes)
	
	# 2. Output Normals (vec4: nx, ny, nz, curvature)
	var output_bytes = PackedByteArray()
	output_bytes.resize(point_count * 16)
	var output_buffer = _rd.storage_buffer_create(output_bytes.size(), output_bytes)
	
	# 3. Uniform Set
	var uniforms = [
		_create_uniform(0, input_buffer),
		_create_uniform(1, index._grid_table_buffer),
		_create_uniform(2, index._sorted_indices_buffer),
		_create_uniform(3, output_buffer)
	]
	var uniform_set = _rd.uniform_set_create(uniforms, shader_rid, 0)
	
	# 4. Push Constants - Same layout as graph_segmentation (64 bytes)
	var radius = 0.1 # 10cm radius for geometric features (capture reliable surfaces)
	if Config.GRAPH_AUTO_RADIUS:
		var volume = resource.aabb.get_volume()
		radius = Config.calculate_auto_radius(point_count, volume) * 1.5 # Slightly larger for normals
	
	# Push constants must be exactly 48 bytes (matches geometric_analysis.glsl)
	var params = PackedByteArray()
	params.resize(48)  # Exactly 48 bytes as required by shader
	params.encode_float(0, index._bounds_min.x)
	params.encode_float(4, index._bounds_min.y)
	params.encode_float(8, index._bounds_min.z)
	params.encode_float(12, index._cell_size)
	params.encode_float(16, index._bounds_max.x)
	params.encode_float(20, index._bounds_max.y)
	params.encode_float(24, index._bounds_max.z)
	params.encode_u32(28, point_count)
	params.encode_u32(32, index._grid_dim.x)
	params.encode_u32(36, index._grid_dim.y)
	params.encode_u32(40, index._grid_dim.z)
	params.encode_float(44, radius * radius)
	# Struct ends at byte 48 (4-byte aligned on float)
	
	# Dispatch
	var groups = int(ceil(point_count / 256.0))
	var compute_list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, params, params.size())
	_rd.compute_list_dispatch(compute_list, groups, 1, 1)
	_rd.compute_list_end()
	
	_rd.submit()
	_rd.sync()
	
	# Retrieve Results
	var result_bytes = _rd.buffer_get_data(output_buffer)
	var normals = PackedVector3Array()
	var curvature = PackedFloat32Array()
	normals.resize(point_count)
	curvature.resize(point_count)
	
	for i in range(point_count):
		var nx = result_bytes.decode_float(i * 16)
		var ny = result_bytes.decode_float(i * 16 + 4)
		var nz = result_bytes.decode_float(i * 16 + 8)
		var c = result_bytes.decode_float(i * 16 + 12)
		
		normals[i] = Vector3(nx, ny, nz)
		curvature[i] = c
	
	# Store in resource
	resource.normals = normals
	resource.curvature = curvature
	
	# Cleanup local resources
	_rd.free_rid(uniform_set)
	_rd.free_rid(input_buffer)
	_rd.free_rid(output_buffer)
	_rd.free_rid(pipeline_rid)
	_rd.free_rid(shader_rid)
	
	var duration = Time.get_ticks_msec() - start_time
	print("SpatialGraph: Geometric Analysis Complete. Processed %d points in %.2f s" % [point_count, duration / 1000.0])
