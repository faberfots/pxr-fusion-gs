class_name CortexModelPack
extends RefCounted
## A known, pinned package contract. External weights stay beside their ONNX graphs.
const MANIFEST="res://modules/spatial_intelligence/models/sam3-pack-manifest.json"
static func verify(directory:String,stop:Callable=Callable())->Dictionary:
	directory=CortexAssets.sam3_directory(directory)
	if not directory.is_absolute_path() or not DirAccess.dir_exists_absolute(directory):return {"error":"Choose the extracted SAM3 model folder."}
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(MANIFEST))!=OK or not parser.data is Dictionary:return {"error":"SAM3 package manifest is unavailable."}
	var root:=directory.simplify_path()
	for entry in parser.data.members:
		if stop.is_valid() and stop.call():return {"error":"Model verification cancelled."}
		var name:String=entry.path
		if name!=name.get_file():return {"error":"Unsafe model package member."}
		var path:=root.path_join(name);var file:=FileAccess.open(path,FileAccess.READ)
		if not file:return {"error":"Missing model package file: "+name}
		if file.get_length()!=int(entry.bytes):file.close();return {"error":"Model package file length differs: "+name}
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
		while file.get_position()<file.get_length():
			if stop.is_valid() and stop.call():file.close();return {"error":"Model verification cancelled."}
			hash.update(file.get_buffer(4*1048576))
		file.close()
		if hash.finish().hex_encode()!=entry.sha256:return {"error":"Model package SHA-256 differs: "+name}
	return {"directory":root,"version":"sam3_vit_h_20260220","upstream_revision":parser.data.provenance.upstream_revision,"execution":"CPU","verified":true}
