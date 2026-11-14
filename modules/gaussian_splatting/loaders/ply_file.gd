class_name PlyFile
extends Resource
## PLY metadata and pure CPU conversion. PLYDocument owns the format contract.
var size := 0
var properties: Array[StringName] = []
var file_path := ""
var data_offset := 0
var bytes_per_vertex := 0
var aabb := AABB()
var document: PLYDocument
var error_message := ""

func _init(path: String = "") -> void:
	if not path.is_empty():
		parse(path)

func parse(path: String, max_vertices: int = 50000000, _legacy_max_file_bytes: int = 0) -> Error:
	document = PLYDocument.new()
	var result := document.parse(path, max_vertices)
	error_message = document.error_message
	if result != OK:
		return result
	result = document.validate_gaussians()
	error_message = document.error_message
	if result != OK:
		return result
	size = document.vertex_count
	file_path = path
	data_offset = document.data_offset
	bytes_per_vertex = document.stride_bytes
	properties.clear()
	for property in document.properties:
		properties.append(StringName(property.name))
	return OK

func get_vertex(index: int) -> Dictionary:
	if not document or index < 0 or index >= size:
		return {}
	var file := document.open_reader()
	if document.format_name == "ascii":
		for _i in range(index):
			file.get_line()
	else:
		file.seek(data_offset + index * bytes_per_vertex)
	var chunk := document.read_vertices(file, 1)
	if chunk.has("error"):
		return {}
	var vertex := {}
	for i in range(properties.size()):
		vertex[properties[i]] = chunk.values[i]
	return vertex

func is_valid() -> bool:
	return document != null and size > 0 and error_message.is_empty()

static func pack_chunk(values:PackedFloat32Array,property_count:int,mapping:Dictionary,instance_id:int,creation_time:float=-2.0,collect_y_samples:bool=true)->Dictionary:
	var count:=int(values.size()/property_count)
	var packed:=PackedFloat32Array();packed.resize(count*GSConstants.SPLAT_STRUCT_FLOATS)
	var bounds:=AABB();var sum:=Vector3.ZERO;var ys:=PackedFloat32Array()
	# Resolve schema once per block; no dictionaries or temporary arrays in the row loop.
	var px:int=mapping.x;var py:int=mapping.y;var pz:int=mapping.z
	var sx:int=mapping.sx;var sy:int=mapping.sy;var sz:int=mapping.sz
	var rw:int=mapping.rw;var rx:int=mapping.rx;var ry:int=mapping.ry;var rz:int=mapping.rz
	var opacity:int=mapping.opacity
	var dc:=PackedInt32Array(mapping.dc);var rgb:=PackedInt32Array(mapping.rgb)
	var divisors:=PackedFloat64Array(mapping.rgb_divisors);var rest:=PackedInt32Array(mapping.rest)
	var has_dc:=not -1 in dc;var coefficients:=int(rest.size()/3)
	for i in range(count):
		var v:=i*property_count;var b:=i*GSConstants.SPLAT_STRUCT_FLOATS
		var position:=Vector3(values[v+px],values[v+py],values[v+pz])
		var scales:=Vector3(values[v+sx],values[v+sy],values[v+sz])
		if scales.x>44.0 or scales.y>44.0 or scales.z>44.0:return {"error":"Gaussian covariance exceeds float32 representation"}
		var q:=Quaternion(values[v+rx],values[v+ry],values[v+rz],values[v+rw])
		if q.length_squared()<0.00000001:return {"error":"Gaussian rotation is a zero quaternion"}
		var matrix:=Basis(q.normalized())*Basis.from_scale(Vector3(exp(scales.x),exp(scales.y),exp(scales.z)))
		var cov:=matrix*matrix.transposed()
		packed[b]=position.x;packed[b+1]=position.y;packed[b+2]=position.z;packed[b+3]=creation_time
		packed[b+4]=cov.x.x;packed[b+5]=cov.y.x;packed[b+6]=cov.z.x
		packed[b+7]=cov.y.y;packed[b+8]=cov.z.y;packed[b+9]=cov.z.z
		packed[b+10]=1.0/(1.0+exp(-clampf(values[v+opacity],-80.0,80.0)))
		packed[b+11]=float(instance_id)
		if has_dc:
			packed[b+12]=values[v+dc[0]];packed[b+13]=values[v+dc[1]];packed[b+14]=values[v+dc[2]]
		else:
			for channel in range(3):packed[b+12+channel]=(clampf(values[v+rgb[channel]]/divisors[channel],0.0,1.0)-0.5)/0.28209479177387814
		for coefficient in range(coefficients):
			var out:=b+15+coefficient*3
			packed[out]=values[v+rest[coefficient]]
			packed[out+1]=values[v+rest[coefficients+coefficient]]
			packed[out+2]=values[v+rest[coefficients*2+coefficient]]
		bounds=AABB(position,Vector3.ZERO) if i==0 else bounds.expand(position)
		sum+=position
		if collect_y_samples and i%16==0:ys.append(position.y)
	return {"data":packed.to_byte_array(),"count":count,"aabb":bounds,"sum":sum,"y_samples":ys}

static func validated_pack(values:PackedFloat32Array,property_count:int,mapping:Dictionary,instance_id:int,created:float)->Dictionary:
	for value in values:
		if not is_finite(value):return {"error":"PLY contains non-finite or unrepresentable values"}
	return pack_chunk(values,property_count,mapping,instance_id,created,false)
