# demo_ui_controller.gd
class_name DemoUIController
extends Node
## ImGui-based debug UI for GaussianSplattingViewer
## VERSION 12.7 - Added Coexistence Fix for Load Zone (2025-11-09)

#region Dependencies
@export var viewer : GaussianSplattingViewer

var show_ui : bool = true
var last_error_message : String = ""
var error_message_time : float = 0.0
var cached_stats : Dictionary = {}
var camera_fov : Array = [75.0]
var stats_are_enabled := false
var stats_warning_shown := false
var _render_load_zone_panel := false
var _last_browse_path := ""
#endregion

#region Initialization
func _ready() -> void:
	add_to_group("gs_debug_ui")
	# --- [THE NEW LINE] ---
	# Add this node to the "debug_ui" group. This allows other scripts (like ProductionUI)
	# to check for its existence and status in a decoupled way.
	add_to_group("debug_ui")
	
	if not viewer:
		push_error("[DemoUIController] CRITICAL: 'viewer' property not assigned!")
		set_process(false)
		return
	
	if not is_instance_valid(viewer):
		push_error("[DemoUIController] CRITICAL: Assigned viewer instance is invalid!")
		set_process(false)
		return
	
	if viewer.enable_debug_stats:
		stats_are_enabled = true
		_connect_viewer_signals()
	else:
		stats_are_enabled = false
		_connect_essential_signals()
		if not stats_warning_shown:
			push_warning("[DemoUIController] Viewer does not have 'Enable Debug Stats' checked")
			stats_warning_shown = true

	if is_instance_valid(viewer):
		if not viewer.load_zone_visibility_changed.is_connected(_on_viewer_load_zone_visibility_changed):
			viewer.load_zone_visibility_changed.connect(_on_viewer_load_zone_visibility_changed)

func _connect_essential_signals() -> void:
	if not viewer: return
	if not viewer.error_occurred.is_connected(_on_viewer_error):
		viewer.error_occurred.connect(_on_viewer_error)
	if not viewer.loading_completed.is_connected(_on_loading_completed):
		viewer.loading_completed.connect(_on_loading_completed)

func _connect_viewer_signals() -> void:
	if not viewer: return
	_connect_essential_signals()
	if not viewer.loading_started.is_connected(_on_loading_started):
		viewer.loading_started.connect(_on_loading_started)
	if not viewer.stats_updated.is_connected(_on_stats_updated):
		viewer.stats_updated.connect(_on_stats_updated)
	var viewport := get_viewport()
	if viewport and not viewport.files_dropped.is_connected(_on_files_dropped):
		pass # ProductionUI owns file-drop commands
#endregion

#region Definitive Input Handling
func _process(_delta: float) -> void:
	if show_ui:
		_render_imgui()

	if not is_instance_valid(viewer) or not is_instance_valid(viewer.camera_controller):
		return

	var ui_has_focus = show_ui and (ImGui.GetIO().WantCaptureMouse or _render_load_zone_panel)

	# [FIX] Use the camera movement API instead of disabling process_mode entirely.
	# The old code disabled the Viewer AND Camera, which froze WASD movement.
	if is_instance_valid(viewer):
		viewer.set_camera_blocker("debug_ui", ui_has_focus or (show_ui and ImGui.GetIO().WantCaptureKeyboard))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_imgui"):
		show_ui = !show_ui
		get_viewport().set_input_as_handled()
	
	elif event.is_action_pressed("toggle_fullscreen"):
		var current_mode = DisplayServer.window_get_mode()
		var new_mode = DisplayServer.WINDOW_MODE_WINDOWED if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(new_mode)
		get_viewport().set_input_as_handled()
#endregion

#region ImGui Rendering
func _render_imgui() -> void:
	ImGui.SetNextWindowSize(Vector2(350, 540), ImGui.Cond_FirstUseEver)
	if ImGui.Begin('Gaussian Splatting Viewer'):
		ImGui.PushItemWidth(ImGui.GetWindowWidth() * 0.6)
		ImGui.Text('Drag and drop .ply files to load!')
		ImGui.Separator()

		if not stats_are_enabled:
			ImGui.PushStyleColor(ImGui.Col_Text, Color.GOLD)
			ImGui.TextWrapped("UI WARNING: Enable Debug Stats in viewer for performance data")
			ImGui.PopStyleColor()
			ImGui.Separator()
			if ImGui.Button("Attempt to Enable Stats Now"):
				if is_instance_valid(viewer):
					viewer.enable_debug_stats = true
					stats_are_enabled = true
					_connect_viewer_signals()
		else:
			_render_error_section()
			_render_quality_section()
			_render_viewer_section()
			_render_camera_section()
			_render_gpu_section()

		ImGui.Dummy(Vector2(0, 10))
		ImGui.Separator()
		ImGui.PushStyleColor(ImGui.Col_Text, Color.WEB_GRAY)
		var cmd_key := 'Cmd' if OS.get_name() == 'macOS' else 'Ctrl'
		ImGui.Text('Press %s-H to toggle GUI' % cmd_key)
		ImGui.Text('Press %s-F to toggle fullscreen' % cmd_key)
		ImGui.Text('Press %s-O to open the Load Zone' % cmd_key)
		ImGui.PopStyleColor()

	ImGui.End()

	if _render_load_zone_panel:
		_render_load_zone()

func _render_error_section() -> void:
	var current_time := Time.get_ticks_msec() * 1e-3
	if not last_error_message.is_empty() and (current_time - error_message_time) < 10.0:
		ImGui.PushStyleColor(ImGui.Col_Text, Color.INDIAN_RED)
		ImGui.Text('ERROR: %s' % last_error_message)
		ImGui.PopStyleColor()
		ImGui.Separator()

func _render_quality_section() -> void:
	if not viewer or not viewer.config: return
	ImGui.SeparatorText('Quality Settings')
	var preset_names := PackedStringArray(["Custom", "Low", "Medium", "High", "Ultra"])
	var current_preset_idx := [int(viewer.config.current_preset)]
	ImGui.Text('Quality Preset:  ')
	ImGui.SameLine()
	if ImGui.Combo('##quality_preset', current_preset_idx, preset_names):
		var preset = GaussianSplattingConfig.QualityPreset.values()[current_preset_idx[0]]
		viewer.config.apply_preset(preset)


func _render_viewer_section() -> void:
	if not viewer: return
	ImGui.SeparatorText('Viewer Status')
	
	var stats := cached_stats if not cached_stats.is_empty() else viewer.get_stats()
	
	if stats.has("viewer_state"):
		ImGui.Text('Status:          %s' % stats.get("viewer_state", "UNKNOWN").to_upper())
	
	var fps := Engine.get_frames_per_second()
	var is_rendering_now : bool = stats.get("is_rendering", false)
	ImGui.Text('Engine FPS:      %d (%s)' % [fps, '%.2fms' % (1e3 / maxi(1, fps)) if is_rendering_now else 'paused'])
	
	
	#var file_name = stats.get("loaded_file", "").get_file() if stats.get("loaded_file", "") else "(none)"
	#ImGui.Text('Loaded File:     %s' % file_name)
	# --- THE KEY CHANGE ---
	# Instead of showing a single file, we get the "loaded_file" stat,
	# which the new viewer correctly reports as "%d models".
	var scene_info = stats.get("loaded_file", "(none)")
	ImGui.Text('Loaded Scene:    %s' % scene_info)
	
	
	ImGui.Text('Total Splats:    %s' % _format_number(stats.get("total_splats", 0)))
	ImGui.Text('Rendered Splats: %s' % _format_number(stats.get("splats_rendered_frame", 0)))
	ImGui.Text('Render Size:     %v' % stats.get("texture_size", Vector2i.ZERO))

func _render_camera_section() -> void:
	if not viewer or not viewer.config or not viewer.camera_controller: return
	
	# --- THE DEFINITIVE FIX ---
	# Before rendering this section, we MUST check if the rasterizer actually exists.
	# If it doesn't, it means no model is loaded. Instead of crashing, we will
	# display a helpful message to the user.
	if not is_instance_valid(viewer.rasterizer):
		ImGui.SeparatorText('Camera')
		ImGui.Text("Camera controls disabled (no model loaded).")
		return
	# --- END OF FIX ---
	
	ImGui.SeparatorText('Camera')
	
	var controller = viewer.camera_controller
	var camera = controller.get_camera()
	var camera_state = controller.get_camera_state()
	
	if not camera or camera_state.is_empty():
		ImGui.Text('No active camera')
		return
	
	ImGui.Text('Position: %+.2v' % camera.global_position)
	ImGui.Text('Mode:     %s' % camera_state.get("mode", "N/A"))

	if camera.has_node("Cursor"):
		var cursor_node = camera.get_node("Cursor")
		ImGui.Text("Cursor Position: %+.2v" % cursor_node.global_position)

	ImGui.Text('FOV:      ')
	ImGui.SameLine()
	
	ImGui.PushItemWidth(ImGui.GetWindowWidth() * 0.4)
	camera_fov[0] = camera.fov
	if ImGui.SliderFloat('##fov_float', camera_fov, 20, 170):
		camera.fov = camera_fov[0]
	ImGui.PopItemWidth()
	
	ImGui.SameLine()
	if ImGui.Button("Reset"):
		camera.fov = viewer.config.camera_default_fov
	
	ImGui.Text('Camera Basis:   ')
	ImGui.SameLine()
	
	# This code is now safe because we've already confirmed viewer.rasterizer is valid.
	ImGui.BeginDisabled(viewer.rasterizer.basis_override != Basis.IDENTITY)
	if ImGui.Button('Override'):
		viewer.rasterizer.basis_override = camera.global_basis.inverse()
	ImGui.EndDisabled()
	
	ImGui.SameLine()
	
	ImGui.BeginDisabled(viewer.rasterizer.basis_override == Basis.IDENTITY)
	if ImGui.Button('Reset##basis_reset'):
		viewer.rasterizer.basis_override = Basis.IDENTITY
	ImGui.EndDisabled()

func _render_gpu_section() -> void:
		# --- ROBUSTNESS ENHANCEMENT ---
	# Add the same is_instance_valid check here for maximum safety, although
	# the 'has("pipeline_stats")' check would likely prevent the crash anyway.
	# This is just good defensive programming.
	if not viewer or not is_instance_valid(viewer.rasterizer) or not cached_stats.has("pipeline_stats"): return
	
	# if not viewer or not cached_stats.has("pipeline_stats"): return
	
	var stats = cached_stats
	ImGui.SeparatorText('GPU Resources')
	var vram_mb = stats.get("total", 0) / 1048576.0
	ImGui.Text('VRAM Used:       %.2f MB' % vram_mb)
	ImGui.Text('GPU Resources:   %d' % stats.get("resource_count", 0))

	ImGui.SeparatorText('Pipeline Status')
	var pipeline_stats = stats.get("pipeline_stats", {})
	ImGui.Text('Valid: %d | Dirty: %d | Errors: %d' % [pipeline_stats.get("valid", 0), pipeline_stats.get("dirty", 0), pipeline_stats.get("error", 0)])

func _render_load_zone() -> void:
	var window_size = Vector2(600, 400)
	var viewport_size = get_viewport().get_visible_rect().size
	var centered_pos = (viewport_size / 2) - (window_size / 2)
	
	ImGui.SetNextWindowSize(window_size, ImGui.Cond_Appearing)
	ImGui.SetNextWindowPos(centered_pos, ImGui.Cond_Appearing)

	var window_open_arr = [_render_load_zone_panel]
	if ImGui.Begin("Load Splat File (Ctrl+O)", window_open_arr, ImGui.WindowFlags_None):
		if not window_open_arr[0]:
			viewer.show_load_zone = false

		ImGui.Text("Select a recent file or browse for a new one.")
		ImGui.Separator()
		
		ImGui.BeginChild("RecentFiles", Vector2(0, -50), true, ImGui.WindowFlags_None)
		var recent_files = HistoryManager.recent_files
		if recent_files.is_empty():
			ImGui.Text("No recent files.")
		else:
			for file_path in recent_files:
				if ImGui.Selectable(file_path.get_file() + "##" + file_path):
					#viewer.load_file(file_path)
					# --- FIX: Call the non-destructive function ---
					viewer.load_new_splat_from_path(file_path) 
					viewer.show_load_zone = false
		ImGui.EndChild()

		if ImGui.Button("Browse for New File..."):
			var file_dialog = FileDialog.new()
			add_child(file_dialog)
			file_dialog.access = FileDialog.ACCESS_FILESYSTEM
			file_dialog.use_native_dialog = true
			if not _last_browse_path.is_empty():
				file_dialog.current_dir = _last_browse_path
			file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			file_dialog.add_filter("*.ply ; Gaussian Splat File")
			
			file_dialog.file_selected.connect(
				func(path): 
					_last_browse_path = path.get_base_dir()
					# viewer.load_file(path)
					# --- FIX: Call the non-destructive function ---
					viewer.load_new_splat_from_path(path) 
					viewer.show_load_zone = false
					file_dialog.queue_free()
			)
			file_dialog.canceled.connect(
				func(): 
					viewer.show_load_zone = false
					file_dialog.queue_free()
			)
			file_dialog.popup_centered()

		ImGui.SameLine()
		if ImGui.Button("Clear History"):
			HistoryManager.clear_history()

	ImGui.End()

#endregion

#region Signal Handlers & Utility
func _on_viewer_error(message: String, _code: int) -> void:
	last_error_message = message
	error_message_time = Time.get_ticks_msec() * 1e-3

func _on_viewer_load_zone_visibility_changed(is_visible: bool) -> void:
	if not show_ui:
		_render_load_zone_panel = false
		return
	
	_render_load_zone_panel = is_visible

func _on_loading_started(_file_path: String) -> void:
	# This signal is less relevant now, but we can keep it for potential future logging.
	pass

func _on_loading_completed(_file_path: String, _splat_count: int) -> void:
	# This signal is for backward compatibility. We do not need to react to it in the UI
	# as the 'all_splats_loading_completed' provides the definitive, aggregate result.
	pass

func _on_stats_updated(stats: Dictionary) -> void:
	cached_stats = stats

func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty() or not viewer: return
	var file_path := files[0]
	if not file_path.ends_with('.ply'):
		last_error_message = "Invalid file type (expected .ply)"
		error_message_time = Time.get_ticks_msec() * 1e-3
		return
	#viewer.load_file(file_path)
	viewer.load_new_splat_from_path(file_path)

# This public function allows other scripts (like ProductionUI) to safely
# check if this debug UI is currently active, without needing to know about ImGui.
func is_main_ui_visible() -> bool:
	return show_ui

static func _format_number(number: int) -> String:
	if number == 0: return "0"
	var in_str := str(number)
	var out_chars := PackedStringArray()
	var length := in_str.length()
	for i in range(1, length + 1):
		out_chars.append(in_str[length - i])
		if i < length and i % 3 == 0: out_chars.append(',')
	out_chars.reverse()
	return ''.join(out_chars)

## This new async wrapper is the key to the fix.
## It allows us to safely 'await' the viewer's async load_file function.
func _load_file_async(file_path: String) -> void:
	# Await the completion of the file loading process. This pauses this
	# function, but not the whole game, until loading is done.
	var load_result := await viewer.load_file(file_path)
	
	# After awaiting, we can check the result and show an error if needed.
	if load_result != OK:
		last_error_message = "Failed to load file: error code %d" % load_result
		error_message_time = Time.get_ticks_msec() * 1e-3
		push_error("[DemoUIController] %s" % last_error_message)
	else:
		# Optionally, log success.
		if viewer.config and viewer.config.enable_verbose_logging:
			print("[DemoUIController] File loaded successfully via UI: %s" % file_path.get_file())

#endregion
