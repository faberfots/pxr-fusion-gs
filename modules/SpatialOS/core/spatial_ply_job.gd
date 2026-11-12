class_name SpatialPLYJob
extends RefCounted
var thread := Thread.new()
var mutex := Mutex.new()
var slots := Semaphore.new()
var queue: Array[Dictionary] = []
var cancelled := false
var done := false
var error := ""
var data: Dictionary = {}
var document: PLYDocument
func start(path: String) -> Error:
	document = PLYDocument.new()
	if document.parse(path) != OK: return ERR_FILE_CORRUPT
	for i in range(4): slots.post()
	return thread.start(_run)
func cancel() -> void:
	mutex.lock()
	cancelled = true
	mutex.unlock()
	slots.post()
func join() -> void:
	if thread.is_started(): thread.wait_to_finish()
func take() -> Dictionary:
	mutex.lock()
	var chunk: Dictionary = queue.pop_front() if not queue.is_empty() else {}
	mutex.unlock()
	if not chunk.is_empty(): slots.post()
	return chunk
func snapshot() -> Dictionary:
	mutex.lock()
	var state := {"done": done, "empty": queue.is_empty(), "error": error, "cancelled": cancelled}
	mutex.unlock()
	return state
func _run() -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	points.resize(document.vertex_count)
	colors.resize(document.vertex_count)
	var file := document.open_reader()
	var offset := 0
	while offset < document.vertex_count:
		slots.wait()
		mutex.lock()
		var stop := cancelled
		mutex.unlock()
		if stop: break
		var count := mini(4096, document.vertex_count - offset)
		var chunk := PLYLoader.read_points(document, file, count)
		if chunk.has("error"):
			error = chunk.error
			break
		for i in range(count):
			points[offset + i] = chunk.points[i]
			colors[offset + i] = chunk.colors[i]
		offset += count
		chunk.loaded = offset
		mutex.lock()
		queue.append(chunk)
		mutex.unlock()
	mutex.lock()
	if not cancelled and error.is_empty(): data = PLYLoader.result(document, points, colors)
	done = true
	mutex.unlock()
