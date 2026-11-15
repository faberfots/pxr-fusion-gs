class_name CortexLocalRuntime
extends Node
## Explicit on-demand CPU server; a native Child handle owns process lifetime.
signal state_changed(message:String)
var policy:AIAccessPolicy
var _thread:Thread
var _mutex:=Mutex.new()
var _cancelled:=false
var _done:=false
var _result:Dictionary={}
var _host:Object
var _health:HTTPRequest
var _waiting:=false
var _deadline:=0
var _next_check:=0
var message:="Bundled Qwen is stopped; no inference process is running."
func _ready()->void:set_process(false)
func start_bundled()->Error:
	if not policy or not policy.configuration_enabled:return ERR_UNAUTHORIZED
	if _thread or _host:return ERR_BUSY
	if OS.get_name()!="Windows" or not OS.has_feature("x86_64") or not ClassDB.class_exists("CortexLocalModelHost"):return ERR_UNAVAILABLE
	_mutex.lock();_cancelled=false;_done=false;_result={};_mutex.unlock()
	_thread=Thread.new();var error:=_thread.start(_prepare)
	if error==OK:_set_message("Verifying bundled Qwen and CPU runtime…");set_process(true)
	else:_thread=null
	return error
func _stopping()->bool:
	_mutex.lock();var value:=_cancelled;_mutex.unlock();return value
func _prepare()->void:
	var data:Dictionary=CortexAssets.catalog().get("qwen",{})
	var result:Dictionary={}
	if data.is_empty() or data.get("runtime_files",[]).is_empty():result={"error":"The portable Qwen assets have not been installed."}
	else:
		var artifacts:Array=[data.model];artifacts.append_array(data.runtime_files)
		for artifact in artifacts:
			if _stopping():result={"error":"Local runtime startup cancelled."};break
			var path:=CortexAssets.resolve(artifact.path);var file:=FileAccess.open(path,FileAccess.READ)
			if not file or file.get_length()!=int(artifact.bytes):result={"error":"A bundled Qwen/runtime file is missing or has changed."};break
			var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
			while file.get_position()<file.get_length() and not _stopping():hash.update(file.get_buffer(4*1048576))
			file.close()
			if _stopping():result={"error":"Local runtime startup cancelled."};break
			if hash.finish().hex_encode()!=artifact.sha256:result={"error":"Bundled Qwen/runtime integrity check failed."};break
		if result.is_empty() and not _stopping():
			var host:Object=ClassDB.instantiate("CortexLocalModelHost")
			if host.call("start",CortexAssets.resolve(data.executable),CortexAssets.resolve(data.model.path)):result={"host":host}
			else:result={"error":host.call("get_last_error")}
	_mutex.lock();_result=result;_done=true;_mutex.unlock()
func _process(_delta:float)->void:
	if _thread:
		_mutex.lock();var done:=_done;_mutex.unlock()
		if not done:return
		_thread.wait_to_finish();_thread=null
		if _result.has("error"):_set_message(_result.error);set_process(false);return
		_host=_result.get("host");_result={}
		if not _host:_set_message("Local startup cancelled.");set_process(false);return
		_deadline=Time.get_ticks_msec()+90000;_next_check=0
		_set_message("Loading Qwen on CPU · loopback only · GPU offload disabled")
	if not _host:return
	if not _host.call("is_running"):_host=null;_set_message("Local runtime exited. Check the bundled files and whether port 18081 is already in use.");set_process(false);return
	if message.begins_with("Ready"):set_process(false);return
	if Time.get_ticks_msec()>_deadline:stop();_set_message("Local runtime did not become ready before the startup deadline.");return
	if not _waiting and Time.get_ticks_msec()>=_next_check:
		if not _health:
			_health=HTTPRequest.new();_health.timeout=2;_health.body_size_limit=65536;_health.max_redirects=0;add_child(_health);_health.request_completed.connect(_health_ready)
		_waiting=true;_next_check=Time.get_ticks_msec()+500
		if _health.request("http://127.0.0.1:18081/health")!=OK:_waiting=false
func _health_ready(result:int,status:int,_headers:PackedStringArray,_body:PackedByteArray)->void:
	_waiting=false
	if _host and _host.call("is_running") and result==HTTPRequest.RESULT_SUCCESS and status==200:_set_message("Ready · Qwen3 1.7B Q8 · CPU only · http://127.0.0.1:18081");set_process(false)
func is_running()->bool:return _host!=null and bool(_host.call("is_running"))
func is_starting()->bool:return _thread!=null or (_host!=null and not message.begins_with("Ready"))
func _set_message(value:String)->void:message=value;state_changed.emit(value)
func stop()->void:
	_mutex.lock();_cancelled=true;_mutex.unlock()
	if _thread:_thread.wait_to_finish();_thread=null
	if _result.has("host"):_result.host.call("stop")
	_result={}
	if _host:_host.call("stop");_host=null
	if _health:_health.cancel_request()
	_waiting=false;set_process(false);_set_message("Bundled Qwen stopped; process and memory released.")
func _exit_tree()->void:stop()
