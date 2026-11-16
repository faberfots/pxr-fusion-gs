class_name GSFloatingPanel
extends PanelContainer
## Scene-authored panel behavior. Layout preferences contain no scene/model state.
signal drag_changed(active: bool)
@export var drag_handle: Control
@export var layout_id := "panel"
@export var fit_content_height:=true
@export var default_position:=Vector2(-1,128)
var _dragging := false
var _drag_offset := Vector2.ZERO
var _placed := false
var _reveal:Tween
const LAYOUT_PATH := "user://viewer-layout.cfg"
func _ready() -> void:
	GSUiScale.apply(self)
	add_to_group("gs_floating_panels")
	if drag_handle: drag_handle.gui_input.connect(_on_header_input)
	get_viewport().size_changed.connect(_fit)
	_load_layout.call_deferred()
	visibility_changed.connect(_on_visibility_changed)
func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = drag_handle.get_global_transform()*event.position - global_position
		drag_changed.emit(_dragging)
		drag_handle.accept_event()
		if not _dragging: save_layout()
func _input(event: InputEvent) -> void:
	if not _dragging: return
	if event is InputEventMouseMotion:
		global_position = get_canvas_transform().affine_inverse()*event.position - _drag_offset
		_fit();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false;drag_changed.emit(false);save_layout()
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging:
		_dragging = false;drag_changed.emit(false);save_layout()
func _fit() -> void:
	var viewport := get_viewport_rect().size
	position = position.clamp(Vector2(12,12), (viewport-GSUiScale.extent(self)-Vector2(12,30)).max(Vector2(12,12)))
func _load_layout() -> void:
	var file := ConfigFile.new()
	if file.load(LAYOUT_PATH) == OK and file.has_section_key(layout_id,"position"):
		var saved: Variant = file.get_value(layout_id,"position")
		if saved is Vector2 and saved.is_finite(): position=saved*get_viewport_rect().size;_placed=true
	_fit()
func save_layout() -> void:
	if not is_inside_tree():return
	var file := ConfigFile.new();file.load(LAYOUT_PATH)
	file.set_value(layout_id,"position",position/get_viewport_rect().size.max(Vector2.ONE))
	file.save(LAYOUT_PATH);_placed=true
func reset_layout() -> void:
	_placed=false
	position=_default_position()
	_fit();save_layout()

func _on_visibility_changed()->void:
	if _reveal:_reveal.kill()
	if not visible:
		if _dragging:_dragging=false;drag_changed.emit(false)
		return
	_reflow.call_deferred()
	modulate.a=0.0
	_reveal=create_tween();_reveal.tween_property(self,"modulate:a",1.0,0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
func _exit_tree()->void:
	if _dragging:drag_changed.emit(false)

func _reflow()->void:
	if not is_inside_tree():return
	if not get_tree().process_frame.is_connected(_finish_reflow):get_tree().process_frame.connect(_finish_reflow,CONNECT_ONE_SHOT)
func _finish_reflow()->void:
	if not is_inside_tree() or not visible:return
	if fit_content_height:reset_size()
	if not _placed:position=_default_position()
	_fit()

func _default_position()->Vector2:
	return Vector2(maxf(12,get_viewport_rect().size.x-GSUiScale.extent(self).x-24) if default_position.x<0 else default_position.x,default_position.y)
