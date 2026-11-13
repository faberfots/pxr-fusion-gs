extends SceneTree
const Checks = preload("res://tests/core_checks.gd")
var failures: Array[String] = []
var picked := Vector3.INF
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func _initialize() -> void: call_deferred("run")
func wait_for_occlusion(pixel:Vector2i)->Color:
	# Mesh changes do not move the GS camera. Respect the configured idle cadence
	# instead of assuming fifteen process frames include a fresh compositor frame.
	var started:=Time.get_ticks_msec()
	var color:=Color.BLACK
	while Time.get_ticks_msec()-started<2000:
		await RenderingServer.frame_post_draw
		color=root.get_texture().get_image().get_pixelv(pixel)
		if color.g>0.8 and color.r<0.05:return color
		await process_frame
	return color
func run() -> void:
	var viewer := GaussianSplattingViewer.new()
	viewer.config = GaussianSplattingConfig.create_default()
	viewer.config.memory_max_vram_budget_mb = 32
	viewer.config.post_sharpness = 0.0
	root.add_child(viewer)
	var device_name:=RenderingServer.get_rendering_device().get_device_name()
	check(root.msaa_3d==GaussianSplattingRasterizer.scene_msaa_mode(root.msaa_3d,device_name),"viewport uses a qualified native scene-depth sample count")
	viewer.load_new_splat_from_path(Checks.fixture("user://pixel.ply", 1))
	for i in range(60): await process_frame
	viewer.camera_controller.position_camera_at(Vector3(0, 0, 1), Vector3.ZERO)
	for i in range(15): await process_frame
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var pixel := Vector2i(image.get_width() / 2, image.get_height() / 2)
	var center := image.get_pixelv(pixel)
	print("VISIBLE PIXEL ", center)
	check(center.r > 0.1, "Gaussian visible through actual projection and display")
	var context := SceneContext.get_context_payload(viewer.get_camera())
	check(context.visible_objects.size() == 1 and context.visible_objects[0].model_id == viewer.get_model_snapshot()[0].model_id, "AI context contains stable visible model identity")
	var overlay := CanvasLayer.new()
	var panel := ColorRect.new()
	panel.color = Color.MAGENTA
	panel.size = Vector2(root.size)
	overlay.add_child(panel)
	root.add_child(overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = await ViewportCapture.capture_scene_only(root)
	check(capture != null and capture.get_pixelv(pixel).b < 0.8 and overlay.visible, "single scene capture excludes and restores UI overlays")
	overlay.free()
	viewer.rasterizer.pick_completed.connect(func(_id, position): picked = position)
	viewer.rasterizer.request_pick(Vector2(pixel), 500)
	for i in range(15): await process_frame
	check(picked.is_finite() and picked.length() < 0.01, "asynchronous per-pixel world picking")
	var blocker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	blocker.mesh = quad
	blocker.position = Vector3(0, 0, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.GREEN
	blocker.material_override = material
	root.add_child(blocker)
	for i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	center = await wait_for_occlusion(pixel)
	print("OCCLUDED PIXEL ", center)
	check(center.g > 0.8 and center.r < 0.05, "opaque Godot geometry occludes Gaussian")
	var demo: Node = load("res://main.tscn").instantiate()
	blocker.material_override = demo.get_node("CSGBox3D").material_override
	demo.free()
	viewer._force_redraw = true
	for i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	center = root.get_texture().get_image().get_pixelv(pixel)
	check(center.r > 0.1, "demo reference grid remains behind Gaussians without disabling ordinary opaque occlusion")
	blocker.free()
	viewer.get_camera().projection = Camera3D.PROJECTION_ORTHOGONAL
	viewer.get_camera().size = 1.0
	for i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	center = root.get_texture().get_image().get_pixelv(pixel)
	check(center.r > 0.1, "orthographic Gaussian projection")
	viewer.config.tile_size=8
	var migration_started:=Time.get_ticks_msec()
	for i in range(300):
		await process_frame
		if i>3 and not viewer._applying_config:break
	await RenderingServer.frame_post_draw
	center=root.get_texture().get_image().get_pixelv(pixel)
	check(center.r>0.1,"Gaussian display remains visible after live atlas migration")
	var model:GaussianSplat=viewer.managed_splats.keys()[0]
	model.global_position.x=4.0
	for i in range(15):await process_frame
	await RenderingServer.frame_post_draw
	center=root.get_texture().get_image().get_pixelv(pixel)
	check(center.r<0.05,"migrated renderer presents live transform updates instead of a frozen frame")
	viewer.free()
	await process_frame
	print("RENDERING COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
