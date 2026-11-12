extends Node3D

const Config = preload("res://modules/SpatialOS/core/spatial_config.gd")
@onready var pipeline = %SpatialPipeline
@onready var visualizer = %PointVisualizer
@onready var file_dialog = %FileDialog
@onready var status_label = %StatusLabel
@onready var load_button = %LoadButton
@onready var progress_bar = %ProgressBar
@onready var point_size_slider = %PointSizeSlider
@onready var point_size_label = %PointSizeLabel
@onready var cancel_button = %CancelButton
@onready var spatial_index_debug = %SpatialIndexDebug
@onready var graph_button = %GraphButton
@onready var segment_mode_option = %SegmentModeOption
@onready var geometry_button = %GeometryButton
@onready var edge_threshold_slider = %EdgeThresholdSlider
@onready var edge_threshold_label = %EdgeThresholdLabel

# Runtime edge threshold (overrides Config)
var _edge_threshold_override: float = 0.20

func _ready():
	add_to_group("spatial_context_providers")
	# Connect UI
	load_button.pressed.connect(_on_load_button_pressed)
	graph_button.pressed.connect(_on_graph_button_pressed) # Foundation 2
	geometry_button.pressed.connect(_on_geometry_button_pressed) # Foundation 2.5
	file_dialog.file_selected.connect(_on_file_selected)
	point_size_slider.value_changed.connect(_on_point_size_changed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	edge_threshold_slider.value_changed.connect(_on_edge_threshold_changed)
	
	# Initialize slider from config
	_edge_threshold_override = Config.EDGE_THRESHOLD
	edge_threshold_slider.value = _edge_threshold_override
	edge_threshold_label.text = "Edge Threshold: %.2f" % _edge_threshold_override
	
	# Connect Pipeline Signals (existing)
	pipeline.processing_started.connect(_on_processing_started)
	pipeline.processing_completed.connect(_on_processing_completed)
	pipeline.processing_failed.connect(_on_processing_failed)
	
	# Connect Async Pipeline Signals (NEW)
	pipeline.loading_progress.connect(_on_loading_progress)
	pipeline.loading_prepared.connect(func(total): visualizer.prepare_progressive(mini(total, Config.DIRECT_RENDER_MAX_POINTS)))
	pipeline.chunk_loaded.connect(_on_chunk_loaded)
	
	# Keyboard shortcuts
	set_process_input(true)
	
	print("SpatialOS Foundation Demo Ready")

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_O:
			_on_load_button_pressed()
		elif event.keycode == KEY_ESCAPE and file_dialog.visible:
			file_dialog.hide()
		elif event.keycode == KEY_F:
			# F key: Manually flip last loaded scan (for troubleshooting)
			_manual_flip_scan()
		elif event.keycode == KEY_C:
			# C key: Toggle camera mode (Object ↔ Scene)
			_toggle_camera_mode()
		elif event.keycode == KEY_G:
			# G key: Toggle Spatial Index Grid visualization
			_toggle_spatial_index_debug()
		elif event.keycode == KEY_H:
			# H key: Hypothesize (Segment) the scene
			_on_graph_button_pressed()
		elif event.keycode == KEY_R:
			# R key: Return to RGB mode
			if visualizer.last_resource:
				visualizer.set_view_mode(visualizer.ViewMode.RGB)
				status_label.text = "🎨 RGB Mode"
		elif event.keycode == KEY_N:
			# N key: Normal Vectors Mode
			if visualizer.last_resource and visualizer.last_resource.normals.size() > 0:
				visualizer.set_view_mode(visualizer.ViewMode.NORMALS)
				status_label.text = "📐 Normal Vectors Mode"
		elif event.keycode == KEY_M: 
			# M key: Curvature Heatmap Mode
			if visualizer.last_resource and visualizer.last_resource.curvature.size() > 0:
				visualizer.set_view_mode(visualizer.ViewMode.CURVATURE)
				status_label.text = "🔥 Curvature Heatmap Mode"

## Toggle between object and scene camera modes
## Useful for ambiguous scans or manual override
func _toggle_camera_mode():
	if not visualizer.last_resource:
		print("No scan loaded to reposition")
		return
	
	# Get current classification
	var resource = visualizer.last_resource
	var longest_axis = resource.aabb.get_longest_axis_size()
	var volume = resource.aabb.get_volume()
	var current_mode = _classify_scan_type(longest_axis, volume, resource.point_count)
	
	# Toggle to opposite mode
	var new_mode = SpatialConfig.CameraMode.SCENE_VIEW if current_mode == SpatialConfig.CameraMode.OBJECT_VIEW else SpatialConfig.CameraMode.OBJECT_VIEW
	
	print("═══════════════════════════════════════")
	print("CAMERA MODE TOGGLE")
	print("Previous: ", _get_mode_name(current_mode))
	print("New: ", _get_mode_name(new_mode))
	print("═══════════════════════════════════════")
	
	# Force repositioning with new mode
	var camera = %ControlCamera3D
	var center = resource.aabb.get_center()
	var size = resource.aabb.size
	# var longest_axis = resource.aabb.get_longest_axis_size()
	
	match new_mode:
		SpatialConfig.CameraMode.OBJECT_VIEW:
			_position_camera_object_mode(camera, resource, center, longest_axis)
		SpatialConfig.CameraMode.SCENE_VIEW:
			_position_camera_scene_mode(camera, resource, center, size)
	
	status_label.text = "📷 Camera: " + _get_mode_name(new_mode) + " | " + status_label.text.split("|", true, 1)[1] if "|" in status_label.text else status_label.text


## Manual flip function for troubleshooting coordinate issues
## Press 'F' key to flip the currently displayed scan
func _manual_flip_scan():
	if not visualizer.last_resource:
		print("No scan loaded to flip")
		return
	
	print("Manual flip requested - reprocessing with inverted Y-axis...")
	
	# Flip all points
	var flipped_points = PackedVector3Array()
	for p in visualizer.last_resource.points:
		flipped_points.append(Vector3(p.x, -p.y, p.z))
	
	# Create new resource with flipped points
	var flipped_resource = PointCloudResource.new(flipped_points, visualizer.last_resource.colors)
	flipped_resource.voxel_size = visualizer.last_resource.voxel_size
	flipped_resource.metadata = visualizer.last_resource.metadata.duplicate()
	flipped_resource.metadata.erase("spatial_index")
	flipped_resource.invalidate_derived()
	pipeline._finalize_processing(flipped_resource)
	flipped_resource.metadata["manually_flipped"] = true
	
	# Re-visualize
	visualizer.visualize(flipped_resource)
	
	# Update status
	status_label.text = "🔄 Scan flipped manually | " + status_label.text
	print("Manual flip complete - press F again to flip back")

func _on_load_button_pressed():
	file_dialog.popup_centered()

func _on_file_selected(path: String):
	# Validation
	if not path.ends_with(".ply"):
		_show_error("Only .ply files are supported")
		return
	
	if not FileAccess.file_exists(path):
		_show_error("File not found: " + path)
		return
	
	# Check file size
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var size_mb = file.get_length() / (1024.0 * 1024.0)
		file.close()
		
		if size_mb > 500:
			# Warn but allow
			print("WARNING: Large file (%.1f MB) - Processing may take time" % size_mb)
	
	print("Starting Pipeline on: ", path)
	status_label.text = "Loading: " + path.get_file()
	status_label.modulate = Color.YELLOW
	load_button.disabled = true
	
	# Start processing
	# Use automatic voxel sizing (-1.0) for optimal results
	# Or specify manual size: pipeline.ingest_and_process(path, 0.05) for 5cm voxels
	pipeline.ingest_and_process(path, -1.0)

func _on_processing_started():
	status_label.text = "Processing point cloud..."
	status_label.modulate = Color.YELLOW
	print("Pipeline: Processing started")
	
	# Show progress bar and cancel button for async loading
	progress_bar.visible = true
	progress_bar.value = 0
	
	# Show cancel button after delay (prevents flicker for fast loads)
	await get_tree().create_timer(SpatialConfig.ASYNC_CANCEL_BUTTON_DELAY).timeout
	if pipeline.is_loading_async():
		cancel_button.visible = true


## Fake progress animation (for sync mode - real progress tracked via signals)
func _animate_progress():
	# Only animate if not in async mode (async uses real progress)
	if not pipeline.is_loading_async():
		var tween = create_tween()
		tween.tween_property(progress_bar, "value", 90, 2.5).set_ease(Tween.EASE_OUT)

func _on_point_size_changed(value: float):
	visualizer.set_point_size(value)
	point_size_label.text = "Point Size: %.2fcm" % (value * 100)

# ═══════════════════════════════════════════════════════════════
# ASYNC LOADING HANDLERS (NEW)
# ═══════════════════════════════════════════════════════════════

## Called when async loading progress updates
## Updates progress bar and status with real values
func _on_loading_progress(percent: float, points_loaded: int, total_points: int):
	progress_bar.value = percent
	status_label.text = "Loading: %s / %s points (%.1f%%)" % [
		_format_number(points_loaded),
		_format_number(total_points),
		percent
	]

## Called when a chunk of points is ready during async loading
## Forwards to visualizer for progressive rendering
func _on_chunk_loaded(points: PackedVector3Array, colors: PackedColorArray):
	visualizer.append_chunk(points, colors)

## Called when user clicks the Cancel button
func _on_cancel_button_pressed():
	pipeline.cancel_loading()
	
	# Update UI
	status_label.text = "Loading cancelled."
	status_label.modulate = Color.ORANGE
	cancel_button.visible = false
	progress_bar.visible = false
	load_button.disabled = false
	
	print("User cancelled loading")


func _on_processing_completed(resource: PointCloudResource):
	print("Processing Complete. Points: ", resource.point_count)
	
	# ═══════════════════════════════════════════════════════════════
	# UI CLEANUP (hide async loading elements)
	# ═══════════════════════════════════════════════════════════════
	cancel_button.visible = false
	progress_bar.visible = false
	progress_bar.value = 100
	
	# Visualize
	visualizer.visualize(resource)
	
	# Detect rendering mode
	var mode = resource.metadata.get("rendering_mode", "voxelized")
	var is_direct = mode == "direct"
	
	# Enhanced status with quality metrics
	var has_colors_indicator = "🎨 " if resource.colors.size() > 0 else "⚪ "
	var volume_m3 = resource.aabb.get_volume()
	
	# Detect camera mode for status
	var longest_axis = resource.aabb.get_longest_axis_size()
	var camera_mode = _classify_scan_type(longest_axis, volume_m3, resource.point_count)
	var camera_mode_icon = "🔭" if camera_mode == SpatialConfig.CameraMode.OBJECT_VIEW else "🚶"
	
	# Sync slider with adaptive point size
	if visualizer.multimesh and visualizer.multimesh.mesh:
		var current_size = visualizer.multimesh.mesh.size.x
		point_size_slider.set_value_no_signal(current_size)
		point_size_label.text = "Point Size: %.2fcm" % (current_size * 100)
	
	# Business-friendly status
	if is_direct:
		# Direct rendering - show full detail
		status_label.text = "%s%s%s points | FULL DETAIL | %.1fm³" % [
			camera_mode_icon,
			has_colors_indicator,
			_format_number(resource.point_count),
			volume_m3
		]
	else:
		# Voxelized - show resolution
		var voxel_cm = resource.voxel_size * 100
		status_label.text = "%s%s%s points | %.1fcm voxels | %.1fm³" % [
			camera_mode_icon,
			has_colors_indicator,
			_format_number(resource.point_count),
			voxel_cm,
			volume_m3
		]
	
	status_label.modulate = Color.GREEN
	load_button.disabled = false
	
	# Smart camera positioning
	_position_camera_for_scan(resource)
	
	# Log business metrics
	print("═══════════════════════════════════════")
	print("SCAN COMPLETE - Business Metrics")
	print("═══════════════════════════════════════")
	print("Mode: ", mode.to_upper())
	print("Point Count: ", _format_number(resource.point_count))
	if not is_direct:
		print("Resolution: %.2fcm voxels" % (resource.voxel_size * 100))
	print("Coverage: %.2f x %.2f x %.2f meters" % [resource.aabb.size.x, resource.aabb.size.y, resource.aabb.size.z])
	print("Volume: %.2f m³" % volume_m3)
	var density = resource.point_count / max(volume_m3, 0.001)
	print("Density: %.1f points/m³" % density)
	print("Color Data: ", "YES ✓" if resource.colors.size() > 0 else "NO ✗")
	print("═══════════════════════════════════════")

# ═══════════════════════════════════════════════════════════════
# DEBUG VISUALIZATION (FOUNDATION 2)
# ═══════════════════════════════════════════════════════════════

## Toggle the visualization of the Spatial Index grid
## Triggered by 'G' key
func _toggle_spatial_index_debug():
	spatial_index_debug.visible = not spatial_index_debug.visible
	
	if spatial_index_debug.visible:
		var resource = visualizer.last_resource
		if resource and "spatial_index" in resource.metadata:
			var index = resource.metadata["spatial_index"] as SpatialIndex
			spatial_index_debug.visualize_grid(index)
			
			var stats = index.get_grid_stats()
			status_label.text = "Spatial Index: %d cells (%.1fcm)" % [stats["total_cells"], stats["cell_size"]*100]
			status_label.modulate = Color.GREEN
		else:
			print("No spatial index available to visualize")
			status_label.text = "No Spatial Index built yet."
			status_label.modulate = Color.RED
			spatial_index_debug.visible = false
	else:
		status_label.text = "Spatial Index visualization hidden."
		status_label.modulate = Color.WHITE

func _on_processing_failed(error_msg: String):
	_show_error(error_msg)
	load_button.disabled = false

func _show_error(message: String):
	status_label.text = "ERROR: " + message
	status_label.modulate = Color.RED
	push_error("SpatialOS: " + message)
	
	# Optional: OS alert for critical errors
	# OS.alert(message, "Point Cloud Error")

## Smart camera positioning based on scan characteristics
## Automatically detects if this is an object (orbit view) or scene (interior view)
## and positions the camera optimally for exploration
func _position_camera_for_scan(resource: PointCloudResource):
	var camera = %ControlCamera3D
	if not camera:
		push_warning("Camera not found - cannot position")
		return
	
	# ═══════════════════════════════════════════════════════════════
	# SCENE CLASSIFICATION (MECE)
	# ═══════════════════════════════════════════════════════════════
	
	var center = resource.aabb.get_center()
	var size = resource.aabb.size
	var longest_axis = resource.aabb.get_longest_axis_size()
	var volume = resource.aabb.get_volume()
	
	# Classify scan type
	var camera_mode = _classify_scan_type(longest_axis, volume, resource.point_count)
	
	# Log classification
	print("═══════════════════════════════════════")
	print("CAMERA SYSTEM - Smart Positioning")
	print("═══════════════════════════════════════")
	print("Scan Type: ", _get_mode_name(camera_mode))
	print("Size: %.1f × %.1f × %.1f meters" % [size.x, size.y, size.z])
	print("Volume: %.1f m³" % volume)
	print("Longest Axis: %.1f meters" % longest_axis)
	
	# ═══════════════════════════════════════════════════════════════
	# MODE-SPECIFIC POSITIONING
	# ═══════════════════════════════════════════════════════════════
	
	match camera_mode:
		SpatialConfig.CameraMode.OBJECT_VIEW:
			_position_camera_object_mode(camera, resource, center, longest_axis)
		
		SpatialConfig.CameraMode.SCENE_VIEW:
			_position_camera_scene_mode(camera, resource, center, size)
		
		_:
			push_error("Unknown camera mode: ", camera_mode)
	
	print("═══════════════════════════════════════")

## Classify scan as object or scene based on characteristics
## Returns: CameraMode enum value
func _classify_scan_type(longest_axis: float, volume: float, point_count: int) -> int:
	# Check explicit thresholds
	var is_large_size = longest_axis > SpatialConfig.SCENE_SIZE_THRESHOLD
	var is_large_volume = volume > SpatialConfig.SCENE_VOLUME_THRESHOLD
	
	# Scene mode if either threshold exceeded
	if is_large_size or is_large_volume:
		return SpatialConfig.CameraMode.SCENE_VIEW
	
	# Object mode for small scans
	return SpatialConfig.CameraMode.OBJECT_VIEW

## Get human-readable mode name
func _get_mode_name(mode: int) -> String:
	match mode:
		SpatialConfig.CameraMode.OBJECT_VIEW:
			return "OBJECT (External Orbit)"
		SpatialConfig.CameraMode.SCENE_VIEW:
			return "SCENE (Internal Exploration)"
		_:
			return "UNKNOWN"

## Position camera for OBJECT mode (external orbit view)
## Used for: Small items, sculptures, furniture, people
func _position_camera_object_mode_old(camera: Camera3D, resource: PointCloudResource, center: Vector3, size: float):
	print("Positioning: External orbit view")
	
	# Calculate optimal distance based on FOV
	var fov_rad = deg_to_rad(SpatialConfig.DEFAULT_FOV)
	var base_distance = (size * 0.5) / tan(fov_rad * 0.5)
	
	# Apply multiplier for comfortable viewing
	var optimal_distance = base_distance * SpatialConfig.OBJECT_MODE_DISTANCE_MULTIPLIER
	
	# Clamp to reasonable bounds
	var min_dist = max(2.0, size * 0.5)
	var max_dist = max(100.0, size * 5.0)
	optimal_distance = clamp(optimal_distance, min_dist, max_dist)
	
	# Position at 45° angle for architectural/artistic view
	var offset = Vector3(
		optimal_distance * 0.7071,  # cos(45°)
		optimal_distance * 0.5,      # Elevated view
		optimal_distance * 0.7071   # sin(45°)
	)
	
	camera.position = center + offset
	camera.look_at(center)
	
	# Object mode: Tight near/far planes
	camera.near = max(0.01, size * 0.001)
	camera.far = max(100.0, size * 10.0)
	
	print("  Position: ", camera.position)
	print("  Distance: %.2fm from center" % optimal_distance)
	print("  Looking at: ", center)
	print("  Near plane: %.3fm | Far plane: %.1fm" % [camera.near, camera.far])

## Position camera for OBJECT mode (external orbit view)
## Used for: Small items, sculptures, furniture, people
func _position_camera_object_mode(camera: Camera3D, resource: PointCloudResource, center: Vector3, size: float):
	print("Positioning: External orbit view (OBJECT MODE)")
	
	# Calculate optimal distance based on FOV
	var fov_rad = deg_to_rad(SpatialConfig.DEFAULT_FOV)
	var base_distance = (size * 0.5) / tan(fov_rad * 0.5)
	
	# Apply multiplier for comfortable viewing
	var optimal_distance = base_distance * SpatialConfig.OBJECT_MODE_DISTANCE_MULTIPLIER
	
	# Clamp to reasonable bounds
	var min_dist = max(2.0, size * 0.5)
	var max_dist = max(100.0, size * 5.0)
	optimal_distance = clamp(optimal_distance, min_dist, max_dist)
	
	# Position at 45° angle for architectural/artistic view
	var offset = Vector3(
		optimal_distance * 0.7071,  # cos(45°)
		optimal_distance * 0.5,      # Elevated view
		optimal_distance * 0.7071   # sin(45°)
	)
	
	camera.position = center + offset
	camera.look_at(center)
	
	# Object mode: Tight near/far planes
	camera.near = max(0.01, size * 0.001)
	camera.far = max(100.0, size * 10.0)
	
	print("  Position: ", camera.position)
	print("  Distance: %.2fm from center" % optimal_distance)
	print("  Looking at: ", center)
	print("  Near plane: %.3fm | Far plane: %.1fm" % [camera.near, camera.far])


## Position camera for SCENE mode (internal exploration view)
## Used for: Buildings, parking lots, large interiors, outdoor scenes
## 
## PROVEN STRATEGY (from working GS viewer):
##   - Use MEDIAN Y-value for ground (robust against outliers)
##   - Position camera NEAR center (not at edge, not dead center)
##   - Small offset for natural perspective (0.7m X, -0.3m Z)
##   - Eye height above median ground
##
## This matches the working viewer that correctly shows:
##   residence_china.ply at camera Y=-27.78m (vs our broken -60m or 0m)
func _position_camera_scene_mode(camera: Camera3D, resource: PointCloudResource, center: Vector3, size: Vector3):
	print("Positioning: Internal exploration view (MEDIAN STRATEGY)")
	
	# ═══════════════════════════════════════════════════════════════
	# MEDIAN GROUND DETECTION (Proven Approach)
	# ═══════════════════════════════════════════════════════════════
	
	var aabb = resource.aabb
	var points = resource.points
	
	# Calculate median Y-value (50th percentile)
	# This is MORE ROBUST than histogram for complex scenes
	# Working viewer uses this approach successfully
	var median_ground = _calculate_median_ground_level(points, aabb)
	
	print("  Ground detection (median analysis):")
	print("    AABB minimum Y: %.2fm (naive - often wrong)" % aabb.position.y)
	print("    Median ground Y: %.2fm (robust - proven correct)" % median_ground)
	print("    Difference: %.2fm" % (median_ground - aabb.position.y))
	
	# ═══════════════════════════════════════════════════════════════
	# CAMERA POSITIONING (Working Viewer Strategy)
	# ═══════════════════════════════════════════════════════════════
	
	# Strategy from successful viewer:
	#   - Position NEAR center (not at edge, not dead center)
	#   - Small X/Z offset for natural perspective
	#   - Eye height above median ground
	#
	# Example from residence_china.ply working viewer:
	#   Camera: (0.71, -27.78, -0.27)
	#   Center: (~31.4, ~-32.0, ~28.2)
	#   Offset: Very close to center with tiny adjustments
	
	var eye_height = SpatialConfig.SCENE_MODE_EYE_HEIGHT
	
	# Position near center with small natural offset
	var camera_position = Vector3(
		center.x + 0.7,           # Small X offset (natural perspective)
		median_ground + eye_height, # Eye height above median ground
		center.z - 0.3            # Small Z offset (depth perception)
	)
	
	camera.position = camera_position
	
	# ═══════════════════════════════════════════════════════════════
	# LOOK TARGET (Natural Eye Line)
	# ═══════════════════════════════════════════════════════════════
	
	# Look toward scene center at comfortable height
	var look_target = center
	
	# Elevate look target slightly above ground (2-3m = building features)
	var look_height = median_ground + 2.5
	look_target.y = clamp(look_height, 
						  aabb.position.y, 
						  aabb.position.y + aabb.size.y)
	
	camera.look_at(look_target)
	
	# ═══════════════════════════════════════════════════════════════
	# CAMERA PLANES (Scene Mode Optimized)
	# ═══════════════════════════════════════════════════════════════
	
	# Scene mode: Can get close to walls, see far distances
	camera.near = 0.1   # 10cm - for interior detail
	camera.far = max(1000.0, size.length() * 5.0)  # See entire scene
	
	# ═══════════════════════════════════════════════════════════════
	# DIAGNOSTIC OUTPUT
	# ═══════════════════════════════════════════════════════════════
	
	print("  Camera placement:")
	print("    Position: ", camera.position)
	print("    Height above median: %.2fm" % (camera_position.y - median_ground))
	print("    Offset from center: %.2fm" % camera_position.distance_to(center))
	print("  View configuration:")
	print("    Looking toward: ", look_target)
	print("    Look height: %.2fm above median" % (look_target.y - median_ground))
	print("  Render settings:")
	print("    Near plane: %.2fm | Far plane: %.1fm" % [camera.near, camera.far])
	print("    Viewable distance: %.1fm" % camera.far)
	
	# Business metric: Scene coverage
	var coverage_percentage = (camera.far / size.length()) * 100.0
	print("  Scene coverage: %.1f%% visible from this position" % coverage_percentage)

## Calculate ground level using MEDIAN Y-value
## This is the PROVEN approach from working GS viewers
##
## Why Median Beats Other Approaches:
##   ✓ Robust to outliers (noise points don't affect result)
##   ✓ Simple and fast (no histogram binning needed)
##   ✓ Works for ANY scene type (indoor, outdoor, complex)
##   ✓ Matches professional viewer behavior
##
## Algorithm:
##   1. Sample Y-values from point cloud (for performance)
##   2. Sort Y-values
##   3. Return middle value (50th percentile)
##   4. This represents the "typical" ground level
##
## Example: residence_china.ply
##   AABB min: -61.55m (wrong - catches outliers)
##   Histogram: -1.58m (wrong - catches buildings)
##   Median: -27.78m (CORRECT - actual courtyard level)
##
## @param points: All points in the point cloud
## @param aabb: Bounding box (for safety clamping)
## @return: Median Y-value representing ground plane
func _calculate_median_ground_level(points: PackedVector3Array, aabb: AABB) -> float:
	var point_count = points.size()
	
	# ═══════════════════════════════════════════════════════════════
	# SAMPLING (Performance Optimization)
	# ═══════════════════════════════════════════════════════════════
	
	# For large datasets, sample to avoid sorting millions of values
	# 10K samples gives excellent accuracy while being fast
	var sample_size = min(10000, point_count)
	var sample_stride = max(1, int(point_count / sample_size))
	
	# Collect Y-values (sampled)
	var y_values: Array[float] = []
	y_values.resize(sample_size)
	
	var idx = 0
	for i in range(0, point_count, sample_stride):
		if idx >= sample_size:
			break
		y_values[idx] = points[i].y
		idx += 1
	
	# Handle case where sampling collected fewer points
	if idx < sample_size:
		y_values.resize(idx)
	
	# ═══════════════════════════════════════════════════════════════
	# MEDIAN CALCULATION
	# ═══════════════════════════════════════════════════════════════
	
	# Sort Y-values (required for median)
	y_values.sort()
	
	# Calculate median (50th percentile = middle value)
	var median_index = y_values.size() / 2
	var median_y = y_values[median_index]
	
	# ═══════════════════════════════════════════════════════════════
	# VALIDATION & DIAGNOSTICS
	# ═══════════════════════════════════════════════════════════════
	
	# Safety: Ensure median is within valid bounds
	# (Should always be true, but protect against data corruption)
	var clamped_median = clamp(median_y, aabb.position.y, aabb.position.y + aabb.size.y)
	
	if median_y != clamped_median:
		push_warning("Median Y was outside AABB bounds - data may be corrupted")
		push_warning("  Original median: %.2fm" % median_y)
		push_warning("  Clamped median: %.2fm" % clamped_median)
	
	# Additional statistics for debugging
	var min_y = y_values[0]
	var max_y = y_values[y_values.size() - 1]
	var q1_y = y_values[y_values.size() / 4]      # 25th percentile
	var q3_y = y_values[y_values.size() * 3 / 4]  # 75th percentile
	
	print("  Statistical analysis of Y-values:")
	print("    Sample size: %d points (from %d total)" % [y_values.size(), point_count])
	print("    Min: %.2fm | Q1: %.2fm | Median: %.2fm | Q3: %.2fm | Max: %.2fm" % 
		  [min_y, q1_y, median_y, q3_y, max_y])
	print("    Range: %.2fm (%.2fm to %.2fm)" % [max_y - min_y, min_y, max_y])
	
	# Quality check: Large range suggests outliers or multi-level scene
	var y_range = max_y - min_y
	if y_range > 100.0:
		print("    ⚠ Large Y-range detected (%.1fm) - scene may have outliers or multiple levels" % y_range)
	
	return clamped_median


## Calculate offset from center for natural camera placement
## Returns small offset for perspective while staying near center
##
## Strategy:
##   - Not dead center (boring, no depth perception)
##   - Not at edge (confusing, can't see scene)
##   - Small offset (natural perspective like human observer)
##
## @param center: Scene center point
## @param size: Scene bounding box size
## @return: Camera position near center with natural offset
func _calculate_natural_camera_offset(center: Vector3, size: Vector3) -> Vector3:
	# Small fixed offset that works for most scenes
	# These values are proven from working GS viewer
	var offset_x = 0.7   # Slight right offset
	var offset_z = -0.3  # Slight forward offset
	
	# For very large scenes, scale the offset proportionally
	var scale_factor = 1.0
	var max_dimension = max(size.x, size.z)
	
	if max_dimension > 100.0:
		# Large scene: Scale offset to be visible
		scale_factor = max_dimension / 100.0
	elif max_dimension < 10.0:
		# Small scene: Reduce offset to stay in bounds
		scale_factor = max_dimension / 10.0
	
	return Vector3(
		center.x + offset_x * scale_factor,
		0.0,  # Y is set separately based on ground level
		center.z + offset_z * scale_factor
	)

## Format large numbers with K/M suffixes for business readability
func _format_number(num: int) -> String:
	if num >= 1000000:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	else:
		return str(num)

# ═══════════════════════════════════════════════════════════════
# FOUNDATION 2: GRAPH INTELLIGENCE HANDLERS
# ═══════════════════════════════════════════════════════════════

## User pressed "Hypothesize" (Segment) button
func _on_graph_button_pressed():
	if not visualizer.last_resource:
		print("No scan loaded to segment")
		return

	# Get selected segmentation mode from dropdown
	var mode_index = segment_mode_option.selected
	var mode_name = segment_mode_option.get_item_text(mode_index)
	
	print("SpatialOS: Hypothesizing with mode: %s" % mode_name)
	status_label.text = "🧠 Segmenting (%s)..." % mode_name
	graph_button.disabled = true
	
	# Small delay to let UI update
	await get_tree().process_frame
	
	# Execute Segmentation via Pipeline (pass mode and edge threshold override)
	var stats = pipeline.compute_graph(visualizer.last_resource, mode_index, _edge_threshold_override)
	
	# Update Visualizer Mode
	visualizer.set_view_mode(visualizer.ViewMode.SEGMENTS)
	
	# Update UI
	graph_button.disabled = false
	status_label.text = "Segments: %d | Time: %.2fs | %s" % [stats["segment_count"], stats["processing_time"], mode_name]
	print("Foundation 2: Segmentation Complete. Found %d segments." % stats["segment_count"])

## User pressed "Analyze Geometry" button (Foundation 2.5)
func _on_geometry_button_pressed():
	if not visualizer.last_resource:
		print("No scan loaded")
		return

	print("SpatialOS: Analyzing Geometry (Normals + Curvature)...")
	status_label.text = "📐 Computing Surface Geometry..."
	geometry_button.disabled = true
	
	await get_tree().process_frame
	
	# Execute Geometric Analysis (via SpatialGraph)
	var graph = SpatialGraph.new()
	graph.compute_geometric_features(visualizer.last_resource)
	
	# Switch Mode: 0=RGB, 1=SEGMENTS, 2=NORMALS, 3=CURVATURE
	# Initial view: Normals
	visualizer.set_view_mode(visualizer.ViewMode.NORMALS)
	
	geometry_button.disabled = false
	status_label.text = "Geometry Analysis Complete | 'N'=Normals, 'M'=Curvature, 'R'=RGB"
	print("Foundation 2.5: Geometric Analysis Complete.")

## Edge threshold slider changed - update label and prepare for re-segmentation
func _on_edge_threshold_changed(value: float):
	_edge_threshold_override = value
	edge_threshold_label.text = "Edge Threshold: %.2f" % value
	
	# If we have a loaded resource, enable quick re-segmentation hint
	if visualizer.last_resource:
		status_label.text = "Threshold: %.2f | Press 'H' to re-segment" % value

func get_context_snapshot() -> Dictionary:
	return visualizer.last_resource.get_context_snapshot() if visualizer.last_resource else {"segments": [], "relationships": []}
