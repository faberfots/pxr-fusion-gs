extends VBoxContainer
## Authored controls bind directly to the existing Sky3D node; no copied live settings.
@export var sky:Sky3D
var controls:Dictionary={}
var _original:Dictionary={}
func _ready()->void:
	_bind.call_deferred()
func _bind()->void:
	%Unavailable.visible=not is_instance_valid(sky)
	%Content.visible=is_instance_valid(sky)
	if not is_instance_valid(sky):return
	_original=GSSkySettings.snapshot(sky)
	_collect(%Content)
	%Preset.item_selected.connect(func(index):
		if index>0:GSSkySettings.preset(sky,%Preset.get_item_text(index))
	)
	%Reset.pressed.connect(func():GSSkySettings.apply(sky,_original))
	%MeshLight.pressed.connect(func():GSSkySettings.soft_mesh_lighting(sky);_sync())
	%Advanced.toggled.connect(func(value):%AdvancedFields.visible=value)
	_sync()
func _collect(parent:Node)->void:
	for child in parent.get_children():
		var field:=str(child.name)
		if field in GSSkySettings.BOOLS and child is BaseButton:
			controls[field]=child
			child.toggled.connect(_change.bind(field))
		elif GSSkySettings.RANGES.has(field) and child is Range:
			controls[field]=child
			child.min_value=GSSkySettings.RANGES[field][0];child.max_value=GSSkySettings.RANGES[field][1]
			child.value_changed.connect(_change.bind(field))
		_collect(child)
func _change(value:Variant,field:String)->void:
	GSSkySettings.set_value(sky,field,value)
	if field=="current_time" and sky.tod:sky.tod.system_sync=false
	_sync()
func _process(_delta:float)->void:
	if is_visible_in_tree() and is_instance_valid(sky) and not controls.is_empty():_sync()
func _sync()->void:
	for field in controls:
		var control:Control=controls[field]
		if control is BaseButton:control.set_pressed_no_signal(sky.get(field))
		else:
			control.set_value_no_signal(sky.get(field))
			var label:=control.get_parent().get_node_or_null("Heading/Value") as Label
			if label:label.text="%.2f" % float(sky.get(field))
	var minutes:=int(round(sky.current_time*60))%1440
	%Clock.text="%02d:%02d" % [minutes/60,minutes%60]
	%State.text=("LIVE · " if sky.enable_game_time else "PAUSED · ")+("DAY" if sky.is_day() else "NIGHT")
	%Preset.select(0)
	if not sky.enable_game_time:
		for index in range(1,%Preset.item_count):
			if is_equal_approx(sky.current_time,GSSkySettings.TIMES[%Preset.get_item_text(index)]):%Preset.select(index)
