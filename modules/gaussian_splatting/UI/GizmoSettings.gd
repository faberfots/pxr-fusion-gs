class_name GSGizmoSettings
extends VBoxContainer
## Scene-authored controls project the controller's shared local preferences.
var preferences:GSGizmoPreferences
var _syncing:=false
const NUMBERS:={"Size":"size","Opacity":"opacity","MoveSnap":"translate_snap","RotateSnap":"rotate_snap","ScaleSnap":"scale_snap"}
const TOGGLES:={"Bounds":"show_bounds","Guides":"show_axes","Planes":"show_planes","RotationLine":"show_rotation_line","RotationArc":"show_rotation_arc"}
const COLORS:={"ColorX":"color_x","ColorY":"color_y","ColorZ":"color_z","BoundsColor":"bounds_color"}
func bind(owner_preferences:GSGizmoPreferences)->void:
	preferences=owner_preferences
	for label in GSGizmoPreferences.PRESETS:%Preset.add_item(label)
	%Preset.add_item("Custom");%Preset.set_item_disabled(3,true)
	%Preset.item_selected.connect(func(index):preferences.apply_preset(%Preset.get_item_text(index)))
	%Reset.pressed.connect(func():preferences.apply_preset("Godot Classic"))
	for node in NUMBERS:
		get_node("%"+node).value_changed.connect(func(value):
			if not _syncing:preferences.set_value(NUMBERS[node],value)
		)
	for node in TOGGLES:
		get_node("%"+node).toggled.connect(func(value):
			if not _syncing:preferences.set_value(TOGGLES[node],value)
		)
	for node in COLORS:
		get_node("%"+node).color_changed.connect(func(value):
			if not _syncing:preferences.set_value(COLORS[node],value)
		)
	for operation in ["Move","Rotation","Scale"]:
		for axis in range(3):
			var key:String=operation.to_lower()+"_axes";var bit:int=1<<axis
			get_node("%"+operation+["X","Y","Z"][axis]).toggled.connect(func(enabled):
				if not _syncing:preferences.set_value(key,(int(preferences.get_value(key))|bit) if enabled else (int(preferences.get_value(key))&~bit))
			)
	preferences.changed.connect(_sync);_sync()
func _sync()->void:
	_syncing=true
	for node in NUMBERS:get_node("%"+node).value=preferences.get_value(NUMBERS[node])
	for node in TOGGLES:get_node("%"+node).set_pressed_no_signal(preferences.get_value(TOGGLES[node]))
	for node in COLORS:get_node("%"+node).color=preferences.get_value(COLORS[node])
	for operation in ["Move","Rotation","Scale"]:
		for axis in range(3):get_node("%"+operation+["X","Y","Z"][axis]).set_pressed_no_signal((int(preferences.get_value(operation.to_lower()+"_axes"))&(1<<axis))!=0)
	%Preset.select(["Godot Classic","Minimal","High Visibility","Custom"].find(preferences.preset_name()))
	%Saved.text="Saved on this computer · Ctrl snaps; Shift refines." if preferences.last_save_error==OK else "Preferences could not be saved: "+error_string(preferences.last_save_error)
	_syncing=false
