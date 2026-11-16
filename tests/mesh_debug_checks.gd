extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(0.35).timeout;await RenderingServer.frame_post_draw
func cyan(image:Image,rect:Rect2i)->int:
	var count:=0
	for y in range(maxi(rect.position.y,0),mini(rect.end.y,image.get_height())):
		for x in range(maxi(rect.position.x,0),mini(rect.end.x,image.get_width())):
			var c:=image.get_pixel(x,y)
			if c.g>0.25 and c.b>0.25 and c.g>c.r*1.4 and c.b>c.r*1.4:count+=1
	return count
func source()->String:
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():return args[0]
	var content:=Node3D.new();var mesh:=MeshInstance3D.new();mesh.mesh=SphereMesh.new()
	var material:=StandardMaterial3D.new();material.albedo_color=Color(0.8,0.12,0.08);mesh.material_override=material;content.add_child(mesh)
	var document:=GLTFDocument.new();var state:=GLTFState.new();var path:="user://debug-model.glb"
	check(document.append_from_scene(content,state)==OK and document.write_to_filesystem(state,path)==OK,"native GLB fixture exports")
	content.free();return path
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");ui.get_node("%MainControls").set_expanded(false)
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://debug-environment.ply",3));gs.position=Vector3(-3,1,0)
	while viewer.is_loading():await process_frame
	var population:int=viewer.total_splats_to_load
	var path:=source();var camera_pose:=Transform3D.IDENTITY;var counts:Array[int]=[]
	for debug in [false,true]:
		debug_collisions_hint=debug
		ui.load_zone_panel.hide();await ui._on_files_dropped(PackedStringArray([path]))
		var deadline:=Time.get_ticks_msec()+60000
		while viewer.placement_active and not viewer.get_placement_state().ready and Time.get_ticks_msec()<deadline:await process_frame
		check(viewer.placement_active and viewer.get_placement_state().ready,"actual file drop loads the GLB completely")
		var mesh:GSSceneMesh=viewer._placement.model
		viewer.confirm_model_placement(true);viewer.frame_models([mesh.model_id]);await settle()
		if not debug:camera_pose=viewer.get_camera().global_transform
		else:viewer.camera_controller.set_camera_transform(camera_pose)
		await settle()
		var image:Image=await ViewportCapture.capture_scene_only(root)
		var region:=Rect2i(image.get_width()/4,image.get_height()/8,image.get_width()/2,image.get_height()*3/4)
		counts.append(cyan(image,region));image.save_png("user://mesh-debug-on.png" if debug else "user://mesh-debug-off.png")
		var center:=viewer.get_asset_world_bounds(mesh).get_center()
		var hit:={"done":false,"id":""};var callback:=func(_id,id,_point):hit.done=true;hit.id=id
		viewer.model_probe_completed.connect(callback)
		viewer.request_model_probe(viewer.get_camera().unproject_position(center)*Vector2(root.size)/root.get_visible_rect().size)
		deadline=Time.get_ticks_msec()+5000
		while not hit.done and Time.get_ticks_msec()<deadline:await process_frame
		viewer.model_probe_completed.disconnect(callback)
		check(hit.id==mesh.model_id,"visible-model picking survives the collision-debug setting")
		mesh.free();await settle()
	print("CYAN PIXELS off ",counts[0]," on ",counts[1])
	check(counts[1]<=counts[0]+300,"collision debug cannot cover imported materials with a cyan mesh")
	check(debug_collisions_hint and viewer.total_splats_to_load==population,"global collision debugging and existing GS residency stay enabled and unchanged")
	scene.free();await process_frame
	print("MESH DEBUG COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
