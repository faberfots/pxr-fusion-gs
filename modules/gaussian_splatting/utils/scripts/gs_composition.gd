class_name GSComposition
extends RefCounted
## Versioned data-only composition codec. The viewer owns live state and transactions.
const FORMAT := "PXRFusion GS scene"
const VERSION := 1
const HASH_CHUNK := 4 * 1024 * 1024
var cancelled := false
var checkpoint:GSAtlasMigration
var _hash_job:GSFileHashJob
var profile:Dictionary={}
signal completed(result:Dictionary)
var _completed:=false
# Keep asynchronous IO alive until cancellation drains, even after its viewer exits.
static var _active:Dictionary={}

func begin(viewer:Node,path:String,opening:bool)->void:
	if cancelled or not is_instance_valid(viewer):
		finish(failure("Scene operation cancelled.",ERR_SKIP));return
	var identity:=get_instance_id()
	_active[identity]=self
	var result:Dictionary=await open(viewer,path) if opening else await save(viewer,path)
	finish(result)
	_active.erase(identity)
func finish(result:Dictionary)->void:
	if _completed:return
	_completed=true;completed.emit(result)
func cancel()->void:
	cancelled=true
	if _hash_job:_hash_job.cancel();_hash_job.join()
	if checkpoint:checkpoint.cancelled=true;checkpoint.dispose()
	finish(failure("Scene operation cancelled.",ERR_SKIP))

class CompositionCheckpoint extends GSAtlasMigration:
	func _read_chunk(rasterizer:GaussianSplattingRasterizer,offset:int,size:int,_tree:SceneTree)->PackedByteArray:
		# Read one bounded chunk without retaining a GPU callback past viewer teardown.
		# The inherited checkpoint still yields to the UI between chunks.
		if cancelled:return PackedByteArray()
		return rasterizer._sync(func():return rasterizer.context.device.buffer_get_data(rasterizer.descriptors.splats.rid,offset,size))

static func matrix(value:Transform3D)->Array:
	return [value.basis.x.x,value.basis.x.y,value.basis.x.z,value.basis.y.x,value.basis.y.y,value.basis.y.z,value.basis.z.x,value.basis.z.y,value.basis.z.z,value.origin.x,value.origin.y,value.origin.z]
static func transform(values:Array)->Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]),Vector3(values[6],values[7],values[8])),Vector3(values[9],values[10],values[11]))
static func numbers(value:Variant,count:int)->bool:
	if not value is Array or value.size()!=count:return false
	for number in value:
		if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)):return false
	return true
static func failure(message:String,code:Error=ERR_FILE_CORRUPT)->Dictionary:
	return {"error":message,"code":code}
static func relative_path(base:String,source:String)->String:
	var folders:=base.replace("\\","/").simplify_path().split("/",false)
	var target:=source.replace("\\","/").simplify_path().split("/",false)
	if folders.is_empty() or target.is_empty() or folders[0].to_lower()!=target[0].to_lower():return source
	var shared:=0
	while shared<mini(folders.size(),target.size()) and folders[shared].to_lower()==target[shared].to_lower():shared+=1
	return "../".repeat(folders.size()-shared)+"/".join(target.slice(shared))
static func view(viewer:Node)->Dictionary:
	var camera:Camera3D=viewer.get_camera()
	var grade:=GSColorSettings.snapshot(viewer.config)
	var tint:Color=grade.post_tint;grade.post_tint=[tint.r,tint.g,tint.b,tint.a]
	var point:Vector3=camera.orbit_point if camera is OrbitCamera else Vector3.ZERO
	var sun:Dictionary={}
	if is_instance_valid(viewer.shadow_light):
		var color:Color=viewer.shadow_light.light_color
		sun={"pose":matrix(viewer.shadow_light.global_transform),"color":[color.r,color.g,color.b,color.a],"energy":viewer.shadow_light.light_energy}
	return {"sky":GSSkySettings.snapshot(GSSkySettings.node(viewer)),"color":grade,"renderer":{"basis":matrix(Transform3D(viewer.rasterizer.basis_override,Vector3.ZERO)),"scale":float(viewer.rasterizer.model_scale[0]),"heatmap":float(viewer.rasterizer.should_enable_heatmap[0]),"render_scale":viewer.config.default_render_scale},"camera":{"pose":matrix(camera.global_transform),"mode":"orbit" if camera is OrbitCamera else "free","orbit_point":[point.x,point.y,point.z],"protected":viewer.camera_controller.safety.protected_fly,"fov":camera.fov,"projection":camera.projection,"size":camera.size,"near":camera.near,"far":camera.far,"keep_aspect":camera.keep_aspect,"frustum_offset":[camera.frustum_offset.x,camera.frustum_offset.y]},"lighting":{"enabled":viewer.lighting.shadows_enabled,"strength":viewer.lighting.shadow_strength,"bias":viewer.lighting.shadow_bias,"resolution":viewer.lighting.shadow_resolution},"sun":sun}
static func capture(viewer:Node,path:String)->Dictionary:
	var models:Array=[]
	var base:=ProjectSettings.globalize_path(path).get_base_dir()
	for record in viewer._records.values():
		var node:GaussianSplat=record.node.get_ref()
		if not is_instance_valid(node) or record.status!="loaded":return failure("Finish loading or remove failed models before saving.",ERR_BUSY)
		var source:=ProjectSettings.globalize_path(record.path).simplify_path()
		if not FileAccess.file_exists(source):return failure("Original PLY is unavailable: "+source,ERR_FILE_NOT_FOUND)
		if not node.global_transform.is_finite():return failure("A model transform is not finite.",ERR_INVALID_DATA)
		models.append({"id":node.model_id,"name":str(node.name),"source":source,"relative_source":relative_path(base,source),"transform":matrix(node.global_transform),"import_kind":int(node.import_kind),"visible":node.visible,"cast_shadow":node.cast_gaussian_shadows,"receive_shadow":node.receive_gaussian_shadows,"splats":int(record.count)})
		models.back().merge(record.get("source_fingerprint",{}))
	return {"format":FORMAT,"version":VERSION,"models":models,"selection":Array(viewer.selected_model_ids),"view":view(viewer)}
func fingerprint(path:String,tree:SceneTree)->Dictionary:
	var job:=GSFileHashJob.new();_hash_job=job
	var result:=job.start(path)
	if result!=OK:_hash_job=null;return failure("Cannot start source verification",result)
	while not job.is_done():
		if cancelled:job.cancel()
		await tree.process_frame
	var metadata:=job.join();_hash_job=null
	if cancelled:return failure("Scene operation cancelled.",ERR_SKIP)
	if metadata.has("error"):return metadata
	profile["source_verify_us"]=int(profile.get("source_verify_us",0))+int(metadata.elapsed_us)
	return {"bytes":metadata.bytes,"sha256":metadata.sha256}

func save(viewer:Node,path:String)->Dictionary:
	if path.get_extension().to_lower()!="pxrscene":return failure("Choose a .pxrscene file.",ERR_INVALID_PARAMETER)
	var document:=capture(viewer,path)
	if document.has("error"):return document
	var hashes:Dictionary={}
	for entry in document.models:
		viewer.composition_progress.emit("Checking original "+entry.source.get_file())
		if not hashes.has(entry.source):hashes[entry.source]=await fingerprint(entry.source,viewer.get_tree())
		if hashes[entry.source].has("error"):return hashes[entry.source]
		if entry.has("sha256") and hashes[entry.source].sha256!=entry.sha256:return failure("Original source changed since import. Reload the model before saving: "+entry.source)
		entry.merge(hashes[entry.source])
	if cancelled or not is_instance_valid(viewer):return failure("Scene operation cancelled.",ERR_SKIP)
	var validated:=validate(document)
	if validated.has("error"):return validated
	var temporary:=path+".tmp-"+Crypto.new().generate_random_bytes(8).hex_encode()
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if not file:return failure("Cannot create scene file: "+path,ERR_CANT_CREATE)
	file.store_string(JSON.stringify(document,"\t",true,true));file.flush()
	var result:=file.get_error();file.close()
	if result==OK:result=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))
	if result!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return failure("Scene could not be saved; the previous file was preserved.",result)
	return {}
static func validate(document:Variant)->Dictionary:
	if not document is Dictionary or document.get("format")!=FORMAT or document.get("version")!=VERSION:return failure("Unsupported or invalid PXRFusion scene.")
	if not document.get("models") is Array or not document.get("selection") is Array or not document.get("view") is Dictionary:return failure("Scene models, selection or view are missing.")
	var ids:Dictionary={}
	for entry in document.models:
		if not entry is Dictionary:return failure("Invalid scene model entry.")
		if not entry.get("id") is String or entry.id.is_empty() or ids.has(entry.id):return failure("Scene model identities must be unique.")
		ids[entry.id]=true
		if not entry.get("source") is String or not entry.get("relative_source") is String or not entry.get("name") is String or not numbers(entry.get("transform"),12):return failure("A model source or transform is invalid.")
		var kind:Variant=entry.get("import_kind",GaussianSplat.ImportKind.AUTO)
		if not numbers([kind],1) or kind!=floor(kind) or int(kind) not in GaussianSplat.ImportKind.values():return failure("Invalid model import kind.")
		if entry.name.is_empty():return failure("A model name is missing.")
		if not entry.get("sha256") is String or entry.sha256.length()!=64:return failure("A model fingerprint is missing or invalid.")
		for character in entry.sha256:
			if character not in "0123456789abcdefABCDEF":return failure("A model fingerprint is invalid.")
		for key in ["splats","bytes"]:
			if typeof(entry.get(key)) not in [TYPE_INT,TYPE_FLOAT] or entry[key]<1 or entry[key]!=floor(entry[key]):return failure("A model population or file length is invalid.")
		for key in ["visible","cast_shadow","receive_shadow"]:
			if not entry.get(key) is bool:return failure("Invalid model visibility or shadow settings.")
	for id in document.selection:
		if not id is String or not ids.has(id):return failure("Selection references an unknown model.")
	var settings:Dictionary=document.view
	for key in ["camera","color","renderer","lighting","sun"]:
		if not settings.get(key) is Dictionary:return failure("Incomplete saved view.")
	if settings.has("sky") and not GSSkySettings.valid(settings.sky):return failure("Invalid saved Sky3D atmosphere.")
	var camera:Dictionary=settings.camera
	if not numbers(camera.get("pose"),12) or absf(transform(camera.pose).basis.determinant())<0.000001 or not numbers(camera.get("orbit_point"),3) or not numbers(camera.get("frustum_offset"),2):return failure("Invalid saved camera pose.")
	if camera.get("mode") not in ["free","orbit"] or not camera.get("protected") is bool or not numbers([camera.get("projection"),camera.get("keep_aspect")],2):return failure("Invalid saved camera mode.")
	if camera.projection!=floor(camera.projection) or int(camera.projection) not in [0,1,2] or camera.keep_aspect!=floor(camera.keep_aspect) or int(camera.keep_aspect) not in [0,1]:return failure("Invalid saved camera mode.")
	for key in ["fov","size","near","far"]:
		if not numbers([camera.get(key)],1) or camera[key]<=0:return failure("Invalid camera lens.")
	if camera.fov>=180 or camera.far<=camera.near:return failure("Invalid camera lens range.")
	var colors:Dictionary=settings.color.duplicate()
	if not numbers(colors.get("post_tint"),4):return failure("Invalid saved tint.")
	colors.post_tint=Color(colors.post_tint[0],colors.post_tint[1],colors.post_tint[2],colors.post_tint[3])
	for field in GSColorSettings.FIELDS:
		if not colors.has(field):return failure("Incomplete saved color grade.")
	if not GSColorSettings.apply(GaussianSplattingConfig.create_default(),colors):return failure("Invalid saved color grade.")
	var renderer:Dictionary=settings.renderer
	if not numbers(renderer.get("basis"),12) or absf(transform(renderer.basis).basis.determinant())<0.000001:return failure("Invalid renderer basis.")
	for key in ["scale","heatmap","render_scale"]:
		if not numbers([renderer.get(key)],1):return failure("Invalid renderer settings.")
	if renderer.scale<=0 or renderer.scale>10 or renderer.heatmap<0 or renderer.heatmap>1 or renderer.render_scale<0.25 or renderer.render_scale>2:return failure("Renderer settings are outside the supported range.")
	var light:Dictionary=settings.lighting
	if not light.get("enabled") is bool or not numbers([light.get("resolution"),light.get("strength"),light.get("bias")],3):return failure("Invalid saved lighting.")
	if light.resolution!=floor(light.resolution) or int(light.resolution) not in [256,512,1024]:return failure("Invalid saved shadow resolution.")
	if light.strength<0 or light.strength>1 or light.bias<0.001 or light.bias>0.2:return failure("Invalid saved shadow settings.")
	if not settings.sun.is_empty():
		if not numbers(settings.sun.get("pose"),12) or not numbers(settings.sun.get("color"),4) or not numbers([settings.sun.get("energy")],1) or settings.sun.energy<0:return failure("Invalid saved directional light.")
	return document
func read(path:String,viewer:Node)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file:return failure("Cannot open scene: "+path,ERR_FILE_NOT_FOUND)
	var parser:=JSON.new()
	var content:=file.get_as_text();file.close()
	if parser.parse(content)!=OK:return failure("Scene JSON is invalid at line %d." % parser.get_error_line())
	var document:=validate(parser.data)
	if document.has("error"):return document
	if document.models.size()>viewer.config.memory_max_instances:return failure("Scene exceeds the current atlas instance capacity.",ERR_OUT_OF_MEMORY)
	var count:=0;var hashes:Dictionary={}
	for entry in document.models:
		var relative:String=entry.relative_source if entry.relative_source.is_absolute_path() else ProjectSettings.globalize_path(path).get_base_dir().path_join(entry.relative_source).simplify_path()
		var source:String=relative if FileAccess.file_exists(relative) else entry.source
		if source.get_extension().to_lower() not in ["ply","gsres"]:return failure("A composition must reference original PLY or GSRES files.")
		viewer.composition_progress.emit("Verifying original "+source.get_file())
		if not hashes.has(source):hashes[source]=await fingerprint(source,viewer.get_tree())
		if hashes[source].has("error"):return hashes[source]
		if hashes[source].bytes!=entry.bytes or hashes[source].sha256!=entry.sha256:return failure("Original PLY differs from the saved scene: "+source)
		var metadata:=PlyConverter.inspect(source,viewer.config.max_vertices)
		if metadata.has("error"):return metadata
		if metadata.vertex_count!=entry.splats:return failure("Original PLY population differs from the saved scene: "+source)
		entry["resolved_source"]=source;count+=int(entry.splats)
	if count>viewer.rasterizer.atlas_capacity_splats:return failure("Scene needs %d splats; current atlas holds %d. Increase the quality/atlas budget first; the current scene is preserved." % [count,viewer.rasterizer.atlas_capacity_splats],ERR_OUT_OF_MEMORY)
	return document
static func apply_view(viewer:Node,settings:Dictionary)->void:
	if settings.has("sky"):GSSkySettings.apply(GSSkySettings.node(viewer),settings.sky)
	var grade:Dictionary=settings.color.duplicate()
	var tint:Array=grade.post_tint;grade.post_tint=Color(tint[0],tint[1],tint[2],tint[3])
	GSColorSettings.apply(viewer.config,grade)
	viewer.config.default_render_scale=settings.renderer.render_scale
	viewer.config.default_model_scale=settings.renderer.scale
	viewer.config.enable_heatmap_by_default=settings.renderer.heatmap>0
	viewer.rasterizer.basis_override=transform(settings.renderer.basis).basis
	viewer.rasterizer.model_scale[0]=settings.renderer.scale
	viewer.rasterizer.should_enable_heatmap[0]=settings.renderer.heatmap
	viewer.lighting.shadows_enabled=settings.lighting.enabled
	viewer.lighting.shadow_strength=settings.lighting.strength
	viewer.lighting.shadow_bias=settings.lighting.bias
	viewer.lighting.shadow_resolution=int(settings.lighting.resolution)
	if not settings.sun.is_empty() and is_instance_valid(viewer.shadow_light):
		viewer.shadow_light.global_transform=transform(settings.sun.pose)
		var color:Array=settings.sun.color
		viewer.shadow_light.light_color=Color(color[0],color[1],color[2],color[3]);viewer.shadow_light.light_energy=settings.sun.energy
	var controller:CameraController=viewer.camera_controller
	var camera:=controller.get_node_or_null("OrbitCamera" if settings.camera.mode=="orbit" else "FreeLookCamera") as CameraInterface
	if not camera:camera=controller.get_camera()
	if camera is OrbitCamera:camera.orbit_point=Vector3(settings.camera.orbit_point[0],settings.camera.orbit_point[1],settings.camera.orbit_point[2])
	# Opening a view teleports; it does not sweep the camera through intervening walls.
	controller.set_protection(false);controller.set_camera(camera);controller.set_camera_transform(transform(settings.camera.pose))
	controller.set_protection(settings.camera.protected)
	for field in ["fov","size","near","far"]:camera.set(field,settings.camera[field])
	camera.projection=int(settings.camera.projection);camera.keep_aspect=int(settings.camera.keep_aspect)
	camera.frustum_offset=Vector2(settings.camera.frustum_offset[0],settings.camera.frustum_offset[1])
func open(viewer:Node,path:String)->Dictionary:
	var document:=await read(path,viewer)
	if document.has("error"):return document
	if cancelled:return failure("Scene operation cancelled.",ERR_SKIP)
	var records:Dictionary=viewer._records
	var free_ids:Array[int]=viewer._free_instance_ids.duplicate()
	var selection:Array=viewer.selected_model_ids.duplicate()
	var undo:Array[Dictionary]=viewer._transform_undo.duplicate();var redo:Array[Dictionary]=viewer._transform_redo.duplicate()
	var initial:bool=viewer._initial_framing;var scene_mode:int=viewer.current_scene_mode
	var was_rendering:bool=viewer.is_rendering()
	viewer._composition_protecting=true
	viewer.stop_rendering();viewer.rasterizer.rendering_enabled=false;viewer.rasterizer.cancel_pick();viewer.rasterizer.update_camera_matrices()
	var checkpoint_started:=Time.get_ticks_usec()
	checkpoint=CompositionCheckpoint.new()
	viewer.composition_progress.emit("Protecting current composition…")
	var result:=await checkpoint.checkpoint(viewer.rasterizer,records,viewer.get_tree())
	if is_instance_valid(viewer):viewer._composition_protecting=false
	profile["checkpoint_us"]=Time.get_ticks_usec()-checkpoint_started
	profile["checkpoint"]=checkpoint.profile.duplicate()
	if result!=OK or cancelled:
		if is_instance_valid(viewer) and not viewer._closing and was_rendering:viewer.start_rendering()
		checkpoint.dispose();return failure("Cannot protect current composition; it was preserved.",result if result!=OK else ERR_SKIP)
	viewer._records={};viewer.select_model_id("");viewer._transform_undo.clear();viewer._transform_redo.clear()
	viewer.rasterizer.clear_gpu_memory();viewer._free_instance_ids.clear()
	for id in range(viewer.config.memory_max_instances,0,-1):viewer._free_instance_ids.append(id)
	viewer._initial_framing=false
	for entry in document.models:
		var pose:Transform3D=viewer.global_transform.affine_inverse()*transform(entry.transform)
		var node:GaussianSplat=viewer._load_new_splat_from_path(entry.resolved_source,GaussianSplattingViewer.LoadMode.APPEND,pose)
		if not node:result=ERR_CANT_CREATE;break
		node.model_id=entry.id;node.visible=entry.visible
		node.import_kind=int(entry.get("import_kind",GaussianSplat.ImportKind.AUTO)) as GaussianSplat.ImportKind
		node.cast_gaussian_shadows=entry.cast_shadow;node.receive_gaussian_shadows=entry.receive_shadow
	while not cancelled and is_instance_valid(viewer) and viewer.is_loading():await viewer.get_tree().process_frame
	if cancelled:return failure("Scene operation cancelled.",ERR_SKIP)
	for record in viewer._records.values():
		if record.status!="loaded":result=ERR_FILE_CORRUPT
		for entry in document.models:
			if record.node.get_ref().model_id==entry.id and record.get("source_fingerprint",{}).get("sha256","")!=entry.sha256:result=ERR_FILE_CORRUPT
	if viewer._records.size()!=document.models.size():result=ERR_FILE_CORRUPT
	if result==OK:
		var previous_scale:float=viewer.rasterizer.render_scale[0]
		viewer.rasterizer.render_scale[0]=document.view.renderer.render_scale
		result=viewer.rasterizer.resize(viewer.get_viewport().size)
		if result!=OK:viewer.rasterizer.render_scale[0]=previous_scale
	if result!=OK:
		viewer._cancel_job();viewer._pending.clear()
		var failed:Dictionary=viewer._records;viewer._records={}
		for record in failed.values():
			var node:Node=record.node.get_ref()
			if is_instance_valid(node):node.queue_free()
		viewer._composition_restoring=true
		viewer.rasterizer.clear_gpu_memory()
		var restored:=await checkpoint.restore(viewer.rasterizer,records,viewer.get_tree(),false)
		if cancelled or not is_instance_valid(viewer):checkpoint.dispose();return failure("Scene operation cancelled.",ERR_SKIP)
		viewer._records=records;viewer._free_instance_ids=free_ids
		if restored.has("error"):
			var recovery:=ProjectSettings.globalize_path(checkpoint.path);checkpoint.path=""
			viewer._composition_restoring=false
			return failure("GPU recovery failed. Resident checkpoint retained at "+recovery,restored.error)
		for record in records.values():
			var node:GaussianSplat=record.node.get_ref()
			if not is_instance_valid(node) or not restored.mapping.has(node.model_id):continue
			var destination:Dictionary=restored.mapping[node.model_id]
			record.offset=destination.offset;record.instance_id=destination.instance_id;node.buffer_offset=destination.offset
			viewer.rasterizer.update_instance_transform(record.instance_id,node.global_transform,record.visible)
		viewer._transform_undo=undo;viewer._transform_redo=redo;viewer._initial_framing=initial;viewer.current_scene_mode=scene_mode
		viewer.select_model_ids(selection);viewer.current_state=GaussianSplattingViewer.ViewerState.READY
		if was_rendering:viewer.start_rendering()
		viewer._composition_restoring=false;checkpoint.dispose();viewer.model_registry_changed.emit()
		return failure("Scene could not load completely; the previous composition was restored.",result)
	for record in records.values():
		var node:Node=record.node.get_ref()
		if is_instance_valid(node):node.queue_free()
	# Restore saved names after old nodes relinquish their names in this parent.
	await viewer.get_tree().process_frame
	if cancelled or not is_instance_valid(viewer):checkpoint.dispose();return failure("Scene operation cancelled.",ERR_SKIP)
	for entry in document.models:
		for record in viewer._records.values():
			var node:GaussianSplat=record.node.get_ref()
			if is_instance_valid(node) and node.model_id==entry.id:node.name=entry.name.validate_node_name()
	# A queued pre-open grade must not overwrite the deliberately restored scene view.
	viewer._queued_configuration=null
	apply_view(viewer,document.view)
	viewer.select_model_ids(document.selection);viewer.current_state=GaussianSplattingViewer.ViewerState.READY
	viewer.start_rendering();viewer._shadow_signature=0;viewer._hybrid_signature=0
	checkpoint.dispose();viewer.model_registry_changed.emit()
	var history:=viewer.get_node_or_null("/root/HistoryManager")
	if history:history.add_file(path)
	return {}
