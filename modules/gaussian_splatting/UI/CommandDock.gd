class_name GSCommandDock
extends GSFloatingPanel
var expanded:=true
func _ready()->void:
	super._ready()
	%Toggle.pressed.connect(func():set_expanded(not expanded))
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()
	$Body/Actions/Orbit.pivot_offset=Vector2(190,190)
	create_tween().set_loops().tween_property($Body/Actions/Orbit,"rotation",TAU,90.0).from(0.0)
func set_expanded(value:bool)->void:
	var old_right:=position.x+size.x
	expanded=value
	%Actions.visible=value;%Brand.visible=value;%Population.visible=value
	%Toggle.tooltip_text="Collapse command orbit" if value else "Open command orbit · drag above to move"
	$Body.custom_minimum_size=Vector2(380,400) if value else Vector2(96,100)
	%Toggle.position=Vector2(126,146) if value else Vector2.ZERO
	%Toggle.size=Vector2(128,128) if value else Vector2(96,96)
	$Body/Header.position=Vector2(38,0) if value else Vector2(0,-12)
	$Body/Header.size=Vector2(304,26) if value else Vector2(96,16)
	reset_size();position.x=old_right-size.x;_fit()
	var file:=ConfigFile.new();file.load(LAYOUT_PATH);file.set_value(layout_id,"expanded",value);file.save(LAYOUT_PATH)
func _load_layout()->void:
	super._load_layout()
	var file:=ConfigFile.new()
	if file.load(LAYOUT_PATH)==OK:set_expanded(bool(file.get_value(layout_id,"expanded",true)))
	_layout()
func _layout()->void:
	reset_size()
	if not _placed:position=Vector2(maxf(12,get_viewport_rect().size.x-size.x-24),24)
	_fit()
func update_population(models:int,splats:int)->void:
	%Population.text="%02d MODELS   /   %.2f M GAUSSIANS" % [models,float(splats)/1000000.0]
func reset_layout()->void:
	_placed=false;_layout();save_layout()
