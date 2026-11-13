extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:quit(1);return
	var scene:Node=load("res://main.tscn").instantiate()
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default()
	scene.get_node("DemoUIController").show_ui=false
	root.add_child(scene)
	scene.get_node("DemoUIController").set_process(false)
	viewer.set_camera_blocker("qualification",true)
	var a:=viewer.load_new_splat_from_path(args[0])
	var b:=viewer.load_new_splat_from_path(args[1])
	for i in range(3):await process_frame
	var start:=Time.get_ticks_msec()
	while viewer.is_loading() and Time.get_ticks_msec()-start<300000:
		await process_frame
	var loaded:=is_instance_valid(a) and is_instance_valid(b) and a.is_loaded and b.is_loaded and viewer.total_splats_to_load==7959786
	print("FULL BALI AND SUZUKI ",loaded," count ",viewer.total_splats_to_load," load_ms ",Time.get_ticks_msec()-start)
	if not loaded:scene.free();quit(1);return
	var ui=scene.get_node("ProductionUI")
	ui.color_panel.apply_profile("Natural")
	viewer.select_model_id(a.model_id)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://bali-selected-natural.png")
	var natural:=viewer.render_texture.get_image()
	viewer.select_model_id("")
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var unselected:=viewer.render_texture.get_image()
	# GPU workgroup reservation can reorder equal-depth contributors; compare
	# measured color drift, rather than treating byte-identical frames as guaranteed.
	var drift:=0.0
	var samples:=0
	for y in range(0,natural.get_height(),12):
		for x in range(0,natural.get_width(),12):
			var first:=natural.get_pixel(x,y)
			var second:=unselected.get_pixel(x,y)
			drift+=Vector3(first.r,first.g,first.b).distance_to(Vector3(second.r,second.g,second.b))
			samples+=1
	drift/=maxi(1,samples)
	var same:=drift<0.005
	print("SELECTED BALI COLOR DRIFT ",drift," acceptable ",same)
	viewer.select_model_id(a.model_id)
	ui.transform_controls.set_mode(GSModelTransformControls.Mode.MOVE)
	ui.color_panel.show_panel()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://bali-color-panel.png")
	print("BALI COLOR STATS ",viewer.get_stats())
	scene.free();await process_frame
	print("BALI COLOR COMPLETE ",same)
	quit(0 if same else 1)
