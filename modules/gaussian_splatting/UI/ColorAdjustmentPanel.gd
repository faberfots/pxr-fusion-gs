class_name GSColorAdjustmentPanel
extends PanelContainer
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
	name="ColorAdjustmentPanel"
	custom_minimum_size=Vector2(310,0)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("18222f")
	style.border_color=Color("35465b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left=18;style.content_margin_right=18
	style.content_margin_top=14;style.content_margin_bottom=16
	add_theme_stylebox_override("panel",style)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	var body:=VBoxContainer.new();_body=body;body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",8);scroll.add_child(body)
	var header:=HBoxContainer.new();body.add_child(header)
	var title:=Label.new();title.text="Color & image";title.add_theme_font_size_override("font_size",19);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var close:=Button.new();close.text="×";close.tooltip_text="Close color panel";close.pressed.connect(hide_panel);header.add_child(close)
	var description:=Label.new();description.text="Adjust splat colors. Keep the source intact.";description.add_theme_font_size_override("font_size",12);body.add_child(description)
	preset=OptionButton.new();preset.add_item("Custom")
	for label in GSColorSettings.PROFILES:preset.add_item(label)
	preset.item_selected.connect(_on_preset);body.add_child(preset)
	for i in range(7):
		var field:String=GSColorSettings.FIELDS[i]
		var row:=HBoxContainer.new();body.add_child(row)
		var label:=Label.new();label.text=LABELS[i];label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
		var number:=Label.new();number.custom_minimum_size.x=48;number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;row.add_child(number);values[field]=number
		var slider:=HSlider.new();slider.min_value=GSColorSettings.RANGES[i].x;slider.max_value=GSColorSettings.RANGES[i].y;slider.step=0.01;slider.custom_minimum_size.y=16
		slider.value_changed.connect(_on_value.bind(field));sliders[field]=slider;body.add_child(slider)
	var tint_row:=HBoxContainer.new();body.add_child(tint_row)
	var tint_label:=Label.new();tint_label.text="Color tint";tint_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;tint_row.add_child(tint_label)
	tint=ColorPickerButton.new();tint.edit_alpha=false;tint.custom_minimum_size=Vector2(80,24);tint.color_changed.connect(_on_tint);tint_row.add_child(tint)
	compare=CheckButton.new();compare.text="Compare original";compare.toggled.connect(_on_compare);body.add_child(compare)
	var footer:=HBoxContainer.new();body.add_child(footer)
	var reset:=Button.new();reset.text="Reset to Natural";reset.size_flags_horizontal=Control.SIZE_EXPAND_FILL;reset.pressed.connect(func():apply_profile("Natural"));footer.add_child(reset)
	var note:=Label.new();note.text="Saved automatically · independent of quality";note.add_theme_font_size_override("font_size",11);body.add_child(note)
	save_timer=Timer.new();save_timer.one_shot=true;save_timer.wait_time=0.4;save_timer.timeout.connect(_save);add_child(save_timer)
	GSColorSettings.load_preferences(viewer.config)
	viewer.configuration_applied.connect(func(_settings):_sync())
	get_viewport().size_changed.connect(_place)
	_sync();_place();hide()
func _place()->void:
	var viewport_size:=get_viewport_rect().size
	var top:=165.0 if viewport_size.y>=400 else 90.0
	if is_instance_valid(_body):size.y=minf(_body.get_combined_minimum_size().y+30,maxf(160,viewport_size.y-top-36))
	position=Vector2(maxf(10,viewport_size.x-size.x-18),top)
func show_panel()->void:
	_sync();show();reset_size();_place()
func hide_panel()->void:
	compare.button_pressed=false
	_on_compare(false)
	_save()
	var focus:=get_viewport().gui_get_focus_owner()
	if focus and is_ancestor_of(focus):focus.release_focus()
	hide()
func apply_profile(label:String)->bool:
	var profile:=GSColorSettings.profile(label)
	if profile.is_empty() or not GSColorSettings.apply(viewer.config,profile):return false
	_sync();save_timer.start();return true
func _on_preset(index:int)->void:
	if not _syncing and index>0:apply_profile(preset.get_item_text(index))
func _on_value(value:float,field:String)->void:
	if _syncing:return
	if GSColorSettings.apply(viewer.config,{field:value}):save_timer.start()
	_sync()
func _on_tint(color:Color)->void:
	if not _syncing and GSColorSettings.apply(viewer.config,{"post_tint":color}):save_timer.start()
func _on_compare(enabled:bool)->void:
	if is_instance_valid(viewer):viewer.set_color_comparison(enabled)
func _save()->void:
	if is_instance_valid(viewer) and viewer.config.color_settings_edited:
		var result:=GSColorSettings.save_preferences(viewer.config)
		if result!=OK:push_warning("Color preferences could not be saved: "+error_string(result))
func _sync()->void:
	if not is_instance_valid(viewer):return
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
	_save()
	if is_instance_valid(viewer):viewer.set_color_comparison(false)
