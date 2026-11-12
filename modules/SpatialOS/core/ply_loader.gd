class_name PLYLoader
extends RefCounted
## All PLY consumers share the bounded, typed PLYDocument reader.
static func load_ply(path: String) -> Dictionary:
	var document := PLYDocument.new()
	if document.parse(path) != OK: return {"error": document.error_message}
	var file := document.open_reader()
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	points.resize(document.vertex_count)
	colors.resize(document.vertex_count)
	var offset := 0
	while offset < document.vertex_count:
		var count := mini(32768, document.vertex_count - offset)
		var chunk := read_points(document, file, count)
		if chunk.has("error"): return chunk
		for i in range(count):
			points[offset + i] = chunk.points[i]
			colors[offset + i] = chunk.colors[i]
		offset += count
	return result(document, points, colors)
static func result(document: PLYDocument, points: PackedVector3Array, colors: PackedColorArray) -> Dictionary:
	var names := document.property_indices
	return {"points": points, "colors": colors, "count": points.size(), "source_file": document.path, "has_colors": names.has("red") or names.has("r") or names.has("f_dc_0"), "is_gaussian_splatting": names.has("scale_0") and names.has("rot_0")}
static func read_points(document: PLYDocument, file: FileAccess, count: int) -> Dictionary:
	var decoded := document.read_vertices(file, count)
	if decoded.has("error"): return decoded
	var values: PackedFloat32Array = decoded.values
	var names := document.property_indices
	var width := document.properties.size()
	var rgb := document.color_mapping()
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	points.resize(count)
	colors.resize(count)
	for i in range(count):
		var base := i * width
		points[i] = Vector3(values[base + names.x], values[base + names.y], values[base + names.z])
		var color := Color.WHITE
		if -1 not in rgb.rgb:
			color = Color(values[base + rgb.rgb[0]] / rgb.rgb_divisors[0], values[base + rgb.rgb[1]] / rgb.rgb_divisors[1], values[base + rgb.rgb[2]] / rgb.rgb_divisors[2])
		elif names.has("f_dc_0") and names.has("f_dc_1") and names.has("f_dc_2"):
			color = Color(0.5 + 0.28209479 * values[base + names.f_dc_0], 0.5 + 0.28209479 * values[base + names.f_dc_1], 0.5 + 0.28209479 * values[base + names.f_dc_2])
		colors[i] = color.clamp()
	return {"points": points, "colors": colors}
