class_name GSLoadJob
extends RefCounted
## Bounded producer/consumer job. The worker owns file/CPU work; the viewer owns nodes and GPU commits.
const MAX_QUEUED_CHUNKS := 4
var request_id := 0
var generation := 0
var path := ""
var instance_id := 0
var expected_count := 0
var max_vertices := 50000000
var chunk_size := 4096
var _mutex := Mutex.new()
var _available := Semaphore.new()
var _queue: Array[Dictionary] = []
var _cancelled := false
var _done := false
var _error := ""
var _thread: Thread
var _bounds := AABB()
var _sum := Vector3.ZERO
var _samples := PackedVector3Array()

func start() -> Error:
	for _i in range(MAX_QUEUED_CHUNKS):
		_available.post()
	_thread = Thread.new()
	return _thread.start(_produce)

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
	for _i in range(MAX_QUEUED_CHUNKS + 1):
		_available.post()

func is_cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func take_chunk() -> Dictionary:
	_mutex.lock()
	var chunk: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
	_mutex.unlock()
	if not chunk.is_empty():
		_available.post()
	return chunk

func result() -> Dictionary:
	_mutex.lock()
	var snapshot := {"done": _done, "empty": _queue.is_empty(), "error": _error, "cancelled": _cancelled, "aabb": _bounds, "sum": _sum, "samples": _samples.duplicate()}
	_mutex.unlock()
	return snapshot

func join() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null

func _publish(chunk: Dictionary) -> bool:
	_available.wait()
	if is_cancelled():
		return false
	_mutex.lock()
	_queue.append(chunk)
	_mutex.unlock()
	return true

func _finish(message: String = "") -> void:
	_mutex.lock()
	_error = message
	_done = true
	_mutex.unlock()

func _produce() -> void:
	if path.get_extension().to_lower() == "gsres":
		_produce_binary()
		return
	var ply := PlyFile.new()
	if ply.parse(path, max_vertices) != OK:
		_finish(ply.error_message)
		return
	if ply.size != expected_count:
		_finish("Source changed after load admission")
		return
	var file := ply.document.open_reader()
	var mapping := ply.document.gaussian_mapping()
	var offset := 0
	var first := true
	while offset < expected_count and not is_cancelled():
		var chunk := ply.document.read_vertices(file, mini(chunk_size, expected_count - offset))
		if chunk.has("error"):
			_finish(chunk.error)
			return
		var converted := PlyFile.pack_chunk(chunk.values, ply.properties.size(), mapping, instance_id, Time.get_ticks_msec() * 0.001)
		if converted.has("error"):
			_finish(converted.error)
			return
		_mutex.lock()
		_bounds = converted.aabb if first else _bounds.merge(converted.aabb)
		_sum += converted.sum
		# Bounded deterministic samples, retained for floor and accurate CPU picking.
		var values: PackedFloat32Array = chunk.values
		var sample_stride := maxi(1, ceili(float(expected_count) / 8192.0))
		for local in range(int(converted.count)):
			if (offset + local) % sample_stride == 0 and _samples.size() < 8192:
				var base := local * ply.properties.size()
				_samples.append(Vector3(values[base + mapping.x], values[base + mapping.y], values[base + mapping.z]))
		_mutex.unlock()
		first = false
		if not _publish({"data": converted.data, "start": offset, "count": converted.count}):
			break
		offset += int(converted.count)
	_finish()

func _produce_binary() -> void:
	var meta := GaussianSplatResource.inspect_file(path, max_vertices)
	if meta.has("error") or int(meta.get("vertex_count", 0)) != expected_count:
		_finish(meta.get("error", "Source changed after load admission"))
		return
	var file := FileAccess.open(path, FileAccess.READ)
	file.seek(GaussianSplatResource.HEADER_BYTES)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	var offset := 0
	var first := true
	while offset < expected_count and not is_cancelled():
		var count := mini(chunk_size, expected_count - offset)
		var data := file.get_buffer(count * GSConstants.SPLAT_STRUCT_BYTES)
		if data.size() != count * GSConstants.SPLAT_STRUCT_BYTES:
			_finish("Truncated binary splat payload")
			return
		hashing.update(data)
		for i in range(count):
			var base := i * GSConstants.SPLAT_STRUCT_BYTES
			for j in range(GSConstants.SPLAT_STRUCT_FLOATS):
				if not is_finite(data.decode_float(base + j * 4)):
					_finish("Non-finite binary splat value")
					return
			var position := Vector3(data.decode_float(base), data.decode_float(base + 4), data.decode_float(base + 8))
			if data.decode_float(base + 40) < 0.0 or data.decode_float(base + 40) > 1.0:
				_finish("Invalid binary opacity")
				return
			data.encode_float(base + 44, float(instance_id))
			data.encode_float(base + 12, Time.get_ticks_msec() * 0.001)
			_mutex.lock()
			_bounds = AABB(position, Vector3.ZERO) if first else _bounds.expand(position)
			_sum += position
			if (offset + i) % maxi(1, ceili(float(expected_count) / 8192.0)) == 0 and _samples.size() < 8192:
				_samples.append(position)
			_mutex.unlock()
			first = false
		if not _publish({"data": data, "start": offset, "count": count}):
			break
		offset += count
	if not is_cancelled() and hashing.finish() != meta.checksum:
		_finish("Binary splat checksum mismatch")
		return
	_finish()
