class_name PlyConverter
extends RefCounted
const STRUCT_STRIDE_BYTES := GSConstants.SPLAT_STRUCT_BYTES

static func inspect(path: String, max_vertices: int = 50000000, _legacy_max_bytes: int = 0) -> Dictionary:
	if path.get_extension().to_lower() == "gsres":
		return GaussianSplatResource.inspect_file(path, max_vertices)
	var ply := PlyFile.new()
	var result := ply.parse(path, max_vertices)
	if result != OK:
		return {"error": ply.error_message, "code": result}
	return {"vertex_count": ply.size, "format": "ply", "ply": ply}

static func get_ply_vertex_count(path: String) -> int:
	var meta := inspect(path)
	return int(meta.get("vertex_count", 0))

static func estimate_vram_usage(count: int) -> int:
	return maxi(0, count) * STRUCT_STRIDE_BYTES

static func convert_ply_to_gsres(source_path: String, destination: String) -> Error:
	var resource := parse_ply_to_resource(source_path)
	if not resource:
		return ERR_INVALID_DATA
	if destination.get_extension().to_lower() == "gsres":
		return resource.save_binary(destination)
	return ResourceSaver.save(resource, destination)

static func parse_ply_to_resource(source_path: String) -> GaussianSplatResource:
	var ply := PlyFile.new()
	if ply.parse(source_path) != OK:
		return null
	var file := ply.document.open_reader()
	var resource := GaussianSplatResource.new()
	resource.splat_count = ply.size
	resource.source_file = source_path
	var mapping := ply.document.gaussian_mapping()
	var first := true
	var done := 0
	while done < ply.size:
		var chunk := ply.document.read_vertices(file, mini(4096, ply.size - done))
		if chunk.has("error"):
			return null
		var converted := PlyFile.pack_chunk(chunk.values, ply.properties.size(), mapping, 0)
		if converted.has("error"):
			return null
		resource.data.append_array(converted.data)
		resource.aabb = converted.aabb if first else resource.aabb.merge(converted.aabb)
		resource.position_sum += converted.sum
		resource.y_samples.append_array(converted.y_samples)
		first = false
		done += int(converted.count)
	return resource
