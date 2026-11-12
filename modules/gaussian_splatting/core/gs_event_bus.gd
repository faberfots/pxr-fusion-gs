# gs_event_bus.gd
# ════════════════════════════════════════════════════════════════════════════════
# GLOBAL EVENT BUS FOR GAUSSIAN SPLATTING SYSTEM
# ════════════════════════════════════════════════════════════════════════════════
# PURPOSE: Aggregates all viewer events into a single, unified stream.
# SSOT: This is THE interface for external systems to monitor the viewer.
# MECE: Event types are mutually exclusive and collectively exhaustive.
# ════════════════════════════════════════════════════════════════════════════════
class_name GSEventBus
extends Node

# ════════════════════════════════════════════════════════════════════════════════
# UNIFIED EVENT SIGNAL
# ════════════════════════════════════════════════════════════════════════════════
## Emitted for ALL viewer events. Payload contains event-specific data.
## External systems only need to connect to this ONE signal.
## @param event_type: String identifier from EVENT_* constants below
## @param payload: Dictionary with event-specific data + timestamp
signal event_emitted(event_type: String, payload: Dictionary)

# ════════════════════════════════════════════════════════════════════════════════
# EVENT TYPE CONSTANTS (MECE Classification)
# ════════════════════════════════════════════════════════════════════════════════
# Loading Events
const EVENT_LOADING_STARTED := "loading_started"      ## File load initiated
const EVENT_LOADING_PROGRESS := "loading_progress"    ## Progress update (0-1)
const EVENT_LOADING_COMPLETED := "loading_completed"  ## All splats loaded to GPU

# Rendering Events
const EVENT_RENDER_STATE_CHANGED := "render_state_changed"  ## Rendering started/stopped

# Scene Events
const EVENT_SCENE_MODE_CHANGED := "scene_mode_changed"      ## Object/Environment mode
const EVENT_SCENE_CLEARED := "scene_cleared"                ## Scene reset

# Error Events
const EVENT_ERROR_OCCURRED := "error_occurred"        ## Unrecoverable error

# Memory Events
const EVENT_MEMORY_WARNING := "memory_warning"        ## VRAM at warning threshold
const EVENT_MEMORY_CRITICAL := "memory_critical"      ## VRAM at critical threshold
const EVENT_MEMORY_RECOVERED := "memory_recovered"    ## VRAM back to safe levels

# Camera Events
const EVENT_CAMERA_POSITIONED := "camera_positioned"  ## Auto-framing complete
const EVENT_CAMERA_MOVEMENT := "camera_movement"      ## Movement state changed

# Preload Events (for Proposal 5)
const EVENT_PRELOAD_STARTED := "preload_started"      ## Background parsing started
const EVENT_PRELOAD_COMPLETED := "preload_completed"  ## Metadata cached

# ════════════════════════════════════════════════════════════════════════════════
# EVENT HISTORY (Optional logging for debugging)
# ════════════════════════════════════════════════════════════════════════════════
## Enable to keep a rolling history of recent events for debugging.
@export var enable_event_history: bool = false

## Maximum number of events to keep in history.
@export var max_history_size: int = 100

## Rolling event history (newest at front).
var _event_history: Array[Dictionary] = []

# ════════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ════════════════════════════════════════════════════════════════════════════════

## Emit an event through the bus.
## Automatically adds timestamp to payload.
## @param event_type: One of the EVENT_* constants
## @param payload: Optional dictionary with event-specific data
func emit_event(event_type: String, payload: Dictionary = {}) -> void:
	# Add metadata to payload
	payload["timestamp"] = Time.get_ticks_msec()
	payload["event_type"] = event_type
	
	# Store in history if enabled
	if enable_event_history:
		_event_history.push_front(payload.duplicate())
		if _event_history.size() > max_history_size:
			_event_history.pop_back()
	
	# Emit the unified signal
	event_emitted.emit(event_type, payload)


## Convenience method for emitting loading progress.
## @param progress: 0.0 to 1.0
## @param loaded_count: Number of splats loaded so far
## @param total_count: Total number of splats to load
func emit_loading_progress(progress: float, loaded_count: int, total_count: int) -> void:
	emit_event(EVENT_LOADING_PROGRESS, {
		"progress": progress,
		"loaded_count": loaded_count,
		"total_count": total_count
	})


## Convenience method for emitting errors.
## @param message: Human-readable error message
## @param error_code: Godot Error enum value
func emit_error(message: String, error_code: int) -> void:
	emit_event(EVENT_ERROR_OCCURRED, {
		"message": message,
		"error_code": error_code,
		"error_name": error_string(error_code)
	})


## Convenience method for emitting memory warnings.
## @param usage_percent: Current VRAM usage (0.0 to 1.0)
## @param available_mb: Remaining VRAM in megabytes
func emit_memory_warning(usage_percent: float, available_mb: float) -> void:
	emit_event(EVENT_MEMORY_WARNING, {
		"usage_percent": usage_percent,
		"available_mb": available_mb
	})


## Get recent event history (if enabled).
## @param count: Number of recent events to return (default: all)
## @return: Array of event dictionaries, newest first
func get_event_history(count: int = -1) -> Array[Dictionary]:
	if count < 0 or count > _event_history.size():
		return _event_history.duplicate()
	return _event_history.slice(0, count)


## Clear event history.
func clear_event_history() -> void:
	_event_history.clear()


## Get a JSON-serializable report of recent events (for LLM/logging).
func get_event_report() -> String:
	return JSON.stringify(_event_history, "\t")
