@tool
class_name GaussianSplatResource
extends Resource
## Versioned, checksummed raw-local-coordinate splats. GPU stride is owned by GSConstants.
const FORMAT_MAGIC := 0x53525347
const FORMAT_VERSION := 2
const HEADER_BYTES := 128
@export var splat_count := 0
@export var aabb := AABB()
@export var data := PackedByteArray()
@export var source_file := ""
var position_sum := Vector3.ZERO
var y_samples := PackedFloat32Array()

func is_valid() -> bool:
	return splat_count > 0 and data.size() == splat_count * GSConstants.SPLAT_STRUCT_BYTES and aabb.position.is_finite() and aabb.size.is_finite() and aabb.size.x >= 0 and aabb.size.y >= 0 and aabb.size.z >= 0

func get_vram_size() -> int:
	return splat_count * GSConstants.SPLAT_STRUCT_BYTES

static func inspect_file(path: String, max_vertices: int = 50000000, _legacy_max_bytes: int = 0) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() < HEADER_BYTES:
		return {"error": "Cannot open binary splats or its header is incomplete"}
	var header := file.get_buffer(HEADER_BYTES)
	if header.decode_u32(0) != FORMAT_MAGIC or header.decode_u32(4) != FORMAT_VERSION or header.decode_u32(8) != GSConstants.SPLAT_STRUCT_BYTES:
		return {"error": "Unsupported binary splat signature, version or stride"}
	var count := header.decode_u64(16)
	if count <= 0 or count > max_vertices or file.get_length() != HEADER_BYTES + count * GSConstants.SPLAT_STRUCT_BYTES:
		return {"error": "Binary splat length/count mismatch"}
	var low := Vector3(header.decode_float(32), header.decode_float(36), header.decode_float(40))
	var extent := Vector3(header.decode_float(44), header.decode_float(48), header.decode_float(52))
	if not low.is_finite() or not extent.is_finite() or extent.x < 0 or extent.y < 0 or extent.z < 0:
		return {"error": "Invalid binary splat bounds"}
	return {"vertex_count": count, "aabb": AABB(low, extent), "checksum": header.slice(64, 96), "payload_offset": HEADER_BYTES, "format": "gsres"}

func save_binary(path: String) -> Error:
	if not is_valid():
		return ERR_INVALID_DATA
	var header := PackedByteArray()
	header.resize(HEADER_BYTES)
	header.encode_u32(0, FORMAT_MAGIC)
	header.encode_u32(4, FORMAT_VERSION)
	header.encode_u32(8, GSConstants.SPLAT_STRUCT_BYTES)
	header.encode_u64(16, splat_count)
	for i in range(6):
		header.encode_float(32 + i * 4, [aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z][i])
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	var digest := hashing.finish()
	for i in range(digest.size()):
		header[64 + i] = digest[i]
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_buffer(header)
	file.store_buffer(data)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		DirAccess.remove_absolute(temporary)
		return result
	return DirAccess.rename_absolute(temporary, path)

static func load_binary(path: String) -> GaussianSplatResource:
	var meta := inspect_file(path)
	if meta.has("error"):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	file.seek(HEADER_BYTES)
	var resource := GaussianSplatResource.new()
	resource.splat_count = meta.vertex_count
	resource.aabb = meta.aabb
	resource.data = file.get_buffer(resource.splat_count * GSConstants.SPLAT_STRUCT_BYTES)
	resource.source_file = path
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(resource.data)
	if hashing.finish() != meta.checksum or not resource.is_valid():
		return null
	return resource
