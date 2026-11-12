class_name SplatBlockAllocator
extends RefCounted
## Main-thread allocation ledger. Every live block has exactly one owner.
const ALLOCATION_ALIGNMENT := GSConstants.SPLAT_STRUCT_BYTES
var total_capacity_bytes := 0
var used_bytes := 0
var _free_ranges: Array = []
var _allocations: Dictionary = {}

func _init(capacity_bytes: int) -> void:
	total_capacity_bytes = maxi(0, capacity_bytes / ALLOCATION_ALIGNMENT * ALLOCATION_ALIGNMENT)
	reset()

func reset() -> void:
	used_bytes = 0
	_allocations.clear()
	_free_ranges = [[0, total_capacity_bytes]] if total_capacity_bytes > 0 else []

func allocate(size_bytes: int) -> int:
	if size_bytes <= 0:
		return -1
	var aligned := _align_up(size_bytes, ALLOCATION_ALIGNMENT)
	for i in range(_free_ranges.size()):
		var entry: Array = _free_ranges[i]
		if entry[1] < aligned:
			continue
		var offset: int = entry[0]
		if entry[1] == aligned:
			_free_ranges.remove_at(i)
		else:
			_free_ranges[i] = [offset + aligned, int(entry[1]) - aligned]
		_allocations[offset] = aligned
		used_bytes += aligned
		return offset
	return -1

func free_block(offset: int, size_bytes: int = 0) -> bool:
	if not _allocations.has(offset):
		return false
	var size: int = _allocations[offset]
	if size_bytes > 0 and _align_up(size_bytes, ALLOCATION_ALIGNMENT) != size:
		return false
	_allocations.erase(offset)
	used_bytes -= size
	_free_ranges.append([offset, size])
	_free_ranges.sort_custom(func(a, b): return a[0] < b[0])
	var i := 0
	while i + 1 < _free_ranges.size():
		if _free_ranges[i][0] + _free_ranges[i][1] == _free_ranges[i + 1][0]:
			_free_ranges[i][1] += _free_ranges[i + 1][1]
			_free_ranges.remove_at(i + 1)
		else:
			i += 1
	return true

func check_memory_guard(size_bytes: int) -> bool:
	if size_bytes <= 0:
		return false
	var aligned := _align_up(size_bytes, ALLOCATION_ALIGNMENT)
	for entry in _free_ranges:
		if entry[1] >= aligned:
			return true
	return false

func high_water_splats() -> int:
	var end := 0
	for offset in _allocations:
		end = maxi(end, int(offset) + int(_allocations[offset]))
	return end / ALLOCATION_ALIGNMENT

func _align_up(size: int, alignment: int) -> int:
	return ((size + alignment - 1) / alignment) * alignment

func get_stats() -> Dictionary:
	return {"total_capacity_mb": total_capacity_bytes / 1048576.0, "used_mb": used_bytes / 1048576.0, "utilization_percent": 100.0 * used_bytes / maxi(1, total_capacity_bytes), "free_chunks_count": _free_ranges.size(), "allocations": _allocations.size()}
