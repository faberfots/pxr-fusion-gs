class_name GSLightingSettings
extends Resource
@export var shadows_enabled := false
@export_range(0,1,0.01) var shadow_strength := 0.65
@export_range(0.001,0.2,0.001) var shadow_bias := 0.02
@export_enum("256:256","512:512","1024:1024") var shadow_resolution := 512
