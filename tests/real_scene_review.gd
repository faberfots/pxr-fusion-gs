extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		printerr("Provide a local Gaussian PLY path after --")
		quit(1)
		return
	var viewer := GaussianSplattingViewer.new()
	viewer.config = GaussianSplattingConfig.create_default()
	viewer.config.memory_max_vram_budget_mb = 512
	viewer.config.post_sharpness = 0.0
	root.add_child(viewer)
	var started := Time.get_ticks_msec()
	var model := viewer.load_new_splat_from_path(arguments[0])
	if not model:
		quit(1)
		return
	while viewer.is_loading() and Time.get_ticks_msec() - started < 60000:
		await process_frame
	if not model.is_loaded:
		printerr("REAL SCENE LOAD FAILED ", viewer.last_error)
		viewer.free()
		quit(1)
		return
	print("REAL SCENE LOADED ", model.splat_count, " splats in ", Time.get_ticks_msec() - started, " ms")
	viewer.set_scene_mode(GaussianSplattingViewer.SceneMode.OBJECT_MODE)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("user://real-scene-review.png")
	print("REAL SCENE STATS ", viewer.get_stats())
	print("REAL SCENE IMAGE ", ProjectSettings.globalize_path("user://real-scene-review.png"))
	var valid: bool = not viewer.rasterizer.get_stats().get("sort_overflow", false)
	viewer.free()
	await process_frame
	quit(0 if valid else 1)
