extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128;viewer.config.loading_cache_enabled=false
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var block:=viewer.config.loading_batch_size
	for preset in GaussianSplattingConfig.QualityPreset.values():
		var settings:=viewer.config.duplicate();settings.apply_preset(preset)
		check(settings.loading_batch_size==block,"render quality preserves the independent loading policy: "+str(preset))
	var path:=Checks.fixture("user://scheduler.ply",40000)
	var model:=viewer.load_new_splat_from_path(path)
	while viewer.is_loading():await process_frame
	await RenderingServer.frame_post_draw;await process_frame
	var profile:Dictionary=viewer.get_load_profiles().back()
	check(model.is_loaded and viewer.total_splats_to_load==40000,"bounded scheduler loads the complete population")
	check(profile.splats==40000 and profile.bytes==40000*240 and profile.chunks==ceili(40000.0/profile.block_splats),"profiling accounts for exact uploaded bytes and blocks")
	check(profile.preparation_work_us>0 and profile.source_hash_us>0 and profile.first_frame_us>=profile.complete_us,"GDScript stage timings distinguish preparation, source hash and first frame")
	check(viewer.rasterizer.queued_upload_bytes()==0 and viewer.rasterizer.take_upload_error()==OK,"all scheduled render-thread uploads are drained before commit")
	check(viewer._records[model.get_instance_id()].source_fingerprint.sha256==FileAccess.get_sha256(path),"profiling and scheduling preserve full source identity")
	viewer.load_new_splat_from_path(Checks.fixture("user://scheduler-cancel.ply",40000))
	viewer._clear_scene_and_reset_atlas()
	for i in range(5):await process_frame
	check(not viewer.is_loading() and viewer.total_splats_to_load==0,"clear cancels staged blocks and preserves allocator ownership")
	scene.free();await process_frame
	print("LOADING SCHEDULER COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
