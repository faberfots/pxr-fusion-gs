extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func load_model(path:String)->GSSceneMesh:
	var job:=GSSceneImportJob.new();job.start(path)
	while not job.is_done():await process_frame
	var loaded:=job.finish()
	if loaded.has("error"):return null
	var model:=GSSceneMesh.new();model.file_path=path
	if model.initialize(loaded.root,loaded.fingerprints)!=OK:model.free();return null
	root.add_child(model)
	return model
func prepared(model:GSSceneMesh,quality:GSMeshMotionJob.Quality,limit:int=30000)->bool:
	var deadline:=Time.get_ticks_msec()+limit
	while not model.prepare_motion_shapes(quality) and model.motion_error==OK and Time.get_ticks_msec()<deadline:await process_frame
	return model.prepare_motion_shapes(quality)
func fixture()->String:
	var content:=Node3D.new();content.name="FreshMotion%d" % Time.get_ticks_usec()
	var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for location in [Vector3(-0.65,0.75,0),Vector3(0.65,0.75,0),Vector3(0,1.65,0)]:
		var box:=BoxMesh.new();box.size=Vector3(0.3,1.5,0.4) if location.y<1 else Vector3(1.6,0.3,0.4)
		for vertex in box.get_faces():builder.add_vertex(vertex+location)
	builder.generate_normals();var mesh:=MeshInstance3D.new();mesh.mesh=builder.commit();content.add_child(mesh)
	var document:=GLTFDocument.new();var state:=GLTFState.new();var path:="user://motion-speed-fixture.glb"
	check(document.append_from_scene(content,state)==OK and document.write_to_filesystem(state,path)==OK,"motion timing fixture exports as a real GLB")
	content.free();return path
func run()->void:
	var args:=OS.get_cmdline_user_args();var warm:bool="--warm" in args
	var path:="user://motion-speed-fixture.glb" if warm else fixture()
	var model:=await load_model(path)
	if not model:check(false,"native motion fixture imports");quit(1);return
	check(await prepared(model,GSMeshMotionJob.Quality.FAST),"default Fast geometry becomes usable without detailed decomposition")
	print("FAST FIXTURE ",model.motion_metrics)
	check(model.motion_metrics.get("cache_hit")==warm,"prepared geometry persists across separate application processes")
	check(await prepared(model,GSMeshMotionJob.Quality.DETAILED),"Detailed remains available on the same loaded model")
	check(model.motion_shapes.size()>=3,"Detailed retains the opening between the moving model's legs")
	check(await prepared(model,GSMeshMotionJob.Quality.FAST) and model.motion_metrics.get("memory_hit",false),"switching back reuses prepared Fast geometry")
	var before:=model.transform;model.transform=Transform3D(Basis.from_euler(Vector3(0.2,0.3,0.1)).scaled_local(Vector3(0.8,1.3,0.6)),Vector3(4,2,-3))
	check(not GSMeshMotionJob.bake_points(model.motion_shapes,model.basis).is_empty(),"cached geometry supports rotated and nonuniformly scaled roots")
	model.transform=before
	if not warm:
		var key:=GSMeshMotionJob.cache_key(model.fingerprints,GSMeshMotionJob.Quality.FAST);model.free()
		var file:=FileAccess.open(GSMeshMotionJob.CACHE_DIRECTORY.path_join(key+".bin"),FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3]));file.close()
		model=await load_model(path)
		check(await prepared(model,GSMeshMotionJob.Quality.FAST) and not model.motion_metrics.get("cache_hit",true),"a truncated cache rebuilds from source instead of disabling collisions")
	model.free()
	if args.size()>0 and args[-1].get_extension().to_lower() in ["glb","gltf"]:
		model=await load_model(args[-1])
		check(model!=null,"the real reported truck imports for the timing check")
		if model:
			var started:=Time.get_ticks_msec();var ready:=await prepared(model,GSMeshMotionJob.Quality.FAST,10000)
			print("REAL TRUCK FAST ",model.motion_metrics," wall_ms=",Time.get_ticks_msec()-started," mesh_parts=",model.geometry_parts.size())
			check(ready and model.motion_metrics.get("milliseconds",10000)<10000,"the real truck's Fast collisions prepare within ten seconds")
			if warm:check(model.motion_metrics.get("cache_hit",false),"the real truck reopens using its persistent shape cache")
			model.free()
	await process_frame
	print("MOTION PREPARATION CHECKS COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
