extends Node
## Separate qualification entry point: official release templates reject --script.
const Checks = preload("res://tests/core_checks.gd")
var failures: Array[String] = []
var scene: Node
var viewer: GaussianSplattingViewer
func _ready() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func settle(seconds: float = 0.2) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
func run() -> void:
	scene = load("res://main.tscn").instantiate()
	viewer = scene.get_node("GaussianSplattingViewer")
	check(viewer.config == null, "packaged real main begins without an injected configuration")
	add_child(scene)
	await settle()
	check(viewer.rasterizer != null and viewer.rasterizer.gpu_init_complete, "optimized release initializes the real viewer renderer")
	if not viewer.rasterizer or not viewer.rasterizer.gpu_init_complete:
		finish();return
	scene.get_node("DemoUIController").show_ui = false
	viewer.set_camera_blocker("qualification", true)
	var ui = scene.get_node("ProductionUI")
	ui.color_panel.show_panel()
	check(ui.color_panel.apply_profile("Warm daylight"), "packaged color panel opens and applies a preset")
	await settle()
	check(is_equal_approx(ui.color_panel.sliders.post_temperature.value, 0.3), "packaged color sliders synchronize with the authoritative configuration")
	ui.color_panel.apply_profile("Natural")
	ui.color_panel.hide_panel()
	# Credits/settings are exercised through the authored production scenes in a
	# real template, including non-resource text files loaded from the PCK.
	var workspace:Control=ui.get_node("%SettingsPanel")
	ui._toggle_panel(workspace);workspace.get_node("%GizmoSection").button_pressed=true
	workspace.get_node("%GizmoSettings").get_node("%Preset").item_selected.emit(2);await settle()
	check(ui.transform_controls.gizmo_preferences.preset_name()=="High Visibility","optimized authored customization controls share the native gizmo preference owner")
	ui.transform_controls.gizmo_preferences.apply_preset("Godot Classic")
	workspace.get_node("%AboutSection").button_pressed=true;await settle()
	var about:Control=workspace.get_node("%AboutLicenses")
	check(about.get_node("%Credits").text.contains("Ethan Truong") and about.get_node("%Credits").text.contains("Christopher Charbonneau"),"optimized package visibly credits the GS and gizmo foundation authors")
	about.current_tab=1;await settle()
	check(about.get_node("%Notices").text.contains("ACTUAL RUNNING GODOT ENGINE") and about.get_node("%Notices").text.contains("Copyright (c) 2024 Ethan Truong"),"optimized PCK contains the full retained licences and exposes actual engine notices")
	workspace.hide()
	# Qualify the new RD pipelines in the actual optimized template, before large data.
	var fixture:=viewer.load_new_splat_from_path(Checks.fixture("user://release-hybrid.ply",1))
	fixture.position.y=1
	await get_tree().process_frame
	while viewer.is_loading():await get_tree().process_frame
	viewer.camera_controller.position_camera_at(Vector3(0,1,2),Vector3(0,1,0))
	var hybrid:Node3D=load("res://tests/scenes/hybrid_lab.tscn").instantiate();add_child(hybrid)
	hybrid.get_node("Pane").position.y=1
	await settle(1.5)
	var composed:=viewer.render_texture.get_image()
	var center:=composed.get_pixel(composed.get_width()/2,composed.get_height()/2)
	check(viewer.rasterizer.transparency_active and center.b>0.3,"optimized release composes participating transparency with actual Gaussian pixels")
	hybrid.free();await settle()
	viewer.lighting.shadows_enabled=true;fixture.receive_gaussian_shadows=true
	await settle(1.5)
	var frame:Dictionary=viewer.rasterizer.shadow_pass.snapshot() if viewer.rasterizer.shadow_pass else {}
	check(not frame.is_empty() and frame.projected>0,"optimized release builds Gaussian opacity shadows and dispatches opt-in receiving")
	viewer.lighting.shadows_enabled=false
	check(not ui.get_node("%ClearBeforeImport").button_pressed,"optimized main defaults to adding imports without clearing")
	var composition:="user://release-import-mode.pxrscene"
	check(await viewer.save_composition(composition)==OK,"optimized release saves the import-mode fixture")
	await ui._import_interactive(composition)
	check(viewer.total_splats_to_load==2,"optimized unchecked Import adds the composition")
	ui.get_node("%ClearBeforeImport").button_pressed=true
	await ui._import_interactive(composition)
	check(viewer.total_splats_to_load==1 and not ui.get_node("%ClearBeforeImport").button_pressed,"optimized checked Import replaces once and resets its safe default")
	viewer._clear_scene_and_reset_atlas();await settle()
	await navigation_checks()
	viewer._clear_scene_and_reset_atlas();await settle()
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	for index in range(args.size() - 1):
		if args[index] == "--dataset": paths.append(args[index + 1])
	if paths.is_empty():
		paths = [Checks.fixture("user://release-a.ply", 1), Checks.fixture("user://release-b.ply", 1)]
	var nodes: Array[GaussianSplat] = []
	for path in paths: nodes.append(viewer.load_new_splat_from_path(path))
	var started := Time.get_ticks_msec()
	await get_tree().process_frame
	while viewer.is_loading() and Time.get_ticks_msec() - started < 300000:
		await get_tree().process_frame
	var expected := 0
	for index in range(paths.size()):
		var ply := PlyFile.new()
		var parsed := ply.parse(paths[index]) == OK
		expected += ply.size if parsed else 0
		check(parsed and is_instance_valid(nodes[index]) and nodes[index].is_loaded, "packaged loader retains every source Gaussian: " + paths[index].get_file())
	check(expected > 0 and viewer.total_splats_to_load == expected, "packaged atlas contains the full combined population")
	print("RELEASE POPULATION ", viewer.total_splats_to_load, " load_ms ", Time.get_ticks_msec() - started)
	viewer.lighting.shadows_enabled=true
	var shadow_started:=Time.get_ticks_msec()
	await settle(0.2)
	while viewer.rasterizer.shadow_pass and viewer.rasterizer.shadow_pass.snapshot().get("signature",0)!=viewer.rasterizer.shadow_request.get("signature",-1) and Time.get_ticks_msec()-shadow_started<15000:await settle(0.1)
	var large_shadow:Dictionary=viewer.rasterizer.shadow_pass.snapshot() if viewer.rasterizer.shadow_pass else {}
	check(not large_shadow.is_empty() and large_shadow.get("projected",0)>0 and viewer.rasterizer.shadow_pass.failure()==0,"optimized release casts shadows from the complete loaded scene within the shared GPU budget")
	print("RELEASE SHADOW projected ",large_shadow.get("projected",0)," cache_ms ",Time.get_ticks_msec()-shadow_started)
	viewer.lighting.shadows_enabled=false;await settle()
	var alpha_lab:Node3D=load("res://tests/scenes/hybrid_lab.tscn").instantiate();add_child(alpha_lab)
	var eye:=viewer.get_camera().global_transform
	alpha_lab.get_node("Pane").global_transform=Transform3D(eye.basis,eye.origin-eye.basis.z*1.5)
	await settle(1.5)
	check(viewer.rasterizer.transparency_active and alpha_lab.get_node("Pane").layers==0 and viewer.total_splats_to_load==expected,"optimized release interleaves a transparent participant with the full unchanged Gaussian population")
	alpha_lab.free();await settle()
	if nodes.is_empty() or not is_instance_valid(nodes[0]):
		finish();return
	viewer.select_model_id(nodes[0].model_id)
	var original := nodes[0].global_transform
	var second := nodes[1].global_transform if nodes.size() > 1 else Transform3D.IDENTITY
	var changed := original.scaled_local(Vector3(1.1, 0.9, 1.2)).rotated_local(Vector3.UP, 0.2)
	changed.origin += Vector3(0.1, 0.2, 0.3)
	nodes[0].global_transform = changed
	await settle()
	check(not nodes[0].global_transform.is_equal_approx(original), "packaged model retains independent XYZ translation, rotation and scale")
	check(nodes.size() < 2 or nodes[1].global_transform.is_equal_approx(second), "packaged edits preserve the other model")
	nodes[0].global_transform = original
	await settle()
	await mesh_checks(args)
	ui.transform_controls.set_mode(GSModelTransformControls.Mode.MOVE)
	ui.get_node("%MainControls").get_node("%ColorButton").pressed.emit()
	await settle()
	get_viewport().get_texture().get_image().save_png("user://release-controls.png")
	ui.color_panel.hide_panel()
	# The identity of the actually running executable is checked by the host tool.
	check(not OS.has_feature("editor"), "qualification runs in a true export template")
	check(NativeMLBridge.availability().available, "optimized release verifies native models and CPU runtime")
	var segmenter := NativeMLBridge.load_default_segmenter()
	check(segmenter != null and segmenter.call("is_ready"), "optimized release initializes the real native ML bridge")
	if segmenter:
		var image:=Image.create(640,384,false,Image.FORMAT_RGB8)
		image.fill(Color8(235,235,235))
		for y in range(384):
			for x in range(640):
				if pow((x-180.0)/110.0,2)+pow((y-190.0)/120.0,2)<=1.0:image.set_pixel(x,y,Color8(200,35,30))
		check(segmenter.call("encode_image",image),"optimized release encodes an actual non-square RGB image")
		var mask:PackedByteArray=segmenter.call("segment_with_points",PackedVector2Array([Vector2(180,190)]),PackedInt32Array([1]))
		check(mask.size()==640*384 and mask[190*640+180]>0 and mask[20*640+20]==0,"optimized release decodes a real prompt-conditioned mask at original image dimensions")
	segmenter = null
	if args.has("--cortex"):await cortex_checks(args)
	finish()
func navigation_fixture(path:String,parts:Array)->String:
	var content:=Node3D.new()
	for part in parts:
		var node:=MeshInstance3D.new();node.mesh=BoxMesh.new();node.mesh.size=part[1];node.position=part[0];content.add_child(node)
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	check(document.append_from_scene(content,state)==OK and document.write_to_filesystem(state,path)==OK,"optimized native collision fixture exports")
	content.free();return path
func navigation_checks()->void:
	viewer.set_camera_blocker("qualification",false)
	var room_path:=navigation_fixture("user://release-drive-room.glb",[[Vector3(0,-0.1,0),Vector3(10,0.2,12)],[Vector3(0,1.5,-3),Vector3(8,3,0.2)],[Vector3(-1.5,1.5,0),Vector3(1,3,0.25)],[Vector3(1.5,1.5,0),Vector3(1,3,0.25)]])
	var actor_path:=navigation_fixture("user://release-drive-arch.glb",[[Vector3(-0.65,0.75,0),Vector3(0.3,1.5,0.4)],[Vector3(0.65,0.75,0),Vector3(0.3,1.5,0.4)],[Vector3(0,1.65,0),Vector3(1.6,0.3,0.4)]])
	var room:=await viewer.load_mesh_from_path(room_path,false,GaussianSplat.ImportKind.ENVIRONMENT)
	var actor:=await viewer.load_mesh_from_path(actor_path,false,GaussianSplat.ImportKind.OBJECT)
	if not actor or not room:check(false,"optimized native navigation fixtures import");viewer.set_camera_blocker("qualification",true);return
	actor.position=Vector3(0,0.025,2);var before:=actor.global_transform
	viewer.select_model_id(actor.model_id);viewer.camera_controller.position_camera_at(Vector3(0,3,7),Vector3(0,0.8,2))
	var ui=scene.get_node("ProductionUI");ui.get_node("%CameraPanel").get_node("%DriveModel").button_pressed=true
	var deadline:=Time.get_ticks_msec()+120000
	while viewer.get_model_navigation_state().preparing and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(viewer.get_model_navigation_state().walking and actor.motion_shapes.size()>=3,"optimized template provides real native convex decomposition and Drive mode")
	if not viewer.get_model_navigation_state().walking:viewer.stop_model_navigation();viewer.set_camera_blocker("qualification",true);return
	var event:=InputEventKey.new();event.keycode=KEY_W;event.physical_keycode=KEY_W;event.pressed=true;get_viewport().push_input(event,true)
	await settle(2.1)
	event=event.duplicate();event.pressed=false;get_viewport().push_input(event,true);await settle()
	check(actor.global_position.z<-1.9 and actor.global_position.z>-2.9 and actor.global_position.y>-0.05 and actor.global_position.y<0.15,"optimized driven geometry passes the doorway, stops at its wall and rests on its GLB floor")
	viewer.stop_model_navigation()
	check(viewer.undo_transform() and actor.global_transform.is_equal_approx(before),"optimized Drive exit joins the existing single-transaction transform undo")
	var panel:SceneManagerPanel=scene.get_node("SceneManagerPanel")
	panel._numeric_edit("position",1,-2);await settle(0.5)
	check(actor.global_position.y>-0.05,"optimized ordinary numeric editing uses solid native-floor contact without Drive")
	actor.global_transform=before;await settle()
	# Native 3D handles require a visible axis and a valid projected world target.
	viewer.camera_controller.position_camera_at(Vector3(4,3,7),Vector3(0,0.8,2))
	var controls:GSModelTransformControls=ui.transform_controls;controls.set_mode(GSModelTransformControls.Mode.ALL);await settle()
	check(controls.runtime.visible and controls.runtime.native.get_world_3d()!=actor.get_world_3d() and not controls.runtime.get_node("%GizmoViewport").get_texture().get_image().is_empty(),"optimized template renders the combined Godot gizmo in its isolated overlay")
	var renders:=controls.runtime.render_requests;await settle()
	check(controls.runtime.render_requests==renders and controls.runtime.get_node("%GizmoViewport").render_target_update_mode==SubViewport.UPDATE_DISABLED,"optimized idle gizmo caches its frame without another continuous 3D pass")
	controls.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	var target:=viewer.get_camera().unproject_position(controls.runtime.proxy.global_position-Vector3(0,0,8))
	controls.begin_drag(2,controls._center);controls.update_drag(target);controls.finish_drag(false)
	await settle(0.5)
	print("RELEASE SOLID GIZMO STOP ",actor.global_position)
	check(actor.global_position.z>-2.9 and actor.global_position.z<-1.9 and not controls.dragging,"optimized ordinary gizmo movement passes the doorway and stops at its back wall")
	actor.global_transform=before
	room.hide();actor.position.y=-1
	var sky:=GSSkySettings.node(viewer);var automatic:bool=sky.auto_exposure;sky.auto_exposure=false
	viewer.camera_controller.position_camera_at(Vector3(0,2,7),Vector3(0,-0.3,2));await settle()
	var point:=Vector3(-0.65,-0.4,2)
	var image:Image=await ViewportCapture.capture_scene_only(get_viewport())
	var pixel:=Vector2i(viewer.get_camera().unproject_position(point)*Vector2(image.get_size())/get_viewport().get_visible_rect().size)
	var with_grid:=image.get_pixelv(pixel)
	var grid:Node3D=scene.get_node("CSGBox3D");grid.hide();await settle()
	image=await ViewportCapture.capture_scene_only(get_viewport());var without_grid:=image.get_pixelv(pixel)
	check(Vector3(with_grid.r,with_grid.g,with_grid.b).distance_to(Vector3(without_grid.r,without_grid.g,without_grid.b))<0.025,"optimized grid and its shadow overlay preserve native pixels below Y=0")
	grid.show();room.show();actor.global_transform=before;sky.auto_exposure=automatic
	viewer.set_camera_blocker("qualification",true)
func mesh_checks(args:PackedStringArray)->void:
	var paths:Array[String]=[]
	for index in range(args.size()-1):
		if args[index]=="--mesh":paths.append(args[index+1])
	if paths.is_empty():return
	var population:int=viewer.total_splats_to_load
	var before:Dictionary={}
	for model in viewer.managed_splats:before[model.model_id]=model.global_transform
	var added:Array[GSSceneMesh]=[]
	for path in paths:
		var started:=Time.get_ticks_msec()
		var mesh:=await viewer.load_mesh_from_path(path,false,GaussianSplat.ImportKind.OBJECT)
		check(mesh!=null and mesh.vertex_count>0,"optimized native glTF importer retains authored mesh content: "+path.get_file())
		if mesh:
			added.append(mesh);print("RELEASE MESH ",path.get_file()," vertices ",mesh.vertex_count," import_ms ",Time.get_ticks_msec()-started)
	var unchanged:bool=viewer.total_splats_to_load==population
	for id in before:unchanged=unchanged and viewer.get_asset_by_id(id).global_transform.is_equal_approx(before[id])
	check(unchanged,"optimized native mesh imports preserve the complete GS atlas and every GS transform")
	if added.is_empty():return
	var mesh:=added[0];var pose:=mesh.global_transform
	mesh.global_transform=Transform3D(Basis.from_euler(Vector3(0.1,0.2,-0.1)).scaled(Vector3(1.1,0.9,1.2)),Vector3(1,0.5,2))
	var edited:=mesh.global_transform
	viewer.select_model_id(mesh.model_id)
	var ui=scene.get_node("ProductionUI");ui.transform_controls.set_mode(GSModelTransformControls.Mode.MOVE)
	viewer.frame_models([mesh.model_id]);await settle(0.8)
	check(ui.transform_controls.toolbar.visible and ui.transform_controls._can_draw,"optimized existing toolbar and gizmo attach to the imported GLB root")
	var world_point:=viewer.get_asset_world_bounds(mesh).get_center()
	var screen:=viewer.get_camera().unproject_position(world_point)*Vector2(get_viewport().size)/get_viewport().get_visible_rect().size
	var clean_image:Image=await ViewportCapture.capture_scene_only(get_viewport())
	var color:=clean_image.get_pixelv(Vector2i(screen)) if clean_image else Color.BLACK
	check(clean_image!=null and maxf(color.r,maxf(color.g,color.b))>0.04,"optimized shadowed native material remains visible with balanced sky fill in a UI-free capture")
	get_viewport().get_texture().get_image().save_png("user://release-mixed-mesh.png")
	var path:="user://release-mixed.pxrscene"
	var mesh_id:=mesh.model_id
	check(await viewer.save_composition(path)==OK and await viewer.open_composition(path)==OK,"optimized mixed composition saves and reopens alongside the full GS population")
	mesh=viewer.get_asset_by_id(mesh_id) as GSSceneMesh
	check(mesh!=null and mesh.global_transform.is_equal_approx(edited) and viewer.total_splats_to_load==population and viewer._mesh_models.size()==added.size(),"optimized mixed reopen preserves exact native transforms, identities and GS population")
	if mesh:mesh.global_transform=pose
func cortex_checks(args:PackedStringArray)->void:
	var brain:Node=get_node("/root/SpatialIntelligence")
	var previous:=SIConfig.settings().experience()
	var saved_connections:=SIConfig.settings().snapshot()
	var ui=scene.get_node("ProductionUI")
	ui._on_cognitive_button_pressed();await settle()
	var panel:CognitivePanel=ui.cognitive_panel
	check(panel.visible and panel.get_node("%WorkspaceTabs").get_tab_count()==3,"optimized release opens the enhanced existing Cortex panel")
	check(panel.get_node("%GoalPicker").item_count==CortexPresets.ORDER.size(),"optimized release exposes the complete guided preset catalog")
	check(not brain.segmentation.is_busy() and not brain.local_runtime.is_running(),"opening packaged Cortex starts no inference")
	panel.choose_preset("connected");SIConfig.settings().update_experience("connected",true);await settle()
	var bounds:=get_viewport().get_visible_rect().grow(1)
	var contained:=true
	for control in [panel.get_node("%Panel"),panel.get_node("%HeaderBar"),panel.close_button,panel.input_field,panel.analyze_button]:
		contained=contained and bounds.encloses(control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size))
	check(contained,"optimized Cortex keeps its header and composer inside the logical viewport with connected Help open")
	panel.get_node("%SharingToggle").button_pressed=true
	check(panel.get_node("%SharingDetails").visible,"optimized assistant disclosure exposes existing connection and sharing controls")
	panel.get_node("%SharingToggle").button_pressed=false
	check(not brain.policy.cloud_enabled and not brain.policy.allows_action(),"optimized disclosure changes grant no transmission or scene actions")
	var result:Dictionary={};brain.segmentation.completed.connect(func(value):result.assign(value))
	var picture:Image
	for index in range(args.size()-1):
		if args[index]=="--cortex-image":picture=Image.load_from_file(args[index+1])
	if picture:
		picture.convert(Image.FORMAT_RGB8)
		panel.choose_preset("find")
		panel._captured({"image":picture,"id":"release-preset-sam3-fixture","signature":brain.scene_signature(viewer),"viewport_size":Vector2(get_viewport().size)})
		panel.get_node("%ConceptPrompt").text="motorcycle";panel.get_node("%SegmentButton").pressed.emit()
		check(brain.segmentation.is_busy(),"guided SAM3 preset starts from its authored Find object button without model-path setup")
		var started:=Time.get_ticks_msec()
		while result.is_empty() and Time.get_ticks_msec()-started<180000:await get_tree().process_frame
		if result.has("error"):print("RELEASE SAM3 ERROR ",result.error)
		check(not result.get("masks",[]).is_empty() and result.get("size",Vector2i.ZERO)==picture.get_size(),"optimized release performs real SAM3 concept inference at original capture dimensions")
		if result.has("preview"):result.preview.save_png("user://release-sam3-mask.png")
	brain.segmentation.release()
	check(brain.local_runtime.start_bundled()==OK,"exported Qwen starts the verified bundled CPU runner")
	var deadline:=Time.get_ticks_msec()+120000
	while brain.local_runtime.is_starting() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(brain.local_runtime.is_running() and brain.local_runtime.message.begins_with("Ready"),"exported Qwen reaches readiness using executable-relative resources")
	var client:=LLMClient.new();client.policy=brain.policy;client.policy.local_enabled=true;add_child(client)
	var reply:={"text":"","error":""}
	client.response_received.connect(func(value):reply.text=value);client.error_occurred.connect(func(value):reply.error=value)
	var profile:=CortexProviders.profile("qwen");profile.max_tokens=24
	client.send_request("Reply with the single word ready.",{},"",profile)
	deadline=Time.get_ticks_msec()+100000
	while client._is_busy and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(not reply.text.is_empty() and reply.error.is_empty(),"optimized release executes real local Qwen inference through the GDScript adapter")
	reply.text="";reply.error=""
	brain.analysis_completed.connect(func(value):reply.text=value);brain.analysis_failed.connect(func(value):reply.error=value)
	panel.choose_preset("scene");panel.get_node("%NewChat").pressed.emit()
	panel.input_field.text="Remember the code word cobalt. Reply with cobalt.";panel.analyze_button.pressed.emit()
	deadline=Time.get_ticks_msec()+100000
	while brain._is_analyzing and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(not reply.text.is_empty() and reply.error.is_empty() and not brain.policy.cloud_enabled,"exported private preset answers through one Ask button without cloud consent or technical setup")
	reply.text="";reply.error=""
	panel.input_field.text="Which code word did I ask you to remember?";panel.analyze_button.pressed.emit()
	deadline=Time.get_ticks_msec()+100000
	while brain._is_analyzing and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(reply.text.to_lower().contains("cobalt") and reply.error.is_empty() and brain.conversations.active().turns.size()==2,"optimized private chat forwards its own history and completes a real follow-up")
	panel.get_node("%NewChat").pressed.emit()
	check(brain.conversations.active().turns.is_empty() and not panel.chat_feed.get_parsed_text().contains("cobalt"),"optimized New chat keeps prior answers out of the new topic")
	check(SIConfig.settings().snapshot()==saved_connections,"exported guided presets preserve all saved advanced connection and model settings")
	client.queue_free();brain.policy.local_enabled=false;brain.local_runtime.stop()
	check(not brain.local_runtime.is_running(),"exported local runner releases its owned process")
	panel.hide_panel()
	SIConfig.settings().update_experience(previous.preset,previous.help_open)
func finish() -> void:
	if is_instance_valid(scene): scene.queue_free()
	for i in range(5): await get_tree().process_frame
	print("RELEASE CHECKS COMPLETE: ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
