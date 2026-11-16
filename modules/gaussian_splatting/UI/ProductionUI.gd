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
@onready var quality_selector: OptionButton = $Surface/SettingsPanel.get_node("%QualitySelector")
@onready var load_file_button: Button = $Surface/MainControls.get_node("%LoadFileButton")
@onready var browse_button: Button = %BrowseButton
@onready var clear_history_button: Button = %ClearHistoryButton
@onready var close_button: Button = %CloseButton
@onready var file_dialog: FileDialog = %FileDialog
@onready var status_timer: Timer = %StatusTimer
@onready var clear_scene_button: Button = $Surface/SettingsPanel.get_node("%ClearSceneButton") # We will add this in the TSCN next
@onready var scene_manager_button: Button = $Surface/MainControls.get_node("%SceneManagerButton") # [NEW]

	## [NEW] Reference to the Scene Manager panel (lazy-loaded)
var _dialog_open := false
var scene_manager_panel: SceneManagerPanel = null
var cognitive_panel: CognitivePanel = null # [NEW] The Neural HUD
var color_panel:GSColorAdjustmentPanel
var transform_controls:GSModelTransformControls

#endregion

#region Initialization
func _enter_tree() -> void:
	$Surface/ColorAdjustmentPanel.viewer=viewer
	$Surface/ModelTransformControls.viewer=viewer
	$Surface/ModelTransformControls.layout_host=self
	$Surface/PlacementHUD.viewer=viewer
	$Surface/LightingPanel.get_node("%SkyControls").sky=viewer.get_parent().get_node_or_null("Sky3D") as Sky3D
func _ready() -> void:
	if not is_instance_valid(viewer):hide();return
	GSUiScale.apply(load_zone_panel)
	GSUiScale.apply(status_label.get_parent())
	load_zone_panel.resized.connect(_scale_auxiliary_layout)
	status_label.get_parent().resized.connect(_scale_auxiliary_layout)
	_scale_auxiliary_layout.call_deferred()
	color_panel=%ColorAdjustmentPanel
	transform_controls=%ModelTransformControls
	status_label.visibility_changed.connect(func():status_label.get_parent().visible=status_label.visible)
	_connect_signals();_initialize_ui_state()
	%ClearBeforeImport.toggled.connect(func(enabled):
		%ImportModeHelp.text="Start fresh · current models will be replaced." if enabled else "Add to this scene · existing models stay in place."
	)
	%LightingPanel.get_node("%Tabs").set_tab_title(1,"Sky & time")
	var dock:GSCommandDock=%MainControls
	dock.get_node("%ColorButton").pressed.connect(func():_toggle_panel(color_panel))
	for pair in [["CameraButton",%CameraPanel],["SettingsButton",%SettingsPanel],["LightingButton",%LightingPanel]]:
		var panel:GSFloatingPanel=pair[1]
		dock.get_node("%"+pair[0]).pressed.connect(_toggle_panel.bind(panel))
		panel.get_node("%Close").pressed.connect(panel.hide)
	for name in ["LoadFileButton","SceneManagerButton","ColorButton","LightingButton","CameraButton","SettingsButton","CognitiveButton"]:
		dock.get_node("%"+name).pressed.connect(func():dock.set_expanded(false))
	for panel in [dock,color_panel,%CameraPanel,%SettingsPanel,%LightingPanel]:
		panel.drag_changed.connect(func(active):viewer.set_camera_blocker("floating_"+panel.layout_id,active))
	%CameraPanel.get_node("%Home").pressed.connect(func():viewer.home_view())
	%CameraPanel.get_node("%FrameSelected").pressed.connect(func():viewer.frame_models(viewer.selected_model_ids))
	%CameraPanel.get_node("%FrameAll").pressed.connect(func():viewer.frame_models([]))
	%CameraPanel.get_node("%DriveModel").toggled.connect(func(enabled):
		if enabled:
			if viewer.start_model_navigation()!=OK:%CameraPanel.get_node("%DriveModel").set_pressed_no_signal(false)
			else:%CameraPanel.hide()
		else:viewer.stop_model_navigation()
	)
	%CameraPanel.get_node("%DriveSpeed").value_changed.connect(viewer.set_model_navigation_speed)
	%CameraPanel.get_node("%ProtectedFly").toggled.connect(func(value):viewer.camera_controller.set_protection(value))
	%CameraPanel.get_node("%OrbitMode").toggled.connect(_on_camera_mode)
	%SettingsPanel.get_node("%ResetLayout").pressed.connect(func():
		for panel in [dock,color_panel,%CameraPanel,%SettingsPanel,%LightingPanel]:panel.reset_layout()
		for manager in get_tree().get_nodes_in_group("gs_scene_managers"):manager.draggable_container.reset_layout()
		if is_instance_valid(cognitive_panel):cognitive_panel.draggable_container.reset_layout()
		transform_controls.reset_toolbar_layout()
	)
	viewer.composition_progress.connect(func(message):status_label.text=message;status_label.show();status_timer.start(5.0))
	viewer.composition_operation_changed.connect(func(active):
		if active:transform_controls.finish_drag(true)
		load_file_button.disabled=active;quality_selector.disabled=active;clear_scene_button.disabled=active
	)
	viewer.placement_changed.connect(func(active):
		if active:transform_controls.finish_drag(true)
		load_file_button.disabled=active;quality_selector.disabled=active
	)
	%SettingsPanel.get_node("%ProgressivePreview").toggled.connect(func(value):
		if viewer.config:viewer.config.loading_progressive_preview=value
	)
	%SettingsPanel.get_node("%Diagnostics").pressed.connect(_toggle_diagnostics)
	%LightingPanel.get_node("%Shadows").toggled.connect(func(value):viewer.lighting.shadows_enabled=value)
	%LightingPanel.get_node("%ShadowStrength").value_changed.connect(func(value):viewer.lighting.shadow_strength=value)
	%LightingPanel.get_node("%ShadowResolution").item_selected.connect(func(index):viewer.lighting.shadow_resolution=[256,512,1024][index])
	viewer.model_registry_changed.connect(_update_population)
	_update_population()
func _toggle_panel(panel:Control)->void:
	if not panel.visible:
		for other in [color_panel,%CameraPanel,%SettingsPanel,%LightingPanel]:
			if other!=panel and other.visible:
				if other.has_method("hide_panel"):other.hide_panel()
				else:other.hide()
	if panel.visible:
		if panel.has_method("hide_panel"):panel.hide_panel()
		else:panel.hide()
	else:
		if panel.has_method("show_panel"):panel.show_panel()
		else:
			panel.show();panel.reset_size()
			if panel is GSFloatingPanel:panel._reflow.call_deferred()
func _toggle_diagnostics()->void:
	for debug in get_tree().get_nodes_in_group("debug_ui"):
		debug.show_ui=not debug.show_ui
func _on_camera_mode(orbit:bool)->void:
	var controller:=viewer.camera_controller
	var camera:=controller.get_node_or_null("OrbitCamera" if orbit else "FreeLookCamera") as CameraInterface
	if not camera:return
	var pose:=controller.get_camera().global_transform
	if camera is OrbitCamera:
		var model:=viewer.get_selected_asset()
		if model:camera.orbit_point=viewer.get_asset_world_bounds(model).get_center()
	controller.set_camera(camera);controller.set_camera_transform(pose)
func _update_population()->void:
	%MainControls.update_population(viewer.get_asset_snapshot().size(),viewer.total_splats_to_load)
func _layout_top_bar()->void:
	%MainControls._layout()
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
	viewer.import_requested.connect(func(replace_scene):%ClearBeforeImport.button_pressed=replace_scene)

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
	$Surface/MainControls.get_node("%CognitiveButton").pressed.connect(_on_cognitive_button_pressed)
	
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
	var state:=viewer.get_loading_state()
	status_label.text=("Preview · %d / %d splats · verification pending" % [state.resident_splats,state.total_splats]) if state.preview else "Loading... %d%%" % int(progress*100)

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
	viewer.request_import()
	
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
		var root := viewer.get_parent()
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
	viewer.show_load_zone = false
	await _import_interactive(path)

func _import_interactive(path:String,point:Vector2=Vector2.INF)->void:
	var replace_scene:bool=%ClearBeforeImport.button_pressed
	var result:Error
	if path.get_extension().to_lower()=="pxrscene":result=await viewer.open_composition(path) if replace_scene else await viewer.add_composition(path)
	else:result=viewer.begin_model_placement(path,point,%ImportKind.selected,replace_scene)
	# Replacement is an explicit, one-import choice; the safe default returns afterward.
	if result==OK:%ClearBeforeImport.button_pressed=false

func _on_file_dialog_canceled() -> void:
	_dialog_open = false
	viewer.show_load_zone = false

func _on_files_dropped(files: PackedStringArray) -> void:
	# ENHANCEMENT: Handle files dropped directly onto the viewport.
	if files.is_empty() or not is_instance_valid(viewer) or load_zone_panel.visible:
		return
		
	var file_path := files[0]
	if file_path.get_extension().to_lower() not in ['ply', 'gsres', 'glb', 'gltf', 'pxrscene']:
		status_label.text = "ERROR: Expected PLY, GSRES, GLB, glTF or PXRSCENE"
		status_label.show()
		status_timer.start(5.0)
		return
		
	# BUG FIX: Call the correct, non-destructive function to add a new splat.
	await _import_interactive(file_path,get_viewport().get_mouse_position())
	
## Logic: Disables camera movement whenever the mouse is over UI
func _apply_iron_dome_to_node(node: Control) -> void:
	if not node: return
	node.mouse_entered.connect(func(): viewer.set_camera_movement_enabled(false))
	node.mouse_exited.connect(func(): viewer.set_camera_movement_enabled(true))

func _on_clear_scene_pressed() -> void:
	if not is_instance_valid(viewer): return
	
	# 1. UI FEEDBACK
	status_label.text = "Clearing scene…"
	status_label.show()
	
	# 2. EXECUTE NUCLEAR CLEAR
	viewer._clear_scene_and_reset_atlas()
	
	# 3. RE-SYNC UI STATE
	_rebuild_recent_files_list()
	status_label.text = "Scene cleared. Ready to import."
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
	for child in recent_files_list.get_children():child.queue_free()
	if HistoryManager.recent_files.is_empty():
		recent_files_list.add_child(preload("res://modules/gaussian_splatting/UI/EmptyRecentLabel.tscn").instantiate())
	else:
		for file_path in HistoryManager.recent_files:
			var button:Button=preload("res://modules/gaussian_splatting/UI/RecentFileButton.tscn").instantiate()
			button.tooltip_text=file_path;button.text=file_path.get_file()
			button.pressed.connect(func():viewer.show_load_zone=false;await _import_interactive(file_path))
			recent_files_list.add_child(button)

## Scans the scene and ensures NO mouse event reaches the 3D world through UI
func _apply_universal_shielding() -> void:
	pass

func _process(_delta: float) -> void:
	if not is_instance_valid(viewer): return
	var navigation:=viewer.get_model_navigation_state()
	var native:=viewer.get_selected_asset() as GSSceneMesh
	var drive:CheckButton=%CameraPanel.get_node_or_null("%DriveModel")
	# An already-running editor instance can hot-reload this script before its
	# authored panel is reinstanced. Keep that existing session usable until restart.
	if drive:
		drive.set_pressed_no_signal(navigation.active)
		drive.disabled=not navigation.active and (not native or native.transform_locked or viewer.resolve_import_kind(native)==GaussianSplat.ImportKind.ENVIRONMENT or viewer.is_loading() or viewer.placement_active or viewer.composition_busy)
		%CameraPanel.get_node("%DriveHelp").text=navigation.status
		%CameraPanel.get_node("%DriveSpeed").set_value_no_signal(navigation.speed)
		%CameraPanel.get_node("%DriveSpeed").visible=navigation.active
	for action in ["Home","FrameSelected","FrameAll","OrbitMode"]:%CameraPanel.get_node("%"+action).disabled=navigation.active
	if navigation.active:status_label.text=navigation.status;status_label.show();status_timer.start(1.0)
	if viewer.config:%SettingsPanel.get_node("%ProgressivePreview").set_pressed_no_signal(viewer.config.loading_progressive_preview)
	if viewer.camera_controller:
		%CameraPanel.get_node("%ProtectedFly").set_pressed_no_signal(viewer.camera_controller.safety.protected_fly)
		%CameraPanel.get_node("%OrbitMode").set_pressed_no_signal(viewer.camera_controller.active_camera is OrbitCamera)
	%CameraPanel.get_node("%FrameSelected").disabled=navigation.active or viewer.selected_model_ids.is_empty()
	%LightingPanel.get_node("%Shadows").set_pressed_no_signal(viewer.lighting.shadows_enabled)
	%LightingPanel.get_node("%ShadowStrength").set_value_no_signal(viewer.lighting.shadow_strength)
	%LightingPanel.get_node("%ShadowResolution").select([256,512,1024].find(viewer.lighting.shadow_resolution))
	%LightingPanel.get_node("%ShadowStatus").text="Captured radiance · dynamic shadows off" if not viewer.lighting.shadows_enabled else "Directional opacity shadows · %d²" % viewer.lighting.shadow_resolution
	var focus := get_viewport().gui_get_focus_owner()
	var editing := is_instance_valid(focus) and focus.is_visible_in_tree() and (focus is LineEdit or focus is TextEdit)
	viewer.set_camera_blocker("godot_ui", get_viewport().gui_get_hovered_control() != null or editing or _dialog_open or file_dialog.visible)

func _exit_tree() -> void:
	if is_instance_valid(cognitive_panel):cognitive_panel.queue_free()
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

func get_ui_obstacles()->Array[Rect2]:
	var result:Array[Rect2]=[]
	for panel in get_tree().get_nodes_in_group("gs_floating_panels"):
		if is_instance_valid(transform_controls) and panel==transform_controls.toolbar:continue
		if panel.get_viewport()==get_viewport() and panel.is_visible_in_tree():result.append(GSUiScale.screen_rect(panel))
	if is_instance_valid(scene_manager_panel) and scene_manager_panel.visible:result.append(GSUiScale.screen_rect(scene_manager_panel.draggable_container))
	if is_instance_valid(cognitive_panel) and cognitive_panel.visible:result.append(GSUiScale.screen_rect(cognitive_panel.draggable_container))
	return result

func _scale_auxiliary_layout()->void:
	load_zone_panel.pivot_offset=load_zone_panel.size*0.5
	var strip:Control=status_label.get_parent()
	strip.pivot_offset=Vector2(strip.size.x*0.5,strip.size.y)
