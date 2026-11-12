class_name GSAtlasMigration
extends RefCounted
## Temporary CPU-side checkpoint of live atlas data. The viewer alone commits ownership.
const CHUNK_BYTES := 240 * 32768
var entries: Array[Dictionary] = []
var path := ""
var error_message := ""
var cancelled := false
signal progress_changed(fraction: float)


func checkpoint(rasterizer: GaussianSplattingRasterizer, records: Dictionary, tree: SceneTree) -> Error:
	path = "user://atlas-migration-%d-%d.tmp" % [Time.get_ticks_usec(), get_instance_id()]
	var total:=0
	for record in records.values():
		if record.status=="loaded":total+=int(record.count)*GSConstants.SPLAT_STRUCT_BYTES
	var staged:=0
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file: return ERR_CANT_CREATE
	for record in records.values():
		if record.status != "loaded" or not is_instance_valid(record.node.get_ref()): continue
		var entry := {"model_id": record.node.get_ref().model_id, "count": record.count, "instance_id": record.instance_id, "file_offset": file.get_position()}
		entries.append(entry)
		var checksum := HashingContext.new()
		checksum.start(HashingContext.HASH_SHA256)
		var size := int(record.count) * GSConstants.SPLAT_STRUCT_BYTES
		var offset := 0
		while offset < size:
			if cancelled: return ERR_SKIP
			var amount := mini(CHUNK_BYTES, size - offset)
			var bytes: PackedByteArray = await _read_chunk(rasterizer,int(record.offset)+offset,amount,tree)
			if bytes.size() != amount: return ERR_FILE_CANT_READ
			file.store_buffer(bytes)
			checksum.update(bytes)
			if file.get_error() != OK: return ERR_FILE_CANT_WRITE
			offset += amount
			staged += amount
			progress_changed.emit(0.4*staged/maxi(1,total))
			await tree.process_frame
		entry["sha256"] = checksum.finish()
	file.close()
	# Verify the checkpoint before releasing any working GPU residency.
	file = FileAccess.open(path, FileAccess.READ)
	if not file:return ERR_FILE_CANT_READ
	for entry in entries:
		file.seek(entry.file_offset)
		var checksum := HashingContext.new()
		checksum.start(HashingContext.HASH_SHA256)
		var remaining := int(entry.count)*GSConstants.SPLAT_STRUCT_BYTES
		while remaining>0:
			if cancelled:return ERR_SKIP
			var amount:=mini(CHUNK_BYTES,remaining)
			var bytes:=file.get_buffer(amount)
			if bytes.size()!=amount:return ERR_FILE_CORRUPT
			checksum.update(bytes)
			remaining-=amount
			await tree.process_frame
		if checksum.finish()!=entry.sha256:return ERR_FILE_CORRUPT
	file.close()
	progress_changed.emit(0.6)
	return OK

func restore(target: GaussianSplattingRasterizer, records: Dictionary, tree: SceneTree, compact_ids: bool) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return {"error": ERR_CANT_OPEN}
	var mapping := {}
	var total:=0
	for entry in entries:total+=int(entry.count)*GSConstants.SPLAT_STRUCT_BYTES
	var uploaded:=0
	var next_id := 1
	for entry in entries:
		var live: Dictionary = {}
		for record in records.values():
			if is_instance_valid(record.node.get_ref()) and record.node.get_ref().model_id == entry.model_id: live = record; break
		if live.is_empty(): continue
		var size := int(entry.count) * GSConstants.SPLAT_STRUCT_BYTES
		var destination := target.allocator.allocate(size)
		var instance := next_id if compact_ids else int(entry.instance_id)
		if destination < 0 or instance > target.config.memory_max_instances: return {"error": ERR_OUT_OF_MEMORY}
		next_id += 1
		file.seek(entry.file_offset)
		var offset := 0
		while offset < size:
			if cancelled: return {"error": ERR_SKIP}
			var amount := mini(CHUNK_BYTES, size - offset)
			var bytes := file.get_buffer(amount)
			if bytes.size() != amount: return {"error": ERR_FILE_CORRUPT}
			if instance != int(entry.instance_id):
				for i in range(amount / GSConstants.SPLAT_STRUCT_BYTES): bytes.encode_float(i * GSConstants.SPLAT_STRUCT_BYTES + 44, float(instance))
			var result := target.upload_splat_data(bytes, destination + offset)
			if result != OK: return {"error": result}
			offset += amount
			uploaded+=amount
			progress_changed.emit(0.6+0.4*uploaded/maxi(1,total))
			await tree.process_frame
		mapping[entry.model_id] = {"offset": destination, "instance_id": instance}
	target._sync(func(): return OK)
	file.close()
	progress_changed.emit(1.0)
	return {"mapping": mapping}

func dispose() -> void:
	if not path.is_empty(): DirAccess.remove_absolute(path)
	path = ""
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not path.is_empty(): DirAccess.remove_absolute(path)

func _read_chunk(rasterizer:GaussianSplattingRasterizer,offset:int,size:int,tree:SceneTree)->PackedByteArray:
	var mutex:=Mutex.new()
	var ready:=[false]
	var received:=[PackedByteArray()]
	var callback:=func(bytes:PackedByteArray):
		mutex.lock()
		received[0]=bytes
		ready[0]=true
		mutex.unlock()
	var result:int=rasterizer._sync(func():return rasterizer.context.device.buffer_get_data_async(rasterizer.descriptors.splats.rid,callback,offset,size))
	if result!=OK:return PackedByteArray()
	while true:
		mutex.lock()
		var complete:bool=ready[0]
		mutex.unlock()
		if complete:return received[0]
		await tree.process_frame
	return PackedByteArray()
