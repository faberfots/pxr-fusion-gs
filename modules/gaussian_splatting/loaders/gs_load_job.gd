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
var chunk_size := GSConstants.DEFAULT_LOADING_BATCH_SIZE
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
var _source_fingerprint:Dictionary={}
var _prepared_reference:Dictionary={}
var _runtime_spans:Array[Dictionary]=[]
var _source_modified:=0
var _started_us:=0
var _profile:Dictionary={}
var gpu_enabled:=false
var gpu_block_splats:=GSConstants.DEFAULT_LOADING_BATCH_SIZE
var cpu_workers:=2
var staging_budget_mb:=256
var gpu_scratch_bytes:=0
var _gpu:GSGpuDecoder
var cache_enabled:=true
var cache_directory:=GSPreparedCache.DEFAULT_ROOT
var cache_budget_mb:=8192
var _cache:GSPreparedCache
var _hash_thread:Thread
var _hash_started:=false
var _hash_error:=""


func measure(stage:String,elapsed:int)->void:
	_mutex.lock();_profile[stage]=int(_profile.get(stage,0))+elapsed;_mutex.unlock()

func start() -> Error:
	_started_us=Time.get_ticks_usec()
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
	var snapshot := {"done": _done, "empty": _queue.is_empty(), "error": _error, "cancelled": _cancelled, "aabb": _bounds, "sum": _sum, "samples": _samples.duplicate() if _done else PackedVector3Array(), "source_fingerprint":_source_fingerprint.duplicate(),"profile":_profile.duplicate(),"prepared_reference":_prepared_reference.duplicate() if _done else {},"runtime_spans":_runtime_spans.duplicate(true) if _done else []}
	_mutex.unlock()
	return snapshot

func join() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null

func _publish(chunk: Dictionary) -> bool:
	var waiting:=Time.get_ticks_usec()
	_available.wait()
	measure("queue_wait_us",Time.get_ticks_usec()-waiting)
	if is_cancelled():
		return false
	_mutex.lock()
	if chunk.get("reset",false):_runtime_spans.clear()
	elif not chunk.data.is_empty():
		var created:float=chunk.data.decode_float(12)
		if not _runtime_spans.is_empty() and int(_runtime_spans.back().start)+int(_runtime_spans.back().count)==int(chunk.start) and _runtime_spans.back().created==created:_runtime_spans.back().count+=int(chunk.count)
		else:_runtime_spans.append({"start":int(chunk.start),"count":int(chunk.count),"created":created})
	_profile["chunks"]=int(_profile.get("chunks",0))+1
	_profile["bytes"]=int(_profile.get("bytes",0))+chunk.data.size()
	_queue.append(chunk)
	_mutex.unlock()
	return true

func _finish(message:String="")->void:
	if _gpu:_gpu.cleanup();_gpu=null
	if _hash_thread:
		_hash_thread.wait_to_finish();_hash_thread=null
	if message.is_empty() and not is_cancelled():
		if _hash_started:message=_hash_error
		else:
			var hashing:=Time.get_ticks_usec();message=_fingerprint_source();measure("source_hash_us",Time.get_ticks_usec()-hashing)
	if message.is_empty() and not is_cancelled() and FileAccess.get_modified_time(path)!=_source_modified:message="Original source changed during import"
	if _cache:
		if message.is_empty() and not is_cancelled() and not _source_fingerprint.is_empty():
			var caching:=Time.get_ticks_usec()
			var written:=_cache.commit(path,expected_count,_source_fingerprint,_bounds,_sum,_samples)
			if written:_prepared_reference=_cache.payload_reference(path,expected_count,_source_fingerprint)
			_mutex.lock();_profile["cache_written"]=written;_profile["cache_write_error"]=_cache.write_error;_mutex.unlock()
			measure("cache_commit_us",Time.get_ticks_usec()-caching)
		else:_cache.abort()
		_cache.release();_cache.evict()
	_mutex.lock()
	_profile["preparation_work_us"]=int(_profile.get("pack_us",0))+int(_profile.get("parallel_pack_work_us",0))+int(_profile.get("gpu_convert_us",0))+int(_profile.get("gpu_validate_patch_us",0))+int(_profile.get("binary_validate_patch_us",0))
	_profile["worker_wall_us"]=Time.get_ticks_usec()-_started_us
	_error=message;_done=true
	_mutex.unlock()
func _hash_background()->void:
	var started:=Time.get_ticks_usec()
	_hash_error=_fingerprint_source()
	measure("source_hash_us",Time.get_ticks_usec()-started)

func _fingerprint_source()->String:
	var result:=GSFileHashJob.hash_file(path,[],is_cancelled)
	if result.has("error"):return result.error
	if FileAccess.get_modified_time(path)!=_source_modified:return "Original source changed during import"
	_mutex.lock();_source_fingerprint={"bytes":result.bytes,"sha256":result.sha256};_mutex.unlock()
	return ""

func _produce()->void:
	_source_modified=FileAccess.get_modified_time(path)
	_hash_started=true;_hash_thread=Thread.new()
	if _hash_thread.start(_hash_background)!=OK:_hash_thread=null;_hash_started=false
	if cache_enabled and path.get_extension().to_lower()!="gsres":
		_cache=GSPreparedCache.new();_cache.directory=cache_directory;_cache.budget_bytes=cache_budget_mb*1048576
		var source:=FileAccess.open(path,FileAccess.READ)
		var size:=source.get_length() if source else 0
		if source:source.close()
		var cached:=_cache.candidate(path,expected_count,size)
		if not cached.is_empty():
			if _produce_cached(cached):_finish();return
			if is_cancelled():_finish("Load cancelled");return
			_mutex.lock();_bounds=AABB();_sum=Vector3.ZERO;_samples.clear();_profile["cache_rejected"]=true;_mutex.unlock()
			if not _publish({"reset":true,"data":PackedByteArray(),"start":0,"count":0}):_finish("Load cancelled");return
		_cache.begin()
	_produce_source()
func _initialize_decoder(properties:int,mapping:Dictionary,binary:bool=false)->void:
	if _gpu:_gpu.cleanup();_gpu=null
	var cpu_request:=chunk_size
	if gpu_enabled and expected_count>=4096:chunk_size=gpu_block_splats
	# Conservative ownership budget: producer tasks, finished blocks and render queue.
	chunk_size=mini(chunk_size,maxi(100,int(staging_budget_mb*1048576.0/(maxi(properties,60)*4*10))))
	if gpu_enabled and expected_count>=4096 and gpu_scratch_bytes>1048576:
		chunk_size=mini(chunk_size,maxi(100,int((gpu_scratch_bytes-4096)*0.9/(4.0*(properties+60)+0.1875))))
		_gpu=GSGpuDecoder.new()
		if not _gpu.initialize(chunk_size,properties,mapping,binary):_gpu=null
		else:chunk_size=mini(chunk_size,_gpu.capacity)
	if not _gpu and not binary:chunk_size=mini(cpu_request,maxi(100,int(staging_budget_mb*1048576.0/(maxi(properties,60)*4*(8+cpu_workers*2)))))
	_mutex.lock();_profile["backend"]="glsl" if _gpu else "gdscript_parallel";_profile["block_splats"]=chunk_size;_profile["cpu_workers"]=cpu_workers;_mutex.unlock()
func _produce_source()->void:
	if path.get_extension().to_lower()=="gsres":_produce_binary();return
	var ply:=PlyFile.new()
	if ply.parse(path,max_vertices)!=OK:_finish(ply.error_message);return
	if ply.size!=expected_count:_finish("Source changed after load admission");return
	var mapping:=ply.document.gaussian_mapping()
	_initialize_decoder(ply.properties.size(),mapping)
	var file:=ply.document.open_reader()
	if not file:_finish("Source could not be opened");return
	var error:=""
	if _gpu:
		var offset:=0
		while offset<expected_count and not is_cancelled():
			var reading:=Time.get_ticks_usec()
			var chunk:=ply.document.read_vertices(file,mini(chunk_size,expected_count-offset),false)
			measure("read_validate_us",Time.get_ticks_usec()-reading)
			if chunk.has("error"):error=chunk.error;break
			var count:=int(chunk.values.size()/ply.properties.size());var packing:=Time.get_ticks_usec()
			var converted:=_gpu.convert(chunk.values,count,instance_id,Time.get_ticks_msec()*0.001,2 if _cache else 0)
			measure("gpu_convert_us",Time.get_ticks_usec()-packing)
			if converted.has("error"):error=converted.error;break
			if not _ingest(converted,chunk.values,ply,offset):break
			offset+=count
	else:error=_produce_parallel(file,ply)
	file.close();_finish(error)
func _produce_parallel(file:FileAccess,ply:PlyFile)->String:
	var pending:Array[Dictionary]=[];var offset:=0;var error:=""
	var mapping:=ply.document.gaussian_mapping()
	while (offset<expected_count or not pending.is_empty()) and not is_cancelled() and error.is_empty():
		while offset<expected_count and pending.size()<cpu_workers and not is_cancelled():
			var reading:=Time.get_ticks_usec()
			var chunk:=ply.document.read_vertices(file,mini(chunk_size,expected_count-offset),false)
			measure("read_validate_us",Time.get_ticks_usec()-reading)
			if chunk.has("error"):error=chunk.error;break
			var slot:Dictionary={"values":chunk.values,"offset":offset,"result":{},"elapsed":0,"task":0}
			var values:PackedFloat32Array=chunk.values;var created:=Time.get_ticks_msec()*0.001
			slot.task=WorkerThreadPool.add_task(func():
				var started:=Time.get_ticks_usec()
				slot.result=PlyFile.validated_pack(values,ply.properties.size(),mapping,instance_id,created)
				slot.elapsed=Time.get_ticks_usec()-started
			)
			pending.append(slot);offset+=int(values.size()/ply.properties.size())
		if not error.is_empty() or pending.is_empty():break
		var slot:Dictionary=pending.pop_front()
		WorkerThreadPool.wait_for_task_completion(slot.task);measure("parallel_pack_work_us",int(slot.elapsed))
		if slot.result.has("error"):error=slot.result.error;break
		if not _ingest(slot.result,slot.values,ply,int(slot.offset)):break
	for slot in pending:WorkerThreadPool.wait_for_task_completion(slot.task)
	return error
func _ingest(converted:Dictionary,values:PackedFloat32Array,ply:PlyFile,offset:int)->bool:
	var sampling:=Time.get_ticks_usec();var mapping:=ply.document.gaussian_mapping()
	var sample_stride:=maxi(1,ceili(float(expected_count)/8192.0))
	var samples:=PackedVector3Array()
	var first_sample:=int((offset+sample_stride-1)/sample_stride)*sample_stride
	for index in range(first_sample,offset+int(converted.count),sample_stride):
		var base:=(index-offset)*ply.properties.size()
		samples.append(Vector3(values[base+mapping.x],values[base+mapping.y],values[base+mapping.z]))
	_mutex.lock()
	_bounds=converted.aabb if offset==0 else _bounds.merge(converted.aabb);_sum+=converted.sum
	for sample in samples:
		if _samples.size()<8192:_samples.append(sample)
	_mutex.unlock();measure("bounds_samples_us",Time.get_ticks_usec()-sampling)
	if _cache:
		var caching:=Time.get_ticks_usec();_cache.append(converted.data,converted.get("cache_leaf_hashes",PackedByteArray()));measure("cache_write_us",Time.get_ticks_usec()-caching)
	return _publish({"data":converted.data,"start":offset,"count":converted.count})

func _produce_binary() -> void:
	var meta := GaussianSplatResource.inspect_file(path, max_vertices)
	if meta.has("error") or int(meta.get("vertex_count", 0)) != expected_count:
		_finish(meta.get("error", "Source changed after load admission"))
		return
	_initialize_decoder(60,{},true)
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
		var converted:=_prepared_block(data,count,offset)
		if converted.has("error"):_finish(converted.error);return
		data=converted.data
		first=false
		if not _publish({"data": data, "start": offset, "count": count}):
			break
		offset += count
	if not is_cancelled() and hashing.finish() != meta.checksum:
		_finish("Binary splat checksum mismatch")
		return
	_finish()

func _prepared_block(data:PackedByteArray,count:int,offset:int,hash_input:bool=false)->Dictionary:
	var processing:=Time.get_ticks_usec()
	var values:=data.to_float32_array()
	if _gpu and count<=_gpu.capacity:
		var converted:=_gpu.convert(values,count,instance_id,Time.get_ticks_msec()*0.001,1 if hash_input else 0)
		if converted.has("error"):return converted
		var samples:=PackedVector3Array();var stride:=maxi(1,ceili(float(expected_count)/8192.0))
		for index in range(int((offset+stride-1)/stride)*stride,offset+count,stride):
			var base:=(index-offset)*60;samples.append(Vector3(values[base],values[base+1],values[base+2]))
		_mutex.lock();_bounds=converted.aabb if offset==0 else _bounds.merge(converted.aabb);_sum+=converted.sum
		for sample in samples:
			if _samples.size()<8192:_samples.append(sample)
		_mutex.unlock();measure("gpu_validate_patch_us",Time.get_ticks_usec()-processing)
		return converted
	for value in values:
		if not is_finite(value):return {"error":"Non-finite binary splat value"}
	var bounds:=AABB();var sum:=Vector3.ZERO;var samples:=PackedVector3Array()
	var stride:=maxi(1,ceili(float(expected_count)/8192.0))
	var created:=Time.get_ticks_msec()*0.001
	for i in range(count):
		var base:=i*GSConstants.SPLAT_STRUCT_FLOATS
		var position:=Vector3(values[base],values[base+1],values[base+2])
		if values[base+10]<0.0 or values[base+10]>1.0:return {"error":"Invalid binary opacity"}
		data.encode_float(i*GSConstants.SPLAT_STRUCT_BYTES+44,float(instance_id))
		data.encode_float(i*GSConstants.SPLAT_STRUCT_BYTES+12,created)
		bounds=AABB(position,Vector3.ZERO) if i==0 else bounds.expand(position)
		sum+=position
		if (offset+i)%stride==0:samples.append(position)
	_mutex.lock()
	_bounds=bounds if offset==0 else _bounds.merge(bounds);_sum+=sum
	for sample in samples:
		if _samples.size()<8192:_samples.append(sample)
	_mutex.unlock()
	measure("binary_validate_patch_us",Time.get_ticks_usec()-processing)
	return {"data":data}
func _produce_cached(meta:Dictionary)->bool:
	var file:=FileAccess.open(meta.payload,FileAccess.READ)
	if not file:return false
	_initialize_decoder(60,{},true)
	var offset:=0
	for entry in meta.chunks:
		if is_cancelled():file.close();return false
		var count:=int(entry.count);var data:=file.get_buffer(count*240)
		if data.size()!=count*240:file.close();return false
		if entry.get("hash_kind","")=="sha256-8k" and _gpu and count<=_gpu.capacity:
			var converted:=_prepared_block(data,count,offset,true)
			if converted.has("error") or converted.cache_leaf_hashes.hex_encode()!=entry.sha256:file.close();return false
			if not _publish({"data":converted.data,"start":offset,"count":count}):file.close();return false
			offset+=count;continue
		if not GSPreparedCache.verify(data,entry):file.close();return false
		var local:=0
		while local<count:
			var amount:=mini(chunk_size,count-local)
			var piece:=data.slice(local*240,(local+amount)*240)
			var converted:=_prepared_block(piece,amount,offset)
			if converted.has("error"):file.close();return false
			if not _publish({"data":converted.data,"start":offset,"count":amount}):file.close();return false
			local+=amount;offset+=amount
	file.close()
	if _hash_thread:_hash_thread.wait_to_finish();_hash_thread=null
	if not _hash_error.is_empty() or _source_fingerprint.get("sha256","")!=meta.source_sha256:return false
	_prepared_reference={"source":path,"directory":cache_directory,"key":meta.key,"count":expected_count,"bytes":_source_fingerprint.bytes,"sha256":meta.source_sha256}
	_mutex.lock();_profile["cache_hit"]=true;_mutex.unlock()
	return true
