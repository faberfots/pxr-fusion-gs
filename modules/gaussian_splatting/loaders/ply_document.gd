class_name PLYDocument
extends RefCounted
## Shared, bounded PLY schema and decoder. No scene or GPU access is permitted here.
const MAX_HEADER_BYTES := 65536
const MAX_PROPERTIES := 256
const TYPE_INFO := {
	"char": [1, "i8"], "int8": [1, "i8"], "uchar": [1, "u8"], "uint8": [1, "u8"],
	"short": [2, "i16"], "int16": [2, "i16"], "ushort": [2, "u16"], "uint16": [2, "u16"],
	"int": [4, "i32"], "int32": [4, "i32"], "uint": [4, "u32"], "uint32": [4, "u32"],
	"float": [4, "f32"], "float32": [4, "f32"], "double": [8, "f64"], "float64": [8, "f64"]
}
var vertex_count := 0
var data_offset := 0
var stride_bytes := 0
var format_name := ""
var path := ""
var properties: Array[Dictionary] = []
var property_indices: Dictionary = {}
var error_message := ""
var _fast_float32 := false

func parse(source_path: String, max_vertices: int = 50000000, _legacy_max_file_bytes: int = 0) -> Error:
	vertex_count = 0
	properties.clear()
	property_indices.clear()
	stride_bytes = 0
	format_name = ""
	error_message = ""
	path = source_path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open PLY file", ERR_FILE_CANT_OPEN)
	if file.get_length() < 4:
		return _fail("PLY file is empty or too short to contain a signature", ERR_PARAMETER_RANGE_ERROR)
	if bounded_line(file, 16).get("line", "").strip_edges() != "ply":
		return _fail("Missing PLY signature")
	var current_element := ""
	var found_vertices := false
	var ended := false
	while file.get_position() < mini(MAX_HEADER_BYTES, file.get_length()):
		var header_line := bounded_line(file, MAX_HEADER_BYTES - file.get_position())
		if header_line.has("error"): return _fail(header_line.error)
		var line: String = header_line.line.strip_edges()
		var parts := line.replace("\t", " ").split(" ", false)
		if parts.is_empty() or parts[0] in ["comment", "obj_info"]:
			continue
		match parts[0]:
			"format":
				if parts.size() != 3 or parts[2] != "1.0" or parts[1] not in ["binary_little_endian", "binary_big_endian", "ascii"]:
					return _fail("Unsupported PLY format/version")
				format_name = parts[1]
			"element":
				if parts.size() != 3 or not parts[2].is_valid_int():
					return _fail("Invalid PLY element declaration")
				current_element = parts[1]
				if current_element == "vertex":
					if found_vertices:
						return _fail("Duplicate vertex element")
					found_vertices = true
					vertex_count = parts[2].to_int()
					if vertex_count <= 0 or vertex_count > max_vertices:
						return _fail("Vertex count is outside the configured limit", ERR_PARAMETER_RANGE_ERROR)
				elif not found_vertices and parts[2].to_int() != 0:
					return _fail("Vertex data must precede other nonempty elements")
			"property":
				if current_element != "vertex":
					continue
				if parts.size() != 3 or not TYPE_INFO.has(parts[1]) or property_indices.has(parts[2]):
					return _fail("Unsupported, duplicate or list-valued vertex property")
				if properties.size() >= MAX_PROPERTIES:
					return _fail("Too many vertex properties")
				property_indices[parts[2]] = properties.size()
				properties.append({"name": parts[2], "type": TYPE_INFO[parts[1]][1], "offset": stride_bytes, "bytes": TYPE_INFO[parts[1]][0]})
				stride_bytes += int(TYPE_INFO[parts[1]][0])
			"end_header":
				ended = true
				break
	if not ended or format_name.is_empty() or not found_vertices or properties.is_empty():
		return _fail("Missing or oversized PLY header")
	for axis in ["x", "y", "z"]:
		if not property_indices.has(axis):
			return _fail("PLY is missing position property: " + axis)
	data_offset = file.get_position()
	if format_name != "ascii" and vertex_count > (file.get_length() - data_offset) / stride_bytes:
		return _fail("Truncated PLY vertex payload")
	_fast_float32 = format_name == "binary_little_endian"
	for property in properties:
		_fast_float32 = _fast_float32 and property.type == "f32"
	return OK

func _fail(message: String, code: Error = ERR_FILE_CORRUPT) -> Error:
	error_message = message
	return code

func open_reader() -> FileAccess:
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		file.big_endian = format_name == "binary_big_endian"
		file.seek(data_offset)
	return file

func read_vertices(file: FileAccess, count: int, validate_values:bool=true) -> Dictionary:
	if file == null or count <= 0:
		return {"error": "Invalid vertex read"}
	var result := PackedFloat32Array()
	if format_name == "ascii":
		result.resize(count * properties.size())
		for row in range(count):
			if file.eof_reached():
				return {"error": "Truncated ASCII PLY"}
			var row_line := bounded_line(file, MAX_HEADER_BYTES)
			if row_line.has("error"): return row_line
			var values: PackedStringArray = row_line.line.strip_edges().replace("\t", " ").split(" ", false)
			if values.size() != properties.size():
				return {"error": "ASCII vertex does not match its schema"}
			for column in range(values.size()):
				if not values[column].is_valid_float():
					return {"error": "Invalid ASCII scalar"}
				result[row * properties.size() + column] = values[column].to_float()
	else:
		var bytes := file.get_buffer(count * stride_bytes)
		if bytes.size() != count * stride_bytes:
			return {"error": "Truncated binary PLY"}
		if _fast_float32:
			result = bytes.to_float32_array()
		else:
			var stream := StreamPeerBuffer.new()
			stream.data_array = bytes
			stream.big_endian = format_name == "binary_big_endian"
			result.resize(count * properties.size())
			for row in range(count):
				for column in range(properties.size()):
					var property := properties[column]
					stream.seek(row * stride_bytes + int(property.offset))
					var value: float
					match property.type:
						"f32": value = stream.get_float()
						"f64": value = stream.get_double()
						"i8": value = stream.get_8()
						"u8": value = stream.get_u8()
						"i16": value = stream.get_16()
						"u16": value = stream.get_u16()
						"i32": value = stream.get_32()
						"u32": value = stream.get_u32()
					result[row * properties.size() + column] = value
	if validate_values:
		for value in result:
			if not is_finite(value):return {"error":"PLY contains non-finite or unrepresentable values"}
	return {"values": result}

func gaussian_mapping() -> Dictionary:
	var mapping := {}
	for key in ["x", "y", "z", "opacity"]:
		mapping[key] = int(property_indices.get(key, -1))
	for pair in [["sx", "scale_0", "scale_x"], ["sy", "scale_1", "scale_y"], ["sz", "scale_2", "scale_z"], ["rw", "rot_0", "rot_w"], ["rx", "rot_1", "rot_x"], ["ry", "rot_2", "rot_y"], ["rz", "rot_3", "rot_z"]]:
		mapping[pair[0]] = int(property_indices.get(pair[1], property_indices.get(pair[2], -1)))
	var dc: Array[int] = []
	for i in range(3):
		dc.append(int(property_indices.get("f_dc_%d" % i, -1)))
	mapping["dc"] = dc
	mapping.merge(color_mapping())
	var rest: Array[int] = []
	var i := 0
	while property_indices.has("f_rest_%d" % i):
		rest.append(property_indices["f_rest_%d" % i])
		i += 1
	mapping["rest"] = rest
	return mapping

func validate_gaussians() -> Error:
	var m := gaussian_mapping()
	for key in ["x", "y", "z", "sx", "sy", "sz", "rw", "rx", "ry", "rz", "opacity"]:
		if int(m[key]) < 0:
			return _fail("Gaussian PLY is missing attribute: " + key)
	if -1 in m.dc and -1 in m.rgb:
		return _fail("Gaussian PLY needs three SH DC or RGB channels")
	var rest_count := 0
	for name in property_indices:
		if str(name).begins_with("f_rest_"): rest_count += 1
	if rest_count != m.rest.size(): return _fail("Non-contiguous SH coefficient properties")
	if m.rest.size() not in [0, 9, 24, 45]:
		return _fail("Only complete SH degrees 0 through 3 are supported")
	return OK

static func bounded_line(file: FileAccess, limit: int) -> Dictionary:
	var line := PackedByteArray()
	while line.size() <= limit and file.get_position() < file.get_length():
		var start := file.get_position()
		var chunk := file.get_buffer(mini(4096, limit - line.size() + 1))
		var newline := chunk.find(10)
		if newline >= 0:
			line.append_array(chunk.slice(0, newline))
			file.seek(start + newline + 1)
			return {"line": line.get_string_from_ascii()}
		line.append_array(chunk)
	if line.size() > limit: return {"error": "PLY line exceeds its bounded size"}
	return {"line": line.get_string_from_ascii()}

func color_mapping() -> Dictionary:
	var indices: Array[int] = []
	var divisors: Array[float] = []
	for channel in [["red", "diffuse_red", "r"], ["green", "diffuse_green", "g"], ["blue", "diffuse_blue", "b"]]:
		var index: int = property_indices.get(channel[0], property_indices.get(channel[1], property_indices.get(channel[2], -1)))
		indices.append(index)
		var type: String = properties[index].type if index >= 0 else ""
		divisors.append({"u8": 255.0, "i8": 255.0, "u16": 65535.0, "i16": 65535.0, "u32": 4294967295.0, "i32": 4294967295.0}.get(type, 1.0))
	return {"rgb": indices, "rgb_divisors": divisors}
