class_name GSAtlasMigration
extends RefCounted
## Temporary CPU-side checkpoint of live atlas data. The viewer alone commits ownership.
const CHUNK_BYTES := 240 * 131072
var entries: Array[Dictionary] = []
var path := ""
var error_message := ""
var _writer:GSCheckpointWriter
var _verification:GSFileHashJob
var _disk_job:GSDiskCheckpointJob
var profile:Dictionary={}
var cancelled:=false:
	set(value):
		cancelled=value
		if value:
			if _writer:_writer.cancel()
			if _verification:_verification.cancel()
			if _disk_job:_disk_job.cancel()
signal progress_changed(fraction: float)



func checkpoint(rasterizer:GaussianSplattingRasterizer,records:Dictionary,tree:SceneTree)->Error:
	var started:=Time.get_ticks_usec()
	path="user://atlas-migration-%d-%d.tmp" % [started,get_instance_id()]
	var models:Array[Dictionary]=[]
	var can_reconstruct:=true
	for record in records.values():
		if record.status!="loaded" or not is_instance_valid(record.node.get_ref()):continue
		if record.get("prepared_reference",{}).is_empty() or record.get("runtime_spans",[]).is_empty():can_reconstruct=false;break
		models.append({"model_id":record.node.get_ref().model_id,"count":record.count,"instance_id":record.instance_id,"prepared_reference":record.prepared_reference.duplicate(),"runtime_spans":record.runtime_spans.duplicate(true)})
	if can_reconstruct and not models.is_empty():
		var scratch:=rasterizer.reserve_import_scratch()
		var disk:=GSDiskCheckpointJob.new();_disk_job=disk
		var launched:=disk.start(path,models,scratch)
		if launched==OK:
			while not disk.status().done:
				if cancelled:disk.cancel()
				await tree.process_frame
			var reconstructed:=disk.join();_disk_job=null
			rasterizer.release_import_scratch()
			if cancelled:return ERR_SKIP
			if not reconstructed.has("error"):
				entries.assign(reconstructed.entries)
				profile["backend"]="prepared_exact";profile["reconstruct_us"]=reconstructed.elapsed_us
				return await _verify(tree,started,int(reconstructed.bytes))
			profile["prepared_fallback_error"]=int(reconstructed.error)
		else:rasterizer.release_import_scratch();_disk_job=null
	# A missing, changed or corrupt preparation cache never removes raw GPU recovery.
	profile["backend"]="gpu_readback"
	var writer:=GSCheckpointWriter.new();_writer=writer
	var result:=writer.start(path)
	if result!=OK:return result
	var total:=0;var staged:=0
	for record in records.values():
		if record.status=="loaded":total+=int(record.count)*240
	for record in records.values():
		if record.status!="loaded" or not is_instance_valid(record.node.get_ref()):continue
		var index:=entries.size()
		entries.append({"model_id":record.node.get_ref().model_id,"count":record.count,"instance_id":record.instance_id,"file_offset":staged})
		var size:=int(record.count)*240;var offset:=0
		while offset<size:
			while not writer.can_accept() and not writer.status().done and not cancelled:await tree.process_frame
			if cancelled:writer.cancel();writer.join();return ERR_SKIP
			if writer.status().done:return writer.join().error
			var amount:=mini(CHUNK_BYTES,size-offset);var reading:=Time.get_ticks_usec()
			var bytes:PackedByteArray=await _read_chunk(rasterizer,int(record.offset)+offset,amount,tree)
			profile["readback_us"]=int(profile.get("readback_us",0))+Time.get_ticks_usec()-reading
			if cancelled:writer.cancel();writer.join();return ERR_SKIP
			if bytes.size()!=amount:writer.cancel();writer.join();return ERR_FILE_CANT_READ
			writer.push(bytes,index);offset+=amount;staged+=amount
			progress_changed.emit(0.4*staged/maxi(1,total))
	writer.close_input()
	while not writer.status().done:
		if cancelled:writer.cancel()
		await tree.process_frame
	var written:=writer.join();_writer=null
	if cancelled:return ERR_SKIP
	if written.error!=OK:return written.error
	if written.digests.size()!=entries.size():return ERR_FILE_CORRUPT
	for i in range(entries.size()):entries[i]["sha256"]=written.digests[i]
	return await _verify(tree,started,staged)

func _verify(tree:SceneTree,started:int,staged:int)->Error:
	# Verification is background IO, independent of rendering frame rate.
	var verifying:=Time.get_ticks_usec();var verification:=GSFileHashJob.new();_verification=verification
	var result:=verification.start(path,entries)
	if result!=OK:return result
	while not verification.is_done():
		if cancelled:verification.cancel()
		await tree.process_frame
	var checked:=verification.join();_verification=null
	if cancelled:return ERR_SKIP
	if checked.has("error"):return int(checked.get("code",ERR_FILE_CORRUPT))
	for i in range(entries.size()):
		if checked.digests[i]!=entries[i].sha256:return ERR_FILE_CORRUPT
	profile["verify_us"]=Time.get_ticks_usec()-verifying;profile["total_us"]=Time.get_ticks_usec()-started;profile["bytes"]=staged
	progress_changed.emit(0.6);return OK

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
		if destination < 0 or instance > target.config.memory_max_instances:
			file.close();return {"error": ERR_OUT_OF_MEMORY}
		next_id += 1
		file.seek(entry.file_offset)
		var offset := 0
		while offset < size:
			if cancelled:
				file.close();return {"error": ERR_SKIP}
			var amount := mini(CHUNK_BYTES, size - offset)
			var bytes := file.get_buffer(amount)
			if bytes.size() != amount:
				file.close();return {"error": ERR_FILE_CORRUPT}
			if instance != int(entry.instance_id):
				for i in range(amount / GSConstants.SPLAT_STRUCT_BYTES): bytes.encode_float(i * GSConstants.SPLAT_STRUCT_BYTES + 44, float(instance))
			var result := target.upload_splat_data(bytes, destination + offset)
			if result != OK:
				file.close();return {"error": result}
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
	cancelled=true
	if _writer:_writer.cancel();_writer.join();_writer=null
	if _verification:_verification.cancel();_verification.join();_verification=null
	if _disk_job:_disk_job.cancel();_disk_job.join();_disk_job=null
	if not path.is_empty(): DirAccess.remove_absolute(path)
	path = ""
func _notification(what: int) -> void:
	if what!=NOTIFICATION_PREDELETE:return
	if _writer:_writer.cancel();_writer.join()
	if _verification:_verification.cancel();_verification.join()
	if _disk_job:_disk_job.cancel();_disk_job.join()
	if not path.is_empty():DirAccess.remove_absolute(path)

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
		if cancelled:return PackedByteArray()
		mutex.lock()
		var complete:bool=ready[0]
		mutex.unlock()
		if complete:return received[0]
		await tree.process_frame
	return PackedByteArray()
