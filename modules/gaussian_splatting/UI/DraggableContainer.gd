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

## Emitted when dragging starts.
signal drag_started

## Emitted when dragging ends.
signal drag_ended

# --- Internal State ---
var _is_dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
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
				drag_ended.emit()


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
	drag_ended.emit()


## Check if currently being dragged.
func is_dragging() -> bool:
	return _is_dragging
