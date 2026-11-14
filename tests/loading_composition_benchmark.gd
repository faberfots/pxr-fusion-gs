extends SceneTree
## Uses the common pre-optimization API so the same journey can be measured before/after.
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:quit(2);return
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default()
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	viewer.set_camera_blocker("benchmark",true)
	var a:=viewer.load_new_splat_from_path(args[0]);var b:=viewer.load_new_splat_from_path(args[1])
	while viewer.is_loading():await process_frame
	if not a or not b or not a.is_loaded or not b.is_loaded:scene.free();quit(1);return
	b.position=Vector3(1.5,0.2,-2);b.rotation_degrees=Vector3(0,25,0);b.scale=Vector3(1.2,0.8,0.9)
	var poses:={a.model_id:a.global_transform,b.model_id:b.global_transform}
	var path:="user://loading-combined.pxrscene";var started:=Time.get_ticks_usec()
	var saved:=await viewer.save_composition(path);var save_us:=Time.get_ticks_usec()-started
	var camera:=viewer.get_camera().global_transform
	started=Time.get_ticks_usec();var opened:=await viewer.open_composition(path);var open_us:=Time.get_ticks_usec()-started
	var exact:=true
	for id in poses:
		viewer.select_model_id(id);var node:=viewer.get_selected_model()
		exact=exact and node!=null and node.global_transform.is_equal_approx(poses[id])
	var record:Dictionary={"save_us":save_us,"occupied_open_us":open_us,"splats":viewer.total_splats_to_load,"save_ok":saved==OK,"open_ok":opened==OK,"transforms_exact":exact,"camera_exact":viewer.get_camera().global_transform.is_equal_approx(camera)}
	if viewer.has_signal("composition_profile_ready"):record.profile=viewer.get("last_composition_profile").duplicate(true)
	print("GDSCRIPT COMPOSITION PROFILE ",JSON.stringify(record))
	var file:=FileAccess.open("user://loading-composition-benchmark.json",FileAccess.WRITE);file.store_string(JSON.stringify(record,"\t"));file.close()
	var good:bool=saved==OK and opened==OK and exact and record.camera_exact and viewer.total_splats_to_load==7959786
	scene.free();await process_frame
	print("COMPOSITION BENCHMARK COMPLETE: ",good)
	quit(0 if good else 1)
