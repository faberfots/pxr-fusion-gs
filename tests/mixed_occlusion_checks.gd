extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:await create_timer(0.65).timeout;await RenderingServer.frame_post_draw
func sample(viewer:GaussianSplattingViewer,world:Vector3)->Color:
	var image:=root.get_texture().get_image();var point:=Vector2i(viewer.get_camera().unproject_position(world)*Vector2(image.get_size())/root.get_visible_rect().size)
	return image.get_pixelv(point.clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=160
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	scene.get_node("ProductionUI").get_node("%MainControls").set_expanded(false);GSSkySettings.node(viewer).auto_exposure=false
	GSColorSettings.apply(viewer.config,GSColorSettings.profile("Natural"))
	var content:=Node3D.new();var native:=MeshInstance3D.new();native.mesh=BoxMesh.new();native.mesh.size=Vector3(1.6,2,0.2);native.position.y=1
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color.GREEN;native.material_override=material;content.add_child(native)
	var document:=GLTFDocument.new();var state:=GLTFState.new();document.append_from_scene(content,state);document.write_to_filesystem(state,"user://occlusion-native.glb");content.free()
	var mesh:=await viewer.load_mesh_from_path("user://occlusion-native.glb",false,GaussianSplat.ImportKind.OBJECT)
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://occlusion-tree.ply",1))
	while viewer.is_loading():await process_frame
	gs.scale=Vector3.ONE*4;gs.position=Vector3(0,1,1)
	viewer.camera_controller.position_camera_at(Vector3(0,1,4),Vector3(0,1,0));await settle()
	for projection in [Camera3D.PROJECTION_PERSPECTIVE,Camera3D.PROJECTION_ORTHOGONAL]:
		viewer.get_camera().projection=projection;viewer.get_camera().size=3
		gs.hide();await settle();var native_only:=sample(viewer,Vector3(0,1,0))
		gs.show();gs.position.z=1;await settle();var front:=sample(viewer,Vector3(0,1,0));var side:=sample(viewer,Vector3(0.65,1,0))
		gs.position.z=-1;await settle();var behind:=sample(viewer,Vector3(0,1,0))
		print("MIXED OCCLUSION ",projection," native ",native_only," GS front ",front," exposed side ",side," GS behind ",behind)
		check(native_only.g>0.75 and front.r>0.3 and front.g<native_only.g-0.1,"foreground GS occludes an imported GLB in projection "+str(projection))
		check(side.g>front.g+0.1,"partial GS coverage leaves the exposed GLB visible in projection "+str(projection))
		check(Vector3(behind.r,behind.g,behind.b).distance_to(Vector3(native_only.r,native_only.g,native_only.b))<0.02,"foreground native GLB occludes GS behind it in projection "+str(projection))
	check(mesh.is_loaded and viewer.total_splats_to_load==1,"bidirectional mixed occlusion preserves native geometry and full GS residency")
	scene.free();await process_frame;print("MIXED OCCLUSION COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
