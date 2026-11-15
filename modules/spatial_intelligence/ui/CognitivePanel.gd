class_name CognitivePanel
extends CanvasLayer
## Existing Cortex entry point. Authored scene controls bind to the existing owners.
@onready var draggable_container:Control=%DraggableContainer
@onready var chat_feed:RichTextLabel=%ChatFeed
@onready var input_field:LineEdit=%InputField
@onready var analyze_button:Button=%AnalyzeButton
@onready var status_light:ColorRect=%StatusLight
@onready var vision_preview:TextureRect=%VisionPreview
@onready var close_button:Button=%CloseButton
@onready var brain:Node=get_node("/root/SpatialIntelligence")
var _is_visible:=false
var _syncing:=false
var _capture:Dictionary={}
var _segmentation:Dictionary={}
var _mask_index:=0
var _probe_point:=Vector2.INF
var _probe_request:=-1
var _viewer:GaussianSplattingViewer
var _segmentation_cancel_pending:=false
var _displayed_preset:=""
const SOURCES=["session","environment","vault","none"]
func _ready()->void:
	chat_feed.text=""
	_print_system_message("Choose what you want to do above. Help explains each preset in plain language.")
	for id in CortexPresets.ORDER:
		var item:=CortexPresets.definition(id)
		%GoalPicker.add_item(item.title);%GoalPicker.set_item_metadata(%GoalPicker.item_count-1,id)
		%GoalPicker.get_popup().set_item_tooltip(%GoalPicker.item_count-1,item.summary+"\n\n"+item.privacy)
	%GoalPicker.item_selected.connect(func(index):choose_preset(str(%GoalPicker.get_item_metadata(index))))
	%GoalHelpButton.toggled.connect(func(open):
		var prefs:=SIConfig.settings().experience()
		var error:=SIConfig.settings().update_experience(prefs.preset,open)
		if error!=OK:_status("Help preference could not be saved.");_sync_guidance()
	)
	%ExampleQuestion.pressed.connect(func():
		input_field.text=CortexPresets.definition(SIConfig.settings().experience().preset).get("example","")
		input_field.grab_focus()
	)
	%GuidedSetup.pressed.connect(_open_advanced)
	SIConfig.settings().experience_changed.connect(_sync_guidance)
	for item in ["Session only","Environment variable","Windows credential store","No credential · loopback only"]:%CredentialSource.add_item(item)
	for item in ["Visible models","Selected models only"]:%ContextScope.add_item(item)
	for item in ["MobileSAM · point prompts","SAM3 · concepts and boxes"]:%SegmentationEngine.add_item(item)
	for item in ["Point prompts","Box prompt · SAM3"]:%PromptMode.add_item(item)
	for provider in CortexProviders.DEFINITIONS:%NewProvider.add_item(CortexProviders.DEFINITIONS[provider].label);%NewProvider.set_item_metadata(%NewProvider.item_count-1,provider)
	%AskConnection.item_selected.connect(_select_connection.bind(%AskConnection))
	%SetupConnection.item_selected.connect(_select_connection.bind(%SetupConnection))
	%AddConnection.pressed.connect(func():
		if brain.policy.configuration_enabled:SIConfig.settings().add_profile(str(%NewProvider.get_item_metadata(%NewProvider.selected)))
	)
	%ApplyConnection.pressed.connect(apply_connection)
	%StartBundledQwen.pressed.connect(func():
		var error:int=brain.local_runtime.start_bundled()
		if error==OK:SIConfig.settings().select("qwen")
		else:_status("Bundled Qwen could not start: "+error_string(error))
	)
	%StopBundledQwen.pressed.connect(func():brain.local_runtime.stop())
	brain.local_runtime.state_changed.connect(func(message):
		%BundledQwenStatus.text=message
		if brain._is_analyzing and CortexPresets.kind(SIConfig.settings().experience().preset)=="private":
			_status("Private assistant ready. Preparing your answer…" if message.begins_with("Ready") else "Preparing your private assistant on this computer. Your scene stays unchanged…")
	)
	%BundledQwenStatus.text=brain.local_runtime.message
	%CredentialSource.item_selected.connect(func(_index):_credential_controls())
	%RevealSecret.toggled.connect(func(enabled):%SecretInput.secret=not enabled)
	%SecretInput.focus_exited.connect(func():%RevealSecret.set_pressed_no_signal(false);%SecretInput.secret=true)
	%VisionCapability.toggled.connect(func(enabled):
		%IncludeImage.disabled=not enabled
		if not enabled:%IncludeImage.button_pressed=false
	)
	%DiscoveredModels.item_selected.connect(func(index):
		if index>0:%ModelName.text=%DiscoveredModels.get_item_text(index)
	)
	%ForgetCredential.pressed.connect(func():
		if not brain.policy.configuration_enabled:return
		CortexCredentials.forget(SIConfig.settings().active());brain.cancel_analysis();_credential_controls();_status("Local credential removed. Provider-side revocation is separate.")
	)
	%ClearSessionKeys.pressed.connect(func():
		CortexCredentials.clear_sessions();brain.cancel_analysis();_credential_controls();_status("Session credentials cleared.")
	)
	%CloudConsent.toggled.connect(func(enabled):
		brain.policy.cloud_enabled=enabled
		if not enabled:brain.cancel_analysis();_set_analysis_busy(false)
	)
	%LocalConsent.toggled.connect(func(enabled):
		brain.policy.local_enabled=enabled
		if not enabled:brain.cancel_analysis();_set_analysis_busy(false)
	)
	%ActionConsent.toggled.connect(func(enabled):
		brain.set_action_consent(enabled);%ActionConsent.set_pressed_no_signal(brain.policy.allows_action())
	)
	analyze_button.pressed.connect(_submit_request);input_field.text_submitted.connect(func(_text):_submit_request())
	close_button.pressed.connect(hide_panel)
	%CancelAnalysis.pressed.connect(func():brain.cancel_analysis();_set_analysis_busy(false);_status("Analysis cancelled."))
	%SetupShortcut.pressed.connect(_open_advanced)
	%ProviderKeysPortal.pressed.connect(_open_provider_portal)
	for pair in [["DiscoverModels","models"],["TestText","text"],["TestVision","vision"],["TestTools","tools"]]:
		get_node("%"+pair[0]).pressed.connect(func():%ConnectionDiagnostics.text="Testing synthetic input…";brain.test_connection(pair[1]))
	%ApplyVision.pressed.connect(apply_vision)
	%BrowseModelPack.pressed.connect(func():%ModelFolderDialog.popup_centered())
	%ModelFolderDialog.dir_selected.connect(func(path):%Sam3Directory.text=path)
	%DetectModelPack.pressed.connect(_detect_model_pack)
	%TestEngine.pressed.connect(test_engine)
	%SegmentationEngine.item_selected.connect(func(_index):_vision_controls())
	%CaptureButton.pressed.connect(func():%SegmentationStatus.text="Capturing clean view…";brain.capture_segmentation())
	%FullViewToggle.toggled.connect(_full_view)
	%ClearPrompts.pressed.connect(clear_prompts)
	%PromptMode.item_selected.connect(func(index):
		%SnapshotCanvas.box_mode=index==1;%FullViewCanvas.box_mode=index==1
	)
	%MaskOpacity.value_changed.connect(func(value):
		%SnapshotCanvas.mask_opacity=value;%FullViewCanvas.mask_opacity=value;%SnapshotCanvas.queue_redraw();%FullViewCanvas.queue_redraw()
	)
	for canvas in [%SnapshotCanvas,%FullViewCanvas]:
		canvas.point_added.connect(_point_added);canvas.box_added.connect(_box_added)
	%SegmentButton.pressed.connect(segment_capture)
	%CancelSegmentation.pressed.connect(_cancel_segmentation)
	%ReleaseEngine.pressed.connect(func():
		if not brain.segmentation.is_busy():brain.segmentation.release();_status("Local inference sessions released.")
	)
	%MaskSelector.item_selected.connect(_choose_mask)
	%AcceptSelection.pressed.connect(select_mask_model)
	brain.analysis_started.connect(func():_set_analysis_busy(true))
	brain.analysis_completed.connect(_on_brain_responded)
	brain.analysis_failed.connect(_on_brain_failed)
	brain.capture_ready.connect(func(image):vision_preview.texture=ImageTexture.create_from_image(image))
	brain.segmentation_capture_ready.connect(_captured)
	brain.segmentation.completed.connect(_segmented)
	brain.segmentation.activity_changed.connect(_segmentation_activity)
	brain.diagnostics_ready.connect(_diagnostics)
	brain.configuration_changed.connect(_sync_settings)
	draggable_container.drag_started.connect(func():
		var viewer:=_active_viewer()
		if viewer:viewer.set_camera_blocker("cortex_drag",true)
	)
	draggable_container.drag_ended.connect(func():
		var viewer:=_active_viewer()
		if viewer:viewer.set_camera_blocker("cortex_drag",false)
	)
	_sync_settings();_segmentation_activity(false)
func _active_viewer()->GaussianSplattingViewer:
	for viewer in get_tree().get_nodes_in_group("gaussian_splat_viewers"):
		if viewer.get_camera()==get_viewport().get_camera_3d():return viewer
	return null
func show_panel()->void:
	visible=true;_is_visible=true
	if SIConfig.settings().experience().preset!="custom":_displayed_preset=""
	_sync_settings()
func hide_panel()->void:
	input_field.release_focus();%SecretInput.clear();%SecretInput.secret=true
	%RevealSecret.set_pressed_no_signal(false);%FullViewToggle.set_pressed_no_signal(false);_full_view(false)
	brain.cancel_analysis();brain.segmentation.cancel();brain.connection_probe.cancel()
	_set_analysis_busy(false);visible=false;_is_visible=false
func _sync_settings()->void:
	if brain.segmentation.is_processing():_segmentation_cancel_pending=true
	_syncing=true
	var settings:=SIConfig.settings();var profile:=settings.active()
	for selector in [%AskConnection,%SetupConnection]:
		selector.clear()
		for item in settings.snapshot().profiles:
			selector.add_item(item.name);selector.set_item_metadata(selector.item_count-1,item.id)
			if item.id==profile.id:selector.select(selector.item_count-1)
	%ConnectionName.text=profile.name;%Endpoint.text=profile.endpoint;%ModelName.text=profile.model
	%Endpoint.editable=profile.provider in ["compatible","ollama"]
	%VisionCapability.set_pressed_no_signal(profile.vision);%ToolsCapability.set_pressed_no_signal(profile.tools)
	%IncludeImage.set_pressed_no_signal(profile.include_image);%IncludeImage.disabled=not profile.vision
	%ContextScope.select(1 if profile.scope=="selected" else 0)
	%CredentialSource.select(SOURCES.find(profile.credential_source));%EnvironmentName.text=profile.environment
	%SecretInput.clear();%RevealSecret.set_pressed_no_signal(false);%SecretInput.secret=true
	%MaxTokens.value=profile.max_tokens;%RequestTimeout.value=profile.timeout
	%TemperatureEnabled.set_pressed_no_signal(profile.temperature_enabled);%Temperature.value=profile.temperature
	var vision:=settings.vision_request_settings()
	%SegmentationEngine.select(0 if vision.engine=="mobile_sam" else 1);%Sam3Directory.text=vision.sam3_directory
	%Confidence.value=vision.confidence;%MaskOpacity.value=vision.mask_opacity
	var actual:=settings.analysis_profile()
	%CloudConsent.visible=not CortexProviders.loopback(actual.endpoint)
	%LocalConsent.visible=CortexProviders.loopback(actual.endpoint)
	%CloudConsent.text="Allow "+actual.name+" to receive my question and scene details"
	%CloudConsent.set_pressed_no_signal(brain.policy.cloud_enabled)
	%LocalConsent.set_pressed_no_signal(brain.policy.local_enabled)
	%ActionConsent.set_pressed_no_signal(brain.policy.allows_action())
	%EngineStatus.text=actual.name+"  /  "+("Choose a model in Setup" if actual.model.is_empty() else actual.model)
	%ApplyConnection.disabled=not brain.policy.configuration_enabled
	%ApplyVision.disabled=not brain.policy.configuration_enabled
	_credential_controls();_vision_controls();_syncing=false;_set_analysis_busy(false);_sync_guidance()
func choose_preset(id:String)->Error:
	var error:int=brain.select_preset(id)
	if error!=OK:_status("Your current settings were kept: "+error_string(error));_sync_guidance();return error
	_displayed_preset="";_sync_settings()
	%FullViewToggle.set_pressed_no_signal(false);_full_view(false);clear_prompts()
	if not _capture.is_empty():%SegmentationStatus.text=_picture_ready_status()
	_status("Ready. Capture your view to begin." if CortexPresets.kind(id)=="segment" else ("Advanced controls are available below." if id=="custom" else "Ready. Type a question or try the example."))
	return OK
func _open_advanced()->void:
	if not brain.policy.configuration_enabled:
		%WorkspaceTabs.tabs_visible=true;%WorkspaceTabs.current_tab=2;_status("Read-only settings. Configuration is managed by the application host.");return
	if choose_preset("custom")==OK:%WorkspaceTabs.current_tab=2
func _sync_guidance()->void:
	var prefs:=SIConfig.settings().experience();var item:=CortexPresets.definition(prefs.preset)
	var changed:bool=_displayed_preset!=prefs.preset;_displayed_preset=prefs.preset
	for index in range(%GoalPicker.item_count):
		if %GoalPicker.get_item_metadata(index)==prefs.preset:%GoalPicker.select(index)
	%GoalPicker.disabled=not brain.policy.configuration_enabled
	%GoalSummary.text=item.summary
	var needs:=""
	if item.kind=="connected":
		var connection:=SIConfig.settings().active()
		if connection.model.is_empty() or (connection.credential_source!="none" and not CortexCredentials.present(connection)):
			needs="One-time setup needed: choose Advanced settings to connect your assistant and account key. The private presets need no account."
		elif connection.provider=="qwen" and not brain.local_runtime.is_running():needs="Choose Understand my scene for the included assistant; it starts it for you."
	elif item.kind=="private" and not ClassDB.class_exists("CortexLocalModelHost"):
		needs="The private assistant needs the app build with local tools included. Your current scene is unaffected."
	elif item.kind=="segment" and not NativeMLBridge.availability().available:
		needs="Local selection needs the app build with its included local tools. You can still capture the view."
	%GoalReadiness.text=needs;%GoalReadiness.visible=not needs.is_empty()
	%GoalSummary.tooltip_text=CortexPresets.help_text(prefs.preset)
	%GoalHelp.text=CortexPresets.help_text(prefs.preset)
	%GoalHelpScroll.visible=prefs.help_open;%GoalHelpButton.set_pressed_no_signal(prefs.help_open)
	%GoalHelpButton.text="Hide help" if prefs.help_open else "How it works"
	%WorkspaceTabs.tabs_visible=item.kind=="custom"
	if changed:%WorkspaceTabs.current_tab=1 if item.kind=="segment" else (2 if item.kind=="custom" else 0)
	var private:bool=item.kind=="private";var guided:bool=item.kind!="custom"
	%AskConnection.visible=not private;%ActionConsent.visible=not guided
	%SelectDescription.visible=not guided
	%ExampleQuestion.visible=item.has("example")
	%GuidedSetup.visible=guided
	%GuidedSetup.text="Connect my assistant" if item.kind=="connected" and not needs.is_empty() else "Advanced settings"
	%PromptMode.visible=not guided
	%ClearPrompts.text="Clear my marks" if guided else "Clear prompts"
	%FullViewToggle.text="Enlarge picture" if guided else "Pick in view"
	%ReleaseEngine.text="Free memory" if guided else "Release memory"
	%VisionPreview.visible=not private
	%VisionLabel.text="Scene names and layout stay on this computer. The picture is not sent." if private else "Your connection settings decide whether a picture is shared."
	%LocalConsent.text="Allow this private assistant to read scene information" if private else "Allow local endpoint analysis"
	input_field.placeholder_text=item.get("placeholder","Ask Cortex about the scene…")
	if item.kind=="segment":
		%SegmentationEngine.select(0 if item.engine=="mobile_sam" else 1);_vision_controls()
		%SelectDescription.text=item.summary
		%EngineStatus.text="PRIVATE SELECTION · "+("MobileSAM" if item.engine=="mobile_sam" else "SAM3")+" · loads only when you search"
	elif private:%EngineStatus.text="PRIVATE ASSISTANT · on this computer · read-only"
	elif item.kind=="custom":%SelectDescription.text="Capture → prompt → inspect → select an existing model."
	%PromptHelp.text=("Click the object in the picture. Right click removes an unwanted area." if item.get("engine")=="mobile_sam" else "Type what you want to find. Drawing a box is optional.") if item.kind=="segment" else %PromptHelp.text
	%CaptureButton.text="1 · Capture my view" if guided else "Capture view"
	%SegmentButton.text="2 · Find object" if guided else "Segment"
	%AcceptSelection.text="3 · Select model" if guided else "Select model at mask point"
	%ConceptPrompt.placeholder_text="What should I find? For example: person, motorcycle, tree"
	_set_analysis_busy(brain._is_analyzing)
func _request_vision_settings()->Dictionary:return SIConfig.settings().vision_request_settings()
func _picture_ready_status()->String:
	return "Picture ready. Click the object, then Find object." if _request_vision_settings().engine=="mobile_sam" else "Picture ready. Describe what you want to find; a box is optional."
func _select_connection(index:int,selector:OptionButton)->void:
	if _syncing:return
	if not brain.policy.configuration_enabled:_sync_settings();return
	var error:=SIConfig.settings().select(str(selector.get_item_metadata(index)))
	if error!=OK:_status("Connection could not be selected: "+error_string(error))
func _credential_controls()->void:
	if %CredentialSource.selected<0:return
	var source:String=SOURCES[%CredentialSource.selected]
	%EnvironmentName.editable=source=="environment"
	%SecretInput.editable=source in ["session","vault"]
	%RevealSecret.disabled=not %SecretInput.editable
	var profile:=SIConfig.settings().active()
	%CredentialStatus.text=("Credential configured" if CortexCredentials.present(profile) else "No credential configured")+" · "+str(profile.credential_source)
	if source=="vault" and not CortexCredentials.vault_available():%CredentialStatus.text="Windows native credential store is unavailable; choose session or environment."
func apply_connection()->Error:
	var profile:=SIConfig.settings().active()
	profile.name=%ConnectionName.text.strip_edges();profile.endpoint=%Endpoint.text.strip_edges().trim_suffix("/")
	profile.model=%ModelName.text.strip_edges();profile.vision=%VisionCapability.button_pressed;profile.tools=%ToolsCapability.button_pressed
	profile.include_image=%IncludeImage.button_pressed;profile.scope="selected" if %ContextScope.selected==1 else "visible"
	profile.credential_source=SOURCES[%CredentialSource.selected];profile.environment=%EnvironmentName.text.strip_edges()
	profile.max_tokens=int(%MaxTokens.value);profile.timeout=%RequestTimeout.value
	profile.temperature_enabled=%TemperatureEnabled.button_pressed;profile.temperature=%Temperature.value
	var error:int=brain.configure_profile(profile,%SecretInput.text)
	if error==OK:%SecretInput.clear();_status("Connection saved. Test its capabilities in Setup → Diagnostics.")
	else:_status("Connection preserved: "+(SIConfig.settings().last_error if not SIConfig.settings().last_error.is_empty() else error_string(error)))
	return error
func _vision_controls()->void:
	var sam3:bool=%SegmentationEngine.selected==1
	%Sam3Directory.editable=sam3;%BrowseModelPack.disabled=not sam3;%DetectModelPack.disabled=not sam3;%Confidence.editable=sam3
	%ConceptPrompt.visible=sam3
	%PromptHelp.text="SAM3 · enter a concept; an optional box narrows the target." if sam3 else "MobileSAM · left click adds foreground; right/Shift-click excludes."
	%PromptMode.set_item_disabled(0,sam3);%PromptMode.set_item_disabled(1,not sam3)
	%PromptMode.select(1 if sam3 else 0)
	%SnapshotCanvas.box_mode=sam3;%FullViewCanvas.box_mode=sam3
func apply_vision()->Error:
	if not brain.policy.configuration_enabled:return ERR_UNAUTHORIZED
	var settings:={"engine":"sam3" if %SegmentationEngine.selected==1 else "mobile_sam","sam3_directory":%Sam3Directory.text.strip_edges(),"confidence":%Confidence.value,"mask_opacity":%MaskOpacity.value}
	var error:=SIConfig.settings().update_segmentation(settings)
	_status("Vision settings saved." if error==OK else "Vision settings were preserved: "+error_string(error))
	return error
func _detect_model_pack()->void:
	if DirAccess.dir_exists_absolute(CortexAssets.sam3_directory("bundle://sam3")):
		%Sam3Directory.text="bundle://sam3";_status("Found the portable SAM3 package under resources/cortex.");return
	var candidate:=OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join("sam3_vit_h")
	if DirAccess.dir_exists_absolute(candidate):%Sam3Directory.text=candidate;_status("Found a candidate pack. Apply, then verify its integrity.")
	else:_status("No sam3_vit_h folder found in Downloads. Browse to the extracted package.")
func test_engine()->void:
	if apply_vision()!=OK:return
	var error:int=brain.segmentation.request(null,"",_request_vision_settings(),PackedVector2Array(),PackedInt32Array(),"",Rect2(),false,true)
	if error!=OK:_status("Engine is busy or unavailable: "+error_string(error))
func _captured(value:Dictionary)->void:
	_set_analysis_busy(false)
	if value.has("error"):%SegmentationStatus.text=value.error;return
	_capture=value;_segmentation={};_probe_point=Vector2.INF;clear_prompts()
	%SnapshotCanvas.set_image(value.image);%FullViewCanvas.set_image(value.image)
	%SegmentationStatus.text=_picture_ready_status()
func clear_prompts()->void:
	for canvas in [%SnapshotCanvas,%FullViewCanvas]:
		canvas.points=PackedVector2Array();canvas.labels=PackedInt32Array();canvas.has_box=false;canvas.rectangle=Rect2();canvas.set_mask(null)
	_segmentation={};_probe_point=Vector2.INF;%MaskSelector.clear()
	%MaskSelector.disabled=true;%MaskSelector.text="Results appear here"
	%AcceptSelection.disabled=true
func _point_added(pixel:Vector2,foreground:bool)->void:
	if %SnapshotCanvas.points.size()>=256:_status("A capture supports at most 256 point prompts.");return
	var points:PackedVector2Array=%SnapshotCanvas.points;var labels:PackedInt32Array=%SnapshotCanvas.labels
	points.append(pixel);labels.append(1 if foreground else 0)
	for canvas in [%SnapshotCanvas,%FullViewCanvas]:canvas.points=points;canvas.labels=labels;canvas.queue_redraw()
func _box_added(rectangle:Rect2)->void:
	for canvas in [%SnapshotCanvas,%FullViewCanvas]:canvas.rectangle=rectangle;canvas.has_box=true;canvas.queue_redraw()
func segment_capture()->void:
	if _capture.is_empty():_status("Capture the current view first.");return
	if _request_vision_settings().engine=="sam3" and %ConceptPrompt.text.strip_edges().is_empty():_status("Enter a concept such as motorcycle or person.");return
	var error:int=brain.segmentation.request(_capture.image,_capture.id,_request_vision_settings(),%SnapshotCanvas.points,%SnapshotCanvas.labels,%ConceptPrompt.text,%SnapshotCanvas.rectangle,%SnapshotCanvas.has_box)
	if error!=OK:_status("Segmentation could not start: "+error_string(error))
	else:
		_segmentation={};_probe_point=Vector2.INF;%MaskSelector.clear();%AcceptSelection.disabled=true
		%MaskSelector.disabled=true;%MaskSelector.text="Finding…"
		for canvas in [%SnapshotCanvas,%FullViewCanvas]:canvas.set_mask(null)
func _segmentation_activity(active:bool)->void:
	%SegmentButton.disabled=active;%ReleaseEngine.disabled=active;%TestEngine.disabled=active
	%CancelSegmentation.disabled=not active
	if active:_segmentation_cancel_pending=false;set_process(true)
	else:
		set_process(false)
		if _segmentation_cancel_pending:
			%SegmentationStatus.text="Cancelled. Stale results were discarded."
			%MaskSelector.text="No results yet";%MaskSelector.disabled=true
		_segmentation_cancel_pending=false
func _cancel_segmentation()->void:
	_segmentation_cancel_pending=brain.segmentation.is_processing()
	brain.segmentation.cancel()
	%SegmentationStatus.text="Cancelling; an active native call may finish privately." if _segmentation_cancel_pending else "Cancelled. Stale results were discarded."
func _process(_delta:float)->void:
	var phase:String=brain.segmentation.phase()
	var caption:=CortexPresets.progress_label(phase) if CortexPresets.kind(SIConfig.settings().experience().preset)=="segment" else phase
	%SegmentationStatus.text=("Cancelling · " if _segmentation_cancel_pending else "")+caption;%EngineVerification.text=phase
func _segmented(result:Dictionary)->void:
	if result.has("error"):%SegmentationStatus.text=result.error;%EngineVerification.text=result.error;%MaskSelector.text="No results yet";%MaskSelector.disabled=true;return
	if result.get("initialized",false):%EngineVerification.text=result.message;_status(result.message);return
	if _capture.is_empty() or result.get("capture_id","")!=_capture.id:return
	if not result.get("preview_only",false):
		_segmentation=result;_mask_index=0;%MaskSelector.clear()
		for i in range(result.get("masks",[]).size()):
			var score:=" · %.2f"%result.scores[i] if i<result.get("scores",[]).size() else ""
			%MaskSelector.add_item(("Result %d%s" if CortexPresets.kind(SIConfig.settings().experience().preset)=="segment" else "Mask %d%s")%[i+1,score])
		%MaskSelector.disabled=result.get("masks",[]).is_empty()
		if %MaskSelector.disabled:%MaskSelector.text="No results yet"
	if result.has("preview"):
		for canvas in [%SnapshotCanvas,%FullViewCanvas]:canvas.set_mask(result.preview)
		_probe_point=result.probe_point
	%AcceptSelection.disabled=not _probe_point.is_finite()
	if CortexPresets.kind(SIConfig.settings().experience().preset)=="segment":
		%SegmentationStatus.text="Found %d area(s). Check the highlight, then Select model."%_segmentation.get("masks",[]).size() if not _segmentation.get("masks",[]).is_empty() else "Nothing found. Try another description, a clearer click, or a new picture."
	else:%SegmentationStatus.text="%s · %d mask(s) · %.0f ms · captured view only"%[str(_segmentation.get("engine","Local")),_segmentation.get("masks",[]).size(),float(result.elapsed_ms)]
func _choose_mask(index:int)->void:
	if index<0 or index>=_segmentation.get("masks",[]).size():return
	_mask_index=index
	_probe_point=Vector2.INF;%AcceptSelection.disabled=true
	brain.segmentation.preview(_segmentation.masks[index],_segmentation.size,_capture.id)
func _full_view(enabled:bool)->void:
	if enabled and _capture.is_empty():%FullViewToggle.set_pressed_no_signal(false);_status("Capture the view before full-view picking.");return
	%FullViewCanvas.visible=enabled
	var viewer:=_active_viewer()
	if viewer:viewer.set_camera_blocker("cortex_fullview",enabled)
func select_mask_model()->void:
	_viewer=_active_viewer()
	if not _viewer or _capture.is_empty() or not _probe_point.is_finite():_status("Run segmentation and choose a nonempty mask first.");return
	if brain.scene_signature(_viewer)!=_capture.signature:_status("The scene or camera changed. Capture and segment again.");return
	if not _viewer.model_probe_completed.is_connected(_model_probed):_viewer.model_probe_completed.connect(_model_probed)
	var pixel:Vector2=_probe_point/Vector2(_capture.image.get_size())*_capture.viewport_size
	_probe_request=_viewer.request_model_probe(pixel)
	if _probe_request<0:_status("The scene is busy. Finish the current operation before selecting.")
func _model_probed(request_id:int,identity:String,_position:Vector3)->void:
	if request_id!=_probe_request:return
	_probe_request=-1
	if not _viewer or brain.scene_signature(_viewer)!=_capture.signature:_status("The capture became stale; selection was not applied.");return
	if identity.is_empty():_status("No visible model resolved at this mask point. Use the scene navigator.");return
	_viewer.select_model_id(identity);_status("Existing model selected. Its transform and camera were preserved.")
func _diagnostics(result:Dictionary)->void:
	if result.has("error"):%ConnectionDiagnostics.text=result.error;_status(result.error);return
	%ConnectionDiagnostics.text=str(result.get("status","Test completed."))+"\n"+JSON.stringify(result.get("metrics",{}))
	if result.has("models"):
		%DiscoveredModels.clear();%DiscoveredModels.add_item("Choose a discovered model…")
		for model in result.models:%DiscoveredModels.add_item(model)
		%ConnectionDiagnostics.text+="\n%d model(s) discovered."%result.models.size()
func _submit_request()->void:
	var prompt:=input_field.text.strip_edges()
	if prompt.is_empty():return
	_print_user_message(prompt);input_field.clear()
	if CortexPresets.kind(SIConfig.settings().experience().preset)=="private":brain.analyze_privately(prompt)
	else:brain.analyze_scene(prompt)
func _set_analysis_busy(busy:bool)->void:
	analyze_button.disabled=busy;input_field.editable=not busy
	analyze_button.text="Thinking…" if busy else ("Start & ask privately" if CortexPresets.kind(SIConfig.settings().experience().preset)=="private" else "Ask assistant")
	analyze_button.tooltip_text="Start the included assistant and share scene names and layout on this computer. No picture, cloud upload or model edits." if CortexPresets.kind(SIConfig.settings().experience().preset)=="private" else "Send the configured input to the chosen connection after granting transmission permission."
	%LocalConsent.set_pressed_no_signal(brain.policy.local_enabled)
	status_light.color=Color(1,0.65,0.25) if busy else Color(0.5,0.65,0.7)
func _on_brain_responded(message:String)->void:_set_analysis_busy(false);status_light.color=Color(0.35,0.9,0.7);_print_ai_message(message);_status("Answer ready. You can ask another question.")
func _on_brain_failed(message:String)->void:_set_analysis_busy(false);status_light.color=Color(1,0.3,0.3);_print_system_message(message)
func _status(message:String)->void:%WorkspaceStatus.text=message
func _print_user_message(message:String)->void:chat_feed.append_text("\n[color=#a7d7e5][b]YOU[/b][/color]  "+message.replace("[","[lb]"))
func _print_ai_message(message:String)->void:chat_feed.append_text("\n[color=#f07979][b]CORTEX[/b][/color]  "+message.replace("[","[lb]"))
func _print_system_message(message:String)->void:chat_feed.append_text("\n[color=#b0bcc8]"+message.replace("[","[lb]")+"[/color]")
func _open_provider_portal()->void:
	var urls:={"openai":"https://platform.openai.com/api-keys","anthropic":"https://platform.claude.com/settings/keys","google":"https://aistudio.google.com/apikey"}
	var provider:=SIConfig.get_provider()
	if urls.has(provider):OS.shell_open(urls[provider])
	else:_status("This connection is managed by its local runtime or organisation.")
func _exit_tree()->void:
	brain.cancel_analysis();brain.segmentation.cancel()
	if is_instance_valid(_viewer):_viewer.cancel_model_probe(_probe_request);_viewer.set_camera_blocker("cortex_fullview",false);_viewer.set_camera_blocker("cortex_drag",false)
