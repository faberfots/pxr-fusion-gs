extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
var completed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	viewer.config.loading_gpu_conversion_enabled=false;viewer.config.loading_cache_enabled=false;viewer.config.loading_batch_size=2000
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	viewer.all_splats_loading_completed.connect(func(_count):completed+=1)
	var ui=scene.get_node("ProductionUI")
	check(not viewer.config.loading_progressive_preview,"progressive display is opt-in and preserves the default atomic import flow")
	ui.get_node("%SettingsPanel").get_node("%ProgressivePreview").button_pressed=true
	check(viewer.config.loading_progressive_preview,"authored workspace control updates the viewer-owned policy")
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://progressive.ply",40000))
	var observed:=false;var matrix_active:=false
	while viewer.is_loading():
		await process_frame
		var state:=viewer.get_loading_state()
		if state.preview and state.resident_splats>0 and state.resident_splats<state.total_splats:
			observed=true
			check(not model.is_loaded and completed==0 and viewer.get_stats().splats_loaded==0,"partial residency never announces complete loading")
			var record:Dictionary=viewer._records[model.get_instance_id()]
			var bytes:PackedByteArray=viewer.rasterizer._sync(func():return viewer.rasterizer.context.device.buffer_get_data(viewer.rasterizer.descriptors.instance_transforms.rid,int(record.instance_id)*64,64))
			matrix_active=bytes.decode_float(60)==1.0
			break
	check(observed and matrix_active,"resident prefix is presented through the existing instance palette while loading")
	while viewer.is_loading():await process_frame
	check(model.is_loaded and completed==1 and viewer.total_splats_to_load==40000,"complete means every original splat is validated and committed")
	var profile:Dictionary=viewer.get_load_profiles().back()
	check(profile.has("first_preview_us") and profile.first_preview_us<profile.complete_us,"profiling distinguishes preview latency from complete residency")
	viewer._clear_scene_and_reset_atlas()
	var path:=Checks.fixture("user://progressive-object.ply",3)
	viewer.begin_model_placement(path,Vector2(20,20),GaussianSplat.ImportKind.OBJECT)
	while viewer.is_loading():await process_frame
	check(viewer.placement_active and not viewer._placement.model.visible,"object placement retains its hidden staging and normal confirmation")
	viewer.cancel_model_placement()
	viewer.load_new_splat_from_path(Checks.fixture("user://progressive-cancel.ply",40000))
	for i in range(8):await process_frame
	viewer._clear_scene_and_reset_atlas()
	check(viewer.total_splats_to_load==0 and not viewer.is_loading(),"clearing a partial preview releases residency and pending work")
	scene.free();await process_frame
	print("LOADING PROGRESSIVE COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
