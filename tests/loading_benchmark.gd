extends SceneTree
## All performance measurements originate in Godot/GDScript, including hashing.
var profiles:Array[Dictionary]=[]
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default()
	if args.has("cpu"):viewer.config.loading_gpu_conversion_enabled=false;viewer.config.loading_cache_enabled=false
	if args.has("fresh"):viewer.config.loading_cache_directory="user://benchmark-cache-"+str(Time.get_ticks_usec())
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	viewer.set_camera_blocker("benchmark",true)
	var ui=scene.get_node("ProductionUI");ui.get_node("%MainControls").set_expanded(false)
	var repeats:=int(args[1]) if args.size()>1 else 1
	for repeat in range(repeats):
		var started:=Time.get_ticks_usec()
		var model:=viewer.load_new_splat_from_path(args[0],GaussianSplattingViewer.LoadMode.REPLACE)
		if not model:scene.free();quit(1);return
		while viewer.is_loading() and Time.get_ticks_usec()-started<300000000:await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		if not model.is_loaded:scene.free();quit(1);return
		var profile:Dictionary=viewer.get_load_profiles().back().duplicate(true)
		profile["request_to_ready_us"]=Time.get_ticks_usec()-started
		profile["engine"]=Engine.get_version_info().string
		profile["batch_splats"]=viewer.config.loading_batch_size
		profile["repeat"]=repeat
		profiles.append(profile)
		print("GDSCRIPT LOAD PROFILE ",JSON.stringify(profile))
		await create_timer(0.25).timeout
	var output:=FileAccess.open("user://loading-benchmark.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(profiles,"\t"));output.close()
	scene.free();await process_frame
	print("LOADING BENCHMARK COMPLETE: ",profiles.size()," successful full loads")
	quit(0)
