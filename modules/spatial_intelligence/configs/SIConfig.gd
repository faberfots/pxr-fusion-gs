class_name SIConfig
extends Resource
## Compatibility facade; CortexSettings and CortexCredentials own their separate facts.
static var _settings:CortexSettings
static func settings()->CortexSettings:
	if not _settings:_settings=CortexSettings.new()
	return _settings
static func get_api_key() -> String:
	return CortexCredentials.resolve(settings().active())
static func get_provider() -> String:
	return str(settings().active().provider)
static func get_model_name() -> String:
	return str(settings().active().model)
static func setup_default_settings() -> void:
	# Never persist settings or secrets during application startup.
	pass
