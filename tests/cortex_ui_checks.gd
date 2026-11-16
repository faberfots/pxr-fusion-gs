extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
var brain:Node
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func click(control:Control)->void:
	var parent:=control.get_parent()
	while parent:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await process_frame;await process_frame
	var position:=control.get_global_transform_with_canvas()*(control.size*0.5)
	var move:=InputEventMouseMotion.new();move.position=position;root.push_input(move,true)
	await process_frame
	for pressed in [true,false]:
		var button:=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_LEFT;button.pressed=pressed;button.position=position;root.push_input(button,true);await process_frame
func run()->void:
	brain=root.get_node("SpatialIntelligence")
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=160
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");ui._on_cognitive_button_pressed()
	var panel:CognitivePanel=ui.cognitive_panel
	await create_timer(0.3).timeout
	check(panel.visible and panel.get_node("%WorkspaceTabs").get_tab_count()==3,"existing Cortex launcher opens the enhanced Ask/Select/Setup panel")
	check(panel.draggable_container.scale==Vector2.ONE*0.67,"Cortex preserves the existing compact HUD density")
	check(not brain.segmentation.is_processing() and not brain.segmentation.is_busy(),"opening Cortex starts no segmentation or background inference")
	await click(panel.get_node("%SetupShortcut"))
	check(panel.get_node("%WorkspaceTabs").current_tab==2,"actual pointer input opens Setup inside the existing panel")
	SIConfig.settings().select("ollama");panel.get_node("%ModelName").text="qwen/test:8b"
	check(panel.apply_connection()==OK,"model names with runtime namespaces are configurable from the existing panel")
	var source:=Checks.fixture("user://cortex-pick.ply",1);var model:=viewer.load_new_splat_from_path(source)
	while viewer.is_loading():await process_frame
	model.position=Vector3(0,1,0);viewer.camera_controller.position_camera_at(Vector3(0,1,3),Vector3(0,1,0))
	await create_timer(0.4).timeout
	var camera:=viewer.get_camera().global_transform;var pose:=model.global_transform
	panel.get_node("%WorkspaceTabs").current_tab=1
	await click(panel.get_node("%CaptureButton"));await create_timer(0.3).timeout
	check(not panel._capture.is_empty() and panel.get_node("%SnapshotCanvas").image!=null,"Select captures the clean scene without starting inference")
	if panel._capture.is_empty():print("CAPTURE STATUS ",panel.get_node("%SegmentationStatus").text);scene.free();quit(1);return
	var canvas:CortexSegmentationCanvas=panel.get_node("%SnapshotCanvas")
	var rectangle:=canvas.image_rect();var mapped:=canvas.image_pixel(rectangle.get_center())
	check(mapped.distance_to(Vector2(canvas.image.get_size())*0.5)<1,"letterboxed preview coordinates map to the original image independently of HUD scaling")
	await click(canvas)
	check(canvas.points.size()==1 and canvas.labels[0]==1,"actual pointer input adds a foreground prompt to the captured image")
	panel.segment_capture();panel._cancel_segmentation()
	var cancel_deadline:=Time.get_ticks_msec()+5000
	while panel.brain.segmentation.is_processing() and Time.get_ticks_msec()<cancel_deadline:await process_frame
	check(panel.get_node("%SegmentationStatus").text.begins_with("Cancelled") and not panel.get_node("%SegmentButton").disabled,"cancellation restores usable controls and a truthful final status")
	var received:=[false];var identity:=[""]
	viewer.model_probe_completed.connect(func(_id,model_id,_position):received[0]=true;identity[0]=model_id)
	viewer.request_model_probe(Vector2(root.size)*0.5)
	var deadline:=Time.get_ticks_msec()+5000
	while not received[0] and Time.get_ticks_msec()<deadline:await process_frame
	check(received[0] and identity[0]==model.model_id,"Cortex's read-only probe resolves the actual existing GPU model identity")
	check(viewer.get_camera().global_transform.is_equal_approx(camera) and model.global_transform.is_equal_approx(pose),"Cortex model probing leaves the camera and model transform unchanged")
	panel.get_node("%WorkspaceTabs").current_tab=0
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("user://cortex-ask.png")
	panel.get_node("%WorkspaceTabs").current_tab=2
	await create_timer(0.15).timeout;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("user://cortex-setup.png")
	await click(panel.close_button)
	check(not panel.visible,"the original close control still closes Cortex")
	scene.free();await process_frame;await process_frame
	check(not is_instance_valid(panel),"viewer teardown releases the lazily created Cortex panel")
	print("CORTEX UI COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
