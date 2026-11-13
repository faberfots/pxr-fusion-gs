class_name GSColorAdjustmentPanel
extends GSFloatingPanel
## Edits the existing viewer configuration; presets never own a second live grade.
var viewer:GaussianSplattingViewer
var preset:OptionButton
var sliders:Dictionary={}
var values:Dictionary={}
var tint:ColorPickerButton
var compare:CheckButton
var save_timer:Timer
var _syncing:=false
var _body:VBoxContainer
const LABELS:=["Exposure","Contrast","Saturation","Warmth","Black point","White point","Sharpness"]
func _ready()->void:
	super._ready()
	_body=%Body
	preset=%Preset;tint=%Tint;compare=%Compare;save_timer=%SaveTimer
	for i in range(7):
		var field:String=GSColorSettings.FIELDS[i]
		sliders[field]=get_node("%"+field)
		values[field]=get_node("%"+field+"Value")
		sliders[field].value_changed.connect(_on_value.bind(field))
	preset.item_selected.connect(_on_preset)
	tint.color_changed.connect(_on_tint)
	compare.toggled.connect(_on_compare)
	%Close.pressed.connect(hide_panel)
	%Reset.pressed.connect(func():apply_profile("Natural"))
	save_timer.timeout.connect(_save)
	if not is_instance_valid(viewer):return
	viewer.configuration_applied.connect(func(_settings):_sync())
	get_viewport().size_changed.connect(_place)
	if not viewer.is_node_ready():await viewer.ready
	if not _has_settings():return
	GSColorSettings.load_preferences(viewer.config)
	_sync();_place();hide()
func _has_settings()->bool:
	return is_instance_valid(viewer) and is_instance_valid(viewer.config)
func _place()->void:
	var viewport_size:=get_viewport_rect().size
	var top:=128.0 if viewport_size.y>=400 else 90.0
	if is_instance_valid(_body):size.y=minf(_body.get_combined_minimum_size().y+30,maxf(160,viewport_size.y-top-36))
	if not _placed:position=Vector2(maxf(12,viewport_size.x-size.x-24),top)
	_fit()
func show_panel()->void:
	if not _has_settings():return
	_sync();show();reset_size();_place()
func hide_panel()->void:
	compare.button_pressed=false
	_on_compare(false)
	_save()
	var focus:=get_viewport().gui_get_focus_owner()
	if focus and is_ancestor_of(focus):focus.release_focus()
	hide()
func apply_profile(label:String)->bool:
	if not _has_settings():return false
	var profile:=GSColorSettings.profile(label)
	if profile.is_empty() or not GSColorSettings.apply(viewer.config,profile):return false
	_sync();save_timer.start();return true
func _on_preset(index:int)->void:
	if not _syncing and index>0:apply_profile(preset.get_item_text(index))
func _on_value(value:float,field:String)->void:
	if _syncing or not _has_settings():return
	if GSColorSettings.apply(viewer.config,{field:value}):save_timer.start()
	_sync()
func _on_tint(color:Color)->void:
	if not _syncing and _has_settings() and GSColorSettings.apply(viewer.config,{"post_tint":color}):save_timer.start()
func _on_compare(enabled:bool)->void:
	if is_instance_valid(viewer):viewer.set_color_comparison(enabled)
func _save()->void:
	if _has_settings() and viewer.config.color_settings_edited:
		var result:=GSColorSettings.save_preferences(viewer.config)
		if result!=OK:push_warning("Color preferences could not be saved: "+error_string(result))
func _sync()->void:
	if not _has_settings():return
	_syncing=true
	for field in sliders:
		sliders[field].value=viewer.config.get(field)
		values[field].text="%.2f" % viewer.config.get(field)
	tint.color=viewer.config.post_tint
	preset.select(0)
	var current:=GSColorSettings.snapshot(viewer.config)
	for label in GSColorSettings.PROFILES:
		if current==GSColorSettings.profile(label):
			for index in range(1,preset.item_count):
				if preset.get_item_text(index)==label:preset.select(index)
	_syncing=false
func _exit_tree()->void:
	super._exit_tree()
	_save()
	if is_instance_valid(viewer):viewer.set_color_comparison(false)
