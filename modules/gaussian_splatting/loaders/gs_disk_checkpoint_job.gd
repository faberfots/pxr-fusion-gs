class_name GSDiskCheckpointJob
extends RefCounted
## Reconstructs immutable resident bytes from verified prepared data on one IO worker.
## Runtime timestamps and identity are restored exactly; node transforms stay with the viewer.
var _mutex := Mutex.new()
var _thread: Thread
var _cancelled := false
var _done := false
var _result: Dictionary = {}
var _written := 0

func start(path: String, models: Array[Dictionary], scratch_bytes: int) -> Error:
	_thread = Thread.new()
	return _thread.start(func():
		var result := _write(path, models, scratch_bytes)
		_mutex.lock(); _result = result; _done = true; _mutex.unlock()
	)

func cancel() -> void:
	_mutex.lock(); _cancelled = true; _mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock(); var value := _cancelled; _mutex.unlock(); return value

func status() -> Dictionary:
	_mutex.lock(); var value := {"done": _done, "bytes": _written}; _mutex.unlock(); return value

func join() -> Dictionary:
	if _thread and _thread.is_started(): _thread.wait_to_finish()
	_thread = null
	_mutex.lock(); var value := _result.duplicate(true); _mutex.unlock(); return value

func _write(path: String, models: Array[Dictionary], scratch_bytes: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	if scratch_bytes < 1048576: return {"error": ERR_UNAVAILABLE}
	var gpu := GSGpuDecoder.new()
	var largest := 1; var time_bytes := 16
	for model in models:
		largest = maxi(largest, int(model.count))
		time_bytes = maxi(time_bytes, model.runtime_spans.size() * 16)
	# Legacy small CPU batches can have many timestamps: reserve their table too.
	if scratch_bytes - time_bytes < 1048576: return {"error": ERR_UNAVAILABLE}
	var capacity := mini(131072, int((scratch_bytes - time_bytes - 4096) * 0.9 / 480.1875))
	capacity = mini(capacity, largest)
	if not gpu.initialize(capacity, 60, {}, true): return {"error": ERR_UNAVAILABLE}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file: gpu.cleanup(); return {"error": ERR_FILE_CANT_WRITE}
	var result: Dictionary = {"entries": [], "bytes": 0, "backend": "prepared_exact"}
	for model in models:
		if is_cancelled(): result = {"error": ERR_SKIP}; break
		var written := _write_model(file, gpu, model)
		if written.has("error"): result = written; break
		result.entries.append(written)
		result.bytes += int(model.count) * 240
	file.flush()
	if not result.has("error") and file.get_error() != OK: result = {"error": ERR_FILE_CANT_WRITE}
	file.close(); gpu.cleanup()
	result["elapsed_us"] = Time.get_ticks_usec() - started
	return result

func _write_model(file: FileAccess, gpu: GSGpuDecoder, model: Dictionary) -> Dictionary:
	var reference: Dictionary = model.prepared_reference
	var cache := GSPreparedCache.new(); cache.directory = reference.directory
	var meta := cache.candidate(reference.source, int(model.count), int(reference.bytes))
	if meta.is_empty() or meta.key != reference.key or meta.source_sha256 != reference.sha256:
		return {"error": ERR_FILE_CORRUPT}
	var spans: Array = model.runtime_spans
	if spans.is_empty() or int(spans.back().start) + int(spans.back().count) != int(model.count) or not gpu.set_time_spans(spans):
		return {"error": ERR_INVALID_DATA}
	var source := FileAccess.open(meta.payload, FileAccess.READ)
	if not source: return {"error": ERR_FILE_CANT_READ}
	var entry := {"model_id": model.model_id, "count": model.count, "instance_id": model.instance_id, "file_offset": file.get_position()}
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	var offset := 0; var error := OK
	for chunk in meta.chunks:
		if is_cancelled(): error = ERR_SKIP; break
		var count := int(chunk.count); var data := source.get_buffer(count * 240)
		if data.size() != count * 240: error = ERR_FILE_CANT_READ; break
		# The small GPU-owned input buffer can validate SHA leaves and retime in one dispatch.
		var gpu_hash: bool = chunk.get("hash_kind", "") == "sha256-8k" and count <= gpu.capacity
		if not gpu_hash and not GSPreparedCache.verify(data, chunk): error = ERR_FILE_CORRUPT; break
		var local := 0
		while local < count:
			if is_cancelled(): error = ERR_SKIP; break
			var amount := mini(gpu.capacity, count - local)
			var piece := data if amount == count else data.slice(local * 240, (local + amount) * 240)
			var converted := gpu.convert(piece.to_float32_array(), amount, int(model.instance_id), 0.0, 1 if gpu_hash else 0, offset + local)
			if converted.has("error") or (gpu_hash and converted.cache_leaf_hashes.hex_encode() != chunk.sha256): error = ERR_FILE_CORRUPT; break
			file.store_buffer(converted.data); hash.update(converted.data)
			if file.get_error() != OK: error = ERR_FILE_CANT_WRITE; break
			_mutex.lock(); _written += converted.data.size(); _mutex.unlock()
			local += amount
		if error != OK: break
		offset += count
	source.close(); cache.release()
	if error != OK: return {"error": error}
	if offset != int(model.count): return {"error": ERR_FILE_CORRUPT}
	entry["sha256"] = hash.finish()
	return entry
