extends Node
## Separate qualification entry point: official release templates reject --script.
const Checks = preload("res://tests/core_checks.gd")
var failures: Array[String] = []
var scene: Node
var viewer: GaussianSplattingViewer
func _ready() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func settle(seconds: float = 0.2) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
func run() -> void:
	scene = load("res://main.tscn").instantiate()
	viewer = scene.get_node("GaussianSplattingViewer")
	check(viewer.config == null, "packaged real main begins without an injected configuration")
	add_child(scene)
	await settle()
	check(viewer.rasterizer != null and viewer.rasterizer.gpu_init_complete, "optimized release initializes the real viewer renderer")
	if not viewer.rasterizer or not viewer.rasterizer.gpu_init_complete:
		finish();return
	scene.get_node("DemoUIController").show_ui = false
	viewer.set_camera_blocker("qualification", true)
	var ui = scene.get_node("ProductionUI")
	ui.color_panel.show_panel()
	check(ui.color_panel.apply_profile("Warm daylight"), "packaged color panel opens and applies a preset")
	await settle()
	check(is_equal_approx(ui.color_panel.sliders.post_temperature.value, 0.3), "packaged color sliders synchronize with the authoritative configuration")
	ui.color_panel.apply_profile("Natural")
	ui.color_panel.hide_panel()
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	for index in range(args.size() - 1):
		if args[index] == "--dataset": paths.append(args[index + 1])
	if paths.is_empty():
		paths = [Checks.fixture("user://release-a.ply", 1), Checks.fixture("user://release-b.ply", 1)]
	var nodes: Array[GaussianSplat] = []
	for path in paths: nodes.append(viewer.load_new_splat_from_path(path))
	var started := Time.get_ticks_msec()
	await get_tree().process_frame
	while viewer.is_loading() and Time.get_ticks_msec() - started < 300000:
		await get_tree().process_frame
	var expected := 0
	for index in range(paths.size()):
		var ply := PlyFile.new()
		var parsed := ply.parse(paths[index]) == OK
		expected += ply.size if parsed else 0
		check(parsed and is_instance_valid(nodes[index]) and nodes[index].is_loaded, "packaged loader retains every source Gaussian: " + paths[index].get_file())
	check(expected > 0 and viewer.total_splats_to_load == expected, "packaged atlas contains the full combined population")
	print("RELEASE POPULATION ", viewer.total_splats_to_load, " load_ms ", Time.get_ticks_msec() - started)
	if nodes.is_empty() or not is_instance_valid(nodes[0]):
		finish();return
	viewer.select_model_id(nodes[0].model_id)
	var original := nodes[0].global_transform
	var second := nodes[1].global_transform if nodes.size() > 1 else Transform3D.IDENTITY
	var changed := original.scaled_local(Vector3(1.1, 0.9, 1.2)).rotated_local(Vector3.UP, 0.2)
	changed.origin += Vector3(0.1, 0.2, 0.3)
	nodes[0].global_transform = changed
	await settle()
	check(not nodes[0].global_transform.is_equal_approx(original), "packaged model retains independent XYZ translation, rotation and scale")
	check(nodes.size() < 2 or nodes[1].global_transform.is_equal_approx(second), "packaged edits preserve the other model")
	nodes[0].global_transform = original
	await settle()
	ui.transform_controls.set_mode(GSModelTransformControls.Mode.MOVE)
	ui.color_panel.show_panel()
	await settle()
	get_viewport().get_texture().get_image().save_png("user://release-controls.png")
	ui.color_panel.hide_panel()
	# The identity of the actually running executable is checked by the host tool.
	check(not OS.has_feature("editor"), "qualification runs in a true export template")
	check(NativeMLBridge.availability().available, "optimized release verifies native models and CPU runtime")
	var segmenter := NativeMLBridge.load_default_segmenter()
	check(segmenter != null and segmenter.call("is_ready"), "optimized release initializes the real native ML bridge")
	if segmenter:
		var image:=Image.create(640,384,false,Image.FORMAT_RGB8)
		image.fill(Color8(235,235,235))
		for y in range(384):
			for x in range(640):
				if pow((x-180.0)/110.0,2)+pow((y-190.0)/120.0,2)<=1.0:image.set_pixel(x,y,Color8(200,35,30))
		check(segmenter.call("encode_image",image),"optimized release encodes an actual non-square RGB image")
		var mask:PackedByteArray=segmenter.call("segment_with_points",PackedVector2Array([Vector2(180,190)]),PackedInt32Array([1]))
		check(mask.size()==640*384 and mask[190*640+180]>0 and mask[20*640+20]==0,"optimized release decodes a real prompt-conditioned mask at original image dimensions")
	segmenter = null
	finish()
func finish() -> void:
	if is_instance_valid(scene): scene.queue_free()
	for i in range(5): await get_tree().process_frame
	print("RELEASE CHECKS COMPLETE: ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
