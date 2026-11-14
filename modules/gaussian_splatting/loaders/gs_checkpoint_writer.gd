class_name GSCheckpointWriter
extends RefCounted
## Two-block disk/hash queue. The worker owns its file; callers retain GPU ownership.
var _mutex:=Mutex.new()
var _wake:=Semaphore.new()
var _queue:Array[Dictionary]=[]
var _closing:=false
var _cancelled:=false
var _done:=false
var _error:int=OK
var _digests:Array[PackedByteArray]=[]
var _thread:Thread
func start(path:String)->Error:
	_thread=Thread.new();return _thread.start(_run.bind(path))
func can_accept()->bool:
	_mutex.lock();var value:=_queue.size()<2 and not _done and not _cancelled;_mutex.unlock();return value
func push(data:PackedByteArray,entry:int)->void:
	_mutex.lock();_queue.append({"data":data,"entry":entry});_mutex.unlock();_wake.post()
func close_input()->void:
	_mutex.lock();_closing=true;_mutex.unlock();_wake.post()
func cancel()->void:
	_mutex.lock();_cancelled=true;_queue.clear();_mutex.unlock();_wake.post()
func status()->Dictionary:
	_mutex.lock();var result:={"done":_done,"error":_error};_mutex.unlock();return result
func join()->Dictionary:
	if _thread and _thread.is_started():_thread.wait_to_finish()
	_thread=null
	return {"error":_error,"digests":_digests}
func _run(path:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if not file:_end(ERR_CANT_CREATE);return
	var hash:HashingContext;var current:=-1
	while true:
		_wake.wait();_mutex.lock()
		var stopped:=_cancelled;var finished:=_closing and _queue.is_empty()
		var item:Dictionary={} if _queue.is_empty() else _queue.pop_front()
		_mutex.unlock()
		if stopped:file.close();_end(ERR_SKIP);return
		if finished:break
		if item.is_empty():continue
		if int(item.entry)!=current:
			if hash:_digests.append(hash.finish())
			hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);current=int(item.entry)
		file.store_buffer(item.data);hash.update(item.data)
		if file.get_error()!=OK:var error:=file.get_error();file.close();_end(error);return
	if hash:_digests.append(hash.finish())
	file.flush();var error:=file.get_error();file.close();_end(error)
func _end(error:int)->void:
	_mutex.lock();_error=error;_done=true;_mutex.unlock()
