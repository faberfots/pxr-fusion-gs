# DraggableContainer.gd
# ════════════════════════════════════════════════════════════════════════════════
# REUSABLE DRAGGABLE CONTROL CONTAINER
# ════════════════════════════════════════════════════════════════════════════════
# PURPOSE: Enables any Control node to be dragged around the screen by a handle.
# SSOT: This script is the single source of truth for drag behavior.
# GODOT 4.5.1+ COMPLIANT: Uses modern input handling patterns.
# ════════════════════════════════════════════════════════════════════════════════
class_name DraggableContainer
extends Control

## The child Control node that acts as the drag handle (e.g., header bar).
## When the user clicks and drags this handle, the entire container moves.
@export var drag_handle: Control

## If true, the container cannot be dragged outside the viewport bounds.
@export var constrain_to_viewport: bool = true
@export var layout_id:=""

## Emitted when dragging starts.
signal drag_started

## Emitted when dragging ends.
signal drag_ended

# --- Internal State ---
var _is_dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_restore.call_deferred()
	# Connect to the drag handle's input events
	if drag_handle:
		drag_handle.gui_input.connect(_on_drag_handle_input)
	else:
		push_warning("[DraggableContainer] No drag_handle assigned. Dragging will not work.")


func _on_drag_handle_input(event: InputEvent) -> void:
	# Handle mouse button events for starting/stopping drag
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				drag_started.emit()
			else:
				# Stop dragging
				_is_dragging = false
				drag_ended.emit();_save()


func _process(_delta: float) -> void:
	if not _is_dragging:
		return
	
	# Calculate new position
	var new_position := get_global_mouse_position() - _drag_offset
	
	# Constrain to viewport if enabled
	if constrain_to_viewport:
		var viewport_size := get_viewport_rect().size
		var container_size := size
		
		# Clamp X
		new_position.x = clampf(new_position.x, 0, maxf(0.0, viewport_size.x - container_size.x))
		# Clamp Y
		new_position.y = clampf(new_position.y, 0, maxf(0.0, viewport_size.y - container_size.y))
	
	# Apply new position
	global_position = new_position


## Programmatically start dragging (useful for touch interfaces).
func start_drag() -> void:
	_is_dragging = true
	_drag_offset = get_global_mouse_position() - global_position
	drag_started.emit()


## Programmatically stop dragging.
func stop_drag() -> void:
	_is_dragging = false
	drag_ended.emit();_save()


## Check if currently being dragged.
func is_dragging() -> bool:
	return _is_dragging

func _input(event:InputEvent)->void:
	if _is_dragging and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:stop_drag()
func _notification(what:int)->void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and _is_dragging:stop_drag()
func _exit_tree()->void:
	if _is_dragging:drag_ended.emit()
func _fit()->void:
	if constrain_to_viewport:position=position.clamp(Vector2(12,12),(get_viewport_rect().size-size-Vector2(12,30)).max(Vector2(12,12)))
func _save()->void:
	if layout_id.is_empty() or not is_inside_tree():return
	var file:=ConfigFile.new();file.load(GSFloatingPanel.LAYOUT_PATH)
	file.set_value(layout_id,"position",position/get_viewport_rect().size.max(Vector2.ONE));file.save(GSFloatingPanel.LAYOUT_PATH)
func _restore()->void:
	var file:=ConfigFile.new()
	if not layout_id.is_empty() and file.load(GSFloatingPanel.LAYOUT_PATH)==OK and file.has_section_key(layout_id,"position"):
		var saved:Variant=file.get_value(layout_id,"position")
		if saved is Vector2 and saved.is_finite():position=saved*get_viewport_rect().size
	_fit()
func reset_layout()->void:
	position=Vector2(24,110);_fit();_save()
