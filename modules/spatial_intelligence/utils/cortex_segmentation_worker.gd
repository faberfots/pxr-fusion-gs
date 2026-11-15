class_name CortexSegmentationWorker
extends RefCounted
## One persistent private inference owner. It sleeps when idle and never touches scene nodes.
var _thread:Thread
var _mutex:=Mutex.new()
var _wake:=Semaphore.new()
var _closing:=false
var _busy:=false
var _cancelled_through:=0
var _request:Dictionary={}
var _results:Array[Dictionary]=[]
var _phase:="Idle"
var _segmenter:Object
var _engine:=""
var _directory:=""
var _capture_id:=""
var _tokenizer:CortexClipTokenizer
var _mask_size:=Vector2i.ZERO
func submit(request:Dictionary)->Error:
	_mutex.lock()
	if _busy or _closing:_mutex.unlock();return ERR_BUSY
	_busy=true;_request=request.duplicate();_phase="Queued";_mutex.unlock()
	if not _thread:
		_thread=Thread.new()
		var error:=_thread.start(_run)
		if error!=OK:_thread=null;_mutex.lock();_busy=false;_mutex.unlock();return error
	_wake.post();return OK
func status()->Dictionary:
	_mutex.lock();var value:={"busy":_busy,"phase":_phase};_mutex.unlock();return value
func take_result()->Dictionary:
	_mutex.lock();var value:Dictionary=_results.pop_front() if not _results.is_empty() else {};_mutex.unlock();return value
func cancel(request_id:int)->void:
	_mutex.lock();_cancelled_through=maxi(_cancelled_through,request_id);_mutex.unlock()
func _cancelled(id:int)->bool:
	_mutex.lock();var value:=_closing or id<=_cancelled_through;_mutex.unlock();return value
func _set_phase(value:String)->void:
	_mutex.lock();_phase=value;_mutex.unlock()
func shutdown()->void:
	_mutex.lock();_closing=true;_mutex.unlock();_wake.post()
	if _thread and _thread.is_started():_thread.wait_to_finish()
	_thread=null
func _run()->void:
	while true:
		_wake.wait();_mutex.lock();var closing:=_closing;var request:=_request;_request={};_mutex.unlock()
		if closing:break
		if request.is_empty():continue
		var started:=Time.get_ticks_usec();var result:=_execute(request)
		if result.get("masks",[]).size()>0 and not _cancelled(request.id):
			_set_phase("Preparing mask preview")
			result.merge(_preview(result.masks[0],result.size))
		result["request_id"]=request.id;result["elapsed_ms"]=(Time.get_ticks_usec()-started)/1000.0
		if _cancelled(request.id):result={"cancelled":true,"request_id":request.id}
		_mutex.lock();_busy=false;_phase="Idle";_results.append(result);_mutex.unlock()
	_segmenter=null;_tokenizer=null
func _execute(request:Dictionary)->Dictionary:
	if _cancelled(request.id):return {}
	if request.task=="preview":
		var rendered:=_preview(request.mask,request.size);rendered["capture_id"]=request.capture_id;rendered["preview_only"]=true;return rendered
	if _engine!=request.engine or _directory!=request.directory or not _segmenter:
		_segmenter=null;_capture_id="";_engine="";_directory=""
		_set_phase("Verifying local artifacts")
		if request.engine=="mobile_sam":
			if not NativeMLBridge.availability().available:return {"error":NativeMLBridge.availability().reason}
			_segmenter=NativeMLBridge.load_default_segmenter()
		else:
			if not ClassDB.class_exists("Sam3Segmenter"):return {"error":"The Cortex native build with SAM3 support is required."}
			var verified:=CortexModelPack.verify(request.directory,func():return _cancelled(request.id))
			if verified.has("error"):return verified
			if _cancelled(request.id):return {}
			var artifacts:Dictionary=NativeMLBridge.artifact_manifest().get("artifacts",{})
			if not artifacts.has("windows_runtime"):return {"error":"Verified ONNX Runtime is unavailable."}
			var runtime:=NativeMLBridge.materialize_runtime(artifacts.windows_runtime)
			if runtime.is_empty():return {"error":"ONNX Runtime integrity check failed."}
			_set_phase("Initializing SAM3 CPU sessions")
			_segmenter=ClassDB.instantiate("Sam3Segmenter")
			if not _segmenter.call("load_model_with_runtime",verified.directory,runtime):
				var message:=str(_segmenter.call("get_last_error"));_segmenter=null;return {"error":"SAM3 initialization failed: "+message}
			_tokenizer=CortexClipTokenizer.new()
			if not _tokenizer.initialize():_segmenter=null;return {"error":_tokenizer.error}
		if not _segmenter:return {"error":"The local segmentation engine could not initialize."}
		_engine=request.engine;_directory=request.directory
	if request.task=="verify":return {"initialized":true,"engine":_engine,"message":"CPU engine initialized; run a capture to verify image inference."}
	if _cancelled(request.id):return {}
	if _capture_id!=request.capture_id:
		_set_phase("Encoding captured image on CPU")
		if not _segmenter.call("encode_image",request.image):return {"error":"Image encoding failed."}
		_capture_id=request.capture_id;_mask_size=request.image.get_size()
	if _cancelled(request.id):return {}
	_set_phase("Decoding segmentation prompt")
	if _engine=="mobile_sam":
		if request.points.is_empty():return {"error":"Add a foreground point to the captured image."}
		var mask:PackedByteArray=_segmenter.call("segment_with_points",request.points,request.labels)
		if mask.size()!=_mask_size.x*_mask_size.y:return {"error":"MobileSAM returned an invalid mask."}
		return {"masks":[mask],"scores":PackedFloat32Array(),"size":_mask_size,"engine":_engine,"capture_id":_capture_id}
	var tokens:=_tokenizer.encode(request.text)
	if tokens.is_empty():return {"error":_tokenizer.error}
	var result:Dictionary=_segmenter.call("segment_with_tokens",tokens,request.rectangle,request.has_box,request.confidence)
	result["engine"]=_engine;result["capture_id"]=_capture_id;return result
func _preview(mask:PackedByteArray,dimensions:Vector2i)->Dictionary:
	if dimensions.x<1 or dimensions.y<1 or mask.size()!=dimensions.x*dimensions.y:return {"error":"Invalid mask dimensions."}
	var rgba:=PackedByteArray();rgba.resize(mask.size()*4)
	for i in range(mask.size()):
		if mask[i]>0:rgba.encode_u32(i*4,0xff3636e6)
	var point:=Vector2.INF;var middle:=int(mask.size()/2)
	for distance in range(mask.size()):
		var index:=middle+int(ceil(distance/2.0))*(1 if distance%2==0 else -1)
		if index>=0 and index<mask.size() and mask[index]>0:point=Vector2(index%dimensions.x,int(index/dimensions.x));break
	return {"preview":Image.create_from_data(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8,rgba),"probe_point":point}
