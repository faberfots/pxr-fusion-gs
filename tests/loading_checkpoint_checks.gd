extends SceneTree
const Checks = preload("res://tests/core_checks.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func bytes_for(viewer: GaussianSplattingViewer, node: GaussianSplat) -> PackedByteArray:
	return viewer.rasterizer._sync(func(): return viewer.rasterizer.context.device.buffer_get_data(viewer.rasterizer.descriptors.splats.rid, node.buffer_offset, node.splat_count * 240))
func run() -> void:
	var viewer := GaussianSplattingViewer.new()
	viewer.config = GaussianSplattingConfig.create_default()
	viewer.config.memory_max_vram_budget_mb = 160
	viewer.config.loading_gpu_block_splats = 4096
	viewer.config.loading_cache_directory = "user://checkpoint-cache-%d" % Time.get_ticks_usec()
	root.add_child(viewer)
	var source := Checks.fixture("user://checkpoint-exact.ply", 40000)
	var a := viewer.load_new_splat_from_path(source)
	while viewer.is_loading(): await process_frame
	var b := viewer.load_new_splat_from_path(source)
	while viewer.is_loading(): await process_frame
	a.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.3, -0.2)).scaled(Vector3(0.8, 1.2, 0.9)), Vector3(1, 2, 3))
	var originals := {a.model_id: bytes_for(viewer, a), b.model_id: bytes_for(viewer, b)}
	check(viewer.get_load_profiles().back().cache_hit, "checkpoint fixture includes a prepared-cache reload with a different runtime identity and time")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source))
	var checkpoint := GSAtlasMigration.new()
	check(await checkpoint.checkpoint(viewer.rasterizer, viewer._records, self) == OK, "checkpoint succeeds after the original source has been removed")
	check(checkpoint.profile.get("backend") == "prepared_exact", "resident checkpoint uses verified disk preparation without global atlas readback")
	var file := FileAccess.open(checkpoint.path, FileAccess.READ)
	var exact := true
	for entry in checkpoint.entries:
		file.seek(entry.file_offset)
		exact = exact and file.get_buffer(int(entry.count) * 240) == originals[entry.model_id]
	file.close()
	check(exact, "all resident Gaussian bytes, runtime IDs and per-block timestamps match the GPU atlas exactly")
	checkpoint.dispose()
	var reference: Dictionary = viewer._records[a.get_instance_id()].prepared_reference
	var meta := GSPreparedCache.new(); meta.directory = reference.directory
	var cache := meta.candidate(reference.source, a.splat_count, reference.bytes)
	var damaged := FileAccess.open(cache.payload, FileAccess.READ_WRITE)
	damaged.seek(100); var old := damaged.get_8(); damaged.seek(100); damaged.store_8(old ^ 1); damaged.close(); meta.release()
	checkpoint = GSAtlasMigration.new()
	check(await checkpoint.checkpoint(viewer.rasterizer, viewer._records, self) == OK and checkpoint.profile.get("backend") == "gpu_readback", "corrupt prepared data falls back to resident GPU recovery without requiring an original file")
	file = FileAccess.open(checkpoint.path, FileAccess.READ); exact = true
	for entry in checkpoint.entries:
		file.seek(entry.file_offset); exact = exact and file.get_buffer(int(entry.count) * 240) == originals[entry.model_id]
	file.close(); checkpoint.dispose()
	check(exact and a.is_loaded and b.is_loaded, "fallback checkpoint preserves both original populations byte for byte")
	viewer.free(); await process_frame
	print("LOADING CHECKPOINT COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
