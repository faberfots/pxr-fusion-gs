class_name CortexProviders
extends RefCounted
## Protocol definitions, never credentials or mutable user preferences.
const DEFINITIONS := {
	"openai": {"label":"OpenAI", "endpoint":"https://api.openai.com/v1", "environment":"OPENAI_API_KEY", "protocol":"openai"},
	"anthropic": {"label":"Anthropic", "endpoint":"https://api.anthropic.com/v1", "environment":"ANTHROPIC_API_KEY", "protocol":"anthropic"},
	"google": {"label":"Gemini", "endpoint":"https://generativelanguage.googleapis.com/v1beta", "environment":"GEMINI_API_KEY", "protocol":"google"},
	"ollama": {"label":"Ollama · local endpoint", "endpoint":"http://127.0.0.1:11434/v1", "environment":"", "protocol":"openai"},
	"qwen": {"label":"Qwen · bundled CPU", "endpoint":"http://127.0.0.1:18081/v1", "environment":"", "protocol":"openai"},
	"compatible": {"label":"OpenAI-compatible", "endpoint":"http://127.0.0.1:8080/v1", "environment":"", "protocol":"openai"}
}
static func canonical(provider:String)->String:
	return {"gemini":"google","claude":"anthropic"}.get(provider.to_lower(),provider.to_lower())
static func loopback(endpoint:String)->bool:
	return RegEx.create_from_string("^https?://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]{1,5})?(/|$)").search(endpoint.to_lower())!=null
static func valid_endpoint(provider:String,endpoint:String)->bool:
	if not DEFINITIONS.has(provider) or endpoint.length()>2048 or "@" in endpoint or "?" in endpoint or "#" in endpoint:return false
	if RegEx.create_from_string("[\\s\\x00-\\x1f]").search(endpoint):return false
	if provider in ["openai","anthropic","google","qwen"]:return endpoint==DEFINITIONS[provider].endpoint
	return loopback(endpoint) or RegEx.create_from_string("^https://[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._~%/-]*)?$").search(endpoint)!=null
static func protocol(profile:Dictionary)->String:
	return DEFINITIONS.get(profile.get("provider",""),{}).get("protocol","")
static func profile(provider:String)->Dictionary:
	var definition:Dictionary=DEFINITIONS[provider]
	return {"id":provider,"name":definition.label,"provider":provider,"endpoint":definition.endpoint,"model":"qwen-local" if provider=="qwen" else "","credential_source":"none" if provider in ["ollama","compatible","qwen"] else "environment","environment":definition.environment,"vision":false,"tools":false,"include_image":false,"scope":"visible","max_tokens":256 if provider=="qwen" else 1024,"temperature_enabled":false,"temperature":0.2,"timeout":90.0 if provider=="qwen" else 45.0,"response_limit_mb":2}
