extends SceneTree
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Supply the large scene and a second Gaussian PLY path after --")
		quit(1)
		return
	var scene: Node = load("res://main.tscn").instantiate()
	var viewer: GaussianSplattingViewer = scene.get_node("GaussianSplattingViewer")
	viewer.config = GaussianSplattingConfig.new()
	viewer.config.apply_preset(GaussianSplattingConfig.QualityPreset.HIGH)
	scene.get_node("DemoUIController").show_ui = false
	root.add_child(scene)
	# Keep off-screen qualification independent of live desktop input.
	scene.get_node("DemoUIController").set_process(false)
	root.gui_disable_input = true
	viewer.set_process_unhandled_input(false)
	check(viewer.rasterizer != null and viewer.rasterizer.gpu_init_complete, "High atlas initializes")
	var first := viewer.load_new_splat_from_path(args[0])
	var second := viewer.load_new_splat_from_path(args[1])
	check(is_instance_valid(first) and is_instance_valid(second), "Bali and second model admitted by shared atlas")
	if not first or not second:
		scene.free()
		quit(1)
		return
	var start := Time.get_ticks_msec()
	var last_progress := 0
	while viewer.is_loading() and Time.get_ticks_msec() - start < 240000:
		await process_frame
		if Time.get_ticks_msec() - last_progress > 5000:
			last_progress = Time.get_ticks_msec()
			print("LARGE LOAD PROGRESS ", viewer.splat_progress_counter[0], " splats; ", Time.get_ticks_msec() - start, " ms")
	check(first.is_loaded and second.is_loaded, "both complete files loaded without downsampling")
	if not first.is_loaded or not second.is_loaded:
		printerr(viewer.last_error)
		scene.free()
		quit(1)
		return
	print("LARGE LOAD COMPLETE ", viewer.total_splats_to_load, " splats in ", Time.get_ticks_msec() - start, " ms")
	check(viewer.get_model_snapshot().size() == 2 and viewer.total_splats_to_load == first.splat_count + second.splat_count, "exactly the two requested models own the full atlas population")
	viewer.select_model_id("")
	# Qualify the actual UI and depth-integrated presentation, not only a raw GPU texture.
	var settle := Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 3000: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://bali-main-review.png")
	var before := first.global_transform
	second.global_transform = Transform3D(Basis.from_euler(Vector3(0.3, -0.4, 0.6)).scaled(Vector3(0.7, 0.9, 1.1)), Vector3(3, 2, -4))
	await process_frame
	await process_frame
	check(first.global_transform.is_equal_approx(before), "second model XYZ rotation/scale/position leaves Bali unchanged")
	check(palette_matches(viewer, second), "second model Transform3D reaches its own GPU palette entry")
	var second_before := second.global_transform
	first.global_transform = Transform3D(Basis.from_euler(Vector3(0.01, 0.02, -0.03)).scaled(Vector3.ONE * 0.95), Vector3(1.5, -2, 3.5))
	await process_frame
	await process_frame
	check(second.global_transform.is_equal_approx(second_before), "Bali XYZ rotation/scale/position leaves second model unchanged")
	check(palette_matches(viewer, first), "Bali Transform3D reaches its own GPU palette entry")
	first.global_transform = before
	# Exercise the existing Scene Manager controls on the second model.
	var panel = scene.get_node("SceneManagerPanel")
	panel._on_object_selected(second)
	panel._on_pos_x_changed(-2.0)
	panel._on_pos_y_changed(-0.9)
	panel._on_pos_z_changed(-2.0)
	panel._on_rot_x_changed(3.0)
	panel._on_rot_y_changed(30.0)
	panel._on_rot_z_changed(-2.0)
	panel._on_scale_changed(0.7)
	panel._sync_ui_to_node_transform()
	check(second.global_position.is_equal_approx(Vector3(-2,-0.9,-2)), "Scene Manager moves the selected model on all XYZ axes")
	check(second.global_rotation_degrees.is_equal_approx(Vector3(3,30,-2)), "Scene Manager rotates XYZ after scaling without corrupting angles")
	check(second.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE*0.7), "Scene Manager scales the selected model")
	check(first.global_transform.is_equal_approx(before), "Scene Manager edits preserve the other model transform")
	for i in range(3): await process_frame
	check(palette_matches(viewer, second), "Scene Manager edits reach the selected GPU palette entry")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://bali-multiple-review.png")
	panel.show()
	for i in range(2): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://bali-transform-controls.png")
	if args.size() > 2 and args[2] == "object":
		var framed := Time.get_ticks_msec()
		viewer.set_scene_mode(GaussianSplattingViewer.SceneMode.OBJECT_MODE)
		for i in range(2): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://bali-object-review.png")
		print("OBJECT MODE CAPTURE MS ",Time.get_ticks_msec()-framed)
	print("LARGE SCENE STATS ", viewer.get_stats())
	check(not viewer.rasterizer.get_stats().get("sort_overflow", false), "large multi-model frame stays within pair capacity")
	scene.free()
	await process_frame
	print("LARGE SCENE COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func palette_matches(viewer: GaussianSplattingViewer, model: GaussianSplat) -> bool:
	var id: int = viewer._node_to_instance_id[model]
	var bytes: PackedByteArray = viewer.rasterizer._sync(func(): return viewer.rasterizer.context.device.buffer_get_data(viewer.rasterizer.descriptors.instance_transforms.rid, id * 64, 64))
	var expected := RenderingContext.pack_projection(Projection(Transform3D(viewer.rasterizer.basis_override.inverse(), Vector3.ZERO) * model.global_transform * Transform3D(viewer.config.source_basis(), Vector3.ZERO)))
	for i in range(16):
		if absf(bytes.decode_float(i * 4) - expected.decode_float(i * 4)) > 0.00001: return false
	return true
