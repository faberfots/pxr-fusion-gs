class_name DemoUIController
extends Node
## Compatibility shortcut owner; every diagnostic control is authored in its scene.
@export var viewer:GaussianSplattingViewer
var show_ui:=false:
	set(value):
		show_ui=value
		if is_node_ready() and has_node("Diagnostics"):$Diagnostics.visible=value
func _enter_tree()->void:
	if has_node("Diagnostics"):$Diagnostics.viewer=viewer
func _ready()->void:
	add_to_group("debug_ui")
	add_to_group("gs_debug_ui")
	if has_node("Diagnostics"):
		$Diagnostics.visible=show_ui
		$Diagnostics.drag_changed.connect(func(active):viewer.set_camera_blocker("diagnostic_drag",active))
func _unhandled_input(event:InputEvent)->void:
	if event.is_action_pressed("toggle_imgui"):
		show_ui=not show_ui
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fullscreen"):
		var mode:=DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
func is_main_ui_visible()->bool:
	return false
