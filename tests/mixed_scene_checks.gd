extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle(seconds:float=0.2)->void:
	await create_timer(seconds).timeout;await RenderingServer.frame_post_draw
func wait_placement(viewer:GaussianSplattingViewer)->void:
	var deadline:=Time.get_ticks_msec()+60000
	while viewer.placement_active and not viewer.get_placement_state().ready and Time.get_ticks_msec()<deadline:await process_frame
func write(path:String,value:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()
func pointer(point:Vector2,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func motion(point:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=point;root.push_input(event,true)
func probe(viewer:GaussianSplattingViewer,world:Vector3)->String:
	var state:={"done":false,"id":""}
	var callback:=func(_request,id,_point):state.done=true;state.id=id
	viewer.model_probe_completed.connect(callback)
	viewer.request_model_probe(viewer.get_camera().unproject_position(world)*Vector2(root.size)/root.get_visible_rect().size)
	var deadline:=Time.get_ticks_msec()+5000
	while not state.done and Time.get_ticks_msec()<deadline:await process_frame
	viewer.model_probe_completed.disconnect(callback)
	return state.id
func floor_fixture()->String:
	var folder:="user://native-fixture";DirAccess.make_dir_recursive_absolute(folder)
	var bytes:=PackedFloat32Array([-2,1,-2,2,1,-2,2,1,2,-2,1,2,0,1,0,0,1,0,0,1,0,0,1,0,0,0,1,0,1,1,0,1]).to_byte_array()
	for value in [0,2,1,0,3,2]:bytes.append(value);bytes.append(0)
	var file:=FileAccess.open(folder+"/floor.bin",FileAccess.WRITE);file.store_buffer(bytes);file.close()
	var image:=Image.create(4,4,false,Image.FORMAT_RGB8);image.fill(Color(0.2,0.5,0.7));image.save_png(folder+"/floor.png")
	var document:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0}],"buffers":[{"uri":"floor.bin","byteLength":140}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":48},{"buffer":0,"byteOffset":48,"byteLength":48},{"buffer":0,"byteOffset":96,"byteLength":32},{"buffer":0,"byteOffset":128,"byteLength":12}],"accessors":[{"bufferView":0,"componentType":5126,"count":4,"type":"VEC3","min":[-2,1,-2],"max":[2,1,2]},{"bufferView":1,"componentType":5126,"count":4,"type":"VEC3"},{"bufferView":2,"componentType":5126,"count":4,"type":"VEC2"},{"bufferView":3,"componentType":5123,"count":6,"type":"SCALAR"}],"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"material":0}]}],"materials":[{"doubleSided":true,"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0.0,"roughnessFactor":1.0}}],"textures":[{"source":0}],"images":[{"uri":"floor.png"}]}
	write(folder+"/floor.gltf",document);return folder+"/floor.gltf"
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=256
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");var controls:GSModelTransformControls=ui.transform_controls
	# Preserve explicit unrestricted authoring checks; default solid manipulation
	# and contacts are qualified separately by solid_edit_checks.
	controls.get_node("%SolidEdits").button_pressed=false
	if args.is_empty():
		await contract_checks(scene,viewer);scene.free();await process_frame
		print("MIXED SCENE COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1);return
	var mesh:=await viewer.load_mesh_from_path(args[0],false,GaussianSplat.ImportKind.OBJECT)
	check(mesh!=null and mesh.is_loaded and viewer.get_asset_snapshot().size()==1 and viewer.get_model_snapshot().is_empty(),"GLB uses native geometry and shared asset identity without allocating a splat record")
	if not mesh:scene.free();quit(1);return
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://mixed-splat.ply",3))
	while viewer.is_loading():await process_frame
	viewer.set_asset_edit_transform(gs,Transform3D(Basis.IDENTITY,Vector3(-1,1,0)))
	mesh.position=Vector3(1,0,0)
	viewer.camera_controller.position_camera_at(Vector3(0,1.4,5),Vector3(0,1,0));await settle(0.5)
	viewer.select_model_id(mesh.model_id);controls.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	check(viewer.get_selected_asset()==mesh and controls.toolbar.visible and controls._can_draw,"selecting GLB attaches the existing transform toolbar and gizmo")
	var original:=mesh.global_transform;var gs_original:=gs.global_transform
	check(controls.begin_drag(0,controls._center),"the existing X-axis gizmo starts a native mesh edit")
	controls.update_drag(controls._center+Vector2(35,0));controls.finish_drag(false)
	await settle()
	check(not mesh.global_transform.is_equal_approx(original) and gs.global_transform.is_equal_approx(gs_original),"shared gizmo moves the mesh and preserves the other GS asset")
	check(viewer.undo_transform() and mesh.global_transform.is_equal_approx(original) and viewer.undo_transform(true),"existing undo and redo restore mesh transforms")
	viewer.select_model_ids([gs.model_id,mesh.model_id]);await settle()
	var before_gs:=viewer.get_asset_edit_transform(gs);var before_mesh:=mesh.global_transform
	controls.begin_drag(0,controls._center);controls.update_drag(controls._center+Vector2(30,0));controls.finish_drag(false)
	await settle()
	check((viewer.get_asset_edit_transform(gs).origin-before_gs.origin).is_equal_approx(mesh.global_position-before_mesh.origin),"mixed multi-selection uses one world-space gizmo delta across GS coordinate conversion and native mesh roots")
	viewer.undo_transform()
	viewer.select_model_id(mesh.model_id);mesh.transform_locked=true
	check(not controls.begin_drag(0,controls._center),"asset lock blocks shared gizmo edits without changing selection")
	mesh.transform_locked=false
	mesh.global_transform=Transform3D(Basis.from_euler(Vector3(0.1,0.3,-0.1)).scaled(Vector3(1.2,0.8,1.1)),Vector3(1,0,0))
	var pose:=mesh.global_transform
	var mesh_id:=mesh.model_id
	await settle()
	var image_point:=viewer.get_camera().unproject_position(viewer.get_asset_world_bounds(mesh).get_center())*Vector2(root.size)/root.get_visible_rect().size
	var probe:={"done":false,"id":""}
	viewer.model_probe_completed.connect(func(_request,id,_point):probe.done=true;probe.id=id)
	viewer.request_model_probe(image_point)
	var deadline:=Time.get_ticks_msec()+5000
	while not probe.done and Time.get_ticks_msec()<deadline:await process_frame
	check(probe.done and probe.id==mesh.model_id,"shared visible-model probe resolves a native mesh to its imported root identity")
	controls.set_mode(GSModelTransformControls.Mode.SELECT);viewer.select_model_id("");await settle()
	var click_point:=image_point*root.get_visible_rect().size/Vector2(root.size)
	motion(click_point);pointer(click_point,true);pointer(click_point,false);await settle(0.5)
	check(viewer.get_selected_asset()==mesh,"actual left click selects the imported GLB root")
	for mode in [GSModelTransformControls.Mode.MOVE,GSModelTransformControls.Mode.ROTATE,GSModelTransformControls.Mode.SCALE]:
		controls.set_mode(mode);await settle()
		var start:=controls._center
		var before:=mesh.global_transform
		motion(start);pointer(start,true);motion(start+Vector2(24,-15));pointer(start+Vector2(24,-15),false);await settle()
		check(not mesh.global_transform.is_equal_approx(before) and not controls.dragging,"actual pointer gizmo edit works for native mode "+str(mode))
		viewer.undo_transform();await settle()
	mesh.global_transform=pose
	var path:="user://mixed-project.pxrscene"
	viewer.select_model_ids([gs.model_id,mesh.model_id])
	check(await viewer.save_composition(path)==OK,"mixed composition saves through the existing scene command")
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(document.version==2 and document.models.size()==2,"mixed schema records explicit mesh type without counting vertices as splats")
	check(await viewer.open_composition(path)==OK,"mixed composition reopens through the existing protected transaction")
	mesh=viewer.get_asset_by_id(mesh_id) as GSSceneMesh
	check(mesh!=null and mesh.global_transform.is_equal_approx(pose) and viewer.total_splats_to_load==3 and viewer.selected_model_ids.size()==2,"reopening preserves stable identities, full GS count, exact nonuniform mesh transform and mixed selection")
	check(await viewer.add_composition(path)==OK and viewer.managed_assets.size()==4 and viewer.total_splats_to_load==6,"adding a mixed composition preserves existing assets and remaps duplicate identities")
	check("*.glb" in str(ui.file_dialog.filters),"the existing Import dialog exposes native mesh formats")
	ui._on_scene_manager_pressed();await settle()
	check(ui.scene_manager_panel.selected_node!=null,"the existing Scene navigator manages mixed asset selection")
	check(root.get_visible_rect().grow(1).encloses(GSUiScale.screen_rect(ui.scene_manager_panel.draggable_container)),"mixed asset details and portable-save controls fit the existing responsive Scene navigator")
	root.get_texture().get_image().save_png("user://mixed-navigator.png")
	ui.scene_manager_panel.hide_panel();controls.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	root.get_texture().get_image().save_png("user://mixed-statue.png")
	if args.size()>1:
		var city:=await viewer.load_mesh_from_path(args[1],false,GaussianSplat.ImportKind.ENVIRONMENT)
		check(city!=null and city.vertex_count>1000000 and viewer.enter_environment(city),"provided city environment imports at its source pose with frame/home navigation")
		if city:
			viewer.select_model_id(city.model_id);await settle(0.5)
			root.get_texture().get_image().save_png("user://mixed-city.png")
			check(city.transparent_surfaces>0,"native city glass is preserved and accurately identified as native fallback")
	viewer._clear_scene_and_reset_atlas();await settle()
	check(viewer.managed_assets.is_empty() and viewer.total_splats_to_load==0,"existing Clear removes mesh and GS assets together")
	check(viewer.begin_model_placement(args[0],Vector2.INF,GaussianSplat.ImportKind.OBJECT)==OK,"GLB enters the existing interactive placement workflow")
	await wait_placement(viewer)
	check(viewer.placement_active and viewer.get_placement_state().ready and viewer.confirm_model_placement(true),"native placement supports Keep original through the existing HUD")
	viewer._clear_scene_and_reset_atlas();await settle()
	viewer.begin_model_placement(args[0]);viewer.cancel_model_placement();await settle(0.4)
	check(not viewer.placement_active and viewer.managed_assets.is_empty(),"cancelling an import prevents a late native result from reappearing")
	while viewer.is_loading():await process_frame
	await contract_checks(scene,viewer)
	scene.free();await process_frame
	print("MIXED SCENE COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func contract_checks(scene:Node,viewer:GaussianSplattingViewer)->void:
	var floor_path:=floor_fixture()
	var floor_mesh:=await viewer.load_mesh_from_path(floor_path,false,GaussianSplat.ImportKind.OBJECT)
	check(floor_mesh!=null and floor_mesh.fingerprints.size()==3,"external glTF resolves and fingerprints geometry plus texture dependencies")
	if not floor_mesh:return
	var sky:Sky3D=scene.get_node("Sky3D")
	check(is_equal_approx(sky.sky_contribution,0.7),"first mesh balances factory-default sky lighting through the existing owner")
	var saved_sky:=GSSkySettings.snapshot(sky)
	var saved_grade:=GSColorSettings.snapshot(viewer.config)
	sky.sky_contribution=0.4;sky.ambient_energy=0.8
	check(not GSSkySettings.soft_mesh_lighting(sky,true) and is_equal_approx(sky.sky_contribution,0.4),"automatic mesh lighting preserves customized atmosphere controls")
	var sky_controls=scene.get_node("ProductionUI").get_node("%LightingPanel").get_node("%SkyControls")
	sky_controls.get_node("%MeshLight").pressed.emit()
	check(is_equal_approx(sky.sky_contribution,0.7) and GSColorSettings.snapshot(viewer.config)==saved_grade,"authored Soft mesh lighting command reuses Sky3D fields without changing GS grading")
	GSSkySettings.apply(sky,saved_sky)
	await physics_frame
	var previous:=Transform3D(Basis.IDENTITY,Vector3(0,3,0));var desired:=Transform3D(Basis.IDENTITY,Vector3(0,0.5,0))
	var constrained:=viewer.camera_controller.constrain_pose(previous,desired)
	check(constrained.origin.y>1.0,"existing protected camera sweeps against imported native geometry")
	var ui=scene.get_node("ProductionUI");ui.get_node("%MainControls").set_expanded(false)
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://occlusion.ply",1))
	while viewer.is_loading():await process_frame
	gs.scale=Vector3.ONE*5;gs.position=Vector3(0,2,0)
	viewer.camera_controller.position_camera_at(Vector3(0,5,5),Vector3(0,1,0));await settle(0.6)
	check(await probe(viewer,Vector3(0,2,0))==gs.model_id,"visible GS in front of an imported opaque mesh remains selectable")
	gs.position.y=0;await settle(0.4)
	check(await probe(viewer,Vector3.ZERO)==floor_mesh.model_id,"opaque imported geometry wins selection over a GS hidden behind it")
	var stale:={"done":false,"id":"unexpected"};var callback:=func(_request,id,_point):stale.done=true;stale.id=id
	viewer.model_probe_completed.connect(callback)
	viewer.request_model_probe(viewer.get_camera().unproject_position(Vector3(0,1,0))*Vector2(root.size)/root.get_visible_rect().size)
	var fov:=viewer.get_camera().fov;viewer.get_camera().fov+=1;await settle(0.5)
	check(stale.done and stale.id.is_empty(),"mixed selection rejects a result captured under a stale camera lens")
	viewer.model_probe_completed.disconnect(callback);viewer.get_camera().fov=fov;await settle()
	gs.hide();await settle()
	var cursor:=viewer.get_camera().unproject_position(Vector3(0,1,0))
	viewer.begin_model_placement(Checks.fixture("user://on-native.ply",1),cursor,GaussianSplat.ImportKind.OBJECT)
	await wait_placement(viewer);await settle(0.4)
	check(viewer.get_placement_state().surface=="Scene geometry" and viewer.get_placement_state().target.distance_to(Vector3(0,1,0))<0.03,"the shared placement workflow places GS on native mesh surfaces")
	viewer.cancel_model_placement();await settle()
	floor_mesh.hide();gs.show();gs.position.y=2;await settle()
	cursor=viewer.get_camera().unproject_position(Vector3(0,2,0))
	viewer.begin_model_placement(floor_path,cursor,GaussianSplat.ImportKind.OBJECT)
	await wait_placement(viewer);await settle(0.6)
	var placement:=viewer.get_placement_state();print("NATIVE ON GS PLACEMENT ",placement)
	check(placement.surface=="GS surface" and viewer.confirm_model_placement(),"the same placement workflow places a native mesh on a GS surface")
	viewer._clear_scene_and_reset_atlas();await settle()
	floor_mesh=await viewer.load_mesh_from_path(floor_path,false,GaussianSplat.ImportKind.OBJECT);floor_mesh.transform_locked=true
	viewer.camera_controller.position_camera_at(Vector3(0,5,5),Vector3(0,1,0));await settle()
	var held:=floor_mesh.global_transform
	ui._on_scene_manager_pressed();await settle()
	viewer.select_model_id(floor_mesh.model_id);await settle()
	var manager=ui.scene_manager_panel
	manager._numeric_edit("position",0,5)
	check(floor_mesh.global_transform.is_equal_approx(held) and not manager.pos_x.editable,"existing numeric controls honor the same native transform lock")
	manager.hide_panel()
	var path:="user://portable-mixed.pxrscene"
	check(await viewer.save_composition(path,true)==OK,"Include asset files creates a portable scene through the existing save command")
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var portable:=true
	for entry in document.models:
		portable=portable and entry.relative_source.begins_with("portable-mixed.pxrscene.assets-")
		entry.source="Z:/unavailable-original.gltf"
		for dependency in entry.get("dependencies",[]):dependency.source="Z:/unavailable-original.bin"
	write(path,document)
	check(portable and await viewer.open_composition(path)==OK,"portable scene reopens using only bundled relative files with original absolute locations unavailable")
	floor_mesh=viewer.managed_assets[0] as GSSceneMesh
	check(floor_mesh.transform_locked and floor_mesh.fingerprints.size()==3 and floor_mesh.global_transform.is_equal_approx(held),"portable reload preserves dependencies, transform and lock")
	var brain:Node=root.get_node("SpatialIntelligence")
	var signature:String=brain.scene_signature(viewer)
	floor_mesh.position.x+=0.1;await settle()
	var context:=SceneContext.get_context_payload(viewer.get_camera());var found:=false
	for item in context.visible_objects:
		if item.model_id==floor_mesh.model_id and item.asset_type=="mesh" and item.vertex_count==4:found=true
	check(found and brain.scene_signature(viewer)!=signature,"Cortex context identifies native geometry and invalidates captured selection after its transform changes")
	floor_mesh.global_transform=held;await settle()
	var saved_hash:=FileAccess.get_sha256(path)
	var cancellation:=func(message):
		if message.begins_with("Including "):viewer._composition.cancel()
	viewer.composition_progress.connect(cancellation)
	check(await viewer.save_composition(path,true)==ERR_SKIP,"portable copy cancellation completes the user operation")
	viewer.composition_progress.disconnect(cancellation);await settle()
	check(FileAccess.get_sha256(path)==saved_hash,"cancelled portable save preserves the previous scene byte-for-byte")
	var action:=ActionController.new();action.policy=AIAccessPolicy.new();root.add_child(action)
	check(action.execute_action("select_object",{"model_id":floor_mesh.model_id}).status=="error","existing Cortex read-only policy denies native selection actions")
	action.policy.role=AIAccessPolicy.Role.OPERATOR;action.policy.actions_enabled=true
	check(action.execute_action("select_object",{"model_id":floor_mesh.model_id}).status=="success" and action.execute_action("reset_view",{}).status=="success","authorized Cortex tools reuse native selection and frame commands")
	action.free()
	var broken:=Checks.fixture("user://mixed-broken.ply",1)
	var text:=FileAccess.get_file_as_string(broken).replace("0 0 0 -3","nan 0 0 -3")
	var file:=FileAccess.open(broken,FileAccess.WRITE);file.store_string(text);file.close()
	gs=viewer.load_new_splat_from_path(Checks.fixture("user://rollback-native.ply",3))
	while viewer.is_loading():await process_frame
	viewer.select_model_id(floor_mesh.model_id)
	var bad:=GSComposition.capture(viewer,"user://mixed-bad.pxrscene")
	for entry in bad.models:
		if entry.get("asset_type","")!="mesh":entry.source=ProjectSettings.globalize_path(broken);entry.relative_source="mixed-broken.ply";entry.bytes=FileAccess.get_file_as_bytes(broken).size();entry.sha256=FileAccess.get_sha256(broken);entry.splats=1
	write("user://mixed-bad.pxrscene",bad)
	var old_id:=floor_mesh.model_id
	check(await viewer.open_composition("user://mixed-bad.pxrscene")!=OK and viewer.get_asset_by_id(old_id)==floor_mesh and floor_mesh.transform_locked and viewer.total_splats_to_load==3,"failed mixed replacement restores the exact native root and resident GS atlas")
	check(await viewer.add_composition("user://mixed-bad.pxrscene")!=OK and viewer.managed_assets.size()==2 and viewer.get_asset_by_id(old_id)==floor_mesh and viewer.total_splats_to_load==3,"failed mixed append removes only new assets and retains the original composition")
	var population:int=viewer.total_splats_to_load
	viewer.begin_model_placement(floor_path,Vector2.INF,GaussianSplat.ImportKind.ENVIRONMENT,true)
	var deadline:=Time.get_ticks_msec()+10000
	while viewer.placement_active and Time.get_ticks_msec()<deadline:await process_frame
	check(viewer.managed_assets.size()==1 and viewer.managed_assets[0] is GSSceneMesh and viewer.total_splats_to_load==0 and population==3,"checked native environment import replaces once at its authored pose")
	floor_mesh=viewer.managed_assets[0] as GSSceneMesh;old_id=floor_mesh.model_id
	# Test-owned malformed input must fail before a requested replacement clears assets.
	write("user://bad-native.gltf",{"asset":3})
	check(await viewer.load_mesh_from_path("user://bad-native.gltf",true)==null and viewer.get_asset_by_id(old_id)==floor_mesh,"malformed glTF rejects a replacement without touching the current scene")
	var dependency:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(floor_path));dependency.buffers[0].uri="missing.bin";write("user://missing-dependency.gltf",dependency)
	check(viewer.begin_model_placement("user://missing-dependency.gltf",Vector2.INF,GaussianSplat.ImportKind.OBJECT,true)!=OK and viewer.managed_assets.size()==1,"missing mesh dependencies fail before starting or clearing a scene")
	root.get_texture().get_image().save_png("user://mixed-native-controls.png")
	viewer.begin_model_placement(floor_path)
	var ref:WeakRef=weakref(viewer)
	viewer.cancel_model_placement()
	await settle(0.2)
	check(not viewer.placement_active,"final pending native placement can be cancelled")
	# Use an independent viewer for the lifecycle check; the caller owns scene cleanup.
	var closing:=GaussianSplattingViewer.new();closing.config=GaussianSplattingConfig.create_default();closing.config.memory_max_vram_budget_mb=256;root.add_child(closing)
	closing.begin_model_placement(floor_path);ref=weakref(closing);closing.queue_free();await settle(0.4)
	check(ref.get_ref()==null,"teardown during a native import drains work without retaining the viewer")
	closing=GaussianSplattingViewer.new();closing.config=GaussianSplattingConfig.create_default();closing.config.memory_max_vram_budget_mb=256;root.add_child(closing)
	closing.open_composition(path)
	deadline=Time.get_ticks_msec()+5000
	while closing._mesh_job==null and closing.composition_busy and Time.get_ticks_msec()<deadline:await process_frame
	ref=weakref(closing);closing.queue_free();await settle(0.4)
	check(ref.get_ref()==null and GSComposition._active.is_empty(),"teardown during mixed composition staging also drains its transaction")
