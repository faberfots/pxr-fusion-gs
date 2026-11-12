class_name AsyncPLYLoader
extends Node
signal progress_updated(percent: float, points_loaded: int, total_points: int)
signal chunk_ready(points: PackedVector3Array, colors: PackedColorArray)
signal loading_completed(data: Dictionary)
signal loading_failed(error_message: String)
signal loading_cancelled()
signal loading_prepared(total_points: int)
var _job: SpatialPLYJob
func load_ply_async(file_path: String) -> bool:
	if _job: return false
	_job = SpatialPLYJob.new()
	var result := _job.start(file_path)
	if result != OK:
		var message := _job.document.error_message
		_job = null
		loading_failed.emit(message if not message.is_empty() else error_string(result))
		return false
	loading_prepared.emit(_job.document.vertex_count)
	return true
func cancel() -> void:
	if not _job: return
	_job.cancel()
	_job.join()
	_job = null
	loading_cancelled.emit()
func is_loading() -> bool:
	return _job != null
func _process(_delta: float) -> void:
	if not _job: return
	for i in range(2):
		var chunk := _job.take()
		if chunk.is_empty(): break
		chunk_ready.emit(chunk.points, chunk.colors)
		progress_updated.emit(100.0 * chunk.loaded / _job.document.vertex_count, chunk.loaded, _job.document.vertex_count)
	var state := _job.snapshot()
	if not state.done or not state.empty: return
	_job.join()
	var result := _job.data
	_job = null
	if not state.error.is_empty(): loading_failed.emit(state.error)
	elif state.cancelled: loading_cancelled.emit()
	else: loading_completed.emit(result)
func _exit_tree() -> void:
	if _job:
		_job.cancel()
		_job.join()
		_job = null
