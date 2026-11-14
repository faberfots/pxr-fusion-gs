@tool
class_name GaussianSplattingConfig extends Resource
## Configuration resource for Gaussian Splatting renderer
## This centralizes all tunable parameters and magic numbers into one place
##
## TIER 2 UPDATE: Removed dynamic buffer resizing parameters. Buffers are now
## pre-allocated to max_duplication_factor to eliminate stuttering.

#region Quality Presets
enum QualityPreset {
	CUSTOM,      ## User-defined settings
	LOW,         ## Optimized for low-end hardware (integrated GPUs)
	MEDIUM,      ## Balanced settings for mid-range GPUs
	HIGH,        ## High quality for dedicated GPUs
	ULTRA        ## Maximum quality for high-end GPUs
}
#endregion

#region Post-Processing (Visuals)
const COLOR_FIELDS := ["post_exposure","post_contrast","post_saturation","post_temperature","post_black_point","post_white_point","post_sharpness","post_tint"]
@export_storage var color_settings_edited := false
@export_group("Post-Processing", "post_")

## Adjusts the overall brightness of the scene.
## Default: 1.0 (Neutral)
@export_range(0.0, 5.0, 0.1) var post_exposure : float = 1.0 :
	set(value):
		post_exposure = value
		_mark_dirty()

## Adjusts the dynamic range between darks and lights.
## Default: 1.0 (Neutral). >1.0 crushes blacks and blows out whites.
@export_range(0.5, 2.0, 0.01) var post_contrast : float = 1.0 : 
	set(value):
		post_contrast = value
		_mark_dirty()

## Color intensity. 0.0 is grayscale, >1.0 is vibrant.
## Default: 1.0 (Neutral)
@export_range(0.0, 2.0, 0.01) var post_saturation : float = 1.0 :
	set(value):
		post_saturation = value
		_mark_dirty()

## Artificial sharpening applied to the splats.
## Gaussian splats can look soft; this recovers perceived detail.
## Low = 0.0, Medium = 0.25, High = 0.5, Ultra = 1.0
@export_range(0.0, 1.0, 0.05) var post_sharpness : float = 0.5 :
	set(value):
		post_sharpness = value
		_mark_dirty()

## The threshold for shadows. Higher values make dark areas pure black.
## Default: 0.05
@export_range(0.0, 0.5, 0.01) var post_black_point : float = 0.05 :
	set(value):
		post_black_point = value
		_mark_dirty()

## The threshold for highlights. Lower values wash out white areas.
## Default: 1.0
@export_range(0.5, 2.0, 0.01) var post_white_point : float = 1.0 :
	set(value):
		post_white_point = value
		_mark_dirty()

## Shifts color balance. Negative = Cool (Blue), Positive = Warm (Orange).
## Default: 0.0
@export_range(-1.0, 1.0, 0.05) var post_temperature : float = 0.0 :
	set(value):
		post_temperature = value
		_mark_dirty()

## Multiplies the final color by this value.
## useful for overall mood or fading to black.
@export var post_tint : Color = Color.WHITE :
	set(value):
		post_tint = value
		_mark_dirty()
#endregion

#region Rendering Parameters
@export_group("Rendering", "")
## Size of each tile in pixels (must match shader constant)
## Larger tiles = fewer dispatches but less parallelism
## Smaller tiles = more dispatches but better GPU utilization
@export_range(8, 32, 2) var tile_size : int = 16 :
	set(value):
		tile_size = value
		_mark_dirty()

## Compatibility with older resources only; source-file size never controls admission.
var max_file_size_mb: float = 0.0

## Maximum number of vertices/splats that can be loaded
## Safety limit to prevent out-of-memory conditions
@export_range(1000000, 100000000, 1000000) var max_vertices : int = 50_000_000 :
	set(value):
		max_vertices = value
		_mark_dirty()
#endregion

#region Buffer Management
@export_group("Buffer Management", "buffer_")
## Maximum allowed splat duplication factor
## Higher = more memory but handles complex scenes better
## Caps how much the buffer can grow to prevent VRAM exhaustion
# @export_range(10.0, 30.0, 1.0) var max_duplication_factor : float = 15.0 :
## Recommended values:
##   - 10.0x: Low VRAM systems (saves ~380MB @ 5M splats)
##   - 12.0x: Balanced (saves ~230MB @ 5M splats)
##   - 15.0x: Safe default (handles most scenes)
##   - 20.0x: High complexity scenes (uses +380MB @ 5M splats)
@export_range(2.0, 64.0, 1.0) var max_duplication_factor : float = 12.0 :
	set(value):
		max_duplication_factor = value
		_mark_dirty()

# --- PHASE 1 NEW FEATURES: Memory & Atlas Configuration ---
# These settings control the "Splat Atlas" (VRAM Heap) dimensions.
# -------------------------------------------------------------------------
@export_group("Memory & Atlas", "memory_")

## Total GS GPU allocation budget, including atlas, projections, sort scratch and render targets.
## Twenty percent remains available for transactional target resizing.
@export_range(64, 8192, 32) var memory_max_vram_budget_mb : int = 500 :
	set(value):
		memory_max_vram_budget_mb = value
		_mark_dirty()

## Maximum number of simultaneous SplatEntity instances allowed.
## Used to pre-allocate the InstanceTransforms buffer (Phase 2 preparation).
## This allows moving up to 'memory_max_instances' objects independently at 60FPS.
@export_range(1, 4095, 1) var memory_max_instances : int = 1000 :
	set(value):
		memory_max_instances = value
		_mark_dirty()
# -------------------------------------------------------------------------
#endregion

#region Loading Parameters
@export_group("Loading", "")
## CPU block size, independent of render quality. Legacy serialized values remain valid.
@export_range(100, 131072, 1) var loading_batch_size:int=GSConstants.DEFAULT_LOADING_BATCH_SIZE
@export_range(4096,131072,1) var loading_gpu_block_splats:int=GSConstants.DEFAULT_LOADING_BATCH_SIZE
@export var loading_progressive_preview:=false
@export var loading_gpu_conversion_enabled:=true
@export_range(1,4,1) var loading_cpu_workers:int=2
@export var loading_cache_enabled:=true
@export var loading_cache_directory:=GSPreparedCache.DEFAULT_ROOT
@export_range(256,32768,256) var loading_cache_budget_mb:int=8192
@export_range(8,512,1) var loading_staging_budget_mb:int=256
@export_range(1, 64, 1) var loading_upload_budget_mb:int=32
@export_range(0.25, 8.0, 0.25) var loading_schedule_budget_ms:float=2.0

## Delay in seconds after cleanup before initializing new scene
## Gives GPU time to complete pending operations
@export_range(0.0, 0.5, 0.05) var cleanup_delay_seconds : float = 0.1 :
	set(value):
		cleanup_delay_seconds = clampf(value, 0.0, 0.5)
		_mark_dirty()
#endregion

#region Performance Tuning
## --- TIER 1 SSOT ENHANCEMENT START ---
## These values are now the Single Source of Truth for both GDScript and GLSL.
## They are marked as read-only in the inspector to prevent accidental changes
## that would require a shader recompilation to take effect. They should only be
## modified by developers who are also editing the shaders.
@export_group("Shader Constants (Advanced)", "shader_")
## Number of splats processed per projection workgroup
@export var shader_projection_workgroup_size : int = 256
## Workgroup size for radix sort stages.
@export var shader_radix_sort_workgroup_size : int = 256
## The base for the radix sort (e.g., 256 for 8-bit passes).
@export var shader_radix_sort_radix : int = 256
## Sub-division factor for sort partitions.
@export var shader_radix_sort_partition_division : int = 4
## --- TIER 1 SSOT ENHANCEMENT END ---

## Whether to add GPU barriers after each compute dispatch
## Disabling can improve performance but may cause rendering artifacts
## Only disable if you understand GPU synchronization hazards
@export_group("Performance", "") # Return to a normal group
@export var enable_compute_barriers : bool = true :
	set(value):
		enable_compute_barriers = value
		_mark_dirty()

## FPS limit when rendering is paused (camera not moving)
## Lower = less power consumption when idle
@export_range(10, 60, 5) var paused_fps_limit : int = 30 :
	set(value):
		paused_fps_limit = clampi(value, 10, 60)
		_mark_dirty()

## Seconds of no camera movement before pausing renders
## Higher = less battery drain, lower = more responsive
@export_range(0.5, 5.0, 0.5) var pause_delay_seconds : float = 2.0 :
	set(value):
		pause_delay_seconds = clampf(value, 0.5, 5.0)
		_mark_dirty()
#endregion

#region Visual Quality
@export_group("Visuals", "")
## Default render scale (1.0 = native resolution)
## Lower = better performance, higher = better quality when upscaling
@export_range(0.25, 2.0, 0.05) var default_render_scale : float = 1.0 :
	set(value):
		default_render_scale = clampf(value, 0.25, 2.0)
		_mark_dirty()

## Default model scale multiplier
## Adjusts the size of loaded splats
@export_range(0.1, 10.0, 0.1) var default_model_scale : float = 1.0 :
	set(value):
		default_model_scale = clampf(value, 0.1, 10.0)
		_mark_dirty()

## Whether to enable heatmap visualization by default
## Shows splat density as color overlay (useful for debugging)
@export var enable_heatmap_by_default : bool = false :
	set(value):
		enable_heatmap_by_default = value
		_mark_dirty()
#endregion

#region Debug and Logging
@export_group("Debugging", "")
## Whether to print detailed GPU resource information
@export var enable_verbose_logging : bool = false :
	set(value):
		enable_verbose_logging = value
		_mark_dirty()

## Whether to track peak VRAM usage
@export var track_memory_stats : bool = true :
	set(value):
		track_memory_stats = value
		_mark_dirty()

## How often to update debug info (in seconds)
## Lower = more responsive UI but higher CPU usage
@export_range(0.05, 1.0, 0.05) var debug_update_interval : float = 0.1 :
	set(value):
		debug_update_interval = clampf(value, 0.05, 1.0)
		_mark_dirty()
#endregion

#region Camera Settings
@export_group("Camera", "camera_")
## Mouse sensitivity for camera rotation
@export_range(0.1, 2.0, 0.1) var camera_mouse_sensitivity : float = 0.4 :
	set(value):
		camera_mouse_sensitivity = clampf(value, 0.1, 2.0)
		_mark_dirty()

## Camera movement speed multiplier when holding shift
@export_range(1.5, 5.0, 0.5) var camera_run_speed_multiplier : float = 2.5 :
	set(value):
		camera_run_speed_multiplier = clampf(value, 1.5, 5.0)
		_mark_dirty()

## Camera movement acceleration
@export_range(10.0, 50.0, 5.0) var camera_acceleration : float = 30.0 :
	set(value):
		camera_acceleration = clampf(value, 10.0, 50.0)
		_mark_dirty()

## Camera movement deceleration (negative acceleration)
@export_range(-30.0, -5.0, 1.0) var camera_deceleration : float = -10.0 :
	set(value):
		camera_deceleration = clampf(value, -30.0, -5.0)
		_mark_dirty()

## Camera velocity multiplier
@export_range(1.0, 10.0, 0.5) var camera_velocity_multiplier : float = 4.0 :
	set(value):
		camera_velocity_multiplier = clampf(value, 1.0, 10.0)
		_mark_dirty()

## Default camera field of view (degrees)
@export_range(20.0, 170.0, 5.0) var camera_default_fov : float = 75.0 :
	set(value):
		camera_default_fov = clampf(value, 20.0, 170.0)
		_mark_dirty()

#endregion

#region Internal State
## Current quality preset being used
var _applying_preset := false

@export_storage var current_preset : QualityPreset = QualityPreset.CUSTOM

## Whether config has been modified since last save
var is_dirty : bool = false

## Emitted when any configuration value changes
signal config_changed
#endregion

#region Preset Management
## Apply a quality preset to all parameters
func apply_preset(preset : QualityPreset) -> void:
	var colors:Dictionary={}
	if color_settings_edited:
		for field in COLOR_FIELDS:colors[field]=get(field)
	_applying_preset = true
	match preset:
		QualityPreset.LOW:
			_apply_low_preset()
		QualityPreset.MEDIUM:
			_apply_medium_preset()
		QualityPreset.HIGH:
			_apply_high_preset()
		QualityPreset.ULTRA:
			_apply_ultra_preset()
		QualityPreset.CUSTOM:
			pass # Keep current values
	
	for field in colors:set(field,colors[field])
	_applying_preset = false
	current_preset = preset
	is_dirty = true
	config_changed.emit()
	
	if enable_verbose_logging:
		print("[GaussianSplattingConfig] Applied preset: %s" % QualityPreset.keys()[preset])

## RESET HELPER: Resets artistic post-processing to neutral values.
## This ensures a consistent baseline when switching presets.
func _reset_post_processing_to_neutral() -> void:
	post_exposure = 1.0
	post_contrast = 1.0
	post_saturation = 1.0
	post_black_point = 0.05
	post_white_point = 1.0
	post_temperature = 0.0
	post_tint = Color.WHITE
	# Note: post_sharpness is NOT reset here as it is handled per-preset below.

## Low quality preset - optimized for integrated GPUs and low-end hardware
func _apply_low_preset() -> void:
	# 1. Resource Constraints
	# Reduce memory usage
	max_duplication_factor = 8.0 # Minimal memory footprint
	
	# --- PHASE 1 UPDATE: Restrict VRAM budget for low-end devices ---
	memory_max_vram_budget_mb = 256 # ~1 Million splats max
	memory_max_instances = 100      # Fewer moving objects
	# ---------------------------------------------------------------
	
	# Smaller batches for smoother loading on slower systems
	
	# 2. Rendering Quality
	# Lower quality defaults
	default_render_scale = 0.75 # Upscale from 75% resolution
	default_model_scale = 1.0
	
	# 3. Post-Processing (Visuals)
	_reset_post_processing_to_neutral()
	post_sharpness = 0.0         # Disable sharpening to save fragments/performance
	
	# 4. Battery & Idle
	# Longer pause for battery savings
	pause_delay_seconds = 1.0 # Pause aggressively to save battery
	paused_fps_limit = 20
	
	# Less frequent debug updates
	debug_update_interval = 0.2

## Medium quality preset - balanced for mid-range dedicated GPUs
func _apply_medium_preset() -> void:
	# 1. Resource Constraints
	# Balanced memory usage
	max_duplication_factor = 15.0
	
	# --- PHASE 1 UPDATE: Balanced VRAM budget ---
	memory_max_vram_budget_mb = 512 # ~2.1 Million splats
	memory_max_instances = 500
	# ---------------------------------------------------------------
	
	# Standard batches
	
	# 2. Rendering Quality
	# Native resolution
	default_render_scale = 1.0 # Native resolution
	default_model_scale = 1.0
	
	# 3. Post-Processing (Visuals)
	_reset_post_processing_to_neutral()
	post_sharpness = 0.25        # Slight sharpening for definition
	
	# 4. Battery & Idle
	# Standard pause behavior
	pause_delay_seconds = 2.0
	paused_fps_limit = 30
	
	# Standard debug updates
	debug_update_interval = 0.1

## High quality preset - for modern dedicated GPUs
func _apply_high_preset() -> void:
	# 1. Resource Constraints
	# More memory for complex scenes
	max_duplication_factor = 4.0
	
	# --- PHASE 1 UPDATE: High VRAM budget ---
	memory_max_vram_budget_mb = 4096 # Complete GS budget; retains full-size large-scene atlas capacity
	memory_max_instances = 2000
	# ---------------------------------------------------------------
	
	# Larger batches for faster loading
	
	# 2. Rendering Quality
	# High quality rendering
	default_render_scale = 1.0
	default_model_scale = 1.0
	
	# 3. Post-Processing (Visuals)
	_reset_post_processing_to_neutral()
	post_sharpness = 0.50        # Standard crisp look
	
	# 4. Battery & Idle
	# Shorter pause for responsiveness
	pause_delay_seconds = 2.5
	paused_fps_limit = 30
	
	# Frequent debug updates
	debug_update_interval = 0.1

## Ultra quality preset - maximum quality for high-end GPUs
func _apply_ultra_preset() -> void:
	# 1. Resource Constraints
	# Maximum memory allocation
	max_duplication_factor = 6.0 # Allocate max buffers
	
	# --- PHASE 1 UPDATE: Massive VRAM budget ---
	memory_max_vram_budget_mb = 6144 # Complete GS budget, including additional pair scratch
	memory_max_instances = 4095
	# ---------------------------------------------------------------
	
	# Very large batches
	
	# 2. Rendering Quality
	# Supersampling enabled
	default_render_scale = 1.25   # Supersampling (Render at 125%)
	default_model_scale = 1.0
	
	# 3. Post-Processing (Visuals)
	_reset_post_processing_to_neutral()
	post_sharpness = 1.0         # Maximum definition
	
	# 4. Battery & Idle
	# Longer pause (high-end users less concerned with battery)
	pause_delay_seconds = 3.0
	paused_fps_limit = 60       # Keep fluid even when idle initialy 30
	
	# Frequent updates for detailed stats
	debug_update_interval = 0.05
#endregion

#region Validation
## Validate all configuration values are within acceptable ranges
## Returns true if valid, false if any values needed correction
func validate() -> bool:
	return validation_errors().is_empty()

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if loading_gpu_block_splats<4096 or loading_gpu_block_splats>131072:errors.append("GPU import block must be 4096..131072 splats")
	if loading_cpu_workers<1 or loading_cpu_workers>4:errors.append("CPU preparation workers must be 1..4")
	if loading_cache_budget_mb<256 or loading_cache_budget_mb>32768:errors.append("Invalid prepared cache quota")
	if loading_batch_size<100 or loading_batch_size>131072:errors.append("Loading block must be 100..131072 splats")
	if loading_staging_budget_mb<8 or loading_staging_budget_mb>512 or loading_upload_budget_mb<1 or loading_upload_budget_mb>64:errors.append("Invalid bounded loading budget")
	if not is_finite(loading_schedule_budget_ms) or loading_schedule_budget_ms<0.25 or loading_schedule_budget_ms>8:errors.append("Invalid loading scheduling budget")
	if tile_size not in [8, 16, 32]: errors.append("Tile size must be 8, 16 or 32")
	if shader_projection_workgroup_size not in [64, 128, 256]: errors.append("Projection workgroup must be 64, 128 or 256")
	if shader_radix_sort_workgroup_size not in [64, 128, 256]: errors.append("Sort workgroup must be 64, 128 or 256")
	if shader_radix_sort_partition_division not in [1, 2, 4] or shader_radix_sort_radix != 256: errors.append("Sort requires radix 256 and partition division 1, 2 or 4")
	if memory_max_instances < 1 or memory_max_instances >= GSConstants.MAX_DYNAMIC_INSTANCES: errors.append("Dynamic instance limit must be between 1 and 4095")
	if memory_max_vram_budget_mb < 1 or memory_max_vram_budget_mb > 8192: errors.append("GPU budget must be 1..8192 MiB")
	if not is_finite(max_duplication_factor) or max_duplication_factor < 2 or max_duplication_factor > 64: errors.append("Duplication capacity must be finite and between 2 and 64")
	if max_vertices < 1 or max_vertices > 50000000: errors.append("Vertex limit must be 1..50000000")
	for value in [post_tint.r, post_tint.g, post_tint.b, post_tint.a, default_render_scale, default_model_scale, post_exposure, post_contrast, post_saturation, post_sharpness, post_black_point, post_white_point, post_temperature]:
		if not is_finite(value): errors.append("Visual settings must be finite")
	if post_white_point <= post_black_point: errors.append("White point must exceed black point")
	return errors

func gpu_signature() -> String:
	return str([tile_size, shader_projection_workgroup_size, shader_radix_sort_workgroup_size, shader_radix_sort_partition_division, max_duplication_factor, memory_max_vram_budget_mb, memory_max_instances])

func source_basis() -> Basis:
	# Explicit legacy asset-to-Godot rotation. All node transforms remain ordinary Godot transforms.
	return Basis(Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))

func pipeline_constants() -> Array[RDPipelineSpecializationConstant]:
	var constants: Array[RDPipelineSpecializationConstant] = []
	var values := [tile_size, shader_projection_workgroup_size, shader_radix_sort_workgroup_size, shader_radix_sort_partition_division, tile_size, tile_size]
	for i in range(values.size()):
		var item := RDPipelineSpecializationConstant.new()
		item.constant_id = i
		item.value = values[i]
		constants.append(item)
	return constants

func get_summary() -> String:
	var summary := PackedStringArray()
	summary.append("=== Gaussian Splatting Configuration ===")
	summary.append("Preset: %s" % QualityPreset.keys()[current_preset])
	
	# --- PHASE 1 UPDATE: Summary info ---
	summary.append("Atlas VRAM Budget: %d MB" % memory_max_vram_budget_mb)
	summary.append("Max Instances: %d" % memory_max_instances)
	# -----------------------------------
	
	summary.append("Tile Size: %d" % tile_size)
	summary.append("Max Duplication Factor: %.1f (Static)" % max_duplication_factor)
	summary.append("Loading Batch: %d splats" % loading_batch_size)
	summary.append("Render Scale: %.2f" % default_render_scale)
	summary.append("Verbose Logging: %s" % ("ON" if enable_verbose_logging else "OFF"))
	return "\n".join(summary)
#endregion

#region Utility Functions
func _mark_dirty() -> void:
	if _applying_preset:
		return
	is_dirty = true
	current_preset = QualityPreset.CUSTOM
	config_changed.emit()

## Save configuration to a file
func save_to_file(path : String) -> Error:
	var error := ResourceSaver.save(self, path)
	if error == OK:
		is_dirty = false
		if enable_verbose_logging:
			print("[GaussianSplattingConfig] Saved to: %s" % path)
	else:
		push_error("[GaussianSplattingConfig] Failed to save config: %d" % error)
	return error

## Load configuration from a file
static func load_from_file(path : String) -> GaussianSplattingConfig:
	if not FileAccess.file_exists(path):
		push_warning("[GaussianSplattingConfig] Config file not found: %s" % path)
		return null
	
	var config = load(path)
	if config is GaussianSplattingConfig:
		config.validate()
		if config.enable_verbose_logging:
			print("[GaussianSplattingConfig] Loaded from: %s" % path)
		return config
	else:
		push_error("[GaussianSplattingConfig] File is not a valid config: %s" % path)
		return null

## Create a default configuration
static func create_default() -> GaussianSplattingConfig:
	var config := GaussianSplattingConfig.new()
	config.apply_preset(QualityPreset.HIGH)
	return config
#endregion
