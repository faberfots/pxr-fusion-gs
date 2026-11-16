class_name CortexConversations
extends RefCounted
## Owns local text conversations. Credentials, captures, scene payloads and permissions live elsewhere.
signal changed
var storage_path:String
var last_error:=""
var _load_failed:=false
var _document:Dictionary={"version":1,"active":"","chats":[]}

func _init(path:String="user://cortex/conversations.json")->void:
	storage_path=path
	if FileAccess.file_exists(path):_load()
	if _document.chats.is_empty():_new_chat()

static func identity()->String:return Crypto.new().generate_random_bytes(16).hex_encode()
static func binding(profile:Dictionary,preset:String)->String:
	# Changing destination, scope or capabilities never forwards the old destination's history.
	return JSON.stringify([profile.get("id"),profile.get("endpoint"),profile.get("model"),profile.get("scope"),profile.get("include_image"),profile.get("tools"),preset]).sha256_text()
func snapshot()->Dictionary:return _document.duplicate(true)
func active()->Dictionary:
	for chat in _document.chats:
		if chat.id==_document.active:return chat.duplicate(true)
	return {}
func _new_chat()->String:
	var id:=identity()
	_document.chats.append({"id":id,"title":"New chat","renamed":false,"draft":"","turns":[]})
	_document.active=id
	return id
func create_chat()->String:
	var id:=_new_chat();_save();changed.emit();return id
func select_chat(id:String)->Error:
	for chat in _document.chats:
		if chat.id==id:_document.active=id;_save();changed.emit();return OK
	return ERR_DOES_NOT_EXIST
func rename_chat(id:String,title:String)->Error:
	title=title.strip_edges()
	if title.is_empty() or title.length()>100:return ERR_INVALID_PARAMETER
	for chat in _document.chats:
		if chat.id==id:chat.title=title;chat.renamed=true;_save();changed.emit();return OK
	return ERR_DOES_NOT_EXIST
func delete_chat(id:String)->Error:
	for index in range(_document.chats.size()):
		if _document.chats[index].id!=id:continue
		_document.chats.remove_at(index)
		if _document.chats.is_empty():_new_chat()
		elif _document.active==id:_document.active=_document.chats[mini(index,_document.chats.size()-1)].id
		_save();changed.emit();return OK
	return ERR_DOES_NOT_EXIST
func set_draft(text:String)->void:
	for chat in _document.chats:
		if chat.id==_document.active:chat.draft=text.left(16000);return
func save()->Error:return _save()
func begin_turn(question:String,key:String,assistant:String)->Dictionary:
	question=question.strip_edges()
	if question.is_empty() or question.length()>16000:return {}
	for chat in _document.chats:
		if chat.id!=_document.active:continue
		var turn:={"id":identity(),"question":question,"answer":"","state":"pending","notice":"","binding":key,"assistant":assistant.left(200)}
		chat.turns.append(turn);chat.draft=""
		if not chat.renamed and chat.turns.size()==1:chat.title=question.replace("\n"," ").left(60)
		_save();changed.emit();return {"chat":chat.id,"turn":turn.id}
	return {}
func finish_turn(ticket:Dictionary,text:String,state:String="complete")->bool:
	if state not in ["complete","failed","cancelled"]:return false
	for chat in _document.chats:
		if chat.id!=ticket.get("chat"):continue
		for turn in chat.turns:
			if turn.id!=ticket.get("turn") or turn.state!="pending":continue
			turn.state=state
			if state=="complete":turn.answer=text
			else:turn.notice=text
			_save();changed.emit();return true
	return false
func history(key:String,max_characters:int=12000)->Array:
	var turns:Array=active().get("turns",[]);var pairs:Array=[];var count:=0
	for index in range(turns.size()-1,-1,-1):
		var turn:Dictionary=turns[index]
		if turn.binding!=key:break
		if turn.state!="complete":continue
		var amount:int=turn.question.length()+turn.answer.length()
		if count+amount>max_characters or pairs.size()>=6:break
		count+=amount;pairs.push_front(turn)
	var result:Array=[]
	for turn in pairs:
		result.append({"role":"user","content":turn.question})
		result.append({"role":"assistant","content":turn.answer})
	return result
func _save()->Error:
	if _load_failed:last_error="Saved chats could not be read. They were preserved; new changes are in memory only.";return ERR_FILE_CORRUPT
	var folder:=ProjectSettings.globalize_path(storage_path).get_base_dir()
	var error:=DirAccess.make_dir_recursive_absolute(folder)
	if error!=OK:last_error="Chats are in memory; their folder could not be created.";return error
	var temporary:=storage_path+"-"+identity()+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if not file:last_error="Chats are in memory; the saved file could not be updated.";return FileAccess.get_open_error()
	file.store_string(JSON.stringify(_document,"\t",true,true));file.flush();error=file.get_error();file.close()
	if error==OK:error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(storage_path))
	if error!=OK:DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));last_error="Chat changes are in memory. The previous saved chats were preserved."
	else:last_error=""
	return error
func _load()->void:
	var file:=FileAccess.open(storage_path,FileAccess.READ);var parser:=JSON.new()
	if not file or file.get_length()>33554432:_invalid();return
	var error:=parser.parse(file.get_as_text());file.close()
	if error!=OK or not valid(parser.data):_invalid();return
	_document=parser.data
	# A closed application cannot resume an HTTP request. Never replay it at startup.
	for chat in _document.chats:
		for turn in chat.turns:
			if turn.state=="pending":turn.state="cancelled";turn.notice="Interrupted when the app closed. Ask again when ready."
func _invalid()->void:
	_load_failed=true;last_error="Saved chats could not be read. They were preserved; new changes are in memory only."
static func valid(value:Variant)->bool:
	if not value is Dictionary or value.size()!=3 or value.get("version")!=1 or not value.get("active") is String or not value.get("chats") is Array:return false
	var ids:Dictionary={};var turns:Dictionary={}
	for chat in value.chats:
		if not chat is Dictionary or chat.size()!=5 or not chat.get("id") is String or chat.id.is_empty() or ids.has(chat.id):return false
		ids[chat.id]=true
		if not chat.get("title") is String or chat.title.length()>100 or not chat.get("renamed") is bool or not chat.get("draft") is String or chat.draft.length()>16000 or not chat.get("turns") is Array:return false
		for turn in chat.turns:
			if not turn is Dictionary or turn.size()!=7:return false
			for field in ["id","question","answer","state","notice","binding","assistant"]:
				if not turn.get(field) is String:return false
			if turn.id.is_empty() or turns.has(turn.id) or turn.state not in ["pending","complete","failed","cancelled"] or turn.question.length()>16000:return false
			turns[turn.id]=true
	return ids.has(value.active)
