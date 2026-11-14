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
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	viewer.config.loading_gpu_conversion_enabled=false;viewer.config.loading_cache_enabled=false;viewer.config.loading_batch_size=4000
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var path:=Checks.fixture("user://parallel-source.ply",40000)
	var model:=viewer.load_new_splat_from_path(path)
	while viewer.is_loading():await process_frame
	check(model.is_loaded and viewer.total_splats_to_load==40000,"parallel GDScript fallback commits every original splat")
	var record:Dictionary=viewer._records[model.get_instance_id()];var profile:Dictionary=viewer.get_load_profiles().back()
	check(profile.backend=="gdscript_parallel" and profile.cpu_workers==2 and profile.parallel_pack_work_us>0,"fallback uses the bounded GDScript worker-pool path")
	check(record.resource.aabb.position==Vector3.ZERO and record.resource.aabb.end==Vector3(39999,0,0),"ordered block assembly preserves complete bounds")
	var stride:=ceili(40000.0/8192);var correct:=true
	for i in range(record.samples.size()):correct=correct and record.samples[i]==Vector3(i*stride,0,0)
	check(correct,"parallel preparation preserves deterministic source-wide camera samples")
	var pose:=model.global_transform
	var other:=viewer.load_new_splat_from_path(Checks.fixture("user://parallel-cancel.ply",40000))
	for i in range(3):await process_frame
	viewer.unregister_splat(other);other.queue_free()
	for i in range(3):await process_frame
	check(model.is_loaded and model.global_transform==pose and viewer.total_splats_to_load==40000,"cancelling pooled work preserves the existing model and population")
	scene.free();await process_frame
	print("LOADING PARALLEL COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
