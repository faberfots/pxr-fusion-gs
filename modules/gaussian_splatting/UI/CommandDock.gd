class_name GSCommandDock
extends GSFloatingPanel
var expanded:=true
var _launcher_held:=false
var _launcher_moved:=false
var _launcher_start:=Vector2.ZERO
var _launcher_position:=Vector2.ZERO
const DRAG_THRESHOLD:=6.0
func _ready()->void:
	super._ready()
	%Toggle.pressed.connect(func():set_expanded(not expanded))
	%Toggle.gui_input.connect(_on_launcher_input)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()
	$Body/Actions/Orbit.pivot_offset=Vector2(190,190)
	create_tween().set_loops().tween_property($Body/Actions/Orbit,"rotation",TAU,90.0).from(0.0)
func set_expanded(value:bool,persist:bool=true)->void:
	var old_right:=position.x+GSUiScale.extent(self).x
	expanded=value
	%Actions.visible=value;%Population.visible=value
	%Toggle.tooltip_text=("Collapse" if value else "Open")+" command orbit · hold left click and drag to move"
	$Body.custom_minimum_size=Vector2(380,400) if value else Vector2(96,100)
	%Toggle.position=Vector2(126,146) if value else Vector2.ZERO
	%Toggle.size=Vector2(128,128) if value else Vector2(96,96)
	reset_size();position.x=old_right-GSUiScale.extent(self).x;_fit()
	if persist:
		var file:=ConfigFile.new();file.load(LAYOUT_PATH);file.set_value(layout_id,"expanded",value);file.save(LAYOUT_PATH)
		save_layout()
func _load_layout()->void:
	var file:=ConfigFile.new()
	var value:=true
	if file.load(LAYOUT_PATH)==OK and file.has_section_key(layout_id,"expanded"):value=bool(file.get_value(layout_id,"expanded"))
	# Establish the rig's dimensions before restoring its saved top-left position.
	set_expanded(value,false)
	super._load_layout()
	_layout()
func _layout()->void:
	reset_size()
	if not _placed:position=Vector2(maxf(12,get_viewport_rect().size.x-GSUiScale.extent(self).x-24),24)
	_fit()
func update_population(models:int,splats:int)->void:
	%Population.text="%02d MODELS   /   %.2f M GAUSSIANS" % [models,float(splats)/1000000.0]
func reset_layout()->void:
	_placed=false;_layout();save_layout()

func _on_launcher_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_launcher_held=true;_launcher_moved=false
		_launcher_start=%Toggle.get_global_transform()*event.position
		_launcher_position=global_position
		%Toggle.grab_focus();drag_changed.emit(true)
		%Toggle.accept_event()
func _input(event:InputEvent)->void:
	super._input(event)
	if not _launcher_held:return
	if event is InputEventMouseMotion:
		var point:Vector2=get_canvas_transform().affine_inverse()*event.position
		if point.distance_to(_launcher_start)>=DRAG_THRESHOLD:_launcher_moved=true
		if _launcher_moved:
			global_position=_launcher_position+point-_launcher_start
			_fit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		var click:=not _launcher_moved
		_finish_launcher_drag()
		if click:set_expanded(not expanded)
		get_viewport().set_input_as_handled()
func _finish_launcher_drag()->void:
	if not _launcher_held:return
	_launcher_held=false
	if _launcher_moved:save_layout()
	drag_changed.emit(false)
func _notification(what:int)->void:
	super._notification(what)
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:_finish_launcher_drag()
func _exit_tree()->void:
	_finish_launcher_drag()
	super._exit_tree()
