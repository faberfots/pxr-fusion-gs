extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func load_model(viewer:GaussianSplattingViewer,path:String)->GaussianSplat:
	var model:=viewer.load_new_splat_from_path(path,GaussianSplattingViewer.LoadMode.REPLACE)
	while viewer.is_loading():await process_frame
	await RenderingServer.frame_post_draw
	return model
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	viewer.config.loading_cache_directory="user://cache-check-"+str(Time.get_ticks_usec())
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var path:=Checks.fixture("user://cached-source.ply",37)
	var model:=await load_model(viewer,path)
	var first:Dictionary=viewer.get_load_profiles().back()
	check(model.is_loaded and first.cache_written,"cold import publishes a complete prepared cache")
	var bounds:=viewer.get_model_world_bounds(model)
	model=await load_model(viewer,path)
	var second:Dictionary=viewer.get_load_profiles().back()
	check(model.is_loaded and second.get("cache_hit",false),"repeat import verifies and uses the prepared payload")
	check(viewer.get_model_world_bounds(model).is_equal_approx(bounds) and second.bytes==37*240,"cache preserves exact population and rendered bounds")
	var cache:=GSPreparedCache.new();cache.directory=viewer.config.loading_cache_directory
	var meta:=cache.candidate(path,37,FileAccess.get_file_as_bytes(path).size());cache.release()
	var file:=FileAccess.open(meta.payload,FileAccess.READ_WRITE);file.seek(24);file.store_float(123);file.close()
	model=await load_model(viewer,path)
	check(model.is_loaded and viewer.get_load_profiles().back().get("cache_rejected",false) and viewer.total_splats_to_load==37,"corrupt payload falls back to original data without duplicating uploaded counts")
	check(viewer.get_model_world_bounds(model).is_equal_approx(bounds),"corrupt cache cannot alter committed source geometry")
	# Same-length source edits must be caught by SHA, even within one timestamp second.
	var text:=FileAccess.get_file_as_string(path);text=text.replace("0 0 0 -3","9 0 0 -3")
	file=FileAccess.open(path,FileAccess.WRITE);file.store_string(text);file.close()
	model=await load_model(viewer,path)
	check(model.is_loaded and viewer.get_load_profiles().back().get("cache_rejected",false),"source SHA rejects a stale cache after a same-length source edit")
	var owned:=cache.directory
	viewer.config.loading_cache_directory="user://cache-unowned-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(viewer.config.loading_cache_directory))
	var sentinel:=viewer.config.loading_cache_directory.path_join("keep.txt")
	file=FileAccess.open(sentinel,FileAccess.WRITE);file.store_string("original");file.close()
	model=await load_model(viewer,path)
	check(model.is_loaded and FileAccess.get_file_as_string(sentinel)=="original" and not FileAccess.file_exists(viewer.config.loading_cache_directory.path_join(".owner")),"cache writes cannot claim a populated, unowned directory")
	viewer.config.loading_cache_directory=owned
	viewer.load_new_splat_from_path(Checks.fixture("user://cache-cancel.ply",40000));viewer._clear_scene_and_reset_atlas()
	for i in range(4):await process_frame
	var temporary:=false
	for name in DirAccess.get_files_at(owned):temporary=temporary or name.ends_with(".tmp")
	check(not temporary,"cancelled preparation closes handles and removes unpublished cache files")
	scene.free();await process_frame
	print("LOADING CACHE COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
