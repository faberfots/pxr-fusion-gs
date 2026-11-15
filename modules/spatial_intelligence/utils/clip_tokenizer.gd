class_name CortexClipTokenizer
extends RefCounted
## CLIP byte-pair vocabulary, pinned to the SAM3 export's 49408-token contract.
const ROOT="res://modules/spatial_intelligence/models/"
var _vocabulary:Dictionary={}
var _ranks:Dictionary={}
var _byte_encoder:Dictionary={}
var _cache:Dictionary={}
var _pattern:=RegEx.new()
var error:=""
var _initialized:=false
func initialize()->bool:
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(ROOT+"clip_vocab.json"))!=OK or not parser.data is Dictionary:error="CLIP vocabulary is unavailable.";return false
	_vocabulary=parser.data
	if _vocabulary.size()!=49408 or _vocabulary.get("<|startoftext|>")!=49406 or _vocabulary.get("<|endoftext|>")!=49407:error="Unsupported CLIP vocabulary.";return false
	var rank:=0
	for line in FileAccess.get_file_as_string(ROOT+"clip_merges.txt").split("\n"):
		if line.is_empty() or line.begins_with("#version:"):continue
		_ranks[line.strip_edges()]=rank;rank+=1
	if rank!=48894:error="Unsupported CLIP merge table.";return false
	var bytes:Array[int]=[]
	for ranges in [[33,127],[161,173],[174,256]]:
		for byte in range(ranges[0],ranges[1]):bytes.append(byte)
	var extra:=256
	for byte in range(256):
		if byte in bytes:_byte_encoder[byte]=String.chr(byte)
		else:_byte_encoder[byte]=String.chr(extra);extra+=1
	_pattern.compile("<\\|startoftext\\|>|<\\|endoftext\\|>|'s|'t|'re|'ve|'m|'ll|'d|[\\p{L}]+|[\\p{N}]|[^\\s\\p{L}\\p{N}]+")
	_initialized=true;return true
func encode(text:String)->PackedInt64Array:
	if not _initialized and not initialize():return PackedInt64Array()
	if text.length()>4096:error="Use a concept prompt of at most 4096 characters.";return PackedInt64Array()
	if ClassDB.class_exists("CortexTextTools"):
		var normalizer:Object=ClassDB.instantiate("CortexTextTools");text=str(normalizer.call("normalize_clip",text))
	else:text=text.xml_unescape().xml_unescape().strip_edges().to_lower()
	var whitespace:=RegEx.create_from_string("\\s+");text=whitespace.sub(text," ",true)
	var output:=PackedInt64Array([49406])
	for found in _pattern.search_all(text):
		var token:=""
		for byte in found.get_string().to_utf8_buffer():token+=_byte_encoder[byte]
		for piece in _bpe(token):
			if not _vocabulary.has(piece):error="CLIP token is unavailable.";return PackedInt64Array()
			output.append(int(_vocabulary[piece]))
	output.append(49407)
	if output.size()>32:output=output.slice(0,32);output[31]=49407
	output.resize(32) # This export uses zero padding, matching OpenAI CLIP tokenization.
	return output
func _bpe(token:String)->Array[String]:
	if _cache.has(token):return _cache[token]
	var word:Array[String]=[]
	for character in token:word.append(character)
	if word.is_empty():return word
	word[-1]+="</w>"
	while word.size()>1:
		var best:=2147483647;var first:="";var second:=""
		for i in range(word.size()-1):
			var rank:int=_ranks.get(word[i]+" "+word[i+1],2147483647)
			if rank<best:best=rank;first=word[i];second=word[i+1]
		if best==2147483647:break
		var merged:Array[String]=[];var index:=0
		while index<word.size():
			if index+1<word.size() and word[index]==first and word[index+1]==second:merged.append(first+second);index+=2
			else:merged.append(word[index]);index+=1
		word=merged
	if _cache.size()<2048:_cache[token]=word
	return word
