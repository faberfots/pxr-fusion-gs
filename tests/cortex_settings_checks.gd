extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var path:="user://cortex-check-%d/settings.json"%Time.get_ticks_usec()
	var settings:=CortexSettings.new(path)
	check(not FileAccess.file_exists(path),"Cortex startup never persists settings or credentials")
	var profile:=settings.profile("ollama");profile.model="qwen/test:8b";profile.name="Local lab"
	check(settings.update_profile(profile)==OK and settings.select("ollama")==OK,"local model identifiers accept runtime namespaces and quantization tags")
	check(CortexSettings.new(path).active()==profile,"non-secret profile selection round-trips across restart")
	profile.credential_source="session"
	check(CortexCredentials.store(profile,"synthetic-cortex-private-fixture")==OK,"session credential can be entered without a native extension")
	check(settings.update_profile(profile)==OK and not FileAccess.get_file_as_string(path).contains("synthetic-cortex-private-fixture"),"saved settings contain credential references rather than credentials")
	var changed:=profile.duplicate();changed.endpoint="http://127.0.0.1:9090/v1"
	check(CortexCredentials.resolve(changed).is_empty(),"changing the destination cannot reuse a session credential")
	var original:=FileAccess.get_sha256(path);var invalid:=profile.duplicate();invalid["api_key"]="synthetic-cortex-private-fixture"
	check(settings.update_profile(invalid)!=OK and FileAccess.get_sha256(path)==original,"unknown or secret fields are rejected without overwriting valid settings")
	invalid=profile.duplicate();invalid.endpoint="http://example.com/v1"
	check(settings.update_profile(invalid)!=OK,"unencrypted remote API destinations are rejected")
	invalid=settings.profile("openai");invalid.endpoint="https://example.com/v1"
	check(settings.update_profile(invalid)!=OK,"official provider credentials cannot be routed to another origin")
	var policy:=AIAccessPolicy.new()
	check(not policy.allows_connection(profile) and not policy.allows_action(),"new Cortex sessions start with transmission and scene commands disabled")
	policy.local_enabled=true
	check(policy.allows_connection(profile) and not policy.cloud_enabled,"local endpoint transmission does not grant cloud consent")
	CortexCredentials.clear_sessions()
	check(CortexCredentials.resolve(profile).is_empty(),"clearing session credentials removes the in-memory key")
	var tokenizer:=CortexClipTokenizer.new()
	check(tokenizer.initialize(),"pinned CLIP vocabulary and merge table initialize")
	if not tokenizer.error.is_empty():print("TOKENIZER INITIALIZATION: ",tokenizer.error)
	var tokens:=tokenizer.encode("motorcycle")
	check(tokens.size()==32 and tokens[0]==49406 and tokens[1]!=49407 and 49407 in tokens and tokens[31]==0,"SAM3 prompts produce the exact fixed-length CLIP token contract")
	check(tokenizer.encode("Motorcycle")==tokens,"CLIP tokenization normalizes prompt case")
	print("CORTEX SETTINGS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
