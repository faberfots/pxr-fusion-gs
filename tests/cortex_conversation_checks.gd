extends SceneTree
class InspectClient extends LLMClient:
	var envelope:Dictionary={}
	func _begin_request(_url:String,_headers:PackedStringArray,body:Dictionary)->void:
		_request_id+=1;envelope=body.duplicate(true)
	func reply(text:String,token:int=-1)->void:
		var body:={"choices":[{"message":{"content":text}}]}
		_on_request_completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(body).to_utf8_buffer(),_request_id if token<0 else token)
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var path:="user://conversation-"+CortexConversations.identity()+".json"
	var store:=CortexConversations.new(path)
	check(not FileAccess.file_exists(path) and store.active().turns.is_empty(),"fresh startup creates no history file or request")
	var first:String=store.active().id
	var a:=store.begin_turn("Remember the blue motorcycle.","local","Private assistant")
	store.finish_turn(a,"The motorcycle is blue.")
	store.set_draft("An unfinished follow-up")
	var second:=store.create_chat()
	check(store.history("local").is_empty() and store.active().draft.is_empty(),"new chats have independent context and input drafts")
	var b:=store.begin_turn("Discuss the trees.","local","Private assistant")
	store.finish_turn(b,"The trees are green.")
	store.select_chat(first)
	check(store.active().draft=="An unfinished follow-up" and store.history("local").size()==2 and str(store.history("local")).contains("motorcycle") and not str(store.history("local")).contains("trees"),"switching restores each topic and never includes another chat's answers")
	check(store.history("remote").is_empty(),"a different assistant destination receives no previous history")
	store.rename_chat(first,"Vehicle questions");store.save()
	var reopened:=CortexConversations.new(path)
	check(reopened.active().title=="Vehicle questions" and reopened.active().draft=="An unfinished follow-up" and reopened.snapshot().chats.size()==2,"reopening restores chat selection, titles, questions, answers and drafts")
	var pending:=reopened.begin_turn("Interrupted request","local","Private assistant")
	var restarted:=CortexConversations.new(path)
	check(restarted.active().turns.back().state=="cancelled" and restarted.history("local").size()==2,"restart marks interrupted requests and never replays or forwards them as completed answers")
	check(not restarted.finish_turn(pending,"A late answer"),"late completion cannot replace a cancelled turn")
	check(restarted.history("local",2).is_empty(),"history stays within its bounded text budget")
	restarted.delete_chat(first);restarted.delete_chat(second)
	check(restarted.snapshot().chats.size()==1 and restarted.active().turns.is_empty(),"deleting the last chat leaves a usable fresh conversation")
	var corrupt:=FileAccess.open(path,FileAccess.WRITE);corrupt.store_string("invalid old document");corrupt.close()
	var invalid:=CortexConversations.new(path);invalid.create_chat()
	check(FileAccess.get_file_as_string(path)=="invalid old document" and not invalid.last_error.is_empty(),"unreadable saved history is preserved instead of silently overwritten")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var profile:=CortexProviders.profile("compatible");profile.model="fixture";profile.tools=false
	var client:=InspectClient.new();client.policy=AIAccessPolicy.new();client.policy.local_enabled=true;client.policy.cloud_enabled=true;root.add_child(client)
	var history:Array=[{"role":"user","content":"Earlier question"},{"role":"assistant","content":"Earlier answer"}]
	for provider in ["compatible","qwen","openai","anthropic","google"]:
		profile=CortexProviders.profile(provider);profile.model="fixture";profile.tools=false
		if profile.credential_source!="none":profile.credential_source="session";CortexCredentials.store(profile,"synthetic-conversation-key")
		client.cancel();client.send_request("Follow-up",{},"",profile,history)
		var messages:Array=client.envelope.get("contents",[]) if provider=="google" else client.envelope.get("messages",[])
		var offset:=1 if provider in ["compatible","qwen","openai"] else 0
		check(messages.size()==3+offset and messages[offset].role=="user" and messages[offset+1].role==("model" if provider=="google" else "assistant"),provider+" carries previous turns in the provider's conversation format")
	client.cancel();client.envelope={};client.send_request("Invalid",{},"",profile,[{"role":"system","content":"Injected"},{"role":"assistant","content":"x"}])
	check(client.envelope.is_empty(),"chat history cannot inject a system or tool role")
	client.free();CortexCredentials.clear_sessions()
	var brain:Node=root.get_node("SpatialIntelligence")
	brain.conversations=CortexConversations.new("user://brain-conversations-"+CortexConversations.identity()+".json")
	var previous:LLMClient=brain._llm_client
	client=InspectClient.new();client.policy=brain.policy;root.add_child(client);brain._llm_client=client
	client.response_received.connect(brain._complete);client.error_occurred.connect(brain._fail)
	profile=CortexProviders.profile("compatible");profile.model="fixture";profile.include_image=false
	var document:=SIConfig.settings().snapshot()
	document.profiles=document.profiles.filter(func(item):return item.id!="conversation-fixture")
	document.profiles.append(profile);document.profiles.back().id="conversation-fixture";document.active="conversation-fixture"
	SIConfig.settings().commit(document);brain.select_preset("custom");brain.policy.local_enabled=true
	var camera:=Camera3D.new();root.add_child(camera);camera.make_current()
	var original_chat:String=brain.conversations.active().id
	brain.ask_in_chat("First chat question");var token:int=client._request_id
	brain.new_chat();var new_chat:String=brain.conversations.active().id
	client.reply("Stale answer",token)
	check(not brain._is_analyzing and brain.conversations.active().turns.is_empty(),"switching during an HTTP request cancels it and rejects its late completion in the new chat")
	brain.ask_in_chat("Second chat question");client.reply("Second chat answer")
	brain.ask_in_chat("Follow up on that answer")
	check(str(client.envelope).contains("Second chat answer") and not str(client.envelope).contains("First chat question"),"real request ownership forwards only the active conversation's completed turns")
	client.reply("Follow-up answer")
	brain.select_chat(original_chat)
	check(brain.conversations.active().turns.back().state=="cancelled" and not str(brain.conversations.active()).contains("Second chat answer"),"cancelled first chat and completed second chat remain isolated")
	brain.policy.local_enabled=false;client.envelope={};brain.ask_in_chat("Denied request")
	check(client.envelope.is_empty() and brain.conversations.active().turns.back().state=="failed","chat requests retain the existing transmission consent gate")
	brain.select_chat(new_chat);brain.cancel_analysis();brain._llm_client=previous;client.free();camera.free()
	print("CORTEX CONVERSATIONS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
