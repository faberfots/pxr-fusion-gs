class_name GSShadowPass
extends RefCounted
## Directional opacity-shadow cache, borrowing the atlas/sort scratch from its owner.
var context:RenderingContext
var resolution:=0
var projection_shader:=RID()
var render_shader:=RID()
var projection_pipeline:=RID()
var render_pipeline:=RID()
var receive_shader:=RID()
var receive_pipeline:=RID()
var receive_parameters:RenderingContext.Descriptor
var receive_sets:Array[RID]=[]
var bounds:RenderingContext.Descriptor
var flags:RenderingContext.Descriptor
var status:RenderingContext.Descriptor
var maps:Array[RID]=[]
var textures:Array[Texture2DRD]=[]
var projection_set:=RID()
var boundary_set:=RID()
var render_sets:Array[RID]=[]
var active_index:=-1
var active:Dictionary={}
var pending:=false
var completed_signature:=0
var _staging:=0
var _owned:Array[RID]=[]
var _mutex:=Mutex.new()
var _generation:=0
var failed_signature:=0
func own(rid:RID,kind:String,bytes:int=0)->RID:
	context.deletion_queue.push(rid,kind,bytes,"gaussian_shadow");_owned.append(rid);return rid
func initialize(renderer:GaussianSplattingRasterizer,width:int)->Error:
	context=renderer.context;resolution=width
	var rd:=context.device
	var bytes:=width*width*16*8*2+((width+renderer.config.tile_size-1)/renderer.config.tile_size)**2*8+(renderer.config.memory_max_instances+1)*4+176
	if bytes>renderer.config.memory_max_vram_budget_mb*1048576-context.deletion_queue.get_tracked_memory():return ERR_OUT_OF_MEMORY
	if width*16>rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D):return ERR_PARAMETER_RANGE_ERROR
	projection_shader=context.load_shader("res://modules/gaussian_splatting/shaders/compute/gs_shadow_projection.glsl",renderer.config)
	render_shader=context.load_shader("res://modules/gaussian_splatting/shaders/compute/gs_shadow_render.glsl",renderer.config)
	if not projection_shader.is_valid() or not render_shader.is_valid():return ERR_CANT_CREATE
	receive_shader=context.load_shader("res://modules/gaussian_splatting/shaders/compute/gs_shadow_receive.glsl")
	if not receive_shader.is_valid():return ERR_CANT_CREATE
	receive_pipeline=own(rd.compute_pipeline_create(receive_shader),"compute_pipeline")
	receive_parameters=context.create_uniform_buffer(160,PackedByteArray(),"shadow_receive_parameters");_owned.append(receive_parameters.rid)
	var grid:=(width+renderer.config.tile_size-1)/renderer.config.tile_size
	bounds=context.create_storage_buffer(grid*grid*8,PackedByteArray(),0,"shadow_tile_ranges");_owned.append(bounds.rid)
	flags=context.create_storage_buffer((renderer.config.memory_max_instances+1)*4,PackedByteArray(),0,"shadow_model_flags");_owned.append(flags.rid)
	status=context.create_storage_buffer(16,PackedByteArray(),0,"shadow_status");_owned.append(status.rid)
	var format:=RDTextureFormat.new();format.width=width*16;format.height=width;format.format=RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	for i in range(2):
		var rid:=own(rd.texture_create(format,RDTextureView.new()),"texture",width*width*16*8)
		if not rid.is_valid():return ERR_OUT_OF_MEMORY
		maps.append(rid)
		var texture:=Texture2DRD.new();texture.texture_rd_rid=rid;textures.append(texture)
	projection_pipeline=own(rd.compute_pipeline_create(projection_shader,context.specialization_constants),"compute_pipeline")
	render_pipeline=own(rd.compute_pipeline_create(render_shader,context.specialization_constants),"compute_pipeline")
	var d:=renderer.descriptors
	projection_set=context.create_descriptor_set([d.splats,d.culled_splats,d.histogram,d.sort_keys,d.sort_values,d.grid_dimensions,d.uniforms,d.instance_transforms,flags],projection_shader);_owned.append(projection_set)
	boundary_set=context.create_descriptor_set([d.histogram,d.sort_keys,bounds],renderer.shaders.gsplat_boundaries);_owned.append(boundary_set)
	for rid in maps:
		var target:=RenderingContext.Descriptor.new(rid,RenderingDevice.UNIFORM_TYPE_IMAGE)
		var set:=context.create_descriptor_set([d.culled_splats,d.sort_values,bounds,target,d.histogram,d.uniforms],render_shader)
		render_sets.append(set);_owned.append(set)
	for rid in maps:
		var texture_uniform:=RDUniform.new();texture_uniform.binding=2;texture_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		texture_uniform.add_id(renderer._sampler);texture_uniform.add_id(rid)
		var uniforms:Array[RDUniform]=[]
		for i in range(2):
			var u:=RDUniform.new();u.binding=i;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id([d.culled_splats.rid,flags.rid][i]);uniforms.append(u)
		uniforms.append(texture_uniform)
		var parameters:=RDUniform.new();parameters.binding=3;parameters.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER;parameters.add_id(receive_parameters.rid);uniforms.append(parameters)
		receive_sets.append(own(rd.uniform_set_create(uniforms,receive_shader,0),"descriptor_set"))
	return OK if projection_pipeline.is_valid() and render_pipeline.is_valid() else ERR_CANT_CREATE
func render(renderer:GaussianSplattingRasterizer,request:Dictionary,snapshot:Dictionary)->void:
	_mutex.lock()
	if pending or request.signature==completed_signature or request.signature==failed_signature:
		_mutex.unlock();return
	pending=true
	_mutex.unlock()
	var rd:=context.device;var d:=renderer.descriptors
	_staging=0 if active_index!=0 else 1
	var uniforms:=PackedByteArray();uniforms.resize(128)
	var position:Vector3=request.position
	for i in range(4):uniforms.encode_float(i*4,[position.x,position.y,position.z,snapshot.model_scale][i])
	for i in range(4):uniforms.encode_u32(16+i*4,[resolution,resolution,snapshot.population,renderer.pair_capacity][i])
	uniforms.encode_float(44,1.0)
	rd.buffer_update(d.uniforms.rid,0,128,uniforms)
	rd.buffer_update(flags.rid,0,request.flags.size(),request.flags)
	rd.buffer_clear(d.histogram.rid,0,16);rd.buffer_clear(bounds.rid,0,bounds.size)
	rd.buffer_update(d.grid_dimensions.rid,0,24,PackedInt32Array([0,1,1,0,1,1]).to_byte_array())
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,projection_pipeline)
	rd.compute_list_bind_uniform_set(list,projection_set,0)
	rd.compute_list_set_push_constant(list,request.view_projection,128)
	rd.compute_list_dispatch(list,maxi(1,ceili(float(snapshot.population)/renderer.config.shader_projection_workgroup_size)),1,1)
	rd.compute_list_add_barrier(list)
	rd.compute_list_end()
	renderer.sort_projected_pairs(boundary_set)
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,render_pipeline)
	rd.compute_list_bind_uniform_set(list,render_sets[_staging],0)
	var grid:=(resolution+renderer.config.tile_size-1)/renderer.config.tile_size
	rd.compute_list_dispatch(list,grid,grid,1)
	rd.compute_list_add_barrier(list)
	rd.compute_list_end()
	rd.buffer_copy(d.histogram.rid,status.rid,0,0,16)
	var result:=rd.buffer_get_data_async(status.rid,_receive.bind(request.duplicate(),_staging,_generation),0,16)
	if result!=OK:
		_mutex.lock();pending=false;failed_signature=request.signature;_mutex.unlock()
func _receive(bytes:PackedByteArray,request:Dictionary,index:int,generation:int)->void:
	_mutex.lock()
	if generation!=_generation:_mutex.unlock();return
	pending=false
	if bytes.size()==16 and bytes.decode_u32(4)==0:
		active_index=index;completed_signature=request.signature;failed_signature=0
		active={"index":index,"texture":textures[index],"view":request.view,"projection":request.projection,"resolution":resolution,"signature":request.signature,"projected":bytes.decode_u32(8),"pairs":bytes.decode_u32(0)}
	elif bytes.size()==16:failed_signature=request.signature
	_mutex.unlock()
func failure()->int:
	_mutex.lock();var result:=failed_signature;_mutex.unlock();return result
func snapshot()->Dictionary:
	_mutex.lock();var result:=active.duplicate();_mutex.unlock();return result
func cleanup()->void:
	_mutex.lock();_generation+=1;active.clear();pending=false;_mutex.unlock()
	for texture in textures:texture.texture_rd_rid=RID()
	if context:
		for i in range(_owned.size()-1,-1,-1):context.deletion_queue.free_rid(context.device,_owned[i])
	_owned.clear();textures.clear();maps.clear();active.clear()

func shade(renderer:GaussianSplattingRasterizer,population:int,appearance:Vector2)->void:
	var frame:=snapshot()
	if frame.is_empty():return
	var bytes:=RenderingContext.pack_projection(frame.view);bytes.append_array(RenderingContext.pack_projection(frame.projection))
	bytes.append_array(PackedFloat32Array([appearance.x,appearance.y,float(resolution),0]).to_byte_array())
	bytes.append_array(PackedInt32Array([population,0,0,0]).to_byte_array())
	var rd:=context.device
	rd.buffer_update(receive_parameters.rid,0,160,bytes)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,receive_pipeline)
	rd.compute_list_bind_uniform_set(list,receive_sets[frame.index],0)
	rd.compute_list_dispatch(list,maxi(1,ceili(float(population)/256.0)),1,1)
	rd.compute_list_add_barrier(list);rd.compute_list_end()
