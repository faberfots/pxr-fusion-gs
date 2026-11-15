class_name CortexSegmentationService
extends Node
signal completed(result:Dictionary)
signal activity_changed(active:bool)
var _worker:CortexSegmentationWorker
var _serial:=0
var _accepted:=0
var last_result:Dictionary={}
func _ready()->void:set_process(false)
func request(image:Image,capture_id:String,settings:Dictionary,points:PackedVector2Array,labels:PackedInt32Array,text:String,rectangle:Rect2=Rect2(),has_box:bool=false,verify_only:bool=false)->Error:
	if is_busy():return ERR_BUSY
	if not verify_only and (not image or image.is_empty()):return ERR_INVALID_DATA
	if not _worker:_worker=CortexSegmentationWorker.new()
	_serial+=1;_accepted=_serial
	var request:={"id":_serial,"task":"verify" if verify_only else "segment","engine":settings.engine,"directory":settings.sam3_directory,"confidence":settings.confidence,"capture_id":capture_id,"image":image.duplicate() if image else null,"points":points.duplicate(),"labels":labels.duplicate(),"text":text,"rectangle":rectangle,"has_box":has_box}
	var error:=_worker.submit(request)
	if error==OK:set_process(true);activity_changed.emit(true)
	return error
func is_busy()->bool:return _worker!=null and _worker.status().busy
func preview(mask:PackedByteArray,dimensions:Vector2i,capture_id:String)->Error:
	if is_busy() or not _worker:return ERR_BUSY
	_serial+=1;_accepted=_serial
	var error:=_worker.submit({"id":_serial,"task":"preview","mask":mask,"size":dimensions,"capture_id":capture_id})
	if error==OK:set_process(true);activity_changed.emit(true)
	return error
func phase()->String:return _worker.status().phase if _worker else "Not initialized"
func cancel()->void:
	_accepted=0
	if _worker:_worker.cancel(_serial)
func release()->void:
	cancel()
	if _worker:_worker.shutdown();_worker=null
	set_process(false);last_result={};activity_changed.emit(false)
func _process(_delta:float)->void:
	if not _worker:set_process(false);return
	var result:=_worker.take_result()
	if result.is_empty():return
	activity_changed.emit(false)
	if int(result.request_id)==_accepted and not result.get("cancelled",false):last_result=result;completed.emit(result)
	if not _worker.status().busy:set_process(false)
func _exit_tree()->void:release()
