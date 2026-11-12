class_name SIConfig
extends Resource
## Public settings are non-secret. Credentials are process-local environment data.
static func get_api_key() -> String:
	var shared := OS.get_environment("GS_AI_API_KEY").strip_edges()
	if not shared.is_empty(): return shared
	var keys := {"openai": "OPENAI_API_KEY", "google": "GEMINI_API_KEY", "anthropic": "ANTHROPIC_API_KEY"}
	return OS.get_environment(keys.get(get_provider(), "")).strip_edges()
static func get_provider() -> String:
	var provider := str(ProjectSettings.get_setting("spatial_intelligence/provider", "openai")).to_lower()
	return {"gemini": "google", "claude": "anthropic"}.get(provider, provider)
static func get_model_name() -> String:
	return str(ProjectSettings.get_setting("spatial_intelligence/model_name", "gpt-4o")).strip_edges()
static func setup_default_settings() -> void:
	# Never persist settings or secrets during application startup.
	pass
