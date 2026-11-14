# gs_constants.gd
# ════════════════════════════════════════════════════════════════════════════════
# SSOT CONSTANTS FOR GAUSSIAN SPLATTING SYSTEM
# ════════════════════════════════════════════════════════════════════════════════
# PURPOSE: Centralized, documented constants replacing all magic numbers.
# SSOT: This is THE single source of truth for all system-wide constants.
# LLM-READY: Every constant includes business context documentation.
# ════════════════════════════════════════════════════════════════════════════════
class_name GSConstants
extends RefCounted

# ════════════════════════════════════════════════════════════════════════════════
# HUMAN ERGONOMICS (Anthropometric Standards)
# ════════════════════════════════════════════════════════════════════════════════
## Standard human eye height in meters.
## Based on ISO 7250 anthropometric data (50th percentile standing height).
## Used for camera positioning in Environment Mode.
const STANDARD_EYE_HEIGHT_M: float = 1.7

## Minimum camera zoom/distance threshold to prevent orbital snapping.
## When camera controller has a "distance" property, we set it to this value
## to prevent the camera from snapping back to a previous orbit position.
const MIN_ZOOM_THRESHOLD_M: float = 0.1

## Environment size threshold in meters.
## Models larger than this are considered "environments" (camera goes inside).
## Models smaller than this are considered "objects" (camera orbits outside).
const ENVIRONMENT_SIZE_THRESHOLD_M: float = 10.0

# ════════════════════════════════════════════════════════════════════════════════
# PERFORMANCE TUNING
# ════════════════════════════════════════════════════════════════════════════════
## Number of histogram bins for Y-axis floor detection algorithm.
## Higher values = more precision, but more memory. 256 is optimal for most scenes.
const HISTOGRAM_BINS: int = 256

## Progress signal emission throttle.
## Only emit progress updates when delta exceeds this value (prevents spam).
## 0.01 = emit every 1% change.
const PROGRESS_EMIT_THRESHOLD: float = 0.01

## Default batch size for loading splats (number of splats per GPU upload batch).
## Larger = faster but more VRAM spikes. Smaller = smoother but slower.
const DEFAULT_LOADING_BATCH_SIZE: int = 131072

# ════════════════════════════════════════════════════════════════════════════════
# MEMORY THRESHOLDS
# ════════════════════════════════════════════════════════════════════════════════
## VRAM usage percentage at which to emit a warning signal.
## Allows UI to show "Low Memory" indicator before problems occur.
const MEMORY_WARNING_THRESHOLD: float = 0.80

## VRAM usage percentage at which to trigger auto-downgrade or refuse new loads.
## This is the "red zone" - system should take protective action.
const MEMORY_CRITICAL_THRESHOLD: float = 0.90

## Bytes per splat in GPU memory (240 bytes per splat struct).
## Used for VRAM estimation before loading.
const BYTES_PER_SPLAT: int = 240

# ════════════════════════════════════════════════════════════════════════════════
# STRUCT MEMORY LAYOUT [SSOT]
# ════════════════════════════════════════════════════════════════════════════════
# [SSOT] Data Structure Definition
const SPLAT_STRUCT_FLOATS: int = 60
const SPLAT_STRUCT_BYTES: int = 240 # 60 * 4

# [SSOT] Memory Layout Indices (Float offsets)
const SPLAT_INDEX_POS: int = 0      # Vec3 (Floats 0, 1, 2)
# Rotation and Scale are packed into Covariance (Floats 4-9)
const SPLAT_INDEX_ROT_SCALE: int = 4 
const SPLAT_INDEX_OPACITY: int = 10  # Float 10
const SPLAT_INDEX_INSTANCE_ID: int = 11 # [NEW] The Neural Link (Uint encoded as float)
const SPLAT_INDEX_SH_DC: int = 12    # Vec3 (Floats 12, 13, 14)

# [NEW] Dynamic System Limits
## Maximum number of dynamic GaussianSplat objects supported in the scene.
const MAX_DYNAMIC_INSTANCES: int = 4096
## GPU Binding slot for the Instance Transforms storage buffer.
## NOTE: This is index 7 in the projection descriptor set (sequential after Uniforms at binding 6).
const BINDING_INSTANCE_TRANSFORMS: int = 7

# ════════════════════════════════════════════════════════════════════════════════
# TIMING CONSTANTS
# ════════════════════════════════════════════════════════════════════════════════
## Camera glide animation duration in seconds (Environment Mode entry effect).
const CAMERA_GLIDE_DURATION_SEC: float = 1.5

## Memory monitor check interval in seconds.
const MEMORY_CHECK_INTERVAL_SEC: float = 1.0

## Retry delay for camera positioning when data isn't ready.
const CAMERA_RETRY_DELAY_SEC: float = 0.5

# ════════════════════════════════════════════════════════════════════════════════
# VALIDATION HELPERS
# ════════════════════════════════════════════════════════════════════════════════
## Returns true if the given splat count would fit in the given VRAM budget (MB).
static func can_fit_in_vram(splat_count: int, budget_mb: float) -> bool:
	var required_bytes: int = splat_count * BYTES_PER_SPLAT
	var budget_bytes: float = budget_mb * 1024.0 * 1024.0
	return required_bytes <= budget_bytes

## Estimates VRAM usage in MB for a given splat count.
static func estimate_vram_mb(splat_count: int) -> float:
	return (splat_count * BYTES_PER_SPLAT) / (1024.0 * 1024.0)
