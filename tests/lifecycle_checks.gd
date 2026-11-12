extends SceneTree
const Checks = preload("res://tests/core_checks.gd")
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func drain(viewer: GaussianSplattingViewer) -> void:
	for frame in range(300):
		await process_frame
		if not viewer.is_loading(): return
	check(false, "load deadline")
func run() -> void:
	var first := Checks.fixture("user://one.ply", 3)
	var second := Checks.fixture("user://two.ply", 7)
	var viewer := GaussianSplattingViewer.new()
	viewer.config = GaussianSplattingConfig.create_default()
	viewer.config.memory_max_vram_budget_mb = 32
	var authored := GaussianSplat.new()
	authored.file_path = first
	viewer.add_child(authored)
	root.add_child(viewer)
	check(viewer.rasterizer != null and viewer.rasterizer.gpu_init_complete, "fallback camera and GPU startup")
	var added := viewer.load_new_splat_from_path(second, GaussianSplattingViewer.LoadMode.APPEND)
	await drain(viewer)
	check(authored.is_loaded and is_instance_valid(added) and added.is_loaded and viewer.total_splats_to_load == 10, "authored model and queued append both load")
	var old_offset := authored.buffer_offset
	authored.free()
	await process_frame
	check(viewer.total_splats_to_load == 7 and viewer.managed_splats.size() == 1, "deletion removes residency")
	var bytes: PackedByteArray = viewer.rasterizer._sync(func(): return viewer.rasterizer.context.device.buffer_get_data(viewer.rasterizer.descriptors.splats.rid, old_offset, 720))
	check(bytes.count(0) == bytes.size(), "deleted GPU slots zeroed")
	check(viewer.rasterizer.resize(Vector2i(96, 96)) == OK, "transactional viewport resize")
	viewer._clear_scene_and_reset_atlas()
	await process_frame
	check(viewer.total_splats_to_load == 0 and viewer.rasterizer.allocator.high_water_splats() == 0, "clear resets live high water")
	var again := viewer.load_new_splat_from_path(first)
	await drain(viewer)
	check(is_instance_valid(again) and again.is_loaded and viewer.total_splats_to_load == 3, "reload after reset")
	if is_instance_valid(again): again.file_path = second
	await drain(viewer)
	check(is_instance_valid(again) and again.is_loaded and viewer.total_splats_to_load == 7, "path revision reload")
	again.global_position = Vector3(10, 0, 0)
	await process_frame
	check(viewer.get_scene_bounds().position.is_equal_approx(Vector3(4, 0, 0)) and viewer.get_scene_bounds().end.is_equal_approx(Vector3(10, 0, 0)), "source basis and node bounds applied once")
	check(viewer.select_model_id(again.model_id) and viewer.get_selected_model() == again and not viewer.select_model_id("missing-model"), "selection uses stable loaded identity")
	var actions := ActionController.new()
	actions.policy = AIAccessPolicy.new()
	actions.policy.role = AIAccessPolicy.Role.OPERATOR
	actions.policy.actions_enabled = true
	root.add_child(actions)
	check(actions.execute_action("select_object", {"model_id": "missing-model"}).status == "error", "unknown AI model selection fails truthfully")
	check(actions.execute_action("select_object", {"model_id": again.model_id}).status == "success", "AI selects actual loaded model")
	check(actions.execute_action("move_camera", {"position": [1, 2]}).status == "error", "malformed authorized camera action rejected")
	check(actions.execute_action("move_camera", {"position": [0, 1, 3], "look_at": [0, 0, 0]}).status == "success" and viewer.get_camera().global_position.is_equal_approx(Vector3(0, 1, 3)), "camera action reports completed transform")
	actions.free()
	var previous_signature := viewer.config.gpu_signature()
	var identity := again.model_id
	var pose := again.global_transform
	var original_data: PackedByteArray = viewer.rasterizer._sync(func(): return viewer.rasterizer.context.device.buffer_get_data(viewer.rasterizer.descriptors.splats.rid,again.buffer_offset,again.splat_count*240))
	viewer.config.tile_size = 8
	for i in range(60):
		await process_frame
		if not viewer._applying_config and not viewer._queued_configuration and i>2: break
	check(viewer.config.gpu_signature() != previous_signature and again.is_loaded, "populated atlas migrates to new structural settings")
	check(again.model_id == identity and again.global_transform.is_equal_approx(pose) and viewer.get_selected_model() == again, "atlas migration preserves stable model identity, transform and selection")
	var migrated_data: PackedByteArray = viewer.rasterizer._sync(func(): return viewer.rasterizer.context.device.buffer_get_data(viewer.rasterizer.descriptors.splats.rid,again.buffer_offset,again.splat_count*240))
	check(migrated_data == original_data, "atlas migration preserves complete Gaussian bytes")
	var previous_instances := viewer.config.memory_max_instances
	viewer.config.memory_max_instances = 0
	for i in range(3): await process_frame
	check(viewer.config.memory_max_instances == previous_instances and again.is_loaded, "invalid migration rolls back without unloading content")

	var camera := viewer.get_camera()
	viewer.set_camera_blocker("test_a", true)
	viewer.set_camera_blocker("test_b", true)
	viewer.set_camera_blocker("test_a", false)
	check(not camera.enable_camera_movement, "independent camera blockers compose")
	viewer.set_camera_blocker("test_b", false)
	check(camera.enable_camera_movement, "camera resumes after final blocker")
	var bad_path := Checks.fixture("user://bad-body.ply", 1)
	var bad_file := FileAccess.open(bad_path, FileAccess.READ)
	var bad_text := bad_file.get_as_text().replace("0 0 0 -3", "invalid 0 0 -3")
	bad_file.close()
	bad_file = FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string(bad_text)
	bad_file.close()
	var completed := [0]
	var outcome := [0, 0]
	viewer.all_splats_loading_completed.connect(func(_count): completed[0] += 1)
	viewer.batch_finished.connect(func(successes, failed): outcome[0] = successes; outcome[1] = failed)
	var rejected := viewer.load_new_splat_from_path(bad_path)
	var accepted := viewer.load_new_splat_from_path(first)
	await drain(viewer)
	check(not rejected.is_loaded and accepted.is_loaded and outcome == [1, 1] and completed[0] == 0, "failed batch reports truthful outcomes and continues queue")
	viewer.free()
	await process_frame
	print("LIFECYCLE COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
