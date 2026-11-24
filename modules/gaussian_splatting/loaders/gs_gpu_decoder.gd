class_name GSGpuDecoder
extends RefCounted
## One worker-owned local RenderingDevice. No scene-tree or global-atlas access.
const BLOCK_BYTES=128*1048576
var device:RenderingDevice
var _shader:=RID()
var _pipeline:=RID()
var _input:=RID()
var _output:=RID()
var _parameters:=RID()
var _status:=RID()
var _summary:=RID()
var _times:=RID()
var _time_count:=0
var _set:=RID()
var _hash_shader:=RID()
var _hash_pipeline:=RID()
var _hash_output:=RID()
var _hash_input_set:=RID()
var _hash_output_set:=RID()
var capacity:=0
var properties:=0
var mode_binary:=false
var mapping:Dictionary={}
func initialize(count:int,property_count:int,schema:Dictionary,binary:bool=false)->bool:
	properties=property_count;mapping=schema;mode_binary=binary
	capacity=mini(count,int(BLOCK_BYTES/(maxi(properties,60)*4)))
	device=RenderingServer.create_local_rendering_device()
	if not device:return false
	var shader_file:=load("res://modules/gaussian_splatting/shaders/compute/gs_import.glsl") as RDShaderFile
	if not shader_file:cleanup();return false
	_shader=device.shader_create_from_spirv(shader_file.get_spirv())
	if not _shader.is_valid():cleanup();return false
	_pipeline=device.compute_pipeline_create(_shader)
	_input=device.storage_buffer_create(capacity*properties*4)
	_output=device.storage_buffer_create(capacity*240)
	_parameters=device.storage_buffer_create(72*4)
	_status=device.storage_buffer_create(4)
	_summary=device.storage_buffer_create(int(ceil(capacity/256.0))*48)
	_times=device.storage_buffer_create(16)
	var uniforms:Array[RDUniform]=[]
	var buffers:=[_input,_output,_parameters,_status,_summary,_times]
	for i in range(buffers.size()):
		if not buffers[i].is_valid():cleanup();return false
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=i;uniform.add_id(buffers[i]);uniforms.append(uniform)
	_set=device.uniform_set_create(uniforms,_shader,0)
	if not _pipeline.is_valid() or not _set.is_valid():cleanup();return false
	var hashing:=load("res://modules/gaussian_splatting/shaders/compute/gs_cache_sha256.glsl") as RDShaderFile
	if not hashing:cleanup();return false
	_hash_shader=device.shader_create_from_spirv(hashing.get_spirv());_hash_pipeline=device.compute_pipeline_create(_hash_shader)
	_hash_output=device.storage_buffer_create(int(ceil(capacity*240.0/GSPreparedCache.LEAF_BYTES))*32)
	var sets:Array[RID]=[]
	for source_buffer in [_input,_output]:
		var source_uniform:=RDUniform.new();source_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;source_uniform.binding=0;source_uniform.add_id(source_buffer)
		var hash_uniform:=RDUniform.new();hash_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;hash_uniform.binding=1;hash_uniform.add_id(_hash_output)
		var hash_uniforms:Array[RDUniform]=[source_uniform,hash_uniform]
		sets.append(device.uniform_set_create(hash_uniforms,_hash_shader,0))
	_hash_input_set=sets[0];_hash_output_set=sets[1]
	if not _hash_pipeline.is_valid() or not _hash_input_set.is_valid() or not _hash_output_set.is_valid():cleanup();return false
	return true
func set_time_spans(spans:Array)->bool:
	var data:=PackedByteArray();data.resize(maxi(1,spans.size())*16)
	var end:=0
	for i in range(spans.size()):
		var span:Dictionary=spans[i]
		if int(span.start)!=end or int(span.count)<1 or not is_finite(float(span.created)):return false
		data.encode_u32(i*16,end);end+=int(span.count);data.encode_u32(i*16+4,end);data.encode_float(i*16+8,span.created)
	device.free_rid(_set);device.free_rid(_times);_times=device.storage_buffer_create(data.size(),data);_time_count=spans.size()
	var uniforms:Array[RDUniform]=[];var buffers:=[_input,_output,_parameters,_status,_summary,_times]
	for i in range(buffers.size()):
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=i;uniform.add_id(buffers[i]);uniforms.append(uniform)
	_set=device.uniform_set_create(uniforms,_shader,0)
	return _set.is_valid()
func convert(values:PackedFloat32Array,count:int,instance:int,created:float,hash_mode:int=0,global_offset:int=0)->Dictionary:
	if not device or count<1 or count>capacity or values.size()!=count*properties:return {"error":"Invalid GPU conversion block"}
	var p:=PackedFloat32Array();p.resize(72)
	if not mode_binary:
		var names:=["x","y","z","sx","sy","sz","rw","rx","ry","rz","opacity"]
		for i in range(names.size()):p[i]=mapping[names[i]]
		for i in range(3):p[11+i]=mapping.dc[i];p[14+i]=mapping.rgb[i];p[23+i]=mapping.rgb_divisors[i]
		p[17]=1 if not -1 in mapping.dc else 0;p[18]=int(mapping.rest.size()/3)
		for i in range(mapping.rest.size()):p[26+i]=mapping.rest[i]
	p[19]=properties;p[20]=count;p[21]=instance;p[22]=created;p[71]=1 if mode_binary else 0
	if mode_binary and _time_count>0:p[17]=1;p[18]=_time_count
	var raw:=values.to_byte_array();var params:=p.to_byte_array()
	if mode_binary and _time_count>0:params.encode_u32(0,global_offset)
	if device.buffer_update(_input,0,raw.size(),raw)!=OK:return {"error":"GPU input transfer failed"}
	device.buffer_update(_parameters,0,params.size(),params);device.buffer_update(_status,0,4,PackedInt32Array([0]).to_byte_array())
	var list:=device.compute_list_begin();device.compute_list_bind_compute_pipeline(list,_pipeline);device.compute_list_bind_uniform_set(list,_set,0)
	var groups:=int(ceil(count/256.0));device.compute_list_dispatch(list,groups,1,1)
	if hash_mode!=0:
		device.compute_list_add_barrier(list)
		device.compute_list_bind_compute_pipeline(list,_hash_pipeline)
		device.compute_list_bind_uniform_set(list,_hash_input_set if hash_mode==1 else _hash_output_set,0)
		# The SHA shader declares exactly two uints. Godot 4.7 validates the
		# block's 8-byte size; extra padding prevents hashing from dispatching.
		device.compute_list_set_push_constant(list,PackedInt32Array([count*240,GSPreparedCache.LEAF_BYTES]).to_byte_array(),8)
		device.compute_list_dispatch(list,int(ceil(ceil(count*240.0/GSPreparedCache.LEAF_BYTES)/64.0)),1,1)
	device.compute_list_end()
	device.submit();device.sync()
	if device.buffer_get_data(_status,0,4).decode_u32(0)!=0:return {"error":"Invalid or non-finite Gaussian data"}
	var stats:=device.buffer_get_data(_summary,0,groups*48).to_float32_array()
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF);var sum:=Vector3.ZERO
	for i in range(groups):
		var base:=i*12
		low=low.min(Vector3(stats[base],stats[base+1],stats[base+2]));high=high.max(Vector3(stats[base+4],stats[base+5],stats[base+6]))
		sum+=Vector3(stats[base+8],stats[base+9],stats[base+10])
	return {"data":device.buffer_get_data(_output,0,count*240),"count":count,"aabb":AABB(low,high-low),"sum":sum,"cache_leaf_hashes":device.buffer_get_data(_hash_output,0,int(ceil(count*240.0/GSPreparedCache.LEAF_BYTES))*32) if hash_mode!=0 else PackedByteArray()}
func cleanup()->void:
	if not device:return
	for rid in [_hash_input_set,_hash_output_set,_hash_pipeline,_hash_output,_hash_shader,_set,_pipeline,_input,_output,_parameters,_status,_summary,_times,_shader]:
		if rid.is_valid():device.free_rid(rid)
	device.free();device=null
