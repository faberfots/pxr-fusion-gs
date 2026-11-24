extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:await create_timer(0.25).timeout;await RenderingServer.frame_post_draw
func motion(point:Vector2,held:bool=false)->void:
	var event:=InputEventMouseMotion.new();event.position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;root.push_input(event,true)
func click(point:Vector2,pressed:bool,ctrl:bool=false)->void:
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.ctrl_pressed=ctrl;root.push_input(event,true)
func box_fixture()->String:
	var content:=Node3D.new();var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.mesh.size=Vector3(1.5,2,1);mesh.position.y=1
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(0.65,0.1,0.06);mesh.material_override=material;content.add_child(mesh)
	var document:=GLTFDocument.new();var state:=GLTFState.new();var path:="user://native-gizmo-box.glb"
	check(document.append_from_scene(content,state)==OK and document.write_to_filesystem(state,path)==OK,"native gizmo fixture exports as a real GLB")
	content.free();return path
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://native-gizmo-gs.ply",3));gs.position=Vector3(-3,1,0)
	while viewer.is_loading():await process_frame
	var mesh:=await viewer.load_mesh_from_path(box_fixture(),false,GaussianSplat.ImportKind.OBJECT)
	if not mesh:check(false,"the shared native fixture imports");scene.free();quit(1);return
	var population:=viewer.total_splats_to_load;var gs_pose:=gs.global_transform
	var ui=scene.get_node("ProductionUI");ui.get_node("%MainControls").set_expanded(false)
	var tools:GSModelTransformControls=ui.transform_controls;viewer.select_model_id(mesh.model_id)
	viewer.camera_controller.position_camera_at(Vector3(4,3,7),Vector3(0,1,0));await settle()
	check(tools.mode==GSModelTransformControls.Mode.ALL and tools.runtime.native.mode==Gizmo3D.ToolMode.ALL,"selecting a model shows the combined Godot move/rotate/scale gizmo by default")
	check(mesh.motion_shapes.is_empty() and mesh._motion_job==null,"viewing the default gizmo starts no collision preparation")
	check(tools.runtime.native.get_world_3d()!=mesh.get_world_3d(),"gizmo geometry lives outside the GS/native depth and physics world")
	var overlay:Image=tools.runtime.get_node("%GizmoViewport").get_texture().get_image();var colored:=0
	for y in range(maxi(0,int(tools._center.y)-110),mini(overlay.get_height(),int(tools._center.y)+110)):
		for x in range(maxi(0,int(tools._center.x)-110),mini(overlay.get_width(),int(tools._center.x)+110)):
			var color:=overlay.get_pixel(x,y)
			if color.a>0.1 and maxf(color.r,maxf(color.g,color.b))-minf(color.r,minf(color.g,color.b))>0.2:colored+=1
	check(colored>250,"the runtime renders actual colored 3D arrows, planes and rings")
	# Allow initial window/layout/hover events to settle after GPU readback.
	await settle();await settle()
	var idle:=tools.runtime.render_requests;await settle();await settle()
	print("IDLE GIZMO render requests ",idle," -> ",tools.runtime.render_requests," viewport_mode ",tools.runtime.get_node("%GizmoViewport").render_target_update_mode)
	check(tools.runtime.render_requests==idle and tools.runtime.get_node("%GizmoViewport").render_target_update_mode==SubViewport.UPDATE_DISABLED,"an unchanged gizmo caches its frame instead of continuously rendering another viewport")
	root.get_texture().get_image().save_png("user://native-gizmo-combined.png")
	viewer.mesh_edit_collisions_enabled=false
	var before:=mesh.global_transform;var camera_before:=viewer.get_camera().global_transform
	var point:=tools.runtime.axis_screen(0);motion(point);click(point,true)
	check(tools.dragging,"the actual Godot arrow hit test starts the existing transform transaction")
	motion(point+(point-tools._center).normalized()*35,true);click(point,false);await settle()
	check(mesh.global_position.x>before.origin.x+0.05 and is_equal_approx(mesh.global_position.y,before.origin.y) and is_equal_approx(mesh.global_position.z,before.origin.z),"dragging the real X arrow moves the existing GLB root along world X")
	check(viewer.get_camera().global_transform.is_equal_approx(camera_before),"Godot gizmo input cannot orbit or move the scene camera")
	var moved:=mesh.global_transform
	check(viewer.undo_transform() and mesh.global_transform.is_equal_approx(before) and viewer.undo_transform(true) and mesh.global_transform.is_equal_approx(moved),"a native arrow drag remains one exact undo and redo")
	mesh.global_transform=before;await settle()
	var native:Node3D=tools.runtime.native
	tools.set_mode(GSModelTransformControls.Mode.ROTATE);await settle()
	var radius:float=native._gizmo_scale*Gizmo3D.GIZMO_CIRCLE_SIZE
	point=tools.runtime.camera.unproject_position(native.global_position+Vector3(1,1,0).normalized()*radius)
	motion(point);click(point,true)
	check(tools.dragging and native._edit.mode==Gizmo3D.TransformMode.ROTATE and native._edit.plane==Gizmo3D.TransformPlane.Z,"the actual Z rotation ring is independently selectable")
	motion(tools.runtime.camera.unproject_position(native.global_position+Vector3(-1,1,0).normalized()*radius),true);click(point,false);await settle()
	check(absf(mesh.global_basis.x.y)>0.95,"dragging the native ring rotates the existing model through a quarter turn")
	mesh.global_transform=before;tools.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	point=tools.runtime.camera.unproject_position(native.global_position+(Vector3.RIGHT+Vector3.UP)*native._gizmo_scale*0.4)
	motion(point);click(point,true)
	check(tools.dragging and native._edit.plane==Gizmo3D.TransformPlane.XY,"the actual XY plane handle is independently selectable")
	motion(point+Vector2(22,-16),true);click(point,false);await settle()
	check(mesh.global_position.distance_to(before.origin)>0.05 and absf(mesh.global_position.z-before.origin.z)<0.001,"the native plane drag stays in XY without moving Z")
	mesh.global_transform=before;tools.set_mode(GSModelTransformControls.Mode.SCALE);await settle()
	point=tools._center+Vector2(2,1);motion(point);click(point,true)
	check(tools.dragging,"the authored center cube retains uniform scaling")
	motion(point+Vector2(24,-18),true);click(point,false);await settle()
	check(mesh.scale.x>1.05 and absf(mesh.scale.x-mesh.scale.y)<0.001 and absf(mesh.scale.x-mesh.scale.z)<0.001,"center-cube dragging scales all three axes uniformly")
	mesh.global_transform=before;tools.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	point=tools._center;motion(point);click(point,true);motion(point+Vector2(25,12),true)
	root.focus_exited.emit();await settle()
	check(not tools.dragging and mesh.global_transform.is_equal_approx(before) and not viewer.camera_controller.has_movement_blocker("model_transform"),"focus loss cancels the exact edit and releases its camera blocker")
	mesh.rotation.y=0.7;var local_before:=mesh.global_transform;tools.get_node("%LocalSpace").button_pressed=true;await settle()
	point=tools.runtime.axis_screen(0);motion(point);click(point,true);motion(point+(point-tools._center).normalized()*30,true);click(point,false);await settle()
	var direction:=local_before.basis.x.normalized();var delta:=mesh.global_position-local_before.origin
	check(delta.length()>0.05 and delta.cross(direction).length()<0.001,"Local moves along the model's orientation using the same native handles")
	mesh.global_transform=before;tools.get_node("%LocalSpace").button_pressed=false;await settle()
	point=tools.runtime.axis_screen(0);motion(point);click(point,true,true);motion(point+(point-tools._center).normalized()*85,true);click(point,false);await settle()
	check(absf(mesh.global_position.x-before.origin.x)>0.1 and absf(mesh.global_position.x-roundf(mesh.global_position.x))<0.002,"Ctrl snapping uses Godot's native translation interval")
	mesh.global_transform=before;await settle()
	var scene_camera:=viewer.get_camera();var perspective:=scene_camera.projection;var old_size:=scene_camera.size
	scene_camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene_camera.size=6;await settle()
	check(tools._center.distance_to(tools.runtime.camera.unproject_position(tools.runtime.proxy.global_position))<1,"orthographic overlay projection remains aligned with the scene")
	point=tools.runtime.axis_screen(0);motion(point);click(point,true);motion(point+(point-tools._center).normalized()*30,true);click(point,false);await settle()
	check(mesh.global_position.x>before.origin.x+0.05,"the same native arrow works with an orthographic scene camera")
	scene_camera.projection=perspective;scene_camera.size=old_size;mesh.global_transform=before;await settle()
	mesh.transform_locked=true;await settle()
	check(not tools.runtime.visible and not tools.begin_drag(0,tools._center),"transform locks disable both native geometry and direct edit requests")
	mesh.transform_locked=false;viewer.select_model_id(gs.model_id);tools.set_mode(GSModelTransformControls.Mode.ALL);viewer.frame_models([gs.model_id]);await settle()
	check(tools.runtime.visible and tools._center.distance_to(viewer.get_camera().unproject_position(viewer.get_model_world_bounds(gs).get_center()))<1,"the same Godot gizmo attaches to a GS visual pivot")
	tools.set_mode(GSModelTransformControls.Mode.SELECT);await settle()
	check(not tools.runtime.visible,"Select only remains available without visible gizmo handles")
	check(viewer.total_splats_to_load==population and gs.global_transform.is_equal_approx(gs_pose),"native-only edits preserve the full GS population and its independent pose")
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		mesh.hide()
		var statue:=await viewer.load_mesh_from_path(args[0],false,GaussianSplat.ImportKind.OBJECT)
		if statue:
			viewer.select_model_id(statue.model_id);viewer.frame_models([statue.model_id]);tools.set_mode(GSModelTransformControls.Mode.ALL);await settle()
			root.get_texture().get_image().save_png("user://native-gizmo-real-model.png")
			check(tools.runtime.visible,"the actual user GLB shows the same combined Godot gizmo")
		else:check(false,"the actual user model imports")
	scene.free();await process_frame
	print("NATIVE GIZMO CHECKS COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
