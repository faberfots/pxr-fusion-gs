class_name GSTransparencyPass
extends RefCounted
## Owned by the existing rasterizer/context. Only render-thread methods touch RD.
var context: RenderingContext
var size := Vector2i.ZERO
var output := Texture2DRD.new()
var gather_shader := RID()
var merge_shader := RID()
var framebuffer := RID()
var pipeline := RID()
var merge_pipeline := RID()
var sampler := RID()
var linear_sampler := RID()
var white := RID()
var heads: RenderingContext.Descriptor
var fragments: RenderingContext.Descriptor
var meta: RenderingContext.Descriptor
var camera: RenderingContext.Descriptor
var grade: RenderingContext.Descriptor
var target: RenderingContext.Descriptor
var capacity := 0
var entries: Array[Dictionary] = []
var geometry := {}
var sets := {}
var _owned: Array[RID] = []
var ready_for_presentation:=false
var overflowed:=false
var _status:RenderingContext.Descriptor
var _pending:=false
var _generation:=0
var _mutex:=Mutex.new()
func own(rid: RID, type_name: String, bytes: int = 0) -> RID:
	context.deletion_queue.push(rid,type_name,bytes,"transparency")
	_owned.append(rid)
	return rid
func initialize(owner_context: RenderingContext, dimensions: Vector2i, free_bytes: int) -> Error:
	context=owner_context;size=dimensions
	var pixels:=size.x*size.y
	capacity=mini(pixels*8,maxi(0,(free_bytes-pixels*20-1048576)/32))
	if capacity<pixels:return ERR_OUT_OF_MEMORY
	var rd:=context.device
	gather_shader=context.load_shader("res://modules/gaussian_splatting/shaders/compute/alpha_gather.glsl")
	merge_shader=context.load_shader("res://modules/gaussian_splatting/shaders/compute/alpha_merge.glsl")
	if not gather_shader.is_valid() or not merge_shader.is_valid():return ERR_CANT_CREATE
	heads=context.create_storage_buffer(pixels*4,PackedByteArray(),0,"alpha_heads");_owned.append(heads.rid)
	fragments=context.create_storage_buffer(capacity*32,PackedByteArray(),0,"alpha_fragments");_owned.append(fragments.rid)
	meta=context.create_storage_buffer(16,PackedByteArray(),0,"alpha_counters");_owned.append(meta.rid)
	_status=context.create_storage_buffer(16,PackedByteArray(),0,"alpha_status");_owned.append(_status.rid)
	camera=context.create_uniform_buffer(128,PackedByteArray(),"alpha_camera");_owned.append(camera.rid)
	grade=context.create_uniform_buffer(48,PackedByteArray(),"alpha_grade");_owned.append(grade.rid)
	target=context.create_texture(size,RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT);_owned.append(target.rid)
	output.texture_rd_rid=target.rid
	rd.texture_clear(target.rid,Color.TRANSPARENT,0,1,0,1)
	framebuffer=own(rd.framebuffer_create_empty(size),"framebuffer")
	var raster:=RDPipelineRasterizationState.new();raster.cull_mode=RenderingDevice.POLYGON_CULL_DISABLED
	pipeline=own(rd.render_pipeline_create(gather_shader,rd.framebuffer_get_format(framebuffer),RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),RDPipelineColorBlendState.new()),"render_pipeline")
	merge_pipeline=own(rd.compute_pipeline_create(merge_shader,context.specialization_constants),"compute_pipeline")
	var state:=RDSamplerState.new()
	state.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR;state.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler=own(rd.sampler_create(state),"sampler")
	state.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE;state.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler=own(rd.sampler_create(state),"sampler")
	var white_format:=RDTextureFormat.new();white_format.width=1;white_format.height=1
	white_format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM;white_format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	white=own(rd.texture_create(white_format,RDTextureView.new(),[PackedByteArray([255,255,255,255])]),"texture",4)
	return OK if pipeline.is_valid() and merge_pipeline.is_valid() else ERR_CANT_CREATE
func uniform(binding: int, type: RenderingDevice.UniformType, ids: Array[RID]) -> RDUniform:
	var value:=RDUniform.new();value.binding=binding;value.uniform_type=type
	for id in ids:value.add_id(id)
	return value
func prepare(draws: Array[Dictionary], available_bytes: int) -> Error:
	var rd:=context.device
	var live_keys:Dictionary={}
	for draw in draws:live_keys[draw.key]=true
	var stale:=false
	for key in geometry.keys():
		if not live_keys.has(key):
			stale=true;var rid:RID=geometry[key].rid;context.deletion_queue.free_rid(rd,rid);_owned.erase(rid);geometry.erase(key)
	# Material textures may have changed while geometry remains stable.
	for key in sets.keys():
		if not str(key).begins_with("merge:") or stale:
			context.deletion_queue.free_rid(rd,sets[key]);_owned.erase(sets[key]);sets.erase(key)
	var needed:=0
	for draw in draws:
		if not geometry.has(draw.key):needed+=draw.vertices.size()
	if needed>available_bytes:return ERR_OUT_OF_MEMORY
	entries.clear()
	for draw in draws:
		if not geometry.has(draw.key):
			var buffer:=context.create_storage_buffer(draw.vertices.size(),draw.vertices,0,"alpha_geometry")
			if not buffer:return ERR_OUT_OF_MEMORY
			geometry[draw.key]=buffer;_owned.append(buffer.rid)
		var texture:RID=RenderingServer.texture_get_rd_texture(draw.texture.get_rid(),true) if draw.texture else white
		if not texture.is_valid():return ERR_CANT_CREATE
		var key:=str(draw.key)+":"+str(texture.get_id())
		if not sets.has(key):
			var uniforms:Array[RDUniform]=[
				uniform(0,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,[geometry[draw.key].rid]),
				uniform(1,RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,[camera.rid]),
				uniform(2,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,[heads.rid]),
				uniform(3,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,[fragments.rid]),
				uniform(4,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,[meta.rid]),
				uniform(5,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,[sampler,texture])]
			sets[key]=own(rd.uniform_set_create(uniforms,gather_shader,0),"descriptor_set")
		var entry:=draw.duplicate();entry["set"]=sets[key];entries.append(entry)
	return OK
func gather(view_projection: PackedByteArray) -> void:
	var rd:=context.device
	# Fill the linked-list sentinels without a CPU-sized temporary image.
	rd.buffer_clear(heads.rid,0,heads.size)
	rd.buffer_update(meta.rid,0,16,PackedInt32Array([0,0,capacity,0]).to_byte_array())
	rd.buffer_update(camera.rid,0,128,view_projection)
	var list:=rd.draw_list_begin(framebuffer)
	rd.draw_list_bind_render_pipeline(list,pipeline)
	for entry in entries:
		var bytes:=RenderingContext.pack_projection(Projection(entry.transform))
		bytes.append_array(PackedFloat32Array([entry.color.r,entry.color.g,entry.color.b,entry.color.a]).to_byte_array())
		bytes.append_array(PackedInt32Array([size.x,capacity,entry.cull,0]).to_byte_array())
		rd.draw_list_bind_uniform_set(list,entry["set"],0)
		rd.draw_list_set_push_constant(list,bytes,bytes.size())
		rd.draw_list_draw(list,false,1,entry.count)
	rd.draw_list_end()
func merge(rasterizer: GaussianSplattingRasterizer, depth: RID, colors: PackedByteArray) -> void:
	var rd:=context.device
	rd.buffer_update(grade.rid,0,48,colors)
	var names: Array[RenderingContext.Descriptor]=[rasterizer.descriptors.culled_splats,rasterizer.descriptors.sort_values,rasterizer.descriptors.tile_bounds,rasterizer.descriptors.tile_splat_pos,target,rasterizer.descriptors.histogram,rasterizer.descriptors.uniforms]
	var uniforms:Array[RDUniform]=[]
	for i in range(names.size()):uniforms.append(uniform(i,names[i].type,[names[i].rid]))
	uniforms.append(uniform(7,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,[rasterizer._sampler,depth]))
	uniforms.append(uniform(8,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,[heads.rid]))
	uniforms.append(uniform(9,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,[fragments.rid]))
	uniforms.append(uniform(10,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,[meta.rid]))
	uniforms.append(uniform(11,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,[linear_sampler,rasterizer.descriptors.render_texture.rid]))
	uniforms.append(uniform(12,RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,[grade.rid]))
	var key:="merge:"+str(depth.get_id())
	if not sets.has(key):
		for cached in sets.keys():
			if str(cached).begins_with("merge:"):
				context.deletion_queue.free_rid(rd,sets[cached]);_owned.erase(sets[cached]);sets.erase(cached)
		sets[key]=own(rd.uniform_set_create(uniforms,merge_shader,0),"descriptor_set")
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,merge_pipeline)
	rd.compute_list_bind_uniform_set(list,sets[key],0)
	rd.compute_list_dispatch(list,rasterizer.tile_dims.x,rasterizer.tile_dims.y,1)
	rd.compute_list_add_barrier(list);rd.compute_list_end()
	if not _pending:
		rd.buffer_copy(meta.rid,_status.rid,0,0,16);_pending=true
		if rd.buffer_get_data_async(_status.rid,_receive_status.bind(_generation),0,16)!=OK:_pending=false
func _receive_status(bytes:PackedByteArray,generation:int)->void:
	if generation!=_generation:return
	_mutex.lock();_pending=false
	if bytes.size()==16:
		overflowed=bytes.decode_u32(4)!=0
		if not overflowed:ready_for_presentation=true
	_mutex.unlock()
func presentation_status()->Vector2i:
	_mutex.lock();var status:=Vector2i(int(ready_for_presentation),int(overflowed));_mutex.unlock();return status
func cleanup() -> void:
	_generation+=1
	output.texture_rd_rid=RID()
	if context:
		for i in range(_owned.size()-1,-1,-1):context.deletion_queue.free_rid(context.device,_owned[i])
	_owned.clear();entries.clear();geometry.clear();sets.clear()
