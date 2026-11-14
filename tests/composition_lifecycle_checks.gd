extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func make_scene()->Node:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	return scene
func run()->void:
	var scene:=make_scene();var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	var path:=Checks.fixture("user://composition-teardown.ply",40000)
	viewer.load_new_splat_from_path(path)
	viewer.load_new_splat_from_path(path)
	while viewer.is_loading():await process_frame
	viewer.save_composition("user://cancel-save.pxrscene")
	check(viewer.composition_busy,"saving yields while hashing originals")
	var reference:WeakRef=weakref(viewer)
	scene.free()
	await create_timer(0.3).timeout
	check(reference.get_ref()==null,"teardown during save releases the viewer and source handles")
	scene=make_scene();viewer=scene.get_node("GaussianSplattingViewer")
	viewer.load_new_splat_from_path(path)
	while viewer.is_loading():await process_frame
	check(await viewer.save_composition("user://cancel-open.pxrscene")==OK,"lifecycle fixture saves its composition")
	viewer.composition_progress.connect(func(message):
		if message.begins_with("Protecting current composition"):scene.call_deferred("free")
	)
	reference=weakref(viewer)
	viewer.open_composition("user://cancel-open.pxrscene")
	await create_timer(0.6).timeout
	check(reference.get_ref()==null,"teardown during atlas checkpoint cancels pending scene work")
	var checkpoints:Array[String]=[]
	for file in DirAccess.get_files_at("user://"):
		if file.begins_with("atlas-migration-") and file.ends_with(".tmp"):checkpoints.append(file)
	check(checkpoints.is_empty(),"cancelled operation releases its temporary atlas checkpoint")
	print("COMPOSITION LIFECYCLE COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
