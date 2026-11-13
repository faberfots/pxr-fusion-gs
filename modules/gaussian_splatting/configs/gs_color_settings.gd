class_name GSColorSettings
extends RefCounted
## Presets and preference codec. The viewer configuration owns the live values.
const PATH := "user://gs-color-settings.cfg"
const FIELDS := GaussianSplattingConfig.COLOR_FIELDS
const RANGES := [Vector2(0,5),Vector2(0.5,2),Vector2(0,2),Vector2(-1,1),Vector2(0,0.5),Vector2(0.5,2),Vector2(0,1)]
const PROFILES := {
	"Natural": [1.0,1.0,1.0,0.0,0.0,1.0,0.0],
	"Warm daylight": [1.0,1.04,1.05,0.3,0.0,1.0,0.15],
	"Soft": [1.05,0.92,0.92,0.0,0.0,1.1,0.0],
	"Vivid": [1.0,1.12,1.22,0.05,0.015,1.0,0.25],
	"Architectural": [1.0,1.08,0.88,0.0,0.01,1.05,0.3]
}
static func snapshot(settings:GaussianSplattingConfig)->Dictionary:
	var result:Dictionary={}
	for field in FIELDS:result[field]=settings.get(field)
	return result
static func profile(label:String)->Dictionary:
	if not PROFILES.has(label):return {}
	var result:Dictionary={}
	for i in range(7):result[FIELDS[i]]=PROFILES[label][i]
	result.post_tint=Color.WHITE
	return result
static func apply(settings:GaussianSplattingConfig,values:Dictionary)->bool:
	for i in range(FIELDS.size()):
		if not values.has(FIELDS[i]):continue
		var value:Variant=values[FIELDS[i]]
		if i==7:
			if not value is Color:return false
		else:
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT]:return false
			if not is_finite(float(value)) or float(value)<RANGES[i].x or float(value)>RANGES[i].y:return false
	var trial:=settings.duplicate(true) as GaussianSplattingConfig
	for field in FIELDS:
		if values.has(field):trial.set(field,values[field])
	if not trial.validate():return false
	var preset:=settings.current_preset
	settings._applying_preset=true
	for field in FIELDS:settings.set(field,trial.get(field))
	settings._applying_preset=false
	settings.current_preset=preset
	settings.color_settings_edited=true
	settings.is_dirty=true
	settings.config_changed.emit()
	return true
static func save_preferences(settings:GaussianSplattingConfig,path:String=PATH)->Error:
	var file:=ConfigFile.new()
	for field in FIELDS:file.set_value("color",field,settings.get(field))
	return file.save(path)
static func load_preferences(settings:GaussianSplattingConfig,path:String=PATH)->bool:
	var file:=ConfigFile.new()
	if file.load(path)!=OK:return false
	var values:Dictionary={}
	for field in FIELDS:values[field]=file.get_value("color",field,settings.get(field))
	return apply(settings,values)
