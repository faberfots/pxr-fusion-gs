class_name PlyFile
extends Resource
## PLY metadata and pure CPU conversion. PLYDocument owns the format contract.
var size := 0
var properties: Array[StringName] = []
var file_path := ""
var data_offset := 0
var bytes_per_vertex := 0
var aabb := AABB()
var document: PLYDocument
var error_message := ""

func _init(path: String = "") -> void:
	if not path.is_empty():
		parse(path)

func parse(path: String, max_vertices: int = 50000000, _legacy_max_file_bytes: int = 0) -> Error:
	document = PLYDocument.new()
	var result := document.parse(path, max_vertices)
	error_message = document.error_message
	if result != OK:
		return result
	result = document.validate_gaussians()
	error_message = document.error_message
	if result != OK:
		return result
	size = document.vertex_count
	file_path = path
	data_offset = document.data_offset
	bytes_per_vertex = document.stride_bytes
	properties.clear()
	for property in document.properties:
		properties.append(StringName(property.name))
	return OK

func get_vertex(index: int) -> Dictionary:
	if not document or index < 0 or index >= size:
		return {}
	var file := document.open_reader()
	if document.format_name == "ascii":
		for _i in range(index):
			file.get_line()
	else:
		file.seek(data_offset + index * bytes_per_vertex)
	var chunk := document.read_vertices(file, 1)
	if chunk.has("error"):
		return {}
	var vertex := {}
	for i in range(properties.size()):
		vertex[properties[i]] = chunk.values[i]
	return vertex

func is_valid() -> bool:
	return document != null and size > 0 and error_message.is_empty()

static func pack_chunk(values: PackedFloat32Array, property_count: int, mapping: Dictionary, instance_id: int, creation_time: float = -2.0) -> Dictionary:
	var count := values.size() / property_count
	var packed := PackedFloat32Array()
	packed.resize(count * GSConstants.SPLAT_STRUCT_FLOATS)
	var bounds := AABB()
	var sum := Vector3.ZERO
	var ys := PackedFloat32Array()
	for i in range(count):
		var v := i * property_count
		var b := i * GSConstants.SPLAT_STRUCT_FLOATS
		var position := Vector3(values[v + mapping.x], values[v + mapping.y], values[v + mapping.z])
		var scales := Vector3(values[v + mapping.sx], values[v + mapping.sy], values[v + mapping.sz])
		# Negative log-scales are valid, including almost planar Gaussians.
		# Only reject a positive scale whose squared magnitude cannot fit float32 covariance.
		if scales.x > 44.0 or scales.y > 44.0 or scales.z > 44.0:
			return {"error": "Gaussian covariance exceeds float32 representation"}
		var q := Quaternion(values[v + mapping.rx], values[v + mapping.ry], values[v + mapping.rz], values[v + mapping.rw])
		if q.length_squared() < 0.00000001:
			return {"error": "Gaussian rotation is a zero quaternion"}
		var matrix := Basis(q.normalized()) * Basis.from_scale(Vector3(exp(scales.x), exp(scales.y), exp(scales.z)))
		var cov := matrix * matrix.transposed()
		packed[b] = position.x
		packed[b + 1] = position.y
		packed[b + 2] = position.z
		packed[b + 3] = creation_time
		var covariance := [cov.x.x, cov.y.x, cov.z.x, cov.y.y, cov.z.y, cov.z.z]
		for j in range(6):
			packed[b + 4 + j] = covariance[j]
		packed[b + 10] = 1.0 / (1.0 + exp(-clampf(values[v + mapping.opacity], -80.0, 80.0)))
		packed[b + 11] = float(instance_id)
		if not -1 in mapping.dc:
			for channel in range(3):
				packed[b + 12 + channel] = values[v + mapping.dc[channel]]
		else:
			for channel in range(3):
				var color_value := values[v + mapping.rgb[channel]]
				packed[b + 12 + channel] = (clampf(color_value / mapping.rgb_divisors[channel], 0.0, 1.0) - 0.5) / 0.28209479177387814
		var coefficients: int = mapping.rest.size() / 3
		for coefficient in range(coefficients):
			for channel in range(3):
				packed[b + 15 + coefficient * 3 + channel] = values[v + mapping.rest[channel * coefficients + coefficient]]
		bounds = AABB(position, Vector3.ZERO) if i == 0 else bounds.expand(position)
		sum += position
		if i % 16 == 0:
			ys.append(position.y)
	return {"data": packed.to_byte_array(), "count": count, "aabb": bounds, "sum": sum, "y_samples": ys}
