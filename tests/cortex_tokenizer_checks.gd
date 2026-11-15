extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/clip-reference.json"))
	if not data is Dictionary:quit(2);return
	var tokenizer:=CortexClipTokenizer.new();var failures:=0
	for fixture in data.fixtures:
		var expected:=PackedInt64Array(fixture.tokens)
		if tokenizer.encode(fixture.text)!=expected:failures+=1;print("FAIL reference CLIP tokens for ",fixture.text)
	print("CLIP REFERENCE COMPLETE: ",data.fixtures.size()," fixtures, ",failures," failures")
	quit(0 if failures==0 else 1)
