# ProductionUI.gd

class_name ProductionUI
extends CanvasLayer
var _migration_load_disabled := false
var _migration_quality_disabled := false


## Production-ready, clean UI for the GaussianSplattingViewer.
## Manages file loading, quality settings, and status feedback for the end-user.

#region Node References
@export var viewer: GaussianSplattingViewer

@onready var status_label: Label = %StatusLabel
@onready var load_zone_panel: PanelContainer = %LoadZonePanel
@onready var recent_files_list: VBoxContainer = %RecentFilesList
@onready var quality_selector: OptionButton = %QualitySelector
@onready var load_file_button: Button = %LoadFileButton
@onready var browse_button: Button = %BrowseButton
@onready var clear_history_button: Button = %ClearHistoryButton
@onready var close_button: Button = %CloseButton
@onready var file_dialog: FileDialog = %FileDialog
@onready var status_timer: Timer = Timer.new()
@onready var clear_scene_button: Button = %ClearSceneButton # We will add this in the TSCN next
@onready var scene_manager_button: Button = %SceneManagerButton # [NEW]

	## [NEW] Reference to the Scene Manager panel (lazy-loaded)
var _dialog_open := false
var scene_manager_panel: SceneManagerPanel = null
var cognitive_panel: CognitivePanel = null # [NEW] The Neural HUD
var color_panel:GSColorAdjustmentPanel
var transform_controls:GSModelTransformControls

#endregion

#region Initialization
func _ready() -> void:
	if not is_instance_valid(viewer):
		self.hide()
		push_error("[ProductionUI] The 'viewer' property has not been assigned! UI is disabled.")
		return
	
	_connect_signals()
	_initialize_ui_state()
	color_panel=GSColorAdjustmentPanel.new();color_panel.viewer=viewer;add_child(color_panel)
	var color_button:=Button.new();color_button.text="Color";color_button.tooltip_text="Color presets and image adjustments"
	color_button.add_theme_font_override("font",scene_manager_button.get_theme_font("font"))
	color_button.add_theme_font_size_override("font_size",scene_manager_button.get_theme_font_size("font_size"))
	%SceneManagerButton.get_parent().add_child(color_button)
	color_button.pressed.connect(func():
		if color_panel.visible:color_panel.hide_panel()
		else:color_panel.show_panel()
	)
	transform_controls=GSModelTransformControls.new();transform_controls.viewer=viewer;add_child(transform_controls)
	get_viewport().size_changed.connect(_layout_top_bar)
	_layout_top_bar.call_deferred()

func _layout_top_bar()->void:
	var controls:Control=%MainControls
	controls.anchor_left=1.0;controls.anchor_right=1.0
	controls.offset_left=-controls.get_combined_minimum_size().x-18
	controls.offset_right=-18

func _connect_signals() -> void:
	# --- Connect to viewer signals ---
	viewer.configuration_applied.connect(func(settings): quality_selector.select(settings.current_preset))
	viewer.configuration_migration_changed.connect(_on_configuration_migration_changed)
	viewer.configuration_migration_progress.connect(func(fraction):status_label.text="Applying quality settings... %d%%" % int(fraction*100))
	viewer.all_splats_loading_started.connect(_on_all_splats_loading_started)
	viewer.all_splats_loading_completed.connect(_on_all_splats_loading_completed)
	viewer.splat_loading_progress.connect(_on_viewer_loading_progress) # Corrected signal for smooth progress
	viewer.loading_completed.connect(_on_viewer_loading_completed)
	viewer.error_occurred.connect(_on_viewer_error)
	viewer.load_zone_visibility_changed.connect(_on_viewer_load_zone_visibility_changed)

	# --- Connect to internal UI element signals ---
	load_file_button.pressed.connect(_on_load_button_pressed)
	browse_button.pressed.connect(_on_browse_button_pressed)
	clear_history_button.pressed.connect(_on_clear_history_button_pressed)
	quality_selector.item_selected.connect(_on_quality_selected)
	close_button.pressed.connect(_on_close_button_pressed)
	# --- THE SOVEREIGN RESET ---
	clear_scene_button.pressed.connect(_on_clear_scene_pressed)

	# --- ENHANCEMENT: Robust File Dialog connections ---
	file_dialog.file_selected.connect(_on_file_dialog_selected)
	file_dialog.canceled.connect(_on_file_dialog_canceled)
	
	# --- [NEW] Scene Manager Button ---
	scene_manager_button.pressed.connect(_on_scene_manager_pressed)

	# --- [NEW] CORTEX: Cognitive Panel Button ---
	if %CognitiveButton:
		%CognitiveButton.pressed.connect(_on_cognitive_button_pressed)
	
	# --- ENHANCEMENT: Add Drag-and-Drop support ---
	var viewport = get_viewport()
	if viewport and not viewport.files_dropped.is_connected(_on_files_dropped):
		viewport.files_dropped.connect(_on_files_dropped)
		
	# --- THE IRON DOME (Input Shielding) v1 ---
	# We prevent the camera from "jumping" when interacting with UI
	#_apply_iron_dome_to_node(load_zone_panel)
	#_apply_iron_dome_to_node(%MainControls) # Ensure your MainControls has a unique name or reference
	
	# --- THE OMNISCIENT IRON DOME ---
	# Instead of connecting one by one, we shield THE ENTIRE UI LAYER.
	# We search for all 'Control' nodes in the scene and apply protection.
	pass # GUI ownership is evaluated centrally each frame
	_apply_universal_shielding()


func _initialize_ui_state() -> void:
	add_child(status_timer)
	status_timer.one_shot = true
	status_timer.timeout.connect(func(): status_label.hide())

	for preset_name in GaussianSplattingConfig.QualityPreset.keys():
		quality_selector.add_item(preset_name.capitalize())
	
	if is_instance_valid(viewer.config):
		quality_selector.select(viewer.config.current_preset)

	status_label.hide()
	load_zone_panel.hide()
#endregion

#region Signal Handlers
func _on_viewer_load_zone_visibility_changed(is_visible: bool) -> void:
	# This "coexistence fix" correctly prevents this UI from appearing
	# if the debug UI is active. This logic is sound and has been kept.
	var debug_ui_nodes = get_tree().get_nodes_in_group("debug_ui")
	if not debug_ui_nodes.is_empty():
		var debug_ui = debug_ui_nodes[0]
		if debug_ui.has_method("is_main_ui_visible") and debug_ui.is_main_ui_visible():
			return

	if not self.visible:
		load_zone_panel.hide()
		return

	load_zone_panel.visible = is_visible
	if is_visible:
		_rebuild_recent_files_list()

# --- Viewer Feedback Handlers ---
func _on_all_splats_loading_started() -> void:
	# This new function handles the start of ANY loading operation.
	status_label.text = "Loading models..."
	status_label.show()
	status_timer.stop()

func _on_viewer_loading_progress(progress: float, _loaded: int, _total: int) -> void:
	status_label.text = "Loading... %d%%" % int(progress * 100)

func _on_all_splats_loading_completed(total_splat_count: int) -> void:
	# This new function handles the completion of ANY loading operation.
	status_label.text = "Load complete (%d total splats)" % total_splat_count
	status_timer.start(3.0)

func _on_viewer_loading_completed(file_path: String, _splat_count: int) -> void:
	#status_label.text = "Successfully loaded %s" % file_path.get_file()
	#status_timer.start(3.0)
	pass

func _on_viewer_error(error_message: String, _error_code: int) -> void:
	status_label.text = "ERROR: %s" % error_message
	status_label.show()
	status_timer.start(5.0)

# --- UI Action Handlers ---
func _on_load_button_pressed() -> void:
	viewer.show_load_zone = true
	
func _on_close_button_pressed() -> void:
	viewer.show_load_zone = false

func _on_browse_button_pressed() -> void:
	# ENHANCEMENT: Simply pop up the persistent, pre-configured dialog.
	_dialog_open = true
	file_dialog.popup_centered()

## [NEW] Toggle the Scene Manager panel visibility
func _on_scene_manager_pressed() -> void:
	if not scene_manager_panel:
		# [FIX] Find the existing panel from the scene root instead of creating a duplicate
		var root := get_tree().root.get_node_or_null("Main")
		if root:
			scene_manager_panel = root.get_node_or_null("SceneManagerPanel") as SceneManagerPanel
		
		if not scene_manager_panel:
			push_warning("[ProductionUI] SceneManagerPanel not found in scene tree.")
			return
	
	# Toggle visibility
	if scene_manager_panel.visible:
		scene_manager_panel.hide_panel()
	else:
		scene_manager_panel.show_panel()

## [NEW] Toggle the Cognitive Panel (Neural HUD)
func _on_cognitive_button_pressed() -> void:
	if not cognitive_panel:
		# Lazy-load the panel
		var scene_path = "res://modules/spatial_intelligence/ui/CognitivePanel.tscn"
		if ResourceLoader.exists(scene_path):
			var scene = load(scene_path)
			cognitive_panel = scene.instantiate()
			# Add to the Scene Root to ensure it floats above everything
			get_tree().root.add_child(cognitive_panel)
			cognitive_panel.hide_panel()
			print("[ProductionUI] Cognitive Panel instantiated.")
		else:
			push_error("[ProductionUI] CognitivePanel.tscn not found at: " + scene_path)
			return
			
	# Toggle visibility
	if cognitive_panel.visible:
		cognitive_panel.hide_panel()
	else:
		cognitive_panel.show_panel()

func _on_clear_history_button_pressed() -> void:
	HistoryManager.clear_history()
	_rebuild_recent_files_list()

func _on_quality_selected(index: int) -> void:
	var preset = GaussianSplattingConfig.QualityPreset.values()[index]
	if is_instance_valid(viewer.config):
		viewer.config.apply_preset(preset)

# --- File Loading Handlers ---
func _on_file_dialog_selected(path: String) -> void:
	_dialog_open = false
	# BUG FIX: Call the correct, non-destructive function to add a new splat.
	viewer.load_new_splat_from_path(path)
	viewer.show_load_zone = false

func _on_file_dialog_canceled() -> void:
	_dialog_open = false
	viewer.show_load_zone = false

func _on_files_dropped(files: PackedStringArray) -> void:
	# ENHANCEMENT: Handle files dropped directly onto the viewport.
	if files.is_empty() or not is_instance_valid(viewer) or load_zone_panel.visible:
		return
		
	var file_path := files[0]
	if file_path.get_extension().to_lower() not in ['ply', 'gsres']:
		status_label.text = "ERROR: Invalid file type (expected .ply)"
		status_label.show()
		status_timer.start(5.0)
		return
		
	# BUG FIX: Call the correct, non-destructive function to add a new splat.
	viewer.load_new_splat_from_path(file_path)
	
## Logic: Disables camera movement whenever the mouse is over UI
func _apply_iron_dome_to_node(node: Control) -> void:
	if not node: return
	node.mouse_entered.connect(func(): viewer.set_camera_movement_enabled(false))
	node.mouse_exited.connect(func(): viewer.set_camera_movement_enabled(true))

func _on_clear_scene_pressed() -> void:
	if not is_instance_valid(viewer): return
	
	# 1. UI FEEDBACK
	status_label.text = "PURGING GPU ATLAS..."
	status_label.show()
	
	# 2. EXECUTE NUCLEAR CLEAR
	viewer._clear_scene_and_reset_atlas()
	
	# 3. RE-SYNC UI STATE
	_rebuild_recent_files_list()
	status_label.text = "Scene cleared. GPU atlas ready."
	status_timer.start(2.0)
	
	# 4. CLOSE LOAD ZONE
	viewer.show_load_zone = false

func _on_clear_scene_pressed_old() -> void:
	if is_instance_valid(viewer):
		# We call the internal reset logic
		viewer._clear_scene_and_reset_atlas()
		status_label.text = "Scene Cleared. VRAM Reset."
		status_label.show()
		status_timer.start(2.0)
		# Hide the load zone if it was open
		viewer.show_load_zone = false

#endregion

#region UI Logic
func _rebuild_recent_files_list() -> void:
	for child in recent_files_list.get_children():
		child.queue_free()

	var recent_files = HistoryManager.recent_files
	if recent_files.is_empty():
		var label = Label.new()
		label.text = "No recent files found."
		recent_files_list.add_child(label)
	else:
		for file_path in recent_files:
			var button = Button.new()
			# Show the full path in a tooltip for clarity
			button.tooltip_text = file_path
			# Show just the filename on the button
			button.text = file_path.get_file()
			button.flat = true
			button.clip_text = true
			# Button.text_alignment takes an integer where 0=Left, 1=Center, 2=Right.
			#button.text_alignment = 1 # 0 = Left
			
			button.pressed.connect(
				func():
					# BUG FIX: Call the correct, non-destructive function.
					viewer.load_new_splat_from_path(file_path)
					viewer.show_load_zone = false
			)
			recent_files_list.add_child(button)

## Scans the scene and ensures NO mouse event reaches the 3D world through UI
func _apply_universal_shielding() -> void:
	pass

func _process(_delta: float) -> void:
	if not is_instance_valid(viewer): return
	var focus := get_viewport().gui_get_focus_owner()
	var editing := is_instance_valid(focus) and focus.is_visible_in_tree() and (focus is LineEdit or focus is TextEdit)
	viewer.set_camera_blocker("godot_ui", get_viewport().gui_get_hovered_control() != null or editing or _dialog_open or file_dialog.visible)

func _exit_tree() -> void:
	if is_instance_valid(viewer): viewer.set_camera_blocker("godot_ui", false)

func _on_configuration_migration_changed(active: bool) -> void:
	if active:
		_migration_load_disabled = load_file_button.disabled
		_migration_quality_disabled = quality_selector.disabled
		load_file_button.disabled = true
		quality_selector.disabled = true
		status_label.text = "Applying quality settings..."
		status_label.show()
		status_timer.stop()
	else:
		load_file_button.disabled = _migration_load_disabled
		quality_selector.disabled = _migration_quality_disabled
		status_label.text = "Quality settings ready."
		status_label.show()
		status_timer.start(2.0)
