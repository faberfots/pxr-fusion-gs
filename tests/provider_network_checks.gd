extends SceneTree
class NetworkClient extends LLMClient:
	var request_timeout := 45.0
	func _make_http_request() -> HTTPRequest:
		var request := super._make_http_request()
		request.timeout = request_timeout
		return request

var received := ""
var error := ""
var calls: Array = []
var failures: Array[String] = []
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func wait_result(client:LLMClient)->void:
	var start := Time.get_ticks_msec()
	while client._is_busy and Time.get_ticks_msec()-start<5000:await process_frame
func run()->void:
	var base := OS.get_cmdline_user_args()[0]
	var client := NetworkClient.new()
	client.policy=AIAccessPolicy.new()
	client.policy.cloud_enabled=true
	root.add_child(client)
	client.response_received.connect(func(text):received=text)
	client.error_occurred.connect(func(text):error=text)
	client.tool_calls_received.connect(func(value):calls=value)
	for provider in ["openai","anthropic","google"]:
		client._provider=provider;client._is_busy=true;received="";error=""
		client._begin_request(base+"/"+provider,PackedStringArray(["Content-Type: application/json"]),{"synthetic_test":true})
		await wait_result(client)
		check(received=="network-ok" and error.is_empty(),provider+" response through actual HTTPRequest transport")
	client._provider="openai"
	for endpoint in ["unauthorized","malformed","oversized","redirect"]:
		error="";received="";client._is_busy=true
		client._begin_request(base+"/"+endpoint,PackedStringArray(),{})
		await wait_result(client)
		check(not error.is_empty() and received.is_empty(),endpoint+" fails truthfully and releases busy state")
	client._is_busy=true;error="";received=""
	client.request_timeout=0.05
	client._begin_request(base+"/slow",PackedStringArray(),{})
	await wait_result(client)
	check(not error.is_empty() and not client._is_busy,"network timeout releases request lifecycle")
	client.request_timeout=45.0
	client._is_busy=true;error="";received=""
	client._begin_request(base+"/slow",PackedStringArray(),{})
	client.cancel()
	client._is_busy=true
	client._begin_request(base+"/openai",PackedStringArray(),{})
	await wait_result(client)
	for i in range(30):await process_frame
	check(received=="network-ok" and error.is_empty(),"cancelled response cannot overwrite the next request")
	client._is_busy=true;error="";received=""
	client._begin_request(base+"/slow",PackedStringArray(),{})
	client.policy.cloud_enabled=false
	await wait_result(client)
	check(received.is_empty() and error=="Cloud consent was withdrawn.","withdrawn consent prevents response delivery")
	client.free()
	print("PROVIDER NETWORK COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
