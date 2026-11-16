class_name GSSceneImportJob
extends RefCounted
## Isolated native glTF parsing; scene generation/attachment stays on the main thread.
var _thread:Thread
var _mutex:=Mutex.new()
var _done:=false
var _cancelled:=false
var _result:Dictionary={}
var _document:GLTFDocument
var _state:GLTFState
var path:String
signal completed(result:Dictionary)
static func supports(value:String)->bool:return value.get_extension().to_lower() in ["glb","gltf"]
static func source_files(value:String)->Dictionary:
	var file:=FileAccess.open(value,FileAccess.READ)
	if not file:return {"error":"Cannot open mesh scene.","code":ERR_FILE_CANT_OPEN}
	var parser:=JSON.new();var text:String
	if value.get_extension().to_lower()=="glb":
		if file.get_length()<20 or file.get_32()!=0x46546c67 or file.get_32()!=2:return {"error":"Expected a glTF 2.0 GLB file.","code":ERR_FILE_CORRUPT}
		var size:=file.get_32();var amount:=file.get_32();var kind:=file.get_32()
		if size!=file.get_length() or kind!=0x4e4f534a or amount>size-20:return {"error":"Invalid GLB document length.","code":ERR_FILE_CORRUPT}
		text=file.get_buffer(amount).get_string_from_utf8()
	else:text=file.get_as_text()
	file.close()
	if parser.parse(text)!=OK or not parser.data is Dictionary:return {"error":"Invalid glTF JSON.","code":ERR_FILE_CORRUPT}
	var json:Dictionary=parser.data
	if not json.get("asset") is Dictionary or not str(json.asset.get("version","")).begins_with("2."):return {"error":"Expected glTF 2.0.","code":ERR_FILE_UNRECOGNIZED}
	var files:Array[String]=[ProjectSettings.globalize_path(value).simplify_path()]
	var portable:=true
	for category in ["buffers","images"]:
		if not json.get(category,[]) is Array:return {"error":"Invalid glTF dependency list.","code":ERR_FILE_CORRUPT}
		for item in json.get(category,[]):
			if not item is Dictionary or not item.get("uri","") is String:return {"error":"Invalid glTF dependency.","code":ERR_FILE_CORRUPT}
			var uri:String=item.get("uri","")
			if uri.is_empty() or uri.begins_with("data:"):continue
			if uri.contains("://"):return {"error":"Mesh dependencies must be local files.","code":ERR_UNAVAILABLE}
			var dependency:=uri.uri_decode()
			if dependency.is_absolute_path():portable=false
			if not dependency.is_absolute_path():dependency=files[0].get_base_dir().path_join(dependency).simplify_path()
			if not FileAccess.file_exists(dependency):return {"error":"Missing mesh dependency: "+uri,"code":ERR_FILE_NOT_FOUND}
			if not dependency in files:files.append(dependency)
	return {"files":files,"portable":portable}
func start(value:String)->Error:
	path=value;_thread=Thread.new();return _thread.start(_work)
func _work()->void:
	var result:=source_files(path)
	if not result.has("error"):
		var fingerprints:Array=[]
		for source in result.files:
			var file:=FileAccess.open(source,FileAccess.READ)
			if not file:result={"error":"Mesh dependency became unavailable.","code":ERR_FILE_CANT_READ};break
			fingerprints.append({"source":source,"bytes":file.get_length(),"sha256":FileAccess.get_sha256(source)});file.close()
		if not result.has("error") and not cancelled():
			_document=GLTFDocument.new();_state=GLTFState.new()
			var error:=_document.append_from_file(path,_state)
			if error!=OK:result={"error":"Godot could not import this glTF scene.","code":error}
			else:
				for item in fingerprints:
					if FileAccess.get_sha256(item.source)!=item.sha256:result={"error":"A mesh source changed during import.","code":ERR_FILE_CORRUPT};break
				if not result.has("error"):result={"fingerprints":fingerprints}
	_mutex.lock();_result=result;_done=true;_mutex.unlock()
func cancelled()->bool:
	_mutex.lock();var value:=_cancelled;_mutex.unlock();return value
func cancel()->void:_mutex.lock();_cancelled=true;_mutex.unlock()
func is_done()->bool:
	_mutex.lock();var value:=_done;_mutex.unlock();return value
func finish()->Dictionary:
	if _thread and _thread.is_started():_thread.wait_to_finish()
	_thread=null
	if cancelled():_document=null;_state=null;return {"error":"Mesh import cancelled.","code":ERR_SKIP}
	if _result.has("error"):return _result
	var root:=_document.generate_scene(_state)
	_document=null;_state=null
	if not root is Node3D:
		if root:root.free()
		return {"error":"The imported scene has no 3D root.","code":ERR_FILE_CORRUPT}
	return {"root":root,"fingerprints":_result.fingerprints}
func drain()->void:
	cancel()
	if _thread and _thread.is_started():_thread.wait_to_finish()
	_thread=null;_document=null;_state=null
