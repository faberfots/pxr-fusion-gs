# res://modules/SpatialOS/core/spatial_config.gd
class_name SpatialConfig
extends Resource

## SpatialOS Configuration - SSOT for all constants
## This is the single source of truth for system-wide settings

# ═══════════════════════════════════════════════════════════════
# VOXELIZATION SETTINGS
# ═══════════════════════════════════════════════════════════════

## Default voxel size in meters (10cm)
const DEFAULT_VOXEL_SIZE: float = 0.1

## GPU grid size (2 million buckets)
const GRID_SIZE: int = 2000000

## GPU workgroup size (optimal for NVIDIA)
const WORKGROUP_SIZE: int = 256

## Bytes per VoxelCell struct (must match shader)
const VOXEL_CELL_SIZE: int = 48

# ═══════════════════════════════════════════════════════════════
# RENDERING SETTINGS
# ═══════════════════════════════════════════════════════════════

## Default point/cube size for visualization
const DEFAULT_POINT_SIZE: float = 0.05

## Maximum points per MultiMesh instance
const MAX_POINTS_PER_MESH: int = 1000000

## Use instanced rendering for performance
const USE_INSTANCED_RENDERING: bool = true

# ═══════════════════════════════════════════════════════════════
# CAMERA SETTINGS
# ═══════════════════════════════════════════════════════════════

## Default camera field of view
const DEFAULT_FOV: float = 75.0

## Minimum camera distance from target
const MIN_CAMERA_DISTANCE: float = 2.0

## Maximum camera distance from target
const MAX_CAMERA_DISTANCE: float = 500.0

## Camera positioning angle (degrees)
const CAMERA_ELEVATION_ANGLE: float = 30.0

# ═══════════════════════════════════════════════════════════════
# CAMERA MODE SETTINGS (MECE Classification)
# ═══════════════════════════════════════════════════════════════

## Camera viewing modes (mutually exclusive)
enum CameraMode {
	OBJECT_VIEW,    # External orbit - for small objects/items
	SCENE_VIEW,     # Internal exploration - for large scenes/buildings
	AUTO            # Automatically detect based on scan characteristics
}

## Default camera mode
const DEFAULT_CAMERA_MODE: int = CameraMode.AUTO

## Threshold: Size for auto-detection (meters)
## Scans with longest axis > this value use SCENE_VIEW
const SCENE_SIZE_THRESHOLD: float = 20.0

## Threshold: Volume for auto-detection (cubic meters)
## Scans with volume > this value use SCENE_VIEW
const SCENE_VOLUME_THRESHOLD: float = 100.0

## Ground plane detection: Percentile to use for ground level
## 0.15 = 15th percentile (empirically good for most scenes)
## Lower values (0.10) = more conservative (deeper ground)
## Higher values (0.25) = more aggressive (higher ground)
const GROUND_PLANE_PERCENTILE: float = 0.10  # Default: 0.15

## Ground plane detection: Sample size for large point clouds
## We sample this many points to calculate statistics (performance vs accuracy)
const GROUND_DETECTION_SAMPLE_SIZE: int = 50000

## Ground plane detection: Histogram bin size (meters)
## Smaller bins = more precision, but more noise
## Larger bins = smoother, but less precision
## 0.5m is empirically optimal for most scenes
const GROUND_HISTOGRAM_BIN_SIZE: float = 0.5

## Ground plane detection: Peak significance threshold
## Peak must contain at least this percentage of sampled points
## Lower = more sensitive (detects smaller peaks)
## Higher = more robust (ignores noise)
const GROUND_PEAK_THRESHOLD: float = 0.015  # 1.5%

## Ground plane detection: Peak region for refinement (bins)
## ±N bins around peak for center-of-mass calculation
## Larger = smoother but less accurate
const GROUND_REFINEMENT_REGION: int = 2  # ±1 meter

## Scene entry: Distance from edge as percentage (0.0 = edge, 0.5 = center)
## 0.25 = Quarter-distance from edge (good visibility, not too far in)
const SCENE_ENTRY_DISTANCE_FACTOR: float = 0.15  # Default: 0.25

## Look target: Height above ground to look at (meters)
## 2.5m = typical building features, trees, human activity level
const SCENE_LOOK_HEIGHT_ABOVE_GROUND: float = 5.0  # Default: 2.5

## Object mode: Camera distance multiplier
const OBJECT_MODE_DISTANCE_MULTIPLIER: float = 1.5

## Scene mode: Human eye height for first-person view (meters)
const SCENE_MODE_EYE_HEIGHT: float = 1.6

## Scene mode: Initial position as percentage from edge (0.0 = edge, 0.5 = center)
const SCENE_MODE_ENTRY_POSITION: float = 0.15  # 15% from edge

## Scene mode: Look toward center or interesting point
const SCENE_MODE_LOOK_AT_CENTER: bool = true

# ═══════════════════════════════════════════════════════════════
# PERFORMANCE SETTINGS
# ═══════════════════════════════════════════════════════════════

## Enable asynchronous file loading
const ASYNC_FILE_LOADING: bool = true

## Enable GPU compaction shader (Phase 3)
const USE_GPU_COMPACTION: bool = true

## LOD system enabled
const LOD_ENABLED: bool = false

## Enable direct point rendering (bypass voxelization)
## Use for large scans or when maximum detail is required
const USE_DIRECT_RENDERING: bool = true

## Direct rendering point limit (for performance)
## Points beyond this will be downsampled
const DIRECT_RENDER_MAX_POINTS: int = 10000000  # 10M points

## Threshold: Auto-enable direct rendering if scan exceeds this size
const AUTO_DIRECT_RENDER_THRESHOLD: int = 1000000  # 1M points

## LOD distance thresholds
const LOD_DISTANCES: Array[float] = [10.0, 50.0, 200.0, 1000.0]

# ═══════════════════════════════════════════════════════════════
# ASYNC LOADING SETTINGS
# ═══════════════════════════════════════════════════════════════

## Enable asynchronous loading (set to false to use legacy sync mode)
## When enabled, large files load in background with progress tracking
const USE_ASYNC_LOADING: bool = true

## Number of points per chunk for progressive rendering
## Smaller = more responsive UI updates, larger = less overhead
## Recommended: 50K-200K depending on target hardware
const ASYNC_CHUNK_SIZE: int = 100000  # 100K points per chunk

## Minimum file size (MB) to trigger async loading
## Files smaller than this load synchronously for speed
const ASYNC_MIN_FILE_SIZE_MB: float = 5.0

## Show cancel button after this delay (seconds)
## Prevents UI flicker for fast-loading files
const ASYNC_CANCEL_BUTTON_DELAY: float = 1.0

## Progress update frequency (every N points)
## Lower = smoother progress bar, higher = less overhead
const ASYNC_PROGRESS_UPDATE_INTERVAL: int = 10000  # Every 10K points

# ═══════════════════════════════════════════════════════════════
# SPATIAL INDEX SETTINGS (FOUNDATION 2)
# ═══════════════════════════════════════════════════════════════

## Grid cell size for spatial hashing (in meters)
## Smaller = more precise but more cells/memory. Larger = faster build but more points per cell.
## 0.2m (20cm) is good for indoor scenes/objects.
const INDEX_GRID_CELL_SIZE: float = 0.2

## Maximum grid dimension per axis (e.g. 256 -> 256x256x256 grid)
## Affects memory usage for the grid table. 256^3 = 16M cells = ~64MB buffer
const INDEX_MAX_GRID_DIM: int = 256

## Compute shader path
const SPATIAL_MAX_WORKGROUP_SIZE: int = 256
const SPATIAL_INDEX_SHADER_PATH: String = "res://modules/SpatialOS/shaders/spatial_index.glsl"

# ═══════════════════════════════════════════════════════════════
# GRAPH INTELLIGENCE SETTINGS (FOUNDATION 2)
# ═══════════════════════════════════════════════════════════════

## Connectivity Radius (in meters)
## Points closer than this distance are considered "connected" (Edge exists)
## Should be roughly 1.5x to 2x the average point spacing to ensure continuity
const GRAPH_CONNECTIVITY_RADIUS: float = 0.05  # 5cm connectivity

## Minimum Cluster Size (points)
## Segments with fewer points than this are considered "noise" and ignored/merged
const GRAPH_MIN_CLUSTER_SIZE: int = 50

## Minimum segment size for post-processing merge (points)
## Segments smaller than this get merged into their nearest neighbor
## This consolidates over-segmented fragments into coherent objects
const SEGMENT_MIN_MERGE_SIZE: int = 200

## Auto-calculate connectivity radius based on point density
## When true, overrides GRAPH_CONNECTIVITY_RADIUS with a calculated value
const GRAPH_AUTO_RADIUS: bool = true

## Segmentation modes available
enum SegmentationMode {
	CONNECTIVITY,    # Connected components (spatial)
	COLOR_CLUSTER,   # K-means clustering on RGB
	DEPTH_EDGES      # Depth discontinuity detection
}

## Default segmentation mode
const DEFAULT_SEGMENTATION_MODE: int = SegmentationMode.CONNECTIVITY

## Number of clusters for color-based segmentation
const COLOR_CLUSTER_K: int = 5

## K-means max iterations
const COLOR_CLUSTER_MAX_ITER: int = 20

## Depth edge threshold (normalized depth difference)
const DEPTH_EDGE_THRESHOLD: float = 0.15

# ═══════════════════════════════════════════════════════════════
# MULTI-MODAL EDGE SEGMENTATION (Foundation 2.6)
# ═══════════════════════════════════════════════════════════════
# Edge-aware region growing uses multiple features to detect object boundaries.
# Points are connected ONLY if their combined edge score is below threshold.

## Edge weight: Spatial distance contribution
## Higher = more emphasis on close proximity
const EDGE_WEIGHT_SPATIAL: float = 0.15

## Edge weight: Normal discontinuity contribution
## Higher = more emphasis on surface orientation changes
const EDGE_WEIGHT_NORMAL: float = 0.35

## Edge weight: Color difference contribution
## Higher = more emphasis on material/color boundaries
const EDGE_WEIGHT_COLOR: float = 0.2

## Edge weight: Curvature difference contribution
## Higher = more emphasis on shape changes (flat vs curved)
const EDGE_WEIGHT_CURVATURE: float = 0.1

## Edge weight: Height discontinuity contribution
## Higher = more emphasis on vertical separation (standing objects)
const EDGE_WEIGHT_HEIGHT: float = 0.2

## Edge score threshold for connectivity
## Lower = more segments (stricter boundaries)
## Higher = fewer segments (more connected)
## 0.20 targets ~20-30 segments for typical scenes
const EDGE_THRESHOLD: float = 0.20

## Minimum height difference to consider a vertical edge (meters)
const HEIGHT_EDGE_MIN: float = 0.03

## Calculate optimal connectivity radius for a point cloud
## Uses average point spacing × multiplier for robust connectivity
## @param point_count: Number of points in the cloud
## @param volume: Volume of the bounding box in m³
## @return: Optimal connectivity radius in meters
static func calculate_auto_radius(point_count: int, volume: float) -> float:
	# Estimate average point spacing from density
	# density = points/volume, spacing ≈ (volume/points)^(1/3)
	var density = float(point_count) / max(volume, 0.001)
	var avg_spacing = pow(1.0 / density, 1.0 / 3.0)
	
	# Multiplier: 1.2x spacing ensures connectivity without over-merging
	# Lower = faster but more fragments, Higher = slower but more connected
	var radius = avg_spacing * 1.2
	
	# Clamp to reasonable bounds
	# Min: 1cm (prevents micro-fragmentation)
	# Max: 50cm (prevents merging distant objects)
	radius = clamp(radius, 0.01, 0.5)
	
	return radius

# ═══════════════════════════════════════════════════════════════
# COORDINATE SYSTEM SETTINGS
# ═══════════════════════════════════════════════════════════════

## Auto-correct Gaussian Splatting coordinate systems
## GS files from COLMAP/Nerfstudio often use Y-down convention
## This flips them to Godot's Y-up convention
const AUTO_FLIP_GAUSSIAN_SPLATTING: bool = true

## Manual coordinate transform options (for non-GS files)
enum CoordinateSystem {
	GODOT_Y_UP,        # Default: Y-up (OpenGL/Godot convention)
	Y_DOWN,            # Flip Y-axis (computer vision convention)
	Z_UP,              # Rotate: Z-up to Y-up (CAD/GIS convention)
	CUSTOM             # User-defined transform
}


# ═══════════════════════════════════════════════════════════════
# FILE SYSTEM PATHS (SSOT)
# ═══════════════════════════════════════════════════════════════

## Base module path
const MODULE_PATH: String = "res://modules/SpatialOS/"

## Shader directory
const SHADER_PATH: String = MODULE_PATH + "shaders/"

## Compute shader path
const COMPUTE_SHADER_PATH: String = SHADER_PATH + "compute/"

## Visual shader path
const VISUAL_SHADER_PATH: String = SHADER_PATH + "visual/"

## Scene directory
const SCENE_PATH: String = MODULE_PATH + "scenes/"

## Core scripts directory
const CORE_PATH: String = MODULE_PATH + "core/"

# ═══════════════════════════════════════════════════════════════
# RESOURCE PATHS
# ═══════════════════════════════════════════════════════════════

## Point material resource
const MATERIAL_PATH: String = VISUAL_SHADER_PATH + "point_material.tres"

## Voxelizer compute shader
const VOXELIZER_SHADER: String = COMPUTE_SHADER_PATH + "voxelizer.glsl"

## Compactor compute shader (Phase 3)
const COMPACTOR_SHADER: String = COMPUTE_SHADER_PATH + "compactor.glsl"

# ═══════════════════════════════════════════════════════════════
# UI SETTINGS
# ═══════════════════════════════════════════════════════════════

## Status update interval in seconds
const STATUS_UPDATE_INTERVAL: float = 0.1

## Show detailed error dialogs
const SHOW_ERROR_DIALOGS: bool = true

## Enable keyboard shortcuts
const ENABLE_SHORTCUTS: bool = true

# ═══════════════════════════════════════════════════════════════
# FILE VALIDATION
# ═══════════════════════════════════════════════════════════════

## Supported file extensions
const SUPPORTED_EXTENSIONS: PackedStringArray = ["ply"]

## Maximum file size in MB (warning threshold)
const MAX_FILE_SIZE_MB: float = 500.0

## Require binary PLY format
const REQUIRE_BINARY_PLY: bool = true

# ═══════════════════════════════════════════════════════════════
# BUSINESS INTELLIGENCE
# ═══════════════════════════════════════════════════════════════

## Enable telemetry
const TELEMETRY_ENABLED: bool = false

## Export formats available
const EXPORT_FORMATS: PackedStringArray = ["csv", "json", "las"]

## Enable LLM query interface
const LLM_INTERFACE_ENABLED: bool = true

# ═══════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

static func get_shader_path(shader_name: String) -> String:
	"""Get full path to a compute shader"""
	return COMPUTE_SHADER_PATH + shader_name

static func validate_paths() -> bool:
	"""Validate all critical resources exist"""
	var missing: Array[String] = []
	
	if not DirAccess.dir_exists_absolute(MODULE_PATH):
		missing.append(MODULE_PATH)
	if not DirAccess.dir_exists_absolute(SHADER_PATH):
		missing.append(SHADER_PATH)
	if not FileAccess.file_exists(MATERIAL_PATH):
		missing.append(MATERIAL_PATH)
	
	if not missing.is_empty():
		push_error("SpatialConfig: Missing paths: " + str(missing))
		return false
	
	return true

static func get_version() -> String:
	"""Get module version"""
	return "1.0.0-alpha"

static func print_config():
	"""Debug print current configuration"""
	print("═══════════════════════════════════════")
	print("SpatialOS Configuration v" + get_version())
	print("═══════════════════════════════════════")
	print("Voxel Size: %.2fcm" % (DEFAULT_VOXEL_SIZE * 100))
	print("Grid Size: %d buckets" % GRID_SIZE)
	print("Max Points: %d" % MAX_POINTS_PER_MESH)
	print("GPU Compaction: %s" % ("ON" if USE_GPU_COMPACTION else "OFF"))
	print("LOD: %s" % ("ON" if LOD_ENABLED else "OFF"))
	print("Module Path: " + MODULE_PATH)
	print("═══════════════════════════════════════")

## Calculate smart ground level using statistical analysis of point distribution
## @param points: Point cloud data
## @param aabb: Axis-aligned bounding box of the cloud
## @return: Estimated ground level Y coordinate
static func calculate_smart_ground_level(points: PackedVector3Array, aabb: AABB) -> float:
	var point_count = points.size()
	
	# For very large datasets, sample to avoid performance hit
	var sample_size = min(SpatialConfig.GROUND_DETECTION_SAMPLE_SIZE, point_count)
	var sample_stride = max(1, int(point_count / sample_size))
	
	# Collect Y values (sampled)
	var y_values: Array[float] = []
	for i in range(0, point_count, sample_stride):
		y_values.append(points[i].y)
	
	# Sort Y values
	y_values.sort()
	
	# Calculate percentile (configurable via SSOT)
	var percentile_index = int(y_values.size() * SpatialConfig.GROUND_PLANE_PERCENTILE)
	var ground_level = y_values[percentile_index]
	
	# Safety: Ensure ground is within AABB bounds
	ground_level = clamp(ground_level, aabb.position.y, aabb.position.y + aabb.size.y)
	
	return ground_level

## Calculate smart entry point for scene exploration
## @param aabb: Scene bounding box
## @param center: Center of the scene
## @param ground_level: Estimated ground level
## @param size: Size of the scene
## @return: Optimal entry position for camera
static func calculate_smart_entry_point(aabb: AABB, center: Vector3, ground_level: float, size: Vector3) -> Vector3:
	var factor = SpatialConfig.SCENE_ENTRY_DISTANCE_FACTOR
	var eye_height = SpatialConfig.SCENE_MODE_EYE_HEIGHT
	
	# Find which horizontal dimension is larger
	var is_wider_in_x = size.x > size.z
	
	var entry_position: Vector3
	
	if is_wider_in_x:
		entry_position = Vector3(
			center.x + size.x * (factor - 0.5),  # Offset from center
			ground_level + eye_height,
			aabb.position.z + size.z * factor
		)
	else:
		entry_position = Vector3(
			aabb.position.x + size.x * factor,
			ground_level + eye_height,
			center.z + size.z * (factor - 0.5)
		)
	
	return entry_position

## Calculate smart look-at target for camera
## @param camera_pos: Current camera position
## @param center: Scene center
## @param ground_level: Estimated ground level
## @param aabb: Scene bounding box
## @return: Target position for camera to look at
static func calculate_look_target(camera_pos: Vector3, center: Vector3, ground_level: float, aabb: AABB) -> Vector3:
	var look_target = center
	
	# Elevate look target to comfortable eye line (SSOT)
	look_target.y = ground_level + SpatialConfig.SCENE_LOOK_HEIGHT_ABOVE_GROUND
	
	# Ensure target is within scene bounds
	look_target.y = clamp(look_target.y, 
						  aabb.position.y, 
						  aabb.position.y + aabb.size.y)
	
	# If camera and target are at similar heights, look slightly down
	if abs(look_target.y - camera_pos.y) < 0.5:
		look_target.y = camera_pos.y - 0.5
	
	return look_target
