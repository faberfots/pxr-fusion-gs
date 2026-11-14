class_name GSPreparedCache
extends RefCounted
## Rebuildable local data. Sources and viewer/atlas ownership never move into the cache.
const VERSION=1
const LEAF_BYTES=8192
const OWNER="PXRFusion prepared GS cache v1"
const DEFAULT_ROOT="user://gs-prepared-cache-v1"
static var _guard:=Mutex.new()
static var _leases:Dictionary={}
var directory:=DEFAULT_ROOT
var budget_bytes:=8192*1048576
var _file:FileAccess
var _temporary:=""
var _chunks:Array=[]
var _written:=0
var _key:=""
var _leased:=""
var write_error:=""
static func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
static func hex_key(value:Variant,length:int)->bool:
	if not value is String or value.length()!=length:return false
	return RegEx.create_from_string("^[0-9a-f]+$").search(value)!=null

func index_path(source:String)->String:
	return directory.path_join(digest(ProjectSettings.globalize_path(source).simplify_path().to_utf8_buffer())+".json")
func candidate(source:String,count:int,size:int)->Dictionary:
	_guard.lock()
	var result:=_candidate(source,count,size)
	if not result.is_empty():
		_leased=result.key;_leases[_leased]=int(_leases.get(_leased,0))+1
	_guard.unlock()
	return result
func _candidate(source:String,count:int,size:int)->Dictionary:
	if not FileAccess.file_exists(directory.path_join(".owner")) or FileAccess.get_file_as_string(directory.path_join(".owner"))!=OWNER:return {}
	var path:=index_path(source)
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file or file.get_length()>80*1048576:return {}
	var meta:Variant=JSON.parse_string(file.get_as_text());file.close()
	if not meta is Dictionary or meta.get("version")!=VERSION or meta.get("stride")!=240 or meta.get("count")!=count or meta.get("source_bytes")!=size:return {}
	if not hex_key(meta.get("key"),32) or not hex_key(meta.get("source_sha256"),64):return {}
	if not meta.get("chunks") is Array or not meta.get("samples") is Array or meta.samples.size()>8192:return {}
	if not meta.get("bounds") is Array or meta.bounds.size()!=6 or not meta.get("sum") is Array or meta.sum.size()!=3:return {}
	for value in meta.bounds+meta.sum:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(value):return {}
	for i in range(3,6):
		if meta.bounds[i]<0:return {}
	var total:=0
	for chunk in meta.chunks:
		if not chunk is Dictionary:return {}
		if typeof(chunk.get("count")) not in [TYPE_INT,TYPE_FLOAT] or chunk.count!=floor(chunk.count) or chunk.count<1 or chunk.count>131072:return {}
		var length:=64 if chunk.get("hash_kind","sha256")=="sha256" else ceili(float(chunk.count)*240.0/(8192 if chunk.get("hash_kind")=="sha256-8k" else 32768))*64
		if chunk.get("hash_kind","sha256") not in ["sha256","sha256-32k","sha256-8k"] or not hex_key(chunk.get("sha256"),length):return {}
		total+=int(chunk.count)
	if total!=count:return {}
	for point in meta.samples:
		if not point is Array or point.size()!=3:return {}
		for value in point:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(value):return {}
	var payload:=directory.path_join(meta.key+".bin")
	file=FileAccess.open(payload,FileAccess.READ)
	if not file or file.get_length()!=count*240:return {}
	file.close()
	var used:=FileAccess.open(directory.path_join(meta.key+".use"),FileAccess.WRITE)
	if used:used.store_8(1);used.close()
	meta["payload"]=payload
	return meta
func payload_reference(source:String,count:int,fingerprint:Dictionary)->Dictionary:
	return {"source":source,"directory":directory,"key":_key,"count":count,"bytes":fingerprint.bytes,"sha256":fingerprint.sha256}
static func hold(reference:Dictionary)->GSPreparedCache:
	if not hex_key(reference.get("key"),32):return null
	var cache:=GSPreparedCache.new();cache.directory=reference.directory;cache._leased=reference.key
	_guard.lock();_leases[reference.key]=int(_leases.get(reference.key,0))+1;_guard.unlock();return cache
func release()->void:
	if _leased.is_empty():return
	_guard.lock()
	var remaining:=int(_leases.get(_leased,1))-1
	if remaining>0:_leases[_leased]=remaining
	else:_leases.erase(_leased)
	_guard.unlock();_leased=""
func begin()->void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK:return
	var marker:=directory.path_join(".owner")
	if not FileAccess.file_exists(marker):
		var existing:=DirAccess.open(directory)
		if not existing or not existing.get_files().is_empty():write_error="Cache directory is not owned by this application";return
		var owner:=FileAccess.open(marker,FileAccess.WRITE)
		if not owner:return
		owner.store_string(OWNER);owner.close()
	elif FileAccess.get_file_as_string(marker)!=OWNER:write_error="Cache owner marker is invalid";return
	_key=Crypto.new().generate_random_bytes(16).hex_encode()
	_temporary=directory.path_join(_key+".tmp")
	_file=FileAccess.open(_temporary,FileAccess.WRITE)
	if not _file:write_error="Cache is not writable"
func append(data:PackedByteArray,leaves:PackedByteArray=PackedByteArray())->void:
	if not _file:return
	if _written+data.size()>budget_bytes:write_error="Prepared file exceeds the local cache quota";abort();return
	_file.store_buffer(data)
	if _file.get_error()!=OK:write_error="Cache write failed";abort();return
	_chunks.append({"count":int(data.size()/240),"hash_kind":"sha256-8k" if not leaves.is_empty() else "sha256","sha256":leaves.hex_encode() if not leaves.is_empty() else digest(data)})
	_written+=data.size()
static func verify(data:PackedByteArray,entry:Dictionary)->bool:
	if entry.get("hash_kind","sha256")=="sha256":return digest(data)==entry.sha256
	var leaves:="";var amount:=LEAF_BYTES if entry.get("hash_kind")=="sha256-8k" else 32768
	for offset in range(0,data.size(),amount):leaves+=digest(data.slice(offset,mini(data.size(),offset+amount)))
	return leaves==entry.sha256
func commit(source:String,count:int,fingerprint:Dictionary,bounds:AABB,sum:Vector3,samples:PackedVector3Array)->bool:
	if not _file:return false
	_file.flush();var error:=_file.get_error();_file.close();_file=null
	if error!=OK or _written!=count*240:abort();return false
	var points:Array=[]
	for sample in samples:points.append([sample.x,sample.y,sample.z])
	var meta:Dictionary={"version":VERSION,"stride":240,"key":_key,"count":count,"source_bytes":fingerprint.bytes,"source_sha256":fingerprint.sha256,"chunks":_chunks,"bounds":[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z],"sum":[sum.x,sum.y,sum.z],"samples":points}
	var index:=index_path(source);var staging:=index+"-"+_key+".tmp"
	var file:=FileAccess.open(staging,FileAccess.WRITE)
	if not file:abort();return false
	file.store_string(JSON.stringify(meta,"",true,true));file.flush();error=file.get_error();file.close()
	_guard.lock()
	var payload:=directory.path_join(_key+".bin")
	if error==OK:error=DirAccess.rename_absolute(ProjectSettings.globalize_path(_temporary),ProjectSettings.globalize_path(payload))
	if error==OK:error=DirAccess.rename_absolute(ProjectSettings.globalize_path(staging),ProjectSettings.globalize_path(index))
	if error!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staging));DirAccess.remove_absolute(ProjectSettings.globalize_path(payload))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_temporary))
	_guard.unlock()
	_temporary=""
	if error!=OK:abort();return false
	evict()
	return true
func evict()->void:
	_guard.lock()
	if FileAccess.get_file_as_string(directory.path_join(".owner"))!=OWNER:_guard.unlock();return
	var folder:=DirAccess.open(directory)
	if not folder:_guard.unlock();return
	var entries:Array=[];var total:=0
	for name in folder.get_files():
		if name.ends_with(".bin") and hex_key(name.trim_suffix(".bin"),32):
			var path:=directory.path_join(name);var file:=FileAccess.open(path,FileAccess.READ)
			if not file:continue
			var size:=file.get_length();file.close();total+=size
			entries.append({"path":path,"key":name.trim_suffix(".bin"),"bytes":size,"modified":maxi(FileAccess.get_modified_time(path),FileAccess.get_modified_time(directory.path_join(name.trim_suffix(".bin")+".use")))})
	entries.sort_custom(func(a,b):return a.modified<b.modified)
	for entry in entries:
		if total<=budget_bytes:break
		if entry.key==_key or _leases.has(entry.key):continue
		# Only validated cache-owned basenames are candidates for eviction.
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(entry.path))==OK:total-=int(entry.bytes)
	_guard.unlock()
func abort()->void:
	if _file:_file.close();_file=null
	if not _temporary.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(_temporary))
	_temporary=""
func _notification(what:int)->void:
	if what!=NOTIFICATION_PREDELETE:return
	# RefCounted is already at zero references here; inline cleanup avoids rebinding self.
	if _file:_file.close()
	if not _temporary.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(_temporary))
	if not _leased.is_empty():
		_guard.lock()
		var remaining:=int(_leases.get(_leased,1))-1
		if remaining>0:_leases[_leased]=remaining
		else:_leases.erase(_leased)
		_guard.unlock()
