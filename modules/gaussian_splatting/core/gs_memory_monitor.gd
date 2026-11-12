# gs_memory_monitor.gd
# ════════════════════════════════════════════════════════════════════════════════
# MEMORY PRESSURE MONITOR FOR GAUSSIAN SPLATTING
# ════════════════════════════════════════════════════════════════════════════════
# PURPOSE: Proactive VRAM monitoring with early warning signals.
# BUSINESS VALUE: Prevents OOM crashes by alerting before problems occur.
# GODOT 4.5+: Uses RenderingServer.get_rendering_info() for VRAM stats.
# ════════════════════════════════════════════════════════════════════════════════
class_name GSMemoryMonitor
extends Node

# ════════════════════════════════════════════════════════════════════════════════
# SIGNALS
# ════════════════════════════════════════════════════════════════════════════════
## Emitted when VRAM usage exceeds warning threshold (default 80%).
signal memory_warning(usage_percent: float, available_mb: float)

## Emitted when VRAM usage exceeds critical threshold (default 90%).
signal memory_critical(usage_percent: float, available_mb: float)

## Emitted when VRAM usage drops back below warning threshold (recovery).
signal memory_recovered(usage_percent: float, available_mb: float)

## Emitted every check interval with current memory stats.
signal memory_stats_updated(stats: Dictionary)

# ════════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════════
## How often to check memory (in seconds).
@export var check_interval_seconds: float = GSConstants.MEMORY_CHECK_INTERVAL_SEC

## VRAM usage percentage at which to emit warning (0.0 to 1.0).
@export var warning_threshold: float = GSConstants.MEMORY_WARNING_THRESHOLD

## VRAM usage percentage at which to emit critical alert (0.0 to 1.0).
@export var critical_threshold: float = GSConstants.MEMORY_CRITICAL_THRESHOLD

## Whether to automatically start monitoring when added to scene.
@export var auto_start: bool = true

## Enable verbose logging.
@export var enable_logging: bool = false

## VRAM budget in MB to monitor against.
## NOTE: Godot does not expose total GPU VRAM, so we use a configurable budget.
## Set this to match your GaussianSplattingConfig.memory_max_vram_budget_mb.
@export var vram_budget_mb: float = 512.0

# ════════════════════════════════════════════════════════════════════════════════
# INTERNAL STATE
# ════════════════════════════════════════════════════════════════════════════════
## Internal timer for periodic checks.
var usage_provider: Callable

var _timer: Timer = null

## Last recorded warning level (0=OK, 1=Warning, 2=Critical).
var _last_warning_level: int = 0

## Whether monitoring is currently active.
var _is_monitoring: bool = false

## Last known stats (for get_current_stats()).
var _last_stats: Dictionary = {}

# ════════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ════════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Create timer but don't add to tree yet
	_timer = Timer.new()
	_timer.wait_time = check_interval_seconds
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)
	
	if auto_start:
		start_monitoring()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop_monitoring()

# ════════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ════════════════════════════════════════════════════════════════════════════════

## Start memory monitoring.
func start_monitoring() -> void:
	if _is_monitoring:
		return
	
	_is_monitoring = true
	_timer.start()
	
	# Do an immediate check
	_check_memory()
	
	if enable_logging:
		print("[GSMemoryMonitor] Monitoring started (interval: %.1fs)" % check_interval_seconds)


## Stop memory monitoring.
func stop_monitoring() -> void:
	if not _is_monitoring:
		return
	
	_is_monitoring = false
	_timer.stop()
	
	if enable_logging:
		print("[GSMemoryMonitor] Monitoring stopped")


## Get current memory statistics.
## @return: Dictionary with usage_percent, used_mb, total_mb, available_mb
func get_current_stats() -> Dictionary:
	return _last_stats.duplicate()


## Force an immediate memory check.
func check_now() -> void:
	_check_memory()


## Check if currently in warning state.
func is_warning() -> bool:
	return _last_warning_level >= 1


## Check if currently in critical state.
func is_critical() -> bool:
	return _last_warning_level >= 2


## Update check interval (restarts timer if monitoring).
func set_check_interval(seconds: float) -> void:
	check_interval_seconds = seconds
	_timer.wait_time = seconds
	if _is_monitoring:
		_timer.stop()
		_timer.start()


## Get a human-readable status string.
func get_status_string() -> String:
	if _last_stats.is_empty():
		return "Not monitored"
	
	var status := "OK"
	if _last_warning_level == 1:
		status = "WARNING"
	elif _last_warning_level == 2:
		status = "CRITICAL"
	
	return "%s - %.1f%% used (%.0f MB free)" % [
		status,
		_last_stats.get("usage_percent", 0) * 100,
		_last_stats.get("available_mb", 0)
	]

# ════════════════════════════════════════════════════════════════════════════════
# INTERNAL: MEMORY CHECKING
# ════════════════════════════════════════════════════════════════════════════════

## Timer callback.
func _on_timer_timeout() -> void:
	_check_memory()


## Perform the actual memory check.
func _check_memory() -> void:
	# Query VRAM stats from RenderingServer
	# NOTE: Godot only provides USED memory, not MAX. We use configurable budget.
	var used_bytes: int = int(usage_provider.call().get("tracked", 0)) if usage_provider.is_valid() else 0
	
	# Convert budget from MB to bytes
	var budget_bytes: float = vram_budget_mb * 1024.0 * 1024.0
	
	# If budget is zero or negative, monitoring is disabled
	if budget_bytes <= 0:
		if enable_logging and _last_stats.is_empty():
			push_warning("[GSMemoryMonitor] VRAM budget not set - monitoring disabled")
		_last_stats = {"error": "VRAM budget not configured"}
		return
	
	# Calculate stats
	var usage_percent: float = float(used_bytes) / budget_bytes
	var used_mb: float = float(used_bytes) / (1024.0 * 1024.0)
	var available_mb: float = vram_budget_mb - used_mb
	
	# Update cached stats
	_last_stats = {
		"usage_percent": usage_percent,
		"used_mb": used_mb,
		"total_mb": vram_budget_mb,
		"available_mb": available_mb,
		"timestamp": Time.get_ticks_msec()
	}
	
	# Emit stats update
	memory_stats_updated.emit(_last_stats)
	
	# Check thresholds and emit appropriate signals
	var new_level: int = 0
	
	if usage_percent >= critical_threshold:
		new_level = 2
	elif usage_percent >= warning_threshold:
		new_level = 1
	
	# Handle level transitions
	if new_level != _last_warning_level:
		_handle_level_change(new_level, usage_percent, available_mb)
	
	_last_warning_level = new_level


## Handle warning level changes.
func _handle_level_change(new_level: int, usage_percent: float, available_mb: float) -> void:
	var old_level := _last_warning_level
	
	# Escalation: OK -> Warning
	if old_level < 1 and new_level >= 1:
		if enable_logging:
			print("[GSMemoryMonitor] WARNING: VRAM at %.1f%% (%.0f MB free)" % [
				usage_percent * 100, available_mb
			])
		memory_warning.emit(usage_percent, available_mb)
	
	# Escalation: Warning -> Critical
	if old_level < 2 and new_level >= 2:
		if enable_logging:
			push_warning("[GSMemoryMonitor] CRITICAL: VRAM at %.1f%% (%.0f MB free)" % [
				usage_percent * 100, available_mb
			])
		memory_critical.emit(usage_percent, available_mb)
	
	# Recovery: Any -> OK
	if old_level > 0 and new_level == 0:
		if enable_logging:
			print("[GSMemoryMonitor] RECOVERED: VRAM at %.1f%% (%.0f MB free)" % [
				usage_percent * 100, available_mb
			])
		memory_recovered.emit(usage_percent, available_mb)
