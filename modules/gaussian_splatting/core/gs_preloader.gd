class_name GSPreloader
extends Node
## Header-only cache. Fingerprints invalidate entries when their source changes.
signal preload_completed(file_path: String, metadata: Dictionary)
signal preload_failed(file_path: String, error: String)
signal preload_started(file_path: String)
@export var max_cache_size := 50
@export var enable_logging := false
var _cached_metadata: Dictionary = {}
var _cache_order: Array[String] = []
var _queue: Array[String] = []
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _thread: Thread
var _terminate := false

func _ready() -> void:
	_thread = Thread.new()
	_thread.start(_worker)

func preload_file(path: String) -> void:
	if is_preloaded(path):
		preload_completed.emit(path, get_cached_metadata(path))
		return
	if not _thread:
		_ready()
	_mutex.lock()
	if not path in _queue:
		_queue.append(path)
		_wake.post()
	_mutex.unlock()

func preload_files(paths: Array[String]) -> void:
	for path in paths:
		preload_file(path)

func is_preloaded(path: String) -> bool:
	if not _cached_metadata.has(path):
		return false
	var metadata: Dictionary = _cached_metadata[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or int(metadata.modified) != FileAccess.get_modified_time(path) or int(metadata.file_bytes) != file.get_length():
		_cached_metadata.erase(path)
		_cache_order.erase(path)
		return false
	return true

func get_cached_metadata(path: String) -> Dictionary:
	return _cached_metadata[path].duplicate(true) if is_preloaded(path) else {}

func get_estimated_vram_mb(path: String) -> float:
	return float(get_cached_metadata(path).get("estimated_vram_mb", -1))

func clear_cache() -> void:
	_cached_metadata.clear()
	_cache_order.clear()

func get_cache_stats() -> Dictionary:
	_mutex.lock()
	var count := _queue.size()
	_mutex.unlock()
	return {"cached_files": _cached_metadata.size(), "max_cache_size": max_cache_size, "queued_files": count, "thread_active": _thread != null and _thread.is_alive()}

func _worker() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var terminate := _terminate
		var path: String = _queue.pop_front() if not _queue.is_empty() else ""
		_mutex.unlock()
		if terminate:
			return
		if path.is_empty():
			continue
		call_deferred("emit_signal", "preload_started", path)
		var metadata := PlyConverter.inspect(path)
		if metadata.has("error"):
			call_deferred("emit_signal", "preload_failed", path, metadata.error)
			continue
		metadata.erase("ply")
		var file := FileAccess.open(path, FileAccess.READ)
		metadata["modified"] = FileAccess.get_modified_time(path)
		metadata["file_bytes"] = file.get_length()
		metadata["estimated_vram_mb"] = int(metadata.vertex_count) * GSConstants.SPLAT_STRUCT_BYTES / 1048576.0
		call_deferred("_store", path, metadata)

func _store(path: String, metadata: Dictionary) -> void:
	while _cached_metadata.size() >= maxi(1, max_cache_size) and not _cache_order.is_empty():
		_cached_metadata.erase(_cache_order.pop_front())
	_cache_order.erase(path)
	_cache_order.append(path)
	_cached_metadata[path] = metadata
	preload_completed.emit(path, metadata.duplicate(true))

func _exit_tree() -> void:
	_mutex.lock()
	_terminate = true
	_mutex.unlock()
	_wake.post()
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
