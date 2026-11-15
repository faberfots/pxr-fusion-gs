extends SceneTree
class InspectClient extends LLMClient:
	var envelope:Dictionary={}
	func _begin_request(url:String,headers:PackedStringArray,body:Dictionary)->void:
		envelope={"url":url,"headers":headers,"body":body.duplicate(true)};_is_busy=false
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var client:=InspectClient.new();client.policy=AIAccessPolicy.new();client.policy.cloud_enabled=true;client.policy.local_enabled=true;root.add_child(client)
	for provider in ["openai","anthropic","google","ollama","compatible","qwen"]:
		var profile:=CortexProviders.profile(provider);profile.model="fixture-model";profile.max_tokens=37
		if profile.credential_source!="none":profile.credential_source="session";CortexCredentials.store(profile,"synthetic-provider-credential")
		client.envelope={};client.send_request("fixture",{"visible_objects":[]},"",profile)
		var body:Dictionary=client.envelope.get("body",{})
		check(not body.is_empty() and client.envelope.url.begins_with(profile.endpoint),provider+" constructs a request only for the configured origin")
		if body.is_empty():continue
		var tokens:int=body.get("generationConfig",{}).get("maxOutputTokens",0) if provider=="google" else body.get("max_completion_tokens" if provider=="openai" else "max_tokens",0)
		check(tokens==37 and not body.has("temperature"),provider+" preserves explicit output limits and omits optional temperature")
		if provider=="qwen":check(body.chat_template_kwargs.enable_thinking==false,"bundled Qwen disables hidden reasoning to keep bounded response latency")
		if profile.credential_source=="none":check(not str(client.envelope.headers).contains("Authorization"),provider+" sends no stale cloud Authorization header")
	var profile:=CortexProviders.profile("compatible");profile.model="fixture";profile.vision=false
	client.envelope={};client.send_request("fixture",{},"synthetic-image",profile)
	check(client.envelope.is_empty(),"image transmission is rejected when the configured model has no vision capability")
	client.policy.role=AIAccessPolicy.Role.ANALYST;client.policy.actions_enabled=true;profile.tools=true
	client.send_request("fixture",{},"",profile)
	check(client.envelope.body.tools.is_empty(),"analyst role cannot advertise scene commands even when a profile declares tools")
	CortexCredentials.clear_sessions();client.free()
	print("CORTEX TRANSPORT COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
