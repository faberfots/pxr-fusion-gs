class_name CortexSettings
extends RefCounted
## Single owner of non-secret profiles. Views edit validated copies and commit atomically.
signal changed(revision:int)
signal experience_changed
const PATH := "user://cortex/settings.json"
const VERSION := 1
var revision := 0
var last_error := ""
var storage_path := PATH
var _document:Dictionary={}
var _experience:Dictionary={"version":1,"preset":CortexPresets.DEFAULT,"help_open":false}
func _init(path:String=PATH)->void:
	storage_path=path
	var profiles:Array=[]
	for provider in CortexProviders.DEFINITIONS:profiles.append(CortexProviders.profile(provider))
	var legacy:=CortexProviders.canonical(str(ProjectSettings.get_setting("spatial_intelligence/provider","openai")))
	if not CortexProviders.DEFINITIONS.has(legacy):legacy="openai"
	for item in profiles:
		if item.id==legacy:
			item.model=str(ProjectSettings.get_setting("spatial_intelligence/model_name","gpt-4o" if legacy=="openai" else ""))
			item.vision=true;item.include_image=true;item.tools=true
			# The old shared override is bound to this initial provider only.
			if not OS.get_environment("GS_AI_API_KEY").is_empty():item.environment="GS_AI_API_KEY"
	_document={"version":VERSION,"active":legacy,"profiles":profiles,"segmentation":{"engine":"mobile_sam","sam3_directory":"bundle://sam3","confidence":0.5,"mask_opacity":0.45}}
	if FileAccess.file_exists(storage_path):_load()
	# UI intent has its own small file so older qualified apps can still read settings.json.
	if segmentation().engine=="sam3":_experience.preset="find"
	_load_experience()
func experience()->Dictionary:return _experience.duplicate(true)
func experience_path()->String:return storage_path.get_base_dir().path_join("experience.json")
func update_experience(preset:String,help_open:bool)->Error:
	if preset not in CortexPresets.ORDER:return ERR_INVALID_PARAMETER
	var value:={"version":1,"preset":preset,"help_open":help_open}
	if value==_experience:return OK
	var path:=experience_path();var folder:=ProjectSettings.globalize_path(path).get_base_dir()
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return ERR_CANT_CREATE
	var temporary:=path+".%d.tmp"%Time.get_ticks_usec()
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if not file:return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify(value));file.flush();var error:=file.get_error();file.close()
	if error==OK:error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))
	if error!=OK:DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));return error
	_experience=value;experience_changed.emit();return OK
func _load_experience()->void:
	var file:=FileAccess.open(experience_path(),FileAccess.READ)
	if not file or file.get_length()>4096:return
	var parser:=JSON.new();var error:=parser.parse(file.get_as_text());file.close()
	if error!=OK or not parser.data is Dictionary:return
	var value:Dictionary=parser.data
	if value.size()!=3 or value.get("version")!=1 or value.get("preset") not in CortexPresets.ORDER or not value.get("help_open") is bool:return
	value.version=1
	_experience=value
func vision_request_settings()->Dictionary:
	var result:=segmentation();var preset:=CortexPresets.definition(_experience.preset)
	if preset.kind=="segment":
		result.engine=preset.engine
	return result
func analysis_profile()->Dictionary:
	var preset:=CortexPresets.definition(_experience.preset)
	var result:=active()
	if preset.kind=="private":
		result=profile("qwen")
		if result.is_empty():result=CortexProviders.profile("qwen")
		result.provider="qwen";result.endpoint=CortexProviders.DEFINITIONS.qwen.endpoint;result.model="qwen-local"
		result.credential_source="none";result.environment="";result.vision=false;result.include_image=false;result.scope=preset.scope
		result.max_tokens=mini(int(result.max_tokens),512)
	if preset.kind in ["private","connected"]:result.tools=false
	return result
func snapshot()->Dictionary:return _document.duplicate(true)
func active()->Dictionary:
	for profile in _document.profiles:
		if profile.id==_document.active:return profile.duplicate(true)
	return {}
func profile(id:String)->Dictionary:
	for item in _document.profiles:
		if item.id==id:return item.duplicate(true)
	return {}
func segmentation()->Dictionary:return _document.segmentation.duplicate(true)
func select(id:String)->Error:
	if profile(id).is_empty():return ERR_DOES_NOT_EXIST
	var next:=snapshot();next.active=id;return commit(next)
func update_profile(value:Dictionary)->Error:
	var next:=snapshot()
	for i in range(next.profiles.size()):
		if next.profiles[i].id==value.get("id"):
			next.profiles[i]=value.duplicate(true);return commit(next)
	return ERR_DOES_NOT_EXIST
func update_segmentation(value:Dictionary)->Error:
	var next:=snapshot();next.segmentation=value.duplicate(true);return commit(next)
func add_profile(provider:String)->Error:
	if not CortexProviders.DEFINITIONS.has(provider):return ERR_INVALID_PARAMETER
	var next:=snapshot();var value:=CortexProviders.profile(provider)
	value.id="profile_"+Crypto.new().generate_random_bytes(8).hex_encode();value.name=CortexProviders.DEFINITIONS[provider].label+" connection"
	next.profiles.append(value);next.active=value.id;return commit(next)
func commit(value:Dictionary)->Error:
	last_error=validate(value)
	if not last_error.is_empty():return ERR_INVALID_DATA
	var folder:=ProjectSettings.globalize_path(storage_path).get_base_dir()
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:last_error="Settings directory is unavailable.";return ERR_CANT_CREATE
	var temporary:=storage_path+"-"+Crypto.new().generate_random_bytes(8).hex_encode()+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if not file:last_error="Settings could not be written.";return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify(value,"\t",true,true));file.flush();var error:=file.get_error();file.close()
	if error==OK:error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(storage_path))
	if error!=OK:DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));last_error="Previous settings were preserved.";return error
	_document=normalize(value);revision+=1;changed.emit(revision);return OK
func _load()->void:
	var file:=FileAccess.open(storage_path,FileAccess.READ)
	if not file or file.get_length()>262144:last_error="Saved Cortex settings are invalid.";return
	var parsed:=JSON.new();var error:=parsed.parse(file.get_as_text());file.close()
	if error!=OK or not parsed.data is Dictionary:last_error="Saved Cortex settings are invalid.";return
	last_error=validate(parsed.data)
	if last_error.is_empty():
		_document=normalize(parsed.data)
		# Add new built-in connections in memory; startup still never writes preferences.
		if profile("qwen").is_empty() and _document.profiles.size()<32:_document.profiles.append(CortexProviders.profile("qwen"))
static func normalize(value:Dictionary)->Dictionary:
	var result:=value.duplicate(true)
	result.version=VERSION
	result.segmentation.confidence=float(result.segmentation.confidence);result.segmentation.mask_opacity=float(result.segmentation.mask_opacity)
	for item in result.profiles:
		item.max_tokens=int(item.max_tokens);item.response_limit_mb=int(item.response_limit_mb)
		item.temperature=float(item.temperature);item.timeout=float(item.timeout)
	return result
static func validate(value:Dictionary)->String:
	if value.keys().size()!=4 or value.get("version")!=VERSION or not value.get("active") is String or not value.get("profiles") is Array or not value.get("segmentation") is Dictionary:return "Unsupported Cortex settings document."
	if value.profiles.is_empty() or value.profiles.size()>32:return "Use between 1 and 32 connections."
	var identities:Dictionary={}
	for item in value.profiles:
		if not item is Dictionary:return "Invalid connection."
		var fields:=CortexProviders.profile("compatible").keys()
		if item.size()!=fields.size():return "Connection contains unknown or secret fields."
		for field in fields:
			if not item.has(field):return "Incomplete connection."
		for field in ["id","name","provider","endpoint","model","credential_source","environment","scope"]:
			if not item[field] is String or item[field].length()>2048:return "Invalid connection text."
		if not RegEx.create_from_string("^[a-zA-Z0-9_-]{1,80}$").search(item.id) or identities.has(item.id):return "Connection identities must be unique."
		identities[item.id]=true
		if item.name.strip_edges().is_empty() or item.name.length()>100:return "Enter a connection name."
		if not CortexProviders.valid_endpoint(item.provider,item.endpoint):return "Use the provider's official endpoint, HTTPS, or a loopback HTTP endpoint."
		if item.model.length()>200 or RegEx.create_from_string("[\\s\\x00-\\x1f]").search(item.model):return "Invalid model identifier."
		if item.credential_source not in ["session","environment","vault","none"]:return "Invalid credential source."
		if item.credential_source=="none" and not CortexProviders.loopback(item.endpoint):return "Remote connections require a credential source."
		if not item.environment.is_empty() and not RegEx.create_from_string("^[A-Z_][A-Z0-9_]{0,127}$").search(item.environment):return "Invalid environment-variable name."
		for field in ["vision","tools","include_image","temperature_enabled"]:
			if not item[field] is bool:return "Invalid connection capability."
		if item.include_image and not item.vision:return "Image input requires a vision-capable model."
		if item.scope not in ["visible","selected"]:return "Invalid scene scope."
		for field in ["max_tokens","timeout","temperature","response_limit_mb"]:
			if typeof(item[field]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(item[field]):return "Invalid numeric connection setting."
		if item.max_tokens!=floor(item.max_tokens) or item.max_tokens<16 or item.max_tokens>32768 or item.timeout<1 or item.timeout>180 or item.temperature<0 or item.temperature>2 or item.response_limit_mb!=floor(item.response_limit_mb) or item.response_limit_mb<1 or item.response_limit_mb>8:return "Connection setting is outside its supported range."
	if not identities.has(value.active):return "Active connection is unavailable."
	var segment:Dictionary=value.segmentation
	if segment.size()!=4 or segment.get("engine") not in ["mobile_sam","sam3"] or not segment.get("sam3_directory") is String or segment.sam3_directory.length()>4096:return "Invalid segmentation settings."
	for field in ["confidence","mask_opacity"]:
		if typeof(segment.get(field)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(segment[field]) or segment[field]<0 or segment[field]>1:return "Invalid segmentation threshold."
	return ""
