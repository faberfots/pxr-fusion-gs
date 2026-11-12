## ═══════════════════════════════════════════════════════════════════════════
## POINT VISUALIZER - SpatialOS Point Cloud Visualization System
## ═══════════════════════════════════════════════════════════════════════════
## 
## PURPOSE:
##   Renders point cloud data using Godot's MultiMesh instancing system
##   Supports both voxelized and direct rendering modes with adaptive sizing
##
## FEATURES:
##   • MultiMesh instanced rendering for performance
##   • Adaptive point sizing based on scan characteristics
##   • True color support from point cloud data
##   • Fallback gradient coloring for scans without color data
##   • MultiMesh caching and reuse optimization
##   • Performance warnings for large datasets
##   • SSOT-compliant material loading
##
## USAGE:
##   visualizer.visualize(point_cloud_resource)
##
## GODOT VERSION: 4.5.1+
## ═══════════════════════════════════════════════════════════════════════════

extends MultiMeshInstance3D

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## SSOT: Load configuration constants
const Config = preload("res://modules/SpatialOS/core/spatial_config.gd")

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL STATE
# ═══════════════════════════════════════════════════════════════════════════

## Cached MultiMesh for reuse (performance optimization)
var _visual_generation := 0
var _color_generation := 0
var _populating := false
var _refresh_colors := false
signal visualization_completed

var cached_multimesh: MultiMesh = null

## Cached point count (for determining if reallocation is needed)
var cached_point_count: int = 0

## Last visualized resource (for reference)
var last_resource: PointCloudResource = null

# ═══════════════════════════════════════════════════════════════════════════
# PROGRESSIVE RENDERING STATE (NEW)
# ═══════════════════════════════════════════════════════════════════════════

## Points accumulated during progressive loading
var _progressive_points: PackedVector3Array = PackedVector3Array()

## Colors accumulated during progressive loading
var _progressive_colors: PackedColorArray = PackedColorArray()

## Whether we're in progressive loading mode
var _is_progressive: bool = false

## Current instance index for progressive updates
var _progressive_index: int = 0

# ═══════════════════════════════════════════════════════════════════════════
# VIEW MODES (FOUNDATION 2)
# ═══════════════════════════════════════════════════════════════════════════

enum ViewMode {
	RGB,        # Standard colors
	SEGMENTS,   # Graph segments (Random color per object)
	NORMALS,    # Surface orientation (XYZ -> RGB)
	CURVATURE   # Surface variation (Heatmap)
}

var current_view_mode: ViewMode = ViewMode.RGB
var _segment_palette: Dictionary = {} # Cache colors for consistent segment ID -> Color mapping

# ═══════════════════════════════════════════════════════════════════════════
# MAIN VISUALIZATION FUNCTION
# ═══════════════════════════════════════════════════════════════════════════

## Visualize a point cloud resource
## This is the main entry point for rendering point cloud data
## 
## @param resource: PointCloudResource containing points, colors, and metadata
func visualize(resource: PointCloudResource) -> void:
	_visual_generation += 1
	var generation := _visual_generation
	_is_progressive = false
	_progressive_points = PackedVector3Array()
	_progressive_colors = PackedColorArray()
	# ─────────────────────────────────────────────────────────────────────
	# VALIDATION & DIAGNOSTICS
	# ─────────────────────────────────────────────────────────────────────
	
	# Clear segment palette to prevent color collisions between runs
	_segment_palette.clear()
	
	# Detect rendering mode from metadata
	var mode = resource.metadata.get("rendering_mode", "voxelized")
	print("Visualizer: Received ", resource.point_count, " points (", mode, " mode)")
	
	# Validate point count
	if resource.point_count <= 0:
		printerr("Visualizer: No points to render.")
		return
	
	# Performance warning for very large datasets
	if resource.point_count > 5000000:
		push_warning("Visualizer: Rendering %d points may cause performance issues" % resource.point_count)
		print("Visualizer: Consider enabling LOD or downsampling for datasets >5M points")
	
	# Store reference for future use
	last_resource = resource
	
	# ─────────────────────────────────────────────────────────────────────
	# MULTIMESH ALLOCATION STRATEGY
	# ─────────────────────────────────────────────────────────────────────
	
	# Determine if we need to reallocate MultiMesh
	# Reuse existing MultiMesh if point count matches (common in iterative workflows)
	var needs_reallocation = (cached_multimesh == null or 
							  cached_point_count != resource.point_count)
	
	if needs_reallocation:
		print("Visualizer: Allocating MultiMesh for ", resource.point_count, " instances")
		
		# Clear old MultiMesh before creating new one (prevents memory leak)
		self.multimesh = null
		
		# Create new MultiMesh with proper configuration
		cached_multimesh = MultiMesh.new()
		cached_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		cached_multimesh.use_colors = true  # Enable per-instance coloring
		
		# ─────────────────────────────────────────────────────────────────
		# MESH CREATION WITH ADAPTIVE SIZING
		# ─────────────────────────────────────────────────────────────────
		
		var mesh_instance = BoxMesh.new()
		
		# Calculate optimal point size based on scan characteristics
		# Large scans need bigger points, dense scans need smaller points
		var scan_scale = resource.aabb.get_longest_axis_size()
		var point_size = _calculate_point_size(resource.point_count, scan_scale)
		
		mesh_instance.size = Vector3(point_size, point_size, point_size)
		print("Visualizer: Point size = %.3fm (scan scale: %.1fm)" % [point_size, scan_scale])
		
		# ─────────────────────────────────────────────────────────────────
		# MATERIAL LOADING (SSOT COMPLIANCE)
		# ─────────────────────────────────────────────────────────────────
		
		# SSOT: Load material from predefined resource ONLY
		# Never create materials in code - single source of truth is the .tres file
		var mat_path = Config.MATERIAL_PATH
		
		if not ResourceLoader.exists(mat_path):
			push_error("SSOT Violation: point_material.tres not found at: " + mat_path)
			push_error("Expected location: " + Config.VISUAL_SHADER_PATH)
			return  # Do not render with incorrect/missing material
		
		mesh_instance.material = load(mat_path)
		cached_multimesh.mesh = mesh_instance
		
		# ─────────────────────────────────────────────────────────────────
		# MULTIMESH INSTANCE COUNT
		# ─────────────────────────────────────────────────────────────────
		
		# CRITICAL: Set instance count BEFORE setting transforms
		# This allocates GPU memory for all instances
		cached_multimesh.instance_count = resource.point_count
		cached_point_count = resource.point_count
		
		# Assign to self so the engine knows about it
		self.multimesh = cached_multimesh
		
		# ─────────────────────────────────────────────────────────────────
		# ALLOCATION VERIFICATION
		# ─────────────────────────────────────────────────────────────────
		
		# Safety Check: Did Godot successfully allocate?
		if self.multimesh.instance_count != resource.point_count:
			printerr("Visualizer: Allocation failed. Requested: ", resource.point_count, 
					 " Allocated: ", self.multimesh.instance_count)
			printerr("Possible causes: Out of VRAM, driver limit, or system memory")
			return
		
		print("Visualizer: MultiMesh allocated successfully")
	else:
		print("Visualizer: Reusing existing MultiMesh (same point count)")
	
	# ─────────────────────────────────────────────────────────────────────
	# TRANSFORM & COLOR ASSIGNMENT
	# ─────────────────────────────────────────────────────────────────────
	
	print("Visualizer: Building scene with transforms and colors...")
	
	# Check if we have matching color data
	var positions: PackedVector3Array = resource.points
	var has_color_data = (resource.colors.size() == resource.point_count)
	
	if not has_color_data and resource.colors.size() > 0:
		push_warning("Visualizer: Color array size mismatch. Points: %d, Colors: %d" % 
					 [resource.point_count, resource.colors.size()])
	
	# Batch update all instances
	_populating = true
	for i in range(resource.point_count):
		if i > 0 and i % 2048 == 0:
			await get_tree().process_frame
			if generation != _visual_generation or not is_inside_tree(): return
		# ─────────────────────────────────────────────────────────────────
		# POSITION (TRANSFORM)
		# ─────────────────────────────────────────────────────────────────
		
		var point_position = positions[i]
		var transform = Transform3D(Basis(), point_position)
		
		# Safety: Validate data integrity
		# Invalid data (NaN/Inf) can cause rendering artifacts or crashes
		if not transform.origin.is_finite():
			push_warning("Visualizer: Invalid point at index ", i, " - replacing with origin")
			transform.origin = Vector3.ZERO
		
		cached_multimesh.set_instance_transform(i, transform)
		

		# ─────────────────────────────────────────────────────────────────
		# COLOR
		# ─────────────────────────────────────────────────────────────────
		
		var color: Color = Color.WHITE
		
		match current_view_mode:
			ViewMode.RGB:
				if has_color_data:
					color = resource.colors[i]
				else:
					var height_factor = _calculate_height_factor(point_position, resource.aabb)
					color = _generate_gradient_color(height_factor)
			
			ViewMode.SEGMENTS:
				var seg_id = resource.segments[i] if resource.segments.size() > i else 0
				if seg_id <= 0:
					color = Color(0.1, 0.1, 0.1) # Noise
				else:
					if not seg_id in _segment_palette:
						var hue = fmod(seg_id * 0.618033988749895, 1.0)
						_segment_palette[seg_id] = Color.from_hsv(hue, 0.8, 0.9)
					color = _segment_palette[seg_id]
			
			ViewMode.NORMALS:
				if resource.normals.size() > i:
					var n = resource.normals[i]
					# Map from [-1, 1] to [0, 1] for RGB
					color = Color((n.x + 1.0) * 0.5, (n.y + 1.0) * 0.5, (n.z + 1.0) * 0.5)
				else:
					color = Color.GRAY
			
			ViewMode.CURVATURE:
				if resource.curvature.size() > i:
					var c = resource.curvature[i]
					# Heatmap: Blue (flat) -> Red (edge), scaled by 5x for visibility
					color = Color.from_hsv((1.0 - clamp(c * 5.0, 0.0, 1.0)) * 0.66, 0.9, 0.9)
				else:
					color = Color.GRAY
		
		cached_multimesh.set_instance_color(i, color)
	
	# ─────────────────────────────────────────────────────────────────────
	# COMPLETION
	# ─────────────────────────────────────────────────────────────────────
	
	_populating = false
	visualization_completed.emit()
	if _refresh_colors:
		_refresh_colors = false
		_update_colors_only.call_deferred()
	print("Visualizer: Render complete (%d instances, %s mode)" % 
		  [resource.point_count, "SEGMENT" if current_view_mode == ViewMode.SEGMENTS else "RGB"])

## Change view mode and refresh colors immediately
func set_view_mode(mode: ViewMode) -> void:
	if current_view_mode == mode:
		return
		
	current_view_mode = mode
	if last_resource:
		if _populating: _refresh_colors = true
		else: _update_colors_only()

## Optimized update of colors only (skips transforms)
func _update_colors_only() -> void:
	_color_generation += 1
	var generation := _color_generation
	var geometry_generation := _visual_generation
	if not last_resource or not cached_multimesh:
		return
		
	print("Visualizer: Updating colors for %s mode..." % ("SEGMENT" if current_view_mode == ViewMode.SEGMENTS else "RGB"))
	var resource = last_resource
	var positions: PackedVector3Array = resource.points
	var has_color_data = (resource.colors.size() == resource.point_count)
	var has_segments = (resource.segments.size() == resource.point_count)
	var has_normals = (resource.normals.size() == resource.point_count)
	var has_curvature = (resource.curvature.size() == resource.point_count)
	
	if current_view_mode == ViewMode.SEGMENTS and not has_segments:
		push_warning("Visualizer: No segment data available.")
		return
	
	for i in range(resource.point_count):
		if i>0 and i%2048==0:
			await get_tree().process_frame
			if generation!=_color_generation or geometry_generation!=_visual_generation or not is_inside_tree(): return
		var color = Color.WHITE
		var point_position = positions[i]
		
		match current_view_mode:
			ViewMode.RGB:
				if has_color_data:
					color = resource.colors[i]
				else:
					var height_factor = _calculate_height_factor(point_position, resource.aabb)
					color = _generate_gradient_color(height_factor)
			
			ViewMode.SEGMENTS:
				var seg_id = resource.segments[i]
				if seg_id <= 0:
					color = Color(0.1, 0.1, 0.1)  # Noise: dark gray
				elif resource.segment_count == 2:
					# Special case: Depth Edges mode (2 segments = interior/edge)
					# Segment 1 = Interior (soft white)
					# Segment 2 = Edge (bright red for visibility)
					if seg_id == 1:
						color = Color(0.9, 0.9, 0.95)  # Soft white/blue
					else:
						color = Color(1.0, 0.2, 0.1)  # Bright red for edges
				else:
					# Standard palette for multi-segment modes
					if not seg_id in _segment_palette:
						var hue = fmod(seg_id * 0.618033988749895, 1.0)
						_segment_palette[seg_id] = Color.from_hsv(hue, 0.8, 0.9)
					color = _segment_palette[seg_id]
			
			ViewMode.NORMALS:
				if has_normals:
					var n = resource.normals[i]
					# Map from [-1, 1] to [0, 1] and RGB
					color = Color((n.x + 1.0) * 0.5, (n.y + 1.0) * 0.5, (n.z + 1.0) * 0.5)
				else:
					color = Color.GRAY
			
			ViewMode.CURVATURE:
				if has_curvature:
					var c = resource.curvature[i]
					# Heatmap: Blue (low curvature/flat) -> Red (high curvature/edge)
					color = Color.from_hsv((1.0 - clamp(c * 5.0, 0.0, 1.0)) * 0.66, 0.9, 0.9)
					# Scale c by 5.0 to visualize subtle curvature
				else:
					color = Color.GRAY
					
		cached_multimesh.set_instance_color(i, color)

## Dynamically update point size
## @param size: New size in meters
func set_point_size(size: float) -> void:
	if not cached_multimesh or not cached_multimesh.mesh:
		return
	
	if cached_multimesh.mesh is BoxMesh:
		# Update the mesh size directly - this updates all instances efficiently
		cached_multimesh.mesh.size = Vector3(size, size, size)


# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

## Calculate optimal point size based on scan characteristics
## 
## Strategy:
##   - Large architectural scans need bigger points to be visible
##   - Dense scans need smaller points to avoid overlap
##   - Very sparse scans need larger points for visibility
##
## @param point_count: Number of points in the scan
## @param scan_scale: Longest axis of the bounding box (meters)
## @return: Optimal point size in meters
func _calculate_point_size(point_count: int, scan_scale: float) -> float:
	# Base size: 0.1% of scan scale
	# This ensures points are proportional to the scene size
	var base_size = scan_scale / 1000.0
	
	# Adjust for point density
	if point_count > 5000000:
		# Very dense (>5M points) - use smaller points to reduce overlap
		base_size *= 0.5
	elif point_count > 1000000:
		# Dense (1-5M points) - slightly smaller points
		base_size *= 0.7
	elif point_count < 100000:
		# Medium sparse (<100K points) - slightly larger for visibility
		base_size *= 1.5
	elif point_count < 10000:
		# Very sparse (<10K points) - much larger for visibility
		base_size *= 2.5
	
	# Clamp to reasonable bounds
	# Min: 1cm (prevents invisible points)
	# Max: 50cm (prevents oversized points)
	return clamp(base_size, 0.01, 0.5)

## Calculate normalized height factor for gradient coloring
## Returns value between 0.0 (bottom) and 1.0 (top) of bounding box
##
## @param position: Point position in world space
## @param aabb: Bounding box of the entire point cloud
## @return: Normalized height factor [0.0 - 1.0]
func _calculate_height_factor(position: Vector3, aabb: AABB) -> float:
	# Handle edge case: zero-height AABB
	if aabb.size.y <= 0:
		return 0.5  # Middle gray
	
	# Normalize height within bounding box
	# 0.0 = bottom of AABB, 1.0 = top of AABB
	var height_factor = (position.y - aabb.position.y) / aabb.size.y
	
	# Clamp to valid range (handles floating point edge cases)
	return clamp(height_factor, 0.0, 1.0)

## Generate gradient color based on height
## Creates a visually pleasing blue-to-red gradient for depth perception
##
## Color scheme:
##   - Bottom (0.0): Cool blue (represents ground/foundation)
##   - Middle (0.5): Cyan/teal
##   - Top (1.0): Warm red (represents peaks/ceiling)
##
## @param height_factor: Normalized height [0.0 - 1.0]
## @return: Gradient color
func _generate_gradient_color(height_factor: float) -> Color:
	# Cool blue (bottom/ground)
	var color_low = Color(0.2, 0.6, 1.0, 1.0)
	
	# Warm red (top/peaks)
	var color_high = Color(1.0, 0.2, 0.2, 1.0)
	
	# Linear interpolation between colors
	return color_low.lerp(color_high, height_factor)

## Get the cached resource (for external reference)
## Useful for other systems that need access to the current point cloud
##
## @return: Last visualized PointCloudResource, or null if none
func get_cached_resource() -> PointCloudResource:
	return last_resource

## Clear the visualization and free resources
## Call this when switching point clouds or cleaning up
func clear_visualization() -> void:
	_visual_generation += 1
	_color_generation += 1
	_populating = false
	_refresh_colors = false
	print("Visualizer: Clearing visualization")
	
	# Clear MultiMesh reference
	self.multimesh = null
	cached_multimesh = null
	cached_point_count = 0
	last_resource = null
	
	# Clear progressive state
	_progressive_points = PackedVector3Array()
	_progressive_colors = PackedColorArray()
	_is_progressive = false
	_progressive_index = 0

# ═══════════════════════════════════════════════════════════════════════════
# PROGRESSIVE RENDERING METHODS (NEW)
# ═══════════════════════════════════════════════════════════════════════════

## Prepare for progressive loading
## Call this before streaming chunks to pre-allocate resources
## @param estimated_total: Estimated total point count (for pre-allocation)
## @param point_size: Optional point size override
func prepare_progressive(estimated_total: int, point_size: float = -1.0) -> void:
	print("Visualizer: Preparing for progressive rendering (%d estimated points)" % estimated_total)
	
	# Clear any existing visualization
	clear_visualization()
	
	# Enter progressive mode
	_is_progressive = true
	_progressive_index = 0
	
	# Pre-allocate arrays (reduces reallocation during streaming)
	_progressive_points = PackedVector3Array()
	_progressive_colors = PackedColorArray()
	
	# Create MultiMesh with estimated capacity
	cached_multimesh = MultiMesh.new()
	cached_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	cached_multimesh.use_colors = true
	
	# Create mesh instance with appropriate size
	var mesh_instance = BoxMesh.new()
	
	if point_size <= 0:
		# Use a reasonable default for unknown scans
		point_size = Config.DEFAULT_POINT_SIZE
	
	mesh_instance.size = Vector3(point_size, point_size, point_size)
	
	# Load material from SSOT path
	var mat_path = Config.MATERIAL_PATH
	if ResourceLoader.exists(mat_path):
		mesh_instance.material = load(mat_path)
	
	cached_multimesh.mesh = mesh_instance
	
	# Pre-allocate instance count (will be visible instantly as cubes appear)
	cached_multimesh.instance_count = estimated_total
	cached_point_count = estimated_total
	
	cached_multimesh.visible_instance_count = 0

	# Assign to scene
	self.multimesh = cached_multimesh
	
	print("Visualizer: Progressive rendering ready (pre-allocated %d instances)" % estimated_total)

## Append a chunk of points during progressive loading
## @param points: PackedVector3Array of new point positions
## @param colors: PackedColorArray of new point colors
func append_chunk(points: PackedVector3Array, colors: PackedColorArray) -> void:
	if not _is_progressive:
		return
	
	if not cached_multimesh:
		push_warning("Visualizer: append_chunk called but no MultiMesh prepared")
		return
	
	var chunk_size = mini(points.size(), cached_multimesh.instance_count - _progressive_index)
	
	# Update instances with chunk data
	for i in range(chunk_size):
		var idx = _progressive_index + i
		var pos = points[i]
		var color = colors[i] if i < colors.size() else Color.WHITE
		
		# Set actual position (makes point visible)
		cached_multimesh.set_instance_transform(idx, Transform3D(Basis(), pos))
		cached_multimesh.set_instance_color(idx, color)
	
	_progressive_index += chunk_size
	cached_multimesh.visible_instance_count = _progressive_index
	
	# Also accumulate for final resource creation
	_progressive_points.append_array(points)
	_progressive_colors.append_array(colors)

## Finalize progressive loading
## Trims unused capacity and creates the final resource
## @return: PointCloudResource with accumulated data
func finalize_progressive() -> PointCloudResource:
	if not _is_progressive:
		push_warning("Visualizer: finalize_progressive called but not in progressive mode")
		return null
	
	print("Visualizer: Finalizing progressive render (%d points)" % _progressive_index)
	
	# Trim MultiMesh to actual size
	if cached_multimesh and _progressive_index < cached_multimesh.instance_count:
		cached_multimesh.instance_count = _progressive_index
		cached_point_count = _progressive_index
	
	# Create resource from accumulated data
	var resource = PointCloudResource.new(_progressive_points, _progressive_colors)
	resource.metadata["rendering_mode"] = "progressive"
	resource.metadata["processed_date"] = Time.get_datetime_string_from_system()
	
	last_resource = resource
	
	# Exit progressive mode
	_is_progressive = false
	_progressive_points = PackedVector3Array()
	_progressive_colors = PackedColorArray()
	
	return resource

## Check if currently in progressive loading mode
func is_progressive_loading() -> bool:
	return _is_progressive

## Get current progressive point count
func get_progressive_count() -> int:
	return _progressive_index

## Get current visualization statistics
## Useful for debugging and performance monitoring
##
## @return: Dictionary with visualization stats
func get_visualization_stats() -> Dictionary:
	if not cached_multimesh or not last_resource:
		return {
			"active": false,
			"point_count": 0,
			"memory_estimate_mb": 0.0
		}
	
	# Estimate memory usage
	# Each instance: Transform3D (48 bytes) + Color (16 bytes) = 64 bytes
	var memory_mb = (cached_point_count * 64) / (1024.0 * 1024.0)
	
	return {
		"active": true,
		"point_count": cached_point_count,
		"has_colors": last_resource.colors.size() > 0,
		"memory_estimate_mb": memory_mb,
		"rendering_mode": last_resource.metadata.get("rendering_mode", "unknown"),
		"scan_volume_m3": last_resource.aabb.get_volume()
	}

# ═══════════════════════════════════════════════════════════════════════════
# LIFECYCLE HOOKS
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	print("Visualizer: Ready and awaiting point cloud data")

func _exit_tree() -> void:
	# Clean up on removal from scene tree
	clear_visualization()
	print("Visualizer: Cleaned up resources")

# ═══════════════════════════════════════════════════════════════════════════
# DEBUG & DIAGNOSTICS
# ═══════════════════════════════════════════════════════════════════════════

## Print detailed diagnostics about current visualization
## Useful for troubleshooting rendering issues
func print_diagnostics() -> void:
	print("═══════════════════════════════════════")
	print("VISUALIZER DIAGNOSTICS")
	print("═══════════════════════════════════════")
	
	if not last_resource:
		print("Status: No resource loaded")
		print("═══════════════════════════════════════")
		return
	
	var stats = get_visualization_stats()
	
	print("Status: Active")
	print("Point Count: ", stats["point_count"])
	print("Has Colors: ", stats["has_colors"])
	print("Rendering Mode: ", stats["rendering_mode"])
	print("Memory Estimate: %.2f MB" % stats["memory_estimate_mb"])
	print("Scan Volume: %.2f m³" % stats["scan_volume_m3"])
	print("AABB: ", last_resource.aabb)
	print("MultiMesh Valid: ", cached_multimesh != null)
	
	if cached_multimesh:
		print("Instance Count: ", cached_multimesh.instance_count)
		print("Transform Format: ", cached_multimesh.transform_format)
		print("Use Colors: ", cached_multimesh.use_colors)
	
	print("═══════════════════════════════════════")

# ═══════════════════════════════════════════════════════════════════════════
# END OF POINT VISUALIZER
# ═══════════════════════════════════════════════════════════════════════════
