class_name GSGizmoPreferences
extends RefCounted
## One local preference owner. Scene transforms and permissions remain viewer-owned.
signal changed
const PATH := "user://gizmo-preferences.cfg"
const DEFAULTS := {
	"size":80.0,"opacity":0.9,"color_x":Color(0.96,0.20,0.32),
	"color_y":Color(0.53,0.84,0.01),"color_z":Color(0.16,0.55,0.96),
	"bounds_color":Color(1,0.5,0),"show_bounds":false,"show_axes":false,
	"show_rotation_line":true,"show_rotation_arc":true,"show_planes":true,
	"translate_snap":1.0,"rotate_snap":15.0,"scale_snap":0.25,
	"move_axes":7,"rotation_axes":7,"scale_axes":7}
const PRESETS := {"Godot Classic":{},"Minimal":{"size":65.0,"opacity":0.75,"show_planes":false,"show_rotation_line":false,"show_rotation_arc":false},
	"High Visibility":{"size":110.0,"opacity":1.0,"show_bounds":true,"color_y":Color(0.6,1,0.1),"color_z":Color(0.2,0.7,1)}}
const LIMITS := {"size":Vector2(30,200),"opacity":Vector2(0.1,1),"translate_snap":Vector2(0.001,10),"rotate_snap":Vector2(0.1,180),"scale_snap":Vector2(0.001,1)}
var values:Dictionary=DEFAULTS.duplicate(true)
var revision:=0
var last_save_error:=OK
func get_value(key:String)->Variant:return values.get(key)
func _validated(key:String,value:Variant)->Variant:
	var fallback:Variant=DEFAULTS[key]
	if LIMITS.has(key):
		if not (value is float or value is int) or not is_finite(float(value)):return fallback
		return clampf(float(value),LIMITS[key].x,LIMITS[key].y)
	if fallback is Color:
		if not value is Color or not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b) or not is_finite(value.a):return fallback
		return Color(clampf(value.r,0,1),clampf(value.g,0,1),clampf(value.b,0,1),1)
	if fallback is bool:return value if value is bool else fallback
	if fallback is int:return clampi(value,0,7) if value is int else fallback
	return fallback
func set_value(key:String,value:Variant,persist:bool=true)->void:
	if not DEFAULTS.has(key):return
	var valid:Variant=_validated(key,value)
	if values[key]==valid:return
	values[key]=valid;_publish(persist)
func _publish(persist:bool)->void:
	revision+=1
	if persist:last_save_error=save_preferences()
	changed.emit()
func apply_preset(label:String,persist:bool=true)->void:
	if not PRESETS.has(label):return
	values=DEFAULTS.duplicate(true);values.merge(PRESETS[label],true);_publish(persist)
func preset_name()->String:
	for label in PRESETS:
		var expected:Dictionary=DEFAULTS.duplicate(true);expected.merge(PRESETS[label],true)
		if values==expected:return label
	return "Custom"
func load_preferences(path:String=PATH)->void:
	values=DEFAULTS.duplicate(true)
	var config:=ConfigFile.new()
	if config.load(path)==OK:
		for key in DEFAULTS:
			values[key]=_validated(key,config.get_value("gizmo",key,DEFAULTS[key]))
	_publish(false)
func save_preferences(path:String=PATH)->Error:
	var config:=ConfigFile.new()
	for key in values:config.set_value("gizmo",key,values[key])
	return config.save(path)
