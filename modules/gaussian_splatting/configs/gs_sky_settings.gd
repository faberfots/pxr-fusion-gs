class_name GSSkySettings
extends RefCounted
## Whitelisted serialization and commands. Sky3D remains the sole live state owner.
const BOOLS=["sky3d_enabled","sky_enabled","clouds_enabled","lights_enabled","fog_enabled","enable_game_time","auto_exposure","night_ambient","show_azimuthal_grid","show_equatorial_grid"]
const RANGES={
	"current_time":[0.0,23.99],"minutes_per_day":[-1440.0,1440.0],"update_interval":[0.016,10.0],
	"camera_exposure":[0.0,16.0],"tonemap_exposure":[0.0,16.0],"skydome_energy":[0.0,16.0],
	"cloud_intensity":[0.0,16.0],"sun_energy":[0.0,16.0],"sun_shadow_opacity":[0.0,1.0],
	"sky_contribution":[0.0,1.0],"ambient_energy":[0.0,16.0],
	"auto_exposure_scale":[0.01,16.0],"auto_exposure_min":[0.0,1600.0],"auto_exposure_max":[30.0,64000.0],"auto_exposure_speed":[0.1,64.0],
	"moon_energy":[0.0,16.0],"moon_shadow_opacity":[0.0,1.0],"night_ambient_min":[0.0,1.0],"ambient_tween_time":[0.0,30.0]}
const TIMES={"Morning":8.0,"Daylight":12.0,"Sunset":18.0,"Night":23.0}
static func soft_mesh_lighting(sky:Sky3D,only_defaults:bool=false)->bool:
	if not is_instance_valid(sky):return false
	if only_defaults and (not is_equal_approx(sky.sky_contribution,1.0) or not is_equal_approx(sky.ambient_energy,1.0) or not sky.sky_enabled or not sky.lights_enabled):return false
	# The Sky3D radiance path can leave fully shadowed native materials black.
	# Blend its existing ambient color through the existing live owner instead.
	sky.sky_contribution=0.7;sky.ambient_energy=1.0
	return true
static func node(viewer:Node)->Sky3D:
	return viewer.shadow_light.get_parent() as Sky3D if is_instance_valid(viewer.shadow_light) else null
static func snapshot(sky:Sky3D)->Dictionary:
	if not is_instance_valid(sky):return {}
	var result:Dictionary={}
	for field in BOOLS+RANGES.keys():result[field]=sky.get(field)
	var tod:=sky.get_node_or_null("TimeOfDay") as TimeOfDay
	if tod:
		result.calendar={"year":tod.year,"month":tod.month,"day":tod.day,"latitude":tod.latitude,"longitude":tod.longitude,"utc":tod.utc,"system_sync":tod.system_sync}
	return result
static func number(value:Variant,minimum:float,maximum:float)->bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value>=minimum and value<=maximum
static func valid(settings:Variant)->bool:
	if not settings is Dictionary:return false
	if settings.is_empty():return true
	for field in BOOLS:
		if not settings.get(field) is bool:return false
	for field in RANGES:
		if not number(settings.get(field),RANGES[field][0],RANGES[field][1]):return false
	if settings.auto_exposure_min>settings.auto_exposure_max:return false
	if settings.has("calendar"):
		var date:Variant=settings.calendar
		if not date is Dictionary or not date.get("system_sync") is bool:return false
		for field in ["year","month","day"]:
			var limits:Dictionary={"year":[-9999,9999],"month":[1,12],"day":[1,31]}
			if not number(date.get(field),limits[field][0],limits[field][1]) or date[field]!=floor(date[field]):return false
		var days:=29 if DateTimeUtil.compute_leap_year(int(date.year)) else 28
		if int(date.month)!=2:days=31 if int(date.month) in [1,3,5,7,8,10,12] else 30
		if date.day>days:return false
		if not number(date.get("latitude"),-90,90) or not number(date.get("longitude"),-180,180) or not number(date.get("utc"),-12,14):return false
	return true
static func set_value(sky:Sky3D,field:String,value:Variant)->bool:
	if not is_instance_valid(sky):return false
	if field in BOOLS:
		if not value is bool:return false
	elif RANGES.has(field):
		if not number(value,RANGES[field][0],RANGES[field][1]):return false
		if field=="auto_exposure_min" and value>sky.auto_exposure_max:return false
		if field=="auto_exposure_max" and value<sky.auto_exposure_min:return false
	else:return false
	sky.set(field,value)
	return true
static func apply(sky:Sky3D,settings:Dictionary)->bool:
	if not is_instance_valid(sky) or not valid(settings):return false
	if settings.is_empty():return true
	sky.enable_game_time=false
	sky.sky3d_enabled=settings.sky3d_enabled
	var tod:=sky.get_node_or_null("TimeOfDay") as TimeOfDay
	if tod and settings.has("calendar"):
		# Set day to one before changing month/year to avoid rollover from the old date.
		tod.day=1
		for field in ["year","month","day","latitude","longitude","utc","system_sync"]:tod.set(field,settings.calendar[field])
	for field in RANGES:sky.set(field,settings[field])
	for field in BOOLS:
		if field not in ["sky3d_enabled","enable_game_time","sky_enabled"]:sky.set(field,settings[field])
	sky.sky_enabled=settings.sky_enabled
	sky.enable_game_time=settings.enable_game_time
	return true
static func preset(sky:Sky3D,label:String)->bool:
	if not is_instance_valid(sky) or not TIMES.has(label):return false
	sky.enable_game_time=false
	if sky.tod:sky.tod.system_sync=false
	sky.current_time=TIMES[label]
	return true
