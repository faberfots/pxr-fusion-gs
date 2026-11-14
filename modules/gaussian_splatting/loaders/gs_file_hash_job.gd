class_name GSFileHashJob
extends RefCounted
## Pure bounded CPU IO shared by source verification and checkpoint verification.
var _mutex:=Mutex.new()
var _cancelled:=false
var _done:=false
var _thread:Thread
var _result:Dictionary={}
func cancel()->void:
	_mutex.lock();_cancelled=true;_mutex.unlock()
func is_cancelled()->bool:
	_mutex.lock();var value:=_cancelled;_mutex.unlock();return value
func is_done()->bool:
	_mutex.lock();var value:=_done;_mutex.unlock();return value
func start(path:String,ranges:Array=[])->Error:
	_thread=Thread.new()
	return _thread.start(func():
		var result:=hash_file(path,ranges,is_cancelled)
		_mutex.lock();_result=result;_done=true;_mutex.unlock()
	)
func join()->Dictionary:
	if _thread and _thread.is_started():_thread.wait_to_finish()
	_thread=null
	_mutex.lock();var result:=_result.duplicate(true);_mutex.unlock();return result
static func hash_file(path:String,ranges:Array=[],stop:Callable=Callable())->Dictionary:
	var started:=Time.get_ticks_usec();var file:=FileAccess.open(path,FileAccess.READ)
	if not file:return {"error":"Cannot read file: "+path,"code":ERR_FILE_CANT_READ}
	var size:=file.get_length();var modified:=FileAccess.get_modified_time(path)
	var sections:Array=ranges if not ranges.is_empty() else [{"file_offset":0,"bytes":size}]
	var digests:Array[PackedByteArray]=[]
	for section in sections:
		var offset:=int(section.file_offset);var amount:=int(section.get("bytes",int(section.get("count",0))*240))
		if offset<0 or amount<0 or offset+amount>size:file.close();return {"error":"Invalid verification range","code":ERR_FILE_CORRUPT}
		file.seek(offset);var remaining:=amount;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
		while remaining>0:
			if stop.is_valid() and stop.call():file.close();return {"error":"Verification cancelled","code":ERR_SKIP}
			var data:=file.get_buffer(mini(4*1048576,remaining))
			if data.is_empty():file.close();return {"error":"File became unreadable","code":ERR_FILE_CANT_READ}
			hash.update(data);remaining-=data.size()
		digests.append(hash.finish())
	var changed:=file.get_length()!=size or FileAccess.get_modified_time(path)!=modified
	file.close()
	if changed:return {"error":"File changed during verification","code":ERR_FILE_CORRUPT}
	return {"bytes":size,"sha256":digests[0].hex_encode(),"digests":digests,"elapsed_us":Time.get_ticks_usec()-started}
