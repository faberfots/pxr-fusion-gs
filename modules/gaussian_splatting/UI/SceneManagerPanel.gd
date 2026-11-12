# SceneManagerPanel.gd
# ════════════════════════════════════════════════════════════════════════════════
# 3D GS SCENE MANAGER - NEURAL LINK CONTROL PANEL
# ════════════════════════════════════════════════════════════════════════════════
# PURPOSE: Provides real-time control over GaussianSplat transforms via UI.
# SSOT: This script is the single source of truth for scene object management UI.
# GODOT 4.5.1+ COMPLIANT: Uses modern patterns for signals, typed arrays, etc.
# ════════════════════════════════════════════════════════════════════════════════
class_name SceneManagerPanel
extends CanvasLayer

## Reference to the GaussianSplattingViewer (REQUIRED - set by parent)
@export var viewer: GaussianSplattingViewer

#region Node References
@onready var draggable_container: DraggableContainer = %DraggableContainer
@onready var header_bar: HBoxContainer = %HeaderBar
@onready var minimize_button: Button = %MinimizeButton
@onready var close_button: Button = %CloseButton
@onready var object_list: VBoxContainer = %ObjectList
@onready var no_objects_label: Label = %NoObjectsLabel
@onready var transform_section: VBoxContainer = %TransformSection
@onready var info_section: VBoxContainer = %InfoSection

# Transform Controls
@onready var pos_x: SpinBox = %PosX
@onready var pos_y: SpinBox = %PosY
@onready var pos_z: SpinBox = %PosZ
@onready var rot_x: SpinBox = %RotX
@onready var rot_y: SpinBox = %RotY
@onready var rot_z: SpinBox = %RotZ
@onready var scale_uniform: SpinBox = %ScaleUniform
@onready var reset_button: Button = %ResetButton

# Info Labels
@onready var instance_id_label: Label = %InstanceIDLabel
@onready var splat_count_label: Label = %SplatCountLabel
@onready var buffer_offset_label: Label = %BufferOffsetLabel
#endregion

#region State
## The currently selected GaussianSplat node (or null)
var selected_node: GaussianSplat:
	get: return viewer.get_selected_model() if is_instance_valid(viewer) else null
	set(value):
		if is_instance_valid(viewer): viewer.select_model_id(value.model_id if is_instance_valid(value) else "")

## Tracks if we are programmatically updating spinboxes (to prevent feedback loops)
var _is_updating_ui := false

## Tracks minimized state
var _is_minimized := false

## Tracks if the user is actively editing a spinbox (prevents sync override)
var _user_is_editing := false

## Preloaded ObjectListItem scene for performance
var _object_list_item_scene: PackedScene = preload("res://modules/gaussian_splatting/UI/ObjectListItem.tscn")
#endregion


func _ready() -> void:
	add_to_group("gs_scene_managers")
	# Validate viewer reference
	if not is_instance_valid(viewer):
		push_error("[SceneManagerPanel] 'viewer' property not assigned! Panel disabled.")
		hide()
		return
	
	# Connect drag handle
	if draggable_container:
		draggable_container.drag_handle = header_bar
		# [NEW] Input Shielding: Stop camera when mouse is over panel
		draggable_container.mouse_entered.connect(_on_mouse_entered_panel)
		draggable_container.mouse_exited.connect(_on_mouse_exited_panel)
	
	# Connect UI signals
	_connect_signals()
	
	# Initial state
	_refresh_object_list()
	_update_transform_controls_enabled(false)


func _connect_signals() -> void:
	# Header buttons
	minimize_button.pressed.connect(_on_minimize_pressed)
	close_button.pressed.connect(_on_close_pressed)
	reset_button.pressed.connect(_on_reset_transform_pressed)
	
	# Transform spinboxes - use value_changed for live updates
	pos_x.value_changed.connect(_on_pos_x_changed)
	pos_y.value_changed.connect(_on_pos_y_changed)
	pos_z.value_changed.connect(_on_pos_z_changed)
	rot_x.value_changed.connect(_on_rot_x_changed)
	rot_y.value_changed.connect(_on_rot_y_changed)
	rot_z.value_changed.connect(_on_rot_z_changed)
	scale_uniform.value_changed.connect(_on_scale_changed)
	
	# [NEW] Focus tracking to prevent sync while user is editing
	for spinbox in [pos_x, pos_y, pos_z, rot_x, rot_y, rot_z, scale_uniform]:
		spinbox.get_line_edit().focus_entered.connect(func(): _user_is_editing = true)
		spinbox.get_line_edit().focus_exited.connect(func(): _user_is_editing = false)
	
	# Viewer signals for list updates
	if viewer:
		viewer.model_registry_changed.connect(func(): call_deferred("_refresh_object_list"))
		# Note: Direct signal to refresh when scene changes would be ideal.
		# For now, we refresh periodically or on demand.


func _process(_delta: float) -> void:
	# Keep transform UI in sync if a node is selected
	# This handles external changes (e.g., animation, scripted movement)
	# [FIX] Skip sync while user is actively editing a spinbox
	if is_instance_valid(selected_node) and not _is_updating_ui and not _user_is_editing:
		_sync_ui_to_node_transform()


#region Object List Management
## Rebuilds the object list from viewer.managed_splats
func _refresh_object_list() -> void:
	# Clear existing items (except the "no objects" placeholder)
	for child in object_list.get_children():
		if child != no_objects_label:
			child.queue_free()
	
	# Check if viewer has any managed splats
	if not is_instance_valid(viewer) or viewer.managed_splats.is_empty():
		no_objects_label.show()
		_clear_selection()
		return
	
	no_objects_label.hide()
	
	# Create list items for each managed node
	for node in viewer.managed_splats.keys():
		if not is_instance_valid(node):
			continue
		
		var item := _object_list_item_scene.instantiate() as HBoxContainer
		var select_button: Button = item.get_node("%SelectButton")
		var visibility_button: Button = item.get_node("%VisibilityButton")
		var delete_button: Button = item.get_node("%DeleteButton")
		
		# Set display name
		var display_name = node.file_path.get_file() if not node.file_path.is_empty() else node.name
		select_button.text = display_name
		
		# Set visibility icon
		visibility_button.text = "👁" if node.visible else "◯"
		
		# Connect signals (capture 'node' in closure)
		select_button.pressed.connect(_on_object_selected.bind(node))
		visibility_button.pressed.connect(_on_visibility_toggled.bind(node, visibility_button))
		delete_button.pressed.connect(_on_delete_pressed.bind(node))
		
		# Store node reference for later lookup
		item.set_meta("splat_node", node)
		
		object_list.add_child(item)
	
	# Auto-select first if nothing selected
	if not is_instance_valid(selected_node) and viewer.managed_splats.size() > 0:
		for candidate in viewer.managed_splats.keys():
			if is_instance_valid(candidate):
				_on_object_selected(candidate)
				break


func _on_viewer_load_completed(_total_count: int) -> void:
	# Refresh list when loading finishes
	call_deferred("_refresh_object_list")
#endregion


#region Selection & Transform
## Called when user clicks an object in the list
func _on_object_selected(node: GaussianSplat) -> void:
	if not is_instance_valid(node) or not node.is_loaded:
		_clear_selection()
		return
	
	selected_node = node
	_update_transform_controls_enabled(true)
	_sync_ui_to_node_transform()
	_update_info_labels()
	
	# Highlight selected item in list
	_update_list_selection_visuals()


## Clears the current selection
func _clear_selection() -> void:
	selected_node = null
	_update_transform_controls_enabled(false)
	
	# Reset info labels
	instance_id_label.text = "  Instance ID: -"
	splat_count_label.text = "  Splat Count: -"
	buffer_offset_label.text = "  Buffer Offset: -"


func _update_transform_controls_enabled(enabled: bool) -> void:
	pos_x.editable = enabled
	pos_y.editable = enabled
	pos_z.editable = enabled
	rot_x.editable = enabled
	rot_y.editable = enabled
	rot_z.editable = enabled
	scale_uniform.editable = enabled
	reset_button.disabled = not enabled


## Syncs UI spinbox values to the selected node's current transform
func _sync_ui_to_node_transform() -> void:
	if not is_instance_valid(selected_node):
		return
	
	_is_updating_ui = true
	
	var t := selected_node.global_transform
	
	# Position
	pos_x.value = t.origin.x
	pos_y.value = t.origin.y  # [FIX] Invert Y for intuitive UI (+ = up)
	pos_z.value = t.origin.z
	
	# Rotation (convert to degrees)
	var euler := selected_node.global_rotation_degrees
	rot_x.value = euler.x
	rot_y.value = euler.y
	rot_z.value = euler.z
	
	# Scale (uniform - use X as reference)
	scale_uniform.value = t.basis.get_scale().x
	
	_is_updating_ui = false


## Updates info labels with Neural Link data
func _update_info_labels() -> void:
	if not is_instance_valid(selected_node) or not is_instance_valid(viewer):
		return
	
	# Get Instance ID from viewer's registry
	var inst_id := -1
	if viewer._node_to_instance_id.has(selected_node):
		inst_id = viewer._node_to_instance_id[selected_node]
	
	instance_id_label.text = "  Instance ID: %d" % inst_id
	splat_count_label.text = "  Splat Count: %s" % _format_number(selected_node.splat_count)
	buffer_offset_label.text = "  Buffer Offset: %d" % selected_node.buffer_offset


func _update_list_selection_visuals() -> void:
	for item in object_list.get_children():
		if item == no_objects_label:
			continue
		
		var stored_node = item.get_meta("splat_node", null)
		var select_button: Button = item.get_node("%SelectButton")
		
		if stored_node == selected_node:
			# Highlight selected
			select_button.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0, 1.0))
		else:
			# Remove highlight
			select_button.remove_theme_color_override("font_color")
#endregion


#region Transform Handlers (Live Update)
func _on_pos_x_changed(value: float) -> void:
	if _is_updating_ui or not is_instance_valid(selected_node):
		return
	selected_node.global_position.x = value


func _on_pos_y_changed(value: float) -> void:
	if _is_updating_ui or not is_instance_valid(selected_node):
		return
	selected_node.global_position.y = value  # [FIX] Invert Y for intuitive UI (+ = up)


func _on_pos_z_changed(value: float) -> void:
	if _is_updating_ui or not is_instance_valid(selected_node):
		return
	selected_node.global_position.z = value


func _on_rot_x_changed(value: float) -> void:
	if _is_updating_ui or not is_instance_valid(selected_node):
		return
	var euler := selected_node.global_rotation_degrees
	euler.x = value
	selected_node.global_rotation_degrees = euler


func _on_rot_y_changed(value: float) -> void:
	if _is_updating_ui or not is_instance_valid(selected_node):
		return
	var euler := selected_node.global_rotation_degrees
	euler.y = value
	selected_node.global_rotation_degrees = euler


func _on_rot_z_changed(value: float) -> void:
	if _is_updating_ui or not is_instance_valid(selected_node):
		return
	var euler := selected_node.global_rotation_degrees
	euler.z = value
	selected_node.global_rotation_degrees = euler


func _on_scale_changed(value: float) -> void:
	if _is_updating_ui or not is_instance_valid(selected_node):
		return
	selected_node.global_basis = Basis.from_euler(selected_node.global_rotation).scaled(Vector3.ONE * value)


func _on_reset_transform_pressed() -> void:
	if not is_instance_valid(selected_node):
		return
	
	selected_node.global_transform = Transform3D.IDENTITY
	_sync_ui_to_node_transform()
#endregion


#region Visibility & Delete
func _on_visibility_toggled(node: GaussianSplat, button: Button) -> void:
	if not is_instance_valid(node):
		return
	
	node.visible = not node.visible
	button.text = "👁" if node.visible else "◯"


func _on_delete_pressed(node: GaussianSplat) -> void:
	if not is_instance_valid(node):
		return
	
	# Clear selection if this was selected
	if node == selected_node:
		_clear_selection()
	
	# Remove node
	node.queue_free()
	
	# Refresh list after a frame
	call_deferred("_refresh_object_list")
#endregion


#region Window Controls
func _on_minimize_pressed() -> void:
	_is_minimized = not _is_minimized
	
	# Toggle visibility of content sections
	transform_section.visible = not _is_minimized
	info_section.visible = not _is_minimized
	
	# Find and toggle object section
	var object_section = draggable_container.get_node("Panel/MainLayout/ObjectSection")
	if object_section:
		object_section.visible = not _is_minimized
	
	# Find and toggle separators
	for child in draggable_container.get_node("Panel/MainLayout").get_children():
		if child is HSeparator:
			child.visible = not _is_minimized
	
	# Update button text
	minimize_button.text = "□" if _is_minimized else "−"


func _on_close_pressed() -> void:
	if is_instance_valid(viewer):
		viewer.set_camera_blocker("scene_manager", false)
	hide()

#region Input Shielding Handlers
func _on_mouse_entered_panel() -> void:
	if is_instance_valid(viewer):
		viewer.set_camera_blocker("scene_manager", true)

func _on_mouse_exited_panel() -> void:
	if is_instance_valid(viewer):
		viewer.set_camera_blocker("scene_manager", false)
#endregion
#endregion


#region Utilities
func _format_number(num: int) -> String:
	# Format large numbers with commas for readability
	var s := str(num)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result


## Public API: Show the panel
func show_panel() -> void:
	show()
	_refresh_object_list()


## Public API: Hide the panel
func hide_panel() -> void:
	for spinbox in [pos_x, pos_y, pos_z, rot_x, rot_y, rot_z, scale_uniform]:
		spinbox.get_line_edit().release_focus()
	_user_is_editing = false
	if is_instance_valid(viewer): viewer.set_camera_blocker("scene_manager", false)
	hide()
#endregion

func select_model(identifier: String) -> bool:
	for node in viewer.managed_splats:
		if is_instance_valid(node) and node.model_id == identifier and node.is_loaded:
			_on_object_selected(node)
			show_panel()
			return true
	return false

func _select_item_by_name(identifier: String) -> bool:
	return select_model(identifier)

func _exit_tree() -> void:
	if is_instance_valid(viewer): viewer.set_camera_blocker("scene_manager", false)
