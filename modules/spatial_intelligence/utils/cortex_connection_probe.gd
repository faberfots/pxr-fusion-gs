class_name CortexConnectionProbe
extends Node
## Explicit, cancellable model discovery. No screenshot/context or credentials in results.
signal completed(result:Dictionary)
var policy:AIAccessPolicy
var _request:HTTPRequest
var _generation:=0
var _profile:Dictionary={}
func discover(profile:Dictionary)->void:
	cancel();_profile=profile.duplicate(true)
	if not policy or not policy.allows_connection(_profile):completed.emit({"error":"Enable transmission to this destination before testing."});return
	if not CortexProviders.valid_endpoint(_profile.provider,_profile.endpoint):completed.emit({"error":"Invalid connection endpoint."});return
	var secret:=CortexCredentials.resolve(_profile)
	if secret.is_empty() and _profile.credential_source!="none":completed.emit({"error":"Configure a credential for this connection first."});return
	var headers:=PackedStringArray(["Content-Type: application/json"])
	match CortexProviders.protocol(_profile):
		"google":headers.append("x-goog-api-key: "+secret)
		"anthropic":headers.append("x-api-key: "+secret);headers.append("anthropic-version: 2023-06-01")
		_:
			if not secret.is_empty():headers.append("Authorization: Bearer "+secret)
	_request=HTTPRequest.new();_request.timeout=_profile.timeout;_request.body_size_limit=2097152;_request.max_redirects=0;add_child(_request)
	_request.request_completed.connect(_receive.bind(_generation))
	var error:=_request.request(_profile.endpoint+"/models",headers)
	if error!=OK:completed.emit({"error":"Connection test could not start: "+error_string(error)})
func _receive(result:int,status:int,_headers:PackedStringArray,body:PackedByteArray,generation:int)->void:
	if generation!=_generation:return
	if not policy or not policy.allows_connection(_profile):completed.emit({"error":"Transmission consent was withdrawn."});return
	if result!=HTTPRequest.RESULT_SUCCESS or status<200 or status>=300:completed.emit({"error":"Connection test failed (transport %d, HTTP %d)."%[result,status]});return
	var parser:=JSON.new()
	if parser.parse(body.get_string_from_utf8())!=OK or not parser.data is Dictionary:completed.emit({"error":"Model catalog is not a valid JSON object."});return
	var entries:Variant=parser.data.get("models",[]) if _profile.provider=="google" else parser.data.get("data",[])
	if not entries is Array or entries.size()>10000:completed.emit({"error":"Unsupported model catalog."});return
	var models:Array[String]=[]
	for entry in entries:
		if entry is Dictionary:
			var name:Variant=entry.get("name" if _profile.provider=="google" else "id","")
			if name is String and not name.is_empty() and name.length()<=200 and not models.has(name):models.append(name)
	models.sort();completed.emit({"models":models,"connection":_profile.id,"status":"Catalog verified; inference and capabilities require their own test."})
func cancel()->void:
	_generation+=1
	if is_instance_valid(_request):_request.cancel_request();_request.queue_free()
	_request=null
func _exit_tree()->void:cancel()
