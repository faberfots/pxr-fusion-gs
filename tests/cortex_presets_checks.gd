extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var path:="user://preset-check-%d/settings.json"%Time.get_ticks_usec()
	var settings:=CortexSettings.new(path)
	check(settings.experience().preset=="pick" and not FileAccess.file_exists(path) and not FileAccess.file_exists(settings.experience_path()),"fresh Cortex offers a useful local default without writing preferences or starting a model")
	var profile:=settings.profile("compatible");profile.model="user-custom-model";profile.name="My saved assistant";profile.tools=true
	settings.update_profile(profile);settings.select(profile.id)
	var original:=settings.snapshot();var digest:=FileAccess.get_sha256(path)
	check(settings.update_experience("find",true)==OK and settings.vision_request_settings().engine=="sam3" and settings.vision_request_settings().sam3_directory=="bundle://sam3","description preset supplies the portable SAM3 configuration without manual paths")
	check(settings.snapshot()==original and FileAccess.get_sha256(path)==digest,"presets preserve saved provider, credentials references and advanced model settings byte for byte")
	settings.update_experience("scene",false)
	var request:=settings.analysis_profile()
	check(request.provider=="qwen" and request.endpoint=="http://127.0.0.1:18081/v1" and request.credential_source=="none" and not request.include_image and not request.tools and request.scope=="visible","private scene preset derives a local read-only request without copying a cloud credential")
	settings.update_experience("selection",false)
	check(settings.analysis_profile().scope=="selected","selected-model preset limits its context to the selected models")
	var reopened:=CortexSettings.new(path)
	check(reopened.experience().preset=="selection" and reopened.snapshot()==original,"goal selection survives reopening while legacy settings stay compatible")
	settings.update_experience("connected",false)
	check(settings.analysis_profile().id==profile.id and not settings.analysis_profile().tools and settings.active().tools,"connected-assistant preset uses the chosen destination and keeps guided requests read-only")
	settings.update_experience("custom",false)
	check(settings.analysis_profile()==settings.active() and settings.vision_request_settings()==settings.segmentation(),"Advanced restores the original settings and capabilities without reconstructing them")
	var prefs:=settings.experience()
	check(settings.update_experience("unknown-preset",false)!=OK and settings.experience()==prefs,"invalid presets cannot replace working preferences")
	for id in CortexPresets.ORDER:
		var item:=CortexPresets.definition(id)
		check(not item.summary.is_empty() and not item.steps.is_empty() and not item.privacy.is_empty() and not item.limit.is_empty(),id+" has plain-language purpose, steps, privacy and capability limits")
	var brain:Node=root.get_node("SpatialIntelligence")
	var saved:=SIConfig.settings().experience();var before:=SIConfig.settings().snapshot()
	brain.policy.configuration_enabled=false
	check(brain.select_preset("scene")==ERR_UNAUTHORIZED and SIConfig.settings().experience()==saved,"managed roles cannot switch configuration through a preset")
	brain.policy.configuration_enabled=true;brain.policy.cloud_enabled=false;brain.policy.local_enabled=false;brain.policy.actions_enabled=false
	brain.select_preset("scene")
	check(not brain.policy.cloud_enabled and not brain.policy.local_enabled and not brain.policy.allows_action() and not brain.local_runtime.is_running() and not brain.segmentation.is_processing(),"selecting a private preset grants no consent, scene actions, model startup or background inference")
	brain.select_preset(saved.preset)
	check(SIConfig.settings().snapshot()==before,"guided use leaves the original connection settings intact")
	print("CORTEX PRESETS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
