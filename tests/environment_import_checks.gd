extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
var camera_events:Array[Dictionary]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	for i in range(4):await physics_frame
	await create_timer(0.15).timeout
func loaded(viewer:GaussianSplattingViewer)->void:
	while viewer.is_loading():await process_frame
	await settle()
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI")
	ui.get_node("%MainControls").set_expanded(false)
	viewer.camera_controller.position_camera_at(Vector3(0,3,5),Vector3.ZERO)
	viewer.event_bus.event_emitted.connect(func(kind,payload):
		if kind==GSEventBus.EVENT_CAMERA_POSITIONED:camera_events.append(payload)
	)
	var pixel:=viewer.get_camera().unproject_position(Vector3(3,0,0))
	check(viewer.begin_model_placement(Checks.fixture("user://environment-wide.ply",32),pixel)==OK,"wide environment begins through the normal interactive import route")
	var environment:GaussianSplat=viewer._placement.model
	await loaded(viewer)
	check(not viewer.placement_active and environment.visible,"Auto environment bypasses point placement and becomes visible")
	check(environment.global_transform.is_equal_approx(Transform3D.IDENTITY),"environment source pose remains unchanged despite the chosen drop point")
	check(viewer.get_camera().global_position.distance_to(Vector3(-15.5,1.7,0))<0.001,"environment entry restores the sample-centred eye-level camera")
	check(camera_events.size()==1 and camera_events[0].model_id==environment.model_id,"environment framing preserves the public camera-positioned event contract")
	var environment_id:=environment.model_id
	var entry_pose:=viewer.get_camera().global_transform
	var environment_pose:=environment.global_transform
	var small:=Checks.fixture("user://environment-small.ply",3)
	check(viewer.begin_model_placement(small,pixel)==OK,"Auto retains interactive surface placement for small objects")
	await loaded(viewer)
	var object:GaussianSplat=viewer._placement.model
	check(viewer.placement_active and viewer.get_placement_state().ready,"small object remains pending for placement")
	viewer.confirm_model_placement(true)
	object.position=Vector3(300,20,400);object.scale=Vector3.ONE*30
	check(object.import_kind==GaussianSplat.ImportKind.OBJECT,"Auto classification remains Object after later scaling")
	var object_pose:=object.global_transform
	viewer.camera_controller.go_home()
	ui.get_node("%CameraPanel").get_node("%Home").pressed.emit()
	check(viewer.get_camera().global_transform.is_equal_approx(entry_pose),"Home returns inside the environment even when an object is selected")
	check(object.global_transform.is_equal_approx(object_pose),"environment navigation preserves existing object placement")
	var orbit:=viewer.camera_controller.get_node("OrbitCamera") as CameraInterface
	viewer.camera_controller.set_camera(orbit)
	check(viewer.enter_environment(environment) and viewer.get_camera() is FreeLookCamera,"Enter environment selects the walkthrough camera")
	await settle()
	check(viewer.get_camera().global_transform.is_equal_approx(entry_pose),"environment view remains stable after orbit-to-free switching")
	check(viewer.frame_models([environment_id]) and viewer.get_camera().global_transform.is_equal_approx(entry_pose),"Frame selected enters an environment instead of framing its underside")
	check(viewer.begin_model_placement(Checks.fixture("user://large-object.ply",32),pixel,GaussianSplat.ImportKind.OBJECT)==OK,"a large object can override automatic environment detection")
	await loaded(viewer)
	check(viewer.placement_active and not viewer._placement.model.visible,"explicit large Object still waits for chosen placement")
	viewer.cancel_model_placement()
	check(viewer.begin_model_placement(small,pixel,GaussianSplat.ImportKind.ENVIRONMENT)==OK,"a small environment can override automatic object detection")
	var small_environment:GaussianSplat=viewer._placement.model
	await loaded(viewer)
	check(not viewer.placement_active and small_environment.visible and small_environment.global_transform.is_equal_approx(Transform3D.IDENTITY),"explicit Environment bypasses placement regardless of size")
	check(viewer.get_camera().global_position.distance_to(Vector3(-1,1.7,0))<0.001,"each environment entry uses its own samples instead of distant objects or other environments")
	viewer.camera_controller.position_camera_at(Vector3(0,3,5),Vector3.ZERO)
	await settle()
	pixel=viewer.get_camera().unproject_position(Vector3(3,0,0))
	check(viewer.begin_model_placement(small,pixel,GaussianSplat.ImportKind.OBJECT)==OK,"a pending object can be reclassified without reloading")
	await loaded(viewer)
	var switched:GaussianSplat=viewer._placement.model
	var initial:=viewer._placement.initial_node
	check(not switched.global_transform.is_equal_approx(initial),"object preview has moved before its type is changed")
	ui.get_node("%PlacementHUD").get_node("%ImportKind").item_selected.emit(2)
	await settle()
	check(not viewer.placement_active and switched.global_transform.is_equal_approx(initial),"switching preview to Environment restores its initial source pose")
	var navigator=scene.get_node("SceneManagerPanel")
	viewer.select_model_id(environment_id)
	navigator.get_node("%ContentKind").item_selected.emit(2)
	check(environment.import_kind==GaussianSplat.ImportKind.ENVIRONMENT,"Scene Navigator edits the selected node's import intent")
	var saved_camera:=viewer.get_camera().global_transform
	var path:="user://environment-combined.pxrscene"
	check(await viewer.save_composition(path)==OK,"combined scene saves import intent alongside exact model transforms")
	check(await viewer.open_composition(path)==OK,"new scene document reopens successfully")
	viewer.select_model_id(environment_id);environment=viewer.get_selected_model()
	check(environment.import_kind==GaussianSplat.ImportKind.ENVIRONMENT and environment.global_transform.is_equal_approx(environment_pose),"environment type and original full matrix survive reopening")
	check(not viewer.placement_active and viewer.get_camera().global_transform.is_equal_approx(saved_camera),"saved scenes restore their camera exactly without triggering import reframing")
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	for entry in document.models:entry.erase("import_kind")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(document));file.close()
	check(await viewer.open_composition(path)==OK,"older version-one documents without import intent remain compatible")
	ui.get_node("%ImportKind").select(2)
	ui.file_dialog.file_selected.emit(small)
	await loaded(viewer)
	check(not viewer.placement_active and viewer.get_selected_model().import_kind==GaussianSplat.ImportKind.ENVIRONMENT,"file picker honors the authored Environment import selector")
	ui.get_node("%ImportKind").select(1)
	await ui._on_files_dropped(PackedStringArray([small]))
	await loaded(viewer)
	check(viewer.placement_active and viewer._placement.model.import_kind==GaussianSplat.ImportKind.OBJECT,"file drop honors the same Object override")
	viewer.cancel_model_placement()
	ui._on_clear_scene_pressed()
	ui.get_node("%CameraPanel").get_node("%Home").pressed.emit()
	check(viewer.get_camera().global_position.is_equal_approx(viewer.camera_controller.safety.home_position),"empty-scene Home retains the established elevated studio view")
	scene.free()
	for i in range(4):await process_frame
	print("ENVIRONMENT IMPORT COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
