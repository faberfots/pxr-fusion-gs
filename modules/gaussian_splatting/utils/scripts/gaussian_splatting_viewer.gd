class_name GaussianSplattingViewer
extends Node3D
## Scene/command owner. Jobs own CPU decoding; rasterizer owns all RD operations.
signal all_splats_loading_started
signal all_splats_loading_completed(total_splat_count: int)
signal loading_started(file_path: String)
signal loading_completed(file_path: String, splat_count: int)
signal splat_loading_progress(progress: float, splats_loaded: int, total_splats: int)
signal error_occurred(error_message: String, error_code: int)
signal render_state_changed(is_rendering: bool)
signal camera_movement_changed(is_moving: bool)
signal splat_clicked(world_position: Vector3)
signal stats_updated(stats: Dictionary)
signal load_zone_visibility_changed(is_visible: bool)
signal scene_mode_changed(mode: SceneMode, mode_name: String)
signal model_registry_changed
signal selection_changed(model_id: String)
var selected_model_id := ""
var selected_model_ids: Array[String] = []
signal multi_selection_changed(model_ids: Array[String])
var _selection_additive := false
var _transform_undo: Array[Dictionary] = []
var _transform_redo: Array[Dictionary] = []
signal configuration_applied(settings: GaussianSplattingConfig)
signal batch_finished(successes: int, failures: int)
const ViewerState = GSStateMachine.State
enum LoadMode { REPLACE, APPEND, SMART }
enum SceneMode { UNKNOWN, OBJECT_MODE, ENVIRONMENT_MODE }
@export var config: GaussianSplattingConfig:
	set(value):
		config = value
		if _ready_complete and not _applying_config:
			call_deferred("_apply_config")
@export var lighting:GSLightingSettings=GSLightingSettings.new()
@export var shadow_light:DirectionalLight3D
var _shadow_signature:=0
var _shadow_error:=false
@export var load_splats_on_ready := true
@export var auto_start_rendering := true
@export var show_loading_ui := false
@export var enable_debug_stats := false
@export var environment_size_threshold := GSConstants.ENVIRONMENT_SIZE_THRESHOLD_M
@export_group("Smart Camera")
@export_range(0.0, 1.0, 0.05) var smart_camera_clearance_factor := 0.5
@export_group("Integrations")
@export var event_bus: GSEventBus
@export var preloader: GSPreloader
@export var memory_monitor: GSMemoryMonitor
@export var camera_controller: CameraController
@export_dir var spatial_shader_directory := "res://modules/gaussian_splatting/shaders/spatial"
@export_dir var compute_shader_directory := "res://modules/gaussian_splatting/shaders/compute"
var rendered_mesh: MeshInstance3D
var rendered_material: ShaderMaterial
var loading_bar: LoadingBar
var stats_timer: Timer
var rasterizer: GaussianSplattingRasterizer
var render_texture: Texture2DRD
var current_scene_mode := SceneMode.UNKNOWN
var _state_machine := GSStateMachine.new()
var current_state: GSStateMachine.State:
	get: return _state_machine.current_state
	set(value): _state_machine.transition_to(value)
var show_load_zone := false:
	set(value):
		if show_load_zone != value:
			show_load_zone = value
			load_zone_visibility_changed.emit(value)
var managed_splats: Dictionary:
	get:
		var result := {}
		for record in _records.values():
			var node = record.node.get_ref()
			if is_instance_valid(node):
				result[node] = record.resource
		return result
var _node_to_instance_id: Dictionary:
	get:
		var result := {}
		for record in _records.values():
			var node = record.node.get_ref()
			if is_instance_valid(node) and int(record.instance_id) > 0:
				result[node] = record.instance_id
		return result
var total_splats_to_load: int:
	get:
		var count := 0
		for record in _records.values():
			if record.status == "loaded":
				count += int(record.count)
		return count
var splat_progress_counter: Array[int] = [0]
var last_error := ""
var frame_count := 0
var time_accumulator := 0.0
var _records: Dictionary = {}
var _pending: Array[int] = []
var _free_instance_ids: Array[int] = []
var _active_job: GSLoadJob
var _active_node_id := 0
var _generation := 0
var _ready_complete := false
var _clearing := false
var _applying_config := false
var _queued_configuration: GaussianSplattingConfig
var _atlas_migration: GSAtlasMigration
var _deferred_registration: Array[WeakRef] = []
var _clear_after_migration := false
signal configuration_migration_changed(active: bool)
signal configuration_migration_progress(fraction:float)

var _applied_config: GaussianSplattingConfig
var _compositor: GSCompositorEffect
var _compositor_camera: Camera3D
var _request_serial := 0
var _batch_total := 0
var _batch_loaded := 0
var _batch_successes := 0
var _batch_failures := 0
var _initial_framing := true
var _last_activity := 0.0
var _idle_elapsed := 0.0
var _last_basis := Basis.IDENTITY
var _force_redraw := true
var _color_comparison := false
var _selection_pick_request := -1
var _left_press := Vector2.INF
var _hybrid_nodes: Array[GSAlphaMesh3D] = []
var _hybrid_signature := 0
var _hybrid_error := ""
signal model_clicked(model_id:String,world_position:Vector3)

func _enter_tree() -> void:
	add_to_group("gaussian_splat_viewers")

func _ready() -> void:
	_state_machine.state_changed.connect(_on_state_changed)
	model_registry_changed.connect(func():
		_force_redraw = true
		_selection_pick_request=-1
		if rasterizer:rasterizer.cancel_pick()
	)
	if not config:
		config = GaussianSplattingConfig.create_default()
	if not config.validate():
		_report_error("Invalid configuration: " + "; ".join(config.validation_errors()), ERR_INVALID_PARAMETER, true)
		return
	_initialize_components()
	if not camera_controller or not get_camera():
		_report_error("No usable viewer camera", ERR_UNAVAILABLE, true)
		return
	_ready_complete = true
	_connect_config()
	_apply_config()
	if not rasterizer or not rasterizer.gpu_init_complete:
		return
	if load_splats_on_ready:
		_discover_owned_splats(self)
	if _pending.is_empty() and not _active_job:
		current_state = ViewerState.READY
		if auto_start_rendering:
			start_rendering()

func _initialize_components() -> void:
	var device:=RenderingServer.get_rendering_device()
	if device:
		var viewport:=get_viewport()
		var scene_msaa:=GaussianSplattingRasterizer.scene_msaa_mode(viewport.msaa_3d,device.get_device_name())
		if scene_msaa!=viewport.msaa_3d:
			viewport.msaa_3d=scene_msaa as Viewport.MSAA
			print("[GSViewer] Using native 4x scene MSAA for llvmpipe depth integration.")
	render_texture = Texture2DRD.new()
	rendered_mesh = get_node_or_null("RenderedSplats")
	if not rendered_mesh:
		rendered_mesh = MeshInstance3D.new()
		rendered_mesh.name = "RenderedSplats"
		add_child(rendered_mesh)
	var quad := QuadMesh.new()
	quad.flip_faces = true
	quad.size = Vector2(2, 2)
	rendered_mesh.mesh = quad
	rendered_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rendered_mesh.extra_cull_margin = 16384.0
	rendered_material = ShaderMaterial.new()
	rendered_material.shader = load(spatial_shader_directory.path_join("main.gdshader"))
	rendered_mesh.set_surface_override_material(0, rendered_material)
	rendered_material.set_shader_parameter("render_texture", render_texture)
	if not camera_controller:
		_create_default_camera_system()
	camera_controller.camera_switched.connect(_on_camera_switched)
	camera_controller.camera_movement_changed.connect(func(moving): camera_movement_changed.emit(moving))
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)
	if show_loading_ui:
		loading_bar = LoadingBar.new()
		loading_bar.color = Color(1, 1, 1, 0)
		loading_bar.size = Vector2(viewport.size.x, 5)
		var layer := CanvasLayer.new()
		layer.name = "LoadingUI"
		layer.add_child(loading_bar)
		add_child(layer)
	stats_timer = get_node_or_null("StatsTimer")
	if not stats_timer:
		stats_timer = Timer.new()
		stats_timer.name = "StatsTimer"
		add_child(stats_timer)
	stats_timer.timeout.connect(func():
		if enable_debug_stats:
			stats_updated.emit(get_stats())
	)
	stats_timer.start(config.debug_update_interval)
	if event_bus:
		loading_started.connect(func(path): event_bus.emit_event(GSEventBus.EVENT_LOADING_STARTED, {"file_path": path}))
		loading_completed.connect(func(path, count): event_bus.emit_event(GSEventBus.EVENT_LOADING_COMPLETED, {"file_path": path, "splat_count": count}))
		splat_loading_progress.connect(func(progress, count, total): event_bus.emit_loading_progress(progress, count, total))
		error_occurred.connect(func(message, code): event_bus.emit_error(message, code))
		render_state_changed.connect(func(rendering): event_bus.emit_event(GSEventBus.EVENT_RENDER_STATE_CHANGED, {"is_rendering": rendering}))
		scene_mode_changed.connect(func(mode, label): event_bus.emit_event(GSEventBus.EVENT_SCENE_MODE_CHANGED, {"mode": mode, "mode_name": label}))

func _connect_config() -> void:
	if config and not config.config_changed.is_connected(_queue_config_application):
		config.config_changed.connect(_queue_config_application)

func _queue_config_application() -> void:
	call_deferred("_apply_config")

func _apply_config() -> void:
	if not _ready_complete: return
	if _applying_config:
		_queued_configuration = config.duplicate(true)
		return
	_applying_config = true
	if not config.validate():
		_report_error("Configuration rejected: " + "; ".join(config.validation_errors()), ERR_INVALID_PARAMETER)
		if _applied_config:
			config = _applied_config.duplicate(true)
		_applying_config = false
		_connect_config()
		return
	if _only_color_changed():
		_update_color_uniforms()
		_applied_config=config.duplicate(true)
		_applying_config=false
		_connect_config()
		configuration_applied.emit(config)
		_apply_queued_configuration.call_deferred()
		return
	var gpu_changed := _applied_config == null or config.gpu_signature() != _applied_config.gpu_signature()
	if gpu_changed and not _records.is_empty():
		if is_loading():
			_queued_configuration = config.duplicate(true)
			config = _applied_config.duplicate(true)
			_applying_config = false
			_connect_config()
			configuration_applied.emit(config)
			return
		var requested := config.duplicate(true)
		var migrated: Error = await _migrate_atlas(requested)
		if migrated != OK:
			_report_error("GPU configuration preserved: " + error_string(migrated), migrated)
			config = _applied_config.duplicate(true)
			_applying_config = false
			_connect_config()
			configuration_applied.emit(config)
			_apply_queued_configuration.call_deferred()
			return
		config = requested
		gpu_changed = false

	if gpu_changed:
		if rasterizer:
			_detach_compositor()
			rasterizer.cleanup()
		rasterizer = GaussianSplattingRasterizer.new(get_viewport().size, render_texture, get_camera(), config)
		rasterizer.compute_shader_path = compute_shader_directory
		var result := rasterizer.init_gpu()
		if result != OK and _applied_config:
			_report_error("GPU configuration was rejected; restoring previous settings: " + error_string(result), result)
			rasterizer.cleanup()
			config = _applied_config.duplicate(true)
			rasterizer = GaussianSplattingRasterizer.new(get_viewport().size, render_texture, get_camera(), config)
			rasterizer.compute_shader_path = compute_shader_directory
			result = rasterizer.init_gpu()
		if result != OK:
			_report_error("Cannot initialize the GS renderer: " + error_string(result), result, true)
			_applying_config = false
			return
		_connect_renderer_signals()
		_free_instance_ids.clear()
		for i in range(config.memory_max_instances, 0, -1):
			_free_instance_ids.append(i)
		_attach_compositor(get_camera())
	else:
		rasterizer.render_scale[0] = config.default_render_scale
		rasterizer.model_scale[0] = config.default_model_scale
		rasterizer.should_enable_heatmap[0] = config.enable_heatmap_by_default
		var resize_result := rasterizer.resize(get_viewport().size)
		if resize_result != OK:
			rasterizer.render_scale[0] = _applied_config.default_render_scale
			config.default_render_scale = _applied_config.default_render_scale
			_report_error("Render scale exceeds available GPU texture headroom", resize_result)
	_update_color_uniforms()
	var camera_fov:=config.camera_default_fov
	if _applied_config and get_camera() and is_equal_approx(config.camera_default_fov,_applied_config.camera_default_fov):camera_fov=get_camera().fov
	camera_controller.apply_settings({"mouse_sensitivity": config.camera_mouse_sensitivity, "run_speed_multiplier": config.camera_run_speed_multiplier, "acceleration": config.camera_acceleration, "deceleration": config.camera_deceleration, "vel_multiplier": config.camera_velocity_multiplier, "fov": camera_fov})
	stats_timer.wait_time = config.debug_update_interval
	if memory_monitor:
		memory_monitor.vram_budget_mb = config.memory_max_vram_budget_mb
		memory_monitor.usage_provider = Callable(rasterizer, "get_stats")
	_applied_config = config.duplicate(true)
	_applying_config = false
	_connect_config()
	configuration_applied.emit(config)
	_apply_queued_configuration.call_deferred()
	_force_redraw = true
	_last_activity = 0.0
	if current_state == ViewerState.UNINITIALIZED or current_state == ViewerState.ERROR:
		current_state = ViewerState.READY

func _discover_owned_splats(parent: Node) -> void:
	for child in parent.get_children():
		if child is GaussianSplattingViewer and child != self:
			continue
		if child is GaussianSplat:
			register_splat(child)
		_discover_owned_splats(child)

func register_splat(node: GaussianSplat) -> void:
	if _atlas_migration:
		if is_instance_valid(node): _deferred_registration.append(weakref(node))
		return
	if _clearing or not _ready_complete or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var id := node.get_instance_id()
	if _records.has(id):
		if _records[id].path != node.file_path or _records[id].revision != node.revision:
			unregister_splat(node)
		else:
			return
	if not rasterizer or not rasterizer.gpu_init_complete:
		_report_error("Renderer is unavailable", ERR_UNAVAILABLE)
		return
	var metadata := PlyConverter.inspect(node.file_path, config.max_vertices)
	if metadata.has("error"):
		_report_error(metadata.error, metadata.get("code", ERR_FILE_CORRUPT))
		return
	var count: int = metadata.vertex_count
	var reserved := 0
	for record in _records.values():
		if record.status != "failed": reserved += int(record.count)
	if reserved + count > rasterizer.atlas_capacity_splats or _records.size() >= config.memory_max_instances:
		_report_error("Model exceeds the complete GPU budget or instance capacity. Existing content was preserved.", ERR_OUT_OF_MEMORY)
		return
	node.assign_viewer(self)
	for record in _records.values():
		var other = record.node.get_ref()
		if is_instance_valid(other) and other.model_id == node.model_id:
			node.model_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var resource := GaussianSplatResource.new()
	resource.splat_count = count
	resource.source_file = node.file_path
	_records[id] = {"node": weakref(node), "path": node.file_path, "revision": node.revision, "count": count, "status": "queued", "instance_id": 0, "offset": -1, "uploaded": 0, "resource": resource, "samples": PackedVector3Array(), "sum": Vector3.ZERO, "transform": Transform3D.IDENTITY, "visible": false}
	_pending.append(id)
	if _active_job:
		_batch_total += count
	model_registry_changed.emit()
	if not _active_job:
		_begin_batch()
		_start_next_job()

func load_new_splat_from_path(path: String, mode: LoadMode = LoadMode.SMART, transform: Transform3D = Transform3D.IDENTITY) -> GaussianSplat:
	if _atlas_migration:
		_report_error("Atlas configuration is being applied; retry loading when it completes.", ERR_BUSY)
		return null
	if not _ready_complete or not rasterizer or not rasterizer.gpu_init_complete:
		_report_error("Renderer is not ready", ERR_UNAVAILABLE)
		return null
	var metadata := PlyConverter.inspect(path, config.max_vertices)
	if metadata.has("error"):
		_report_error(metadata.error, metadata.get("code", ERR_FILE_CORRUPT))
		return null
	if int(metadata.vertex_count) > rasterizer.atlas_capacity_splats:
		_report_error("Atlas capacity exceeded: this model has %s splats; the current atlas holds %s. Choose a larger atlas budget or unload another model." % [metadata.vertex_count, rasterizer.atlas_capacity_splats], ERR_OUT_OF_MEMORY)
		return null
	# SMART safely appends. Replacing edited content requires an explicit REPLACE command.
	if mode == LoadMode.REPLACE:
		_clear_scene_and_reset_atlas()
	var count := int(metadata.vertex_count)
	var reserved := 0
	for record in _records.values():
		if record.status != "failed": reserved += int(record.count)
	if reserved + count > rasterizer.atlas_capacity_splats or _records.size() >= config.memory_max_instances:
		_report_error("Cannot append within the GPU budget. Clear the scene or explicitly choose Replace.", ERR_OUT_OF_MEMORY)
		return null
	var node := GaussianSplat.new()
	node.name = path.get_file().get_basename().validate_node_name()
	node.file_path = path
	node.transform = transform
	node.assign_viewer(self)
	add_child(node)
	register_splat(node)
	return node if _records.has(node.get_instance_id()) else null

func load_file(path: String) -> Error:
	return OK if load_new_splat_from_path(path, LoadMode.REPLACE) else FAILED

func _begin_batch() -> void:
	_batch_loaded = 0
	_batch_total = 0
	_batch_successes = 0
	_batch_failures = 0
	for id in _pending:
		if _records.has(id):
			_batch_total += int(_records[id].count)
	current_state = ViewerState.LOADING
	all_splats_loading_started.emit()

func _start_next_job() -> void:
	while not _pending.is_empty():
		var id: int = _pending.pop_front()
		if not _records.has(id):
			continue
		var record: Dictionary = _records[id]
		var node = record.node.get_ref()
		if not is_instance_valid(node):
			_records.erase(id)
			continue
		var offset := rasterizer.allocator.allocate(int(record.count) * GSConstants.SPLAT_STRUCT_BYTES)
		if offset < 0 or _free_instance_ids.is_empty():
			if offset >= 0:
				rasterizer.allocator.free_block(offset)
			_fail_record(id, "No contiguous atlas block or free instance identity", ERR_OUT_OF_MEMORY)
			continue
		record.offset = offset
		record.instance_id = _free_instance_ids.pop_back()
		record.status = "loading"
		rasterizer.update_instance_transform(record.instance_id, node.global_transform, false)
		_active_job = GSLoadJob.new()
		_request_serial += 1
		_active_job.request_id = _request_serial
		_active_job.generation = _generation
		_active_job.path = record.path
		_active_job.instance_id = record.instance_id
		_active_job.expected_count = record.count
		_active_job.max_vertices = config.max_vertices
		_active_job.chunk_size = config.loading_batch_size
		_active_node_id = id
		var result := _active_job.start()
		if result != OK:
			_active_job = null
			_fail_record(id, "Cannot start decoding worker", result)
			continue
		loading_started.emit(record.path)
		return
	_finish_batch()

func _pump_job() -> void:
	if not _active_job:
		return
	var id := _active_node_id
	if not _records.has(id) or not is_instance_valid(_records[id].node.get_ref()):
		_cancel_job()
		_start_next_job()
		return
	var record: Dictionary = _records[id]
	for _i in range(2):
		var chunk := _active_job.take_chunk()
		if chunk.is_empty():
			break
		var result := rasterizer.upload_splat_data(chunk.data, int(record.offset) + int(chunk.start) * GSConstants.SPLAT_STRUCT_BYTES)
		if result != OK:
			_cancel_job()
			_fail_record(id, "GPU upload admission failed", result)
			_start_next_job()
			return
		record.uploaded += int(chunk.count)
		_batch_loaded += int(chunk.count)
		splat_progress_counter[0] = _batch_loaded
	var snapshot := _active_job.result()
	var denominator := maxi(_batch_total, _batch_loaded)
	splat_loading_progress.emit(float(_batch_loaded) / maxi(1, denominator), _batch_loaded, denominator)
	if loading_bar:
		loading_bar.update_progress(float(_batch_loaded) / maxi(1, denominator))
	if not snapshot.done or not snapshot.empty:
		return
	_active_job.join()
	_active_job = null
	_active_node_id = 0
	if not snapshot.error.is_empty() or snapshot.cancelled or int(record.uploaded) != int(record.count):
		_fail_record(id, snapshot.error if not snapshot.error.is_empty() else "Load cancelled or incomplete", ERR_FILE_CORRUPT)
	else:
		rasterizer._sync(func(): return OK)
		record.resource.aabb = snapshot.aabb
		record.resource.position_sum = snapshot.sum
		record.samples = snapshot.samples
		record.sum = snapshot.sum
		record.status = "loaded"
		var node = record.node.get_ref()
		node.splat_count = record.count
		node.buffer_offset = record.offset
		node.is_loaded = true
		record.transform = node.global_transform
		record.visible = node.is_visible_in_tree()
		rasterizer.update_instance_transform(record.instance_id, record.transform, record.visible)
		_batch_successes += 1
		node.loaded.emit()
		loading_completed.emit(record.path, record.count)
		var history := get_node_or_null("/root/HistoryManager")
		if history:
			history.add_file(record.path)
		model_registry_changed.emit()
	_start_next_job()

func _fail_record(id: int, message: String, code: int) -> void:
	_batch_failures += 1
	if _records.has(id):
		var record: Dictionary = _records[id]
		_release_record(record)
		record.status = "failed"
	_report_error(message, code)
	model_registry_changed.emit()

func _finish_batch() -> void:
	current_state = ViewerState.READY
	batch_finished.emit(_batch_successes, _batch_failures)
	if _batch_failures == 0:
		all_splats_loading_completed.emit(total_splats_to_load)
	if loading_bar:
		loading_bar.set_visibility(false)
	if _initial_framing and total_splats_to_load > 0:
		recenter_camera()
		_initial_framing = false
	if auto_start_rendering:
		start_rendering()
	_last_activity = 0.0
	_apply_queued_configuration.call_deferred()

func _cancel_job() -> void:
	if _active_job:
		_active_job.cancel()
		_active_job.join()
	_active_job = null
	_active_node_id = 0

func _release_record(record: Dictionary) -> void:
	if _atlas_migration: return # Old ownership is released atomically with the old atlas.
	if rasterizer and rasterizer.gpu_init_complete:
		if int(record.instance_id) > 0:
			rasterizer.update_instance_transform(record.instance_id, Transform3D.IDENTITY, false)
		if int(record.offset) >= 0:
			rasterizer.clear_splat_data(record.offset, int(record.count) * GSConstants.SPLAT_STRUCT_BYTES)
			rasterizer.allocator.free_block(record.offset, int(record.count) * GSConstants.SPLAT_STRUCT_BYTES)
	if int(record.instance_id) > 0 and not record.instance_id in _free_instance_ids:
		_free_instance_ids.append(record.instance_id)
	record.instance_id = 0
	record.offset = -1
	var node = record.node.get_ref()
	if is_instance_valid(node):
		node.is_loaded = false
		node.splat_count = 0
		node.buffer_offset = 0

func unregister_splat(node: GaussianSplat) -> void:
	var id := node.get_instance_id()
	if not _records.has(id):
		return
	if _active_node_id == id:
		_cancel_job()
	var record: Dictionary = _records[id]
	if is_instance_valid(record.node.get_ref()) and selected_model_ids.has(record.node.get_ref().model_id):
		var remaining:=selected_model_ids.duplicate()
		remaining.erase(record.node.get_ref().model_id)
		select_model_ids(remaining)
	_records.erase(id)
	_transform_undo.assign(_transform_undo.filter(func(edit):return not edit.before.has(node.model_id)))
	_transform_redo.assign(_transform_redo.filter(func(edit):return not edit.before.has(node.model_id)))
	_pending.erase(id)
	_release_record(record)
	model_registry_changed.emit()
	_last_activity = 0.0
	if not _clearing and not _active_job and current_state == ViewerState.LOADING:
		call_deferred("_start_next_job")

func _clear_scene_and_reset_atlas() -> void:
	if _atlas_migration:
		_clear_after_migration = true
		return
	_clearing = true
	_apply_shadow_receivers({})
	_generation += 1
	_cancel_job()
	_pending.clear()
	var nodes: Array[Node] = []
	for record in _records.values():
		var node = record.node.get_ref()
		if is_instance_valid(node):
			nodes.append(node)
	_records.clear()
	select_model_id("")
	_transform_undo.clear();_transform_redo.clear()
	for node in nodes:
		node.is_loaded = false
		node.queue_free()
	if rasterizer:
		rasterizer.clear_gpu_memory()
	_free_instance_ids.clear()
	for i in range(config.memory_max_instances, 0, -1):
		_free_instance_ids.append(i)
	_initial_framing = true
	current_scene_mode = SceneMode.UNKNOWN
	splat_progress_counter[0] = 0
	current_state = ViewerState.READY
	_clearing = false
	model_registry_changed.emit()
	if event_bus:
		event_bus.emit_event(GSEventBus.EVENT_SCENE_CLEARED, {})
	if auto_start_rendering:
		start_rendering()

func _on_splat_node_changed(node: GaussianSplat) -> void:
	register_splat(node)

func _ensure_scene_splats_loaded() -> void:
	_discover_owned_splats(self)

func _process(delta: float) -> void:
	if not _ready_complete or _atlas_migration or not rasterizer or not rasterizer.gpu_init_complete:
		return
	_pump_job()
	_prepare_transparency()
	_prepare_shadows()
	var changed := rasterizer.update_camera_matrices()
	var basis_changed := rasterizer.basis_override != _last_basis
	_last_basis = rasterizer.basis_override
	for id in _records.keys():
		var record: Dictionary = _records[id]
		var node = record.node.get_ref()
		if not is_instance_valid(node):
			_release_record(record)
			_records.erase(id)
			continue
		if record.status != "loaded":
			continue
		var effective: bool = node.is_visible_in_tree()
		if basis_changed or not record.transform.is_equal_approx(node.global_transform) or effective != record.visible:
			record.transform = node.global_transform
			record.visible = effective
			rasterizer.update_instance_transform(record.instance_id, record.transform, effective)
			changed = true
			_force_redraw = true
	_last_activity = 0.0 if changed else _last_activity + delta
	_idle_elapsed += delta
	var due := _last_activity < config.pause_delay_seconds or _idle_elapsed >= 1.0 / config.paused_fps_limit
	rasterizer.rendering_enabled = (current_state == ViewerState.RENDERING and due) or _force_redraw
	if due:
		_idle_elapsed = 0.0
	rasterizer.selected_instance_id = _selected_instance_id()
	rasterizer.update_camera_matrices()
	_force_redraw = false
	if not _compositor:
		rasterizer.rasterize()
	frame_count += 1
	time_accumulator += delta

func _on_state_changed(previous: GSStateMachine.State, next: GSStateMachine.State) -> void:
	if (previous == ViewerState.RENDERING) != (next == ViewerState.RENDERING):
		render_state_changed.emit(next == ViewerState.RENDERING)

func start_rendering() -> void:
	if current_state == ViewerState.READY:
		current_state = ViewerState.RENDERING

func stop_rendering() -> void:
	if current_state == ViewerState.RENDERING:
		current_state = ViewerState.READY
	if rasterizer:
		rasterizer.rendering_enabled = false

func toggle_rendering() -> void:
	if is_rendering():
		stop_rendering()
	else:
		start_rendering()

func is_rendering() -> bool:
	return current_state == ViewerState.RENDERING

func is_loading() -> bool:
	return current_state == ViewerState.LOADING

func _on_viewport_resized() -> void:
	if rasterizer:
		var result := rasterizer.resize(get_viewport().size)
		if result == OK:
			_update_hybrid_presentation()
		if result != OK:
			_report_error("Viewport resize exceeds the total GPU budget; previous render size preserved", result)

func _attach_compositor(camera: Camera3D) -> void:
	if not is_instance_valid(camera):
		return
	_compositor = GSCompositorEffect.new()
	_compositor.rasterizer_ref = weakref(rasterizer)
	var compositor: Compositor = camera.compositor.duplicate() if camera.compositor else Compositor.new()
	var effects: Array[CompositorEffect] = compositor.compositor_effects.duplicate()
	effects.append(_compositor)
	compositor.compositor_effects = effects
	camera.compositor = compositor
	_compositor_camera = camera

func _detach_compositor() -> void:
	if is_instance_valid(_compositor_camera) and _compositor_camera.compositor:
		var effects: Array[CompositorEffect] = _compositor_camera.compositor.compositor_effects.duplicate()
		effects.erase(_compositor)
		_compositor_camera.compositor.compositor_effects = effects
	_compositor = null
	_compositor_camera = null

func _on_camera_switched(_previous: CameraInterface, next: CameraInterface) -> void:
	_detach_compositor()
	if rasterizer:
		rasterizer.camera = next
		_attach_compositor(next)

func set_camera(camera: CameraInterface) -> void:
	if camera_controller:
		camera_controller.set_camera(camera)

func get_camera() -> CameraInterface:
	return camera_controller.get_camera() if camera_controller else null

func set_camera_movement_enabled(enabled: bool) -> void:
	if camera_controller:
		camera_controller.set_movement_blocker("viewer_legacy", not enabled)

func set_camera_blocker(owner_id: StringName, blocked: bool) -> void:
	if camera_controller:
		camera_controller.set_movement_blocker(owner_id, blocked)

func reset_camera() -> void:
	recenter_camera()

func _world_transform(node: GaussianSplat) -> Transform3D:
	var transform: Transform3D = node.global_transform * Transform3D(config.source_basis(), Vector3.ZERO)
	if rasterizer:
		transform = Transform3D(rasterizer.basis_override.inverse(), Vector3.ZERO) * transform
		transform.origin *= float(rasterizer.model_scale[0])
		transform.basis = transform.basis.scaled(Vector3.ONE * float(rasterizer.model_scale[0]))
	return transform

func get_scene_bounds() -> AABB:
	var result := AABB()
	var first := true
	for record in _records.values():
		var node = record.node.get_ref()
		if record.status != "loaded" or not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var bounds: AABB = _world_transform(node) * record.resource.aabb
		result = bounds if first else result.merge(bounds)
		first = false
	return result

func recenter_camera(auto_mode: bool = true) -> void:
	var camera := get_camera()
	if not camera or total_splats_to_load == 0:
		return
	var bounds := get_scene_bounds()
	var size := maxf(bounds.get_longest_axis_size(), 0.1)
	if auto_mode: current_scene_mode = SceneMode.ENVIRONMENT_MODE if size >= environment_size_threshold else SceneMode.OBJECT_MODE
	scene_mode_changed.emit(current_scene_mode, SceneMode.keys()[current_scene_mode])
	var center := bounds.get_center()
	if current_scene_mode == SceneMode.ENVIRONMENT_MODE:
		var ys: Array = []
		var sum := Vector3.ZERO
		var total_weight := 0.0
		for record in _records.values():
			var node = record.node.get_ref()
			if record.status != "loaded" or not is_instance_valid(node) or not node.is_visible_in_tree() or record.samples.is_empty(): continue
			var transform := _world_transform(node)
			var take := mini(record.samples.size(), maxi(1, int(40000.0 * record.count / total_splats_to_load)))
			var weight := float(record.count) / take
			for i in range(take):
				var point: Vector3 = transform * record.samples[int(i * float(record.samples.size()) / take)]
				ys.append([point.y, weight])
				sum += point * weight
				total_weight += weight
		ys.sort_custom(func(a, b): return a[0] < b[0])
		var floor := bounds.position.y
		var cumulative := 0.0
		for sample in ys:
			cumulative += sample[1]
			if cumulative >= total_weight * 0.1:
				floor = sample[0]
				break
		var nexus := sum / total_weight if total_weight > 0 else center
		var position := Vector3(nexus.x, floor + GSConstants.STANDARD_EYE_HEIGHT_M, nexus.z)
		camera_controller.position_camera_at(position, position + Vector3.FORWARD)
	else:
		var distance := maxf(1.0, size * 0.75 / tan(deg_to_rad(camera.fov * 0.5)))
		camera_controller.position_camera_at(center + Vector3(0.75, 0.5, 1).normalized() * distance, center)
	if event_bus:
		event_bus.emit_event(GSEventBus.EVENT_CAMERA_POSITIONED, {"position": camera.global_position, "mode": current_scene_mode})

func set_scene_mode(mode: SceneMode, reposition_camera: bool = true) -> void:
	current_scene_mode = mode
	scene_mode_changed.emit(mode, SceneMode.keys()[mode])
	if reposition_camera:
		recenter_camera(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_load_zone"):
		show_load_zone = not show_load_zone
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_press=event.position
			_selection_additive=event.ctrl_pressed or event.meta_pressed
			return
		var input_scale:Vector2=Vector2(get_viewport().size)/get_viewport().get_visible_rect().size
		var clicked:bool=_left_press.is_finite() and ((_left_press-event.position)*input_scale).length()<5
		_left_press=Vector2.INF
		if clicked and not is_loading() and not _atlas_migration and rasterizer and camera_controller and not camera_controller.is_movement_blocked():
			_request_serial += 1
			_selection_pick_request=_request_serial
			rasterizer.request_pick(event.position*input_scale, _request_serial)
			_last_activity = 0.0

func _on_model_pick_completed(request_id:int,instance_id:int,position:Vector3)->void:
	if request_id!=_selection_pick_request:return
	_selection_pick_request=-1
	for record in _records.values():
		var node=record.node.get_ref()
		if is_instance_valid(node) and record.status=="loaded" and record.instance_id==instance_id:
			if _selection_additive: toggle_model_selection(node.model_id)
			else: select_model_id(node.model_id)
			model_clicked.emit(node.model_id,position)
			return
	select_model_id("")

func _on_pick_completed(_request_id: int, position: Vector3) -> void:
	if position.is_finite():
		splat_clicked.emit(position)
		camera_controller.focus_on_position(position)

func preload_file(path: String) -> void:
	if preloader:
		preloader.preload_file(path)

func get_model_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in _records.values():
		var node = record.node.get_ref()
		if not is_instance_valid(node):
			continue
		var transform: Transform3D = node.global_transform
		result.append({"model_id": node.model_id, "transform": _world_transform(node), "name": str(node.name), "file": record.path.get_file(), "file_path": record.path, "status": record.status, "visible": node.is_visible_in_tree(), "position": [transform.origin.x, transform.origin.y, transform.origin.z], "rotation_degrees": [node.global_rotation_degrees.x, node.global_rotation_degrees.y, node.global_rotation_degrees.z], "scale": [transform.basis.get_scale().x, transform.basis.get_scale().y, transform.basis.get_scale().z], "splat_count": record.count, "instance_id": record.instance_id, "buffer_offset_bytes": record.offset, "bounds": record.resource.aabb})
	return result

func get_stats() -> Dictionary:
	var result := {"viewer_state": ViewerState.keys()[current_state], "is_loading": is_loading(), "is_rendering": is_rendering(), "loaded_file": "%d models" % _count_loaded_models(), "fps": Engine.get_frames_per_second(), "frame_count": frame_count, "total_splats": total_splats_to_load, "splats_loaded": total_splats_to_load, "scene_mode": SceneMode.keys()[current_scene_mode]}
	if rasterizer:
		result.merge(rasterizer.get_stats(), true)
	if camera_controller:
		result["camera"] = camera_controller.get_camera_state()
	return result

func _count_loaded_models() -> int:
	var count := 0
	for record in _records.values():
		if record.status == "loaded":
			count += 1
	return count

func reset_stats() -> void:
	frame_count = 0
	time_accumulator = 0.0

func _report_error(message: String, code: int, fatal: bool = false) -> void:
	last_error = message
	if fatal:
		current_state = ViewerState.ERROR
	push_warning("[GSViewer] " + message)
	error_occurred.emit(message, code)

func _handle_error(message: String, code: int) -> void:
	_report_error(message, code)

func _create_default_camera_system() -> void:
	camera_controller = CameraController.new()
	camera_controller.name = "AutoCameraController"
	var camera := FreeLookCamera.new()
	camera.name = "FreeLookCamera"
	var target := Node3D.new()
	target.name = "Target"
	target.top_level = true
	camera.add_child(target)
	var cursor := MeshInstance3D.new()
	cursor.name = "Cursor"
	cursor.top_level = true
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	cursor.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.8, 0.2, 0)
	cursor.set_surface_override_material(0, material)
	cursor.set_script(load("res://modules/gaussian_splatting/cameras/cursor.gd"))
	camera.add_child(cursor)
	var timer := Timer.new()
	timer.name = "OrbitSwapTimer"
	timer.one_shot = true
	timer.wait_time = 0.135
	camera.add_child(timer)
	camera_controller.add_child(camera)
	add_child(camera_controller)
	camera_controller.set_camera(camera)

func _exit_tree() -> void:
	_apply_shadow_receivers({})
	for node in _hybrid_nodes:
		if is_instance_valid(node):node.set_integrated(false)
	if _atlas_migration: _atlas_migration.cancelled = true
	_ready_complete = false
	_clearing = true
	_cancel_job()
	_detach_compositor()
	if rasterizer:
		rasterizer.cleanup()
	rasterizer = null
	remove_from_group("gaussian_splat_viewers")


func get_selected_model() -> GaussianSplat:
	for record in _records.values():
		var node = record.node.get_ref()
		if is_instance_valid(node) and node.model_id == selected_model_id and record.status == "loaded": return node
	return null

func select_model_id(model_id: String) -> bool:
	return select_model_ids([] if model_id.is_empty() else [model_id])

func select_model_ids(model_ids: Array) -> bool:
	var next: Array[String] = []
	for value in model_ids:
		var model_id := str(value)
		if next.has(model_id): continue
		var valid := false
		for record in _records.values():
			var node = record.node.get_ref()
			if is_instance_valid(node) and node.model_id == model_id and record.status == "loaded": valid = true
		if not valid: return false
		next.append(model_id)
	if next == selected_model_ids: return true
	selected_model_ids = next
	selected_model_id = next.back() if not next.is_empty() else ""
	_force_redraw = true
	_last_activity = 0.0
	selection_changed.emit(selected_model_id)
	multi_selection_changed.emit(selected_model_ids.duplicate())
	return true

func toggle_model_selection(model_id: String) -> bool:
	var next := selected_model_ids.duplicate()
	if next.has(model_id): next.erase(model_id)
	else: next.append(model_id)
	return select_model_ids(next)

func get_selected_models() -> Array[GaussianSplat]:
	var result: Array[GaussianSplat] = []
	for record in _records.values():
		var node = record.node.get_ref()
		if is_instance_valid(node) and selected_model_ids.has(node.model_id) and record.status == "loaded": result.append(node)
	return result

func commit_transform_edit(before: Dictionary, after: Dictionary) -> void:
	if before == after or before.is_empty(): return
	_transform_undo.append({"before":before.duplicate(),"after":after.duplicate()})
	if _transform_undo.size()>100: _transform_undo.pop_front()
	_transform_redo.clear()

func undo_transform(redo: bool = false) -> bool:
	if _atlas_migration or is_loading(): return false
	var source := _transform_redo if redo else _transform_undo
	if source.is_empty(): return false
	var edit: Dictionary = source.back()
	var values: Dictionary = edit.after if redo else edit.before
	var nodes := {}
	for record in _records.values():
		var node = record.node.get_ref()
		if is_instance_valid(node): nodes[node.model_id] = node
	for id in values:
		if not nodes.has(id): return false
	for id in values: nodes[id].global_transform = values[id]
	source.pop_back()
	if redo: _transform_undo.append(edit)
	else: _transform_redo.append(edit)
	return true

func _selected_instance_id() -> int:
	var node := get_selected_model()
	return int(_records[node.get_instance_id()].instance_id) if node else 0

func _apply_queued_configuration() -> void:
	if not _queued_configuration or _applying_config or is_loading() or not _ready_complete: return
	var queued := _queued_configuration
	_queued_configuration = null
	config = queued
	_apply_config()

func _connect_renderer_signals() -> void:
	rasterizer.model_pick_completed.connect(_on_model_pick_completed)
	rasterizer.frame_failed.connect(func(message, code):
		stop_rendering()
		_report_error(message, code)
	)
	rasterizer.pick_completed.connect(_on_pick_completed)

func _migrate_atlas(requested: GaussianSplattingConfig) -> Error:
	var plan := GaussianSplattingRasterizer.memory_plan(requested, (Vector2(get_viewport().size) * requested.default_render_scale).ceil())
	var count := 0
	var instances := 0
	for record in _records.values():
		if record.status == "loaded" and is_instance_valid(record.node.get_ref()):
			count += int(record.count)
			instances += 1
	if plan.has("error") or int(plan.get("splats",0)) < count or requested.memory_max_instances < instances: return ERR_OUT_OF_MEMORY
	var old := rasterizer
	var previous := _applied_config.duplicate(true)
	old.rendering_enabled = false
	old.update_camera_matrices()
	_atlas_migration = GSAtlasMigration.new()
	_atlas_migration.progress_changed.connect(func(fraction):configuration_migration_progress.emit(fraction))
	_apply_shadow_receivers({})
	configuration_migration_changed.emit(true)
	set_camera_blocker("atlas_migration", true)
	# The frame remains visible while only the atlas owner changes. No model is re-read from disk.
	var frozen := render_texture.get_image()
	var result: Error = ERR_FILE_CANT_READ
	if frozen:
		rendered_material.set_shader_parameter("render_texture", ImageTexture.create_from_image(frozen))
		result = await _atlas_migration.checkpoint(old, _records, get_tree())
	var restored := {}
	var replacement: GaussianSplattingRasterizer
	if result == OK:
		_detach_compositor()
		old.cleanup()
		replacement = _make_migration_renderer(requested)
		replacement.compute_shader_path = compute_shader_directory
		replacement.basis_override = old.basis_override
		result = replacement.init_gpu()
		if result == OK:
			restored = await _atlas_migration.restore(replacement, _records, get_tree(), true)
			result = restored.get("error", OK)
		if result != OK:
			replacement.cleanup()
			replacement = _make_migration_renderer(previous)
			replacement.compute_shader_path = compute_shader_directory
			replacement.basis_override = old.basis_override
			var rollback := replacement.init_gpu()
			if rollback == OK:
				restored = await _atlas_migration.restore(replacement, _records, get_tree(), false)
				rollback = restored.get("error", OK)
			if rollback != OK:
				_report_error("Atlas recovery failed; checkpoint retained at " + ProjectSettings.globalize_path(_atlas_migration.path), rollback, true)
				_atlas_migration.path = "" # Retain recovery evidence instead of deleting source data.
				restored = {}
	if replacement and not restored.is_empty() and not restored.has("error"):
		rasterizer = replacement
		render_texture = replacement.render_texture
		_connect_renderer_signals()
		_free_instance_ids.clear()
		var used := {}
		for record_id in _records.keys():
			var record: Dictionary = _records[record_id]
			var node = record.node.get_ref()
			if not is_instance_valid(node):
				_records.erase(record_id)
				continue
			if not restored.mapping.has(node.model_id): continue
			var destination: Dictionary = restored.mapping[node.model_id]
			record.offset = destination.offset
			record.instance_id = destination.instance_id
			node.buffer_offset = destination.offset
			record.transform = node.global_transform
			record.visible = node.is_visible_in_tree()
			used[int(destination.instance_id)] = true
			rasterizer.update_instance_transform(record.instance_id, record.transform, record.visible)
		for id in range(rasterizer.config.memory_max_instances,0,-1):
			if not used.has(id): _free_instance_ids.append(id)
		_attach_compositor(get_camera())
		rendered_material.set_shader_parameter("render_texture", render_texture)
		rendered_material.set_shader_parameter("integrated_frame",false)
		_force_redraw = true
	elif old.gpu_init_complete:
		rendered_material.set_shader_parameter("render_texture", render_texture)
	_atlas_migration.dispose()
	_atlas_migration = null
	set_camera_blocker("atlas_migration", false)
	configuration_migration_changed.emit(false)
	model_registry_changed.emit()
	for reference in _deferred_registration:
		var node = reference.get_ref()
		if is_instance_valid(node): register_splat.call_deferred(node)
	_deferred_registration.clear()
	if _clear_after_migration:
		_clear_after_migration = false
		_clear_scene_and_reset_atlas.call_deferred()
	return result

func _make_migration_renderer(settings: GaussianSplattingConfig) -> GaussianSplattingRasterizer:
	return GaussianSplattingRasterizer.new(get_viewport().size,Texture2DRD.new(),get_camera(),settings)

func set_color_comparison(original:bool)->void:
	_color_comparison=original
	if is_instance_valid(rendered_material):_update_color_uniforms()

func _only_color_changed()->bool:
	if not _applied_config:return false
	for property in config.get_property_list():
		var field:String=property.name
		if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0 or field in GaussianSplattingConfig.COLOR_FIELDS or field=="color_settings_edited":continue
		if config.get(field)!=_applied_config.get(field):return false
	return true

func _update_color_uniforms()->void:
	var settings:Dictionary=GSColorSettings.profile("Natural") if _color_comparison else GSColorSettings.snapshot(config)
	for field in settings:rendered_material.set_shader_parameter(field.trim_prefix("post_"),settings[field])
	_force_redraw=true

func get_model_world_bounds(node:GaussianSplat)->AABB:
	if not is_instance_valid(node) or not _records.has(node.get_instance_id()):return AABB()
	return _world_transform(node)*_records[node.get_instance_id()].resource.aabb

func get_model_edit_transform(node:GaussianSplat)->Transform3D:
	return _world_transform(node)*Transform3D(config.source_basis().inverse(),Vector3.ZERO)

func set_model_edit_transform(node:GaussianSplat,value:Transform3D)->void:
	if not is_instance_valid(node) or not node.is_loaded or _atlas_migration:return
	var frame:=get_model_edit_transform(node)*node.global_transform.affine_inverse()
	node.global_transform=frame.affine_inverse()*value

func frame_models(ids:Array)->bool:
	var bounds:=AABB()
	var found:=false
	for record in _records.values():
		var model:GaussianSplat=record.node.get_ref()
		if not is_instance_valid(model) or record.status!="loaded" or not model.is_visible_in_tree():continue
		if not ids.is_empty() and not ids.has(model.model_id):continue
		var box:=get_model_world_bounds(model)
		bounds=bounds.merge(box) if found else box
		found=true
	if not found or not get_camera():return false
	var extent:=maxf(bounds.size.length()*0.5,0.1)
	var distance:=extent/maxf(0.1,sin(deg_to_rad(get_camera().fov*0.5)))*1.15
	var center:=bounds.get_center()
	camera_controller.position_camera_at(center+Vector3(0.75,0.5,1).normalized()*distance,center)
	return true

func _prepare_transparency() -> void:
	var draws: Array[Dictionary]=[]
	var current: Array[GSAlphaMesh3D]=[]
	for candidate in get_tree().get_nodes_in_group("gs_alpha_meshes"):
		var node:=candidate as GSAlphaMesh3D
		if not node or node.get_world_3d()!=get_world_3d():continue
		var batch:=node.capture()
		if not batch.is_empty():draws.append_array(batch);current.append(node)
	var identity:Array=[]
	for draw in draws:identity.append([draw.key,draw.transform,draw.color,draw.texture,draw.cull])
	var signature:=hash([identity,GSColorSettings.snapshot(config),_color_comparison,rasterizer.texture_size,rasterizer.get_instance_id()])
	if signature==_hybrid_signature:
		_update_hybrid_presentation();return
	_hybrid_signature=signature
	var settings:GaussianSplattingConfig=config
	if _color_comparison:
		settings=GaussianSplattingConfig.create_default()
		GSColorSettings.apply(settings,GSColorSettings.profile("Natural"))
	var tint_color:=settings.post_tint.srgb_to_linear()
	var grade:=PackedFloat32Array([settings.post_exposure,settings.post_contrast,settings.post_saturation,settings.post_temperature,settings.post_black_point,settings.post_white_point,settings.post_sharpness,0,tint_color.r,tint_color.g,tint_color.b,0]).to_byte_array()
	var result:=rasterizer.prepare_transparency(draws,grade)
	for node in _hybrid_nodes:
		if is_instance_valid(node):node.set_integrated(false)
	_hybrid_nodes=current
	_update_hybrid_presentation()
	if result!=OK and _hybrid_error!=str(result):
		_hybrid_error=str(result);_report_error("Transparent integration could not fit or initialize; ordinary mesh rendering retained.",result)
	_force_redraw=true

func _update_hybrid_presentation()->void:
	var state:=rasterizer.transparency.presentation_status() if rasterizer.transparency_active and rasterizer.transparency else Vector2i.ZERO
	var integrated:=state.x!=0
	for node in _hybrid_nodes:
		if is_instance_valid(node):node.set_integrated(integrated)
	var output:Texture2DRD=rasterizer.transparency.output if integrated else rasterizer.render_texture
	if render_texture!=output:
		render_texture=output;rendered_material.set_shader_parameter("render_texture",output)
		rendered_material.set_shader_parameter("integrated_frame",integrated);_force_redraw=true
	if state.y!=0 and _hybrid_error!="overflow":
		_hybrid_error="overflow";_report_error("Transparent fragment capacity exceeded; last complete composition retained. Reduce overlapping transparent layers or render resolution.",ERR_OUT_OF_MEMORY)

func _prepare_shadows()->void:
	rasterizer.update_shadow_appearance(lighting.shadow_strength,lighting.shadow_bias)
	var request:Dictionary={}
	var signature:=hash([lighting.shadows_enabled,lighting.shadow_resolution])
	if lighting.shadows_enabled and is_instance_valid(shadow_light) and shadow_light.is_visible_in_tree() and shadow_light.light_energy>0 and _count_loaded_models()>0:
		var flags:=PackedInt32Array();flags.resize(config.memory_max_instances+1)
		var bounds:=AABB();var found:=false
		var poses:Array=[]
		for record in _records.values():
			var model:GaussianSplat=record.node.get_ref()
			if not is_instance_valid(model) or record.status!="loaded":continue
			flags[int(record.instance_id)]=(1 if model.cast_gaussian_shadows else 0)|(2 if model.receive_gaussian_shadows else 0)
			if not model.is_visible_in_tree():flags[int(record.instance_id)]=0;continue
			var box:=get_model_world_bounds(model)
			bounds=bounds.merge(box) if found else box;found=true
			poses.append([model.model_id,model.global_transform,flags[int(record.instance_id)],record.count])
		if found:
			var radius:=maxf(1,bounds.size.length()*0.55+0.25)
			var basis:=shadow_light.global_basis.orthonormalized()
			var position:=bounds.get_center()+basis.z*radius*2
			var view:=Projection(Transform3D(basis,position).affine_inverse())
			var projection:=Projection.create_orthogonal(-radius,radius,-radius,radius,0.01,radius*4)
			signature=hash([poses,basis,rasterizer.model_scale[0],rasterizer.basis_override,lighting.shadow_resolution,rasterizer.get_instance_id()])
			var matrices:=RenderingContext.pack_projection(view);matrices.append_array(RenderingContext.pack_projection(projection))
			request={"signature":signature,"resolution":lighting.shadow_resolution,"flags":flags.to_byte_array(),"position":position,"view":view,"projection":projection,"view_projection":matrices}
	if request.is_empty():_apply_shadow_receivers({})
	if signature!=_shadow_signature:
		_shadow_signature=signature
		var result:=rasterizer.prepare_shadow(request)
		if result!=OK and not _shadow_error:
			_shadow_error=true;_report_error("Gaussian shadows could not fit the remaining GPU budget; original appearance retained.",result)
		_force_redraw=true
	if rasterizer.shadow_pass and rasterizer.shadow_pass.failure()!=0 and not _shadow_error:
		_shadow_error=true;_report_error("Gaussian shadow footprint capacity exceeded; last complete shadow map retained.",ERR_OUT_OF_MEMORY)
	var active:Dictionary=rasterizer.shadow_pass.snapshot() if rasterizer.shadow_pass and lighting.shadows_enabled and not request.is_empty() else {}
	_apply_shadow_receivers(active)

func _apply_shadow_receivers(frame:Dictionary)->void:
	if not is_inside_tree():return
	for receiver in get_tree().get_nodes_in_group("gs_shadow_receivers"):
		if receiver.get_world_3d()==get_world_3d():receiver.apply_shadow(frame,lighting)
