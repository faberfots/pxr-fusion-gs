extends TabContainer
## Read-only generated credits. Loaded on first open, away from GS startup work.
var _loaded:=false
var _notices_loaded:=false
func _ready()->void:
	visibility_changed.connect(_load_when_visible)
	tab_changed.connect(func(_index):_load_notices())
	%Credits.meta_clicked.connect(func(meta):
		var url:=str(meta)
		if url.begins_with("https://"):OS.shell_open(url)
	)
	%Search.text_submitted.connect(func(query):
		if query.is_empty():return
		var found:Vector2i=%Notices.search(query,0,0,0)
		if found.x>=0:
			%Notices.set_caret_line(found.y);%Notices.set_caret_column(found.x);%Notices.center_viewport_to_caret()
	)
func _load_when_visible()->void:
	if _loaded or not is_visible_in_tree():return
	_loaded=true
	var document:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legal/credits.json"))
	if not document is Dictionary:
		%Credits.text="Credit information could not be read. See CREDITS.md and the accompanying licences.";return
	var lines:PackedStringArray=["[b]PXRFusion[/b] · POLYGONICS SAS", "",_escape(document.product.foundation_statement),"","[b]Foundations and components[/b]"]
	for component in document.components:
		lines.append("\n[b]"+_escape(component.name)+"[/b]")
		if not component.authors.is_empty():lines.append(_escape(component.authors))
		if not component.role.is_empty():lines.append(_escape(component.role))
		lines.append(_escape(component.license))
		if not component.upstream.is_empty():lines.append("[url="+component.upstream+"]Project website[/url]")
	lines.append("\nThird-party resources retain their own terms. Provenance limits are documented in CREDITS.md and the dependency inventory.")
	%Credits.text="\n".join(lines)
	_load_notices()
func _load_notices()->void:
	if _notices_loaded or not is_visible_in_tree() or current_tab!=1:return
	_notices_loaded=true
	var notices:=FileAccess.get_file_as_string("res://assets/legal/notices.txt")
	notices+="\n\n=== ACTUAL RUNNING GODOT ENGINE ===\n"+Engine.get_license_text()
	for entry in Engine.get_copyright_info():
		notices+="\n\n"+str(entry.name)
		for part in entry.parts:
			notices+="\n"+"\n".join(PackedStringArray(part.get("copyright",part.get("copyrights",[]))))+"\nLicence: "+str(part.license)
	for identifier in Engine.get_license_info():notices+="\n\n=== "+str(identifier)+" ===\n"+str(Engine.get_license_info()[identifier])
	%Notices.text=notices
func _escape(value:String)->String:return value.replace("[","[lb]")
