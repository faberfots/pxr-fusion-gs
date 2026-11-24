extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:await create_timer(0.35).timeout;await RenderingServer.frame_post_draw
func ready(viewer:GaussianSplattingViewer,model:GSSceneMesh)->bool:
	var deadline:=Time.get_ticks_msec()+120000
	while not viewer.prepare_asset_edits([model.model_id]) and Time.get_ticks_msec()<deadline:await process_frame
	var result:=viewer.prepare_asset_edits([model.model_id])
	print("SHAPE READINESS ",result," parts ",model.geometry_parts.size()," shapes ",model.motion_shapes.size()," error ",model.motion_error," processing ",model.is_processing())
	return result
func fixture(path:String,position:Vector3,size:Vector3)->String:
	var content:=Node3D.new();var node:=MeshInstance3D.new();node.mesh=BoxMesh.new();node.mesh.size=size;node.position=position
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(0.85,0.06,0.04);node.material_override=material;content.add_child(node)
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	check(document.append_from_scene(content,state)==OK and document.write_to_filesystem(state,path)==OK,"solid edit fixture exports as native GLB")
	content.free();return path
func sample(image:Image,camera:Camera3D,world:Vector3)->Color:
	var point:=Vector2i(camera.unproject_position(world)*Vector2(image.get_size())/root.get_visible_rect().size)
	var sum:=Color(0,0,0,0)
	for y in range(-5,6):
		for x in range(-5,6):sum+=image.get_pixelv((point+Vector2i(x,y)).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
	return sum/121.0
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=160
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");ui.get_node("%MainControls").set_expanded(false)
	var sky:=GSSkySettings.node(viewer);sky.auto_exposure=false
	var path:=fixture("user://solid-edit-model.glb",Vector3(0,0.5,0),Vector3(0.7,1,0.7))
	var actor:=await viewer.load_mesh_from_path(path,false,GaussianSplat.ImportKind.OBJECT)
	var wall:=await viewer.load_mesh_from_path(fixture("user://solid-edit-wall.glb",Vector3(0,1.5,0),Vector3(0.2,3,4)),false,GaussianSplat.ImportKind.OBJECT);wall.position.x=1
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://solid-edit-gs.ply",3));gs.position=Vector3(4,1,0)
	while viewer.is_loading():await process_frame
	var population:int=viewer.total_splats_to_load;var gs_pose:=gs.global_transform
	# Deliberate direct pose restoration: the reference background must respect a
	# valid native silhouette even below Y=0, independently of editing safeguards.
	actor.position=Vector3(-2,-0.65,0);wall.hide();viewer.select_model_id(actor.model_id)
	viewer.camera_controller.position_camera_at(Vector3(0,2,5),Vector3(-2,-0.15,0));await settle()
	var grid:CSGBox3D=scene.get_node("CSGBox3D")
	var on:Image=await ViewportCapture.capture_scene_only(root);var with_grid:=sample(on,viewer.get_camera(),Vector3(-2,-0.15,0));on.save_png("user://solid-edit-grid-on.png")
	grid.hide();await settle()
	var off:Image=await ViewportCapture.capture_scene_only(root);var without_grid:=sample(off,viewer.get_camera(),Vector3(-2,-0.15,0));off.save_png("user://solid-edit-grid-off.png")
	print("NATIVE BELOW GRID ",with_grid," versus ",without_grid)
	check(Vector3(with_grid.r,with_grid.g,with_grid.b).distance_to(Vector3(without_grid.r,without_grid.g,without_grid.b))<0.025,"reference grid cannot paint over a native model below the grid plane")
	grid.show();actor.position=Vector3(-2,0.05,0);wall.show()
	viewer.camera_controller.position_camera_at(Vector3(-1,3,6),Vector3(-1,0.7,0));viewer.select_model_id(actor.model_id)
	var controls:GSModelTransformControls=ui.transform_controls;controls.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	if viewer.has_method("prepare_asset_edits"):
		var deadline:=Time.get_ticks_msec()+15000
		while not viewer.prepare_asset_edits([actor.model_id]) and Time.get_ticks_msec()<deadline:await process_frame
	var panel:SceneManagerPanel=scene.get_node("SceneManagerPanel")
	panel._numeric_edit("position",1,-2.0);await settle()
	check(actor.global_position.y>=-0.025,"normal numeric editing stops the GLB geometry at the reference floor")
	actor.position=Vector3(-2,0.05,0);await settle()
	var start:=controls._center
	check(controls.begin_drag(0,start),"normal gizmo movement starts without entering Drive mode")
	controls.update_drag(start+(controls._ends[0]-start).normalized()*4000);controls.finish_drag(false);await settle()
	print("SOLID GIZMO WALL STOP ",actor.global_position)
	check(actor.global_position.x>0.0 and actor.global_position.x<0.6,"normal gizmo movement cannot tunnel through another GLB")
	var stopped:=actor.global_transform
	check(viewer.undo_transform() and actor.global_position.is_equal_approx(Vector3(-2,0.05,0)) and viewer.undo_transform(true) and actor.global_transform.is_equal_approx(stopped),"collision-clamped gizmo editing remains one exact undo and redo")
	actor.position=Vector3(-2,0.05,0);await settle()
	viewer.select_model_ids([gs.model_id,actor.model_id]);await settle()
	var gs_before:=viewer.get_asset_edit_transform(gs);var actor_before:=actor.global_transform
	controls.begin_drag(0,controls._center);controls.update_drag(controls._center+(controls._ends[0]-controls._center).normalized()*4000);controls.finish_drag(false);await settle()
	check((viewer.get_asset_edit_transform(gs).origin-gs_before.origin).is_equal_approx(actor.global_position-actor_before.origin) and actor.global_position.x<0.6,"mixed multi-selection stops together at a native collision without changing relative translation")
	var group_gs:=gs.global_transform;var group_native:=actor.global_transform
	controls.set_mode(GSModelTransformControls.Mode.SCALE);await settle()
	controls.begin_drag(0,controls._center);controls.update_drag(controls._center-(controls._ends[0]-controls._center).normalized()*300);controls.finish_drag(false);await settle()
	check(gs.global_transform.is_equal_approx(group_gs) and actor.global_transform.is_equal_approx(group_native),"a blocked group scale preserves every member's relative pose")
	controls.set_mode(GSModelTransformControls.Mode.MOVE)
	viewer.undo_transform();viewer.select_model_id(actor.model_id)
	controls.get_node("%SolidEdits").button_pressed=false
	var affine:=Transform3D(Basis(Vector3(1,0.2,0),Vector3(0.1,1,0),Vector3(0,0,1)),gs.global_position)
	check(viewer.apply_asset_edits({gs.model_id:affine},true) and gs.global_transform.is_equal_approx(affine),"unrestricted GS authoring preserves the requested affine matrix exactly")
	var tiny:=Transform3D(Basis.from_scale(Vector3.ONE*0.001),gs.global_position)
	check(viewer.apply_asset_edits({gs.model_id:tiny},true) and gs.global_transform.is_equal_approx(tiny),"shared editing preserves existing small but non-singular GS scales")
	gs.global_transform=gs_pose
	panel._numeric_edit("position",1,-1);panel._numeric_edit("position",0,2);await settle()
	check(actor.global_position.is_equal_approx(Vector3(2,-1,0)),"the authored Solid toggle permits an intentional overlap and below-floor pose")
	var saved_pose:=actor.global_transform;var saved_id:=actor.model_id
	controls.get_node("%ShapeQuality").select(1);controls.get_node("%ShapeQuality").item_selected.emit(1)
	check(await viewer.save_composition("user://solid-edit-scene.pxrscene")==OK and await viewer.open_composition("user://solid-edit-scene.pxrscene")==OK,"solid editing uses the existing exact mixed-scene transaction")
	actor=viewer.get_asset_by_id(saved_id) as GSSceneMesh
	check(not viewer.mesh_edit_collisions_enabled and actor.global_transform.is_equal_approx(saved_pose),"saved Solid policy and intentional below-floor pose reopen exactly without automatic correction")
	check(viewer.mesh_edit_shape_quality==GSMeshMotionJob.Quality.DETAILED,"the authored collision quality selection saves and reopens through the existing view settings")
	controls.get_node("%ShapeQuality").select(0);controls.get_node("%ShapeQuality").item_selected.emit(0)
	controls.get_node("%SolidEdits").button_pressed=true
	var environment:=await viewer.load_mesh_from_path(fixture("user://solid-edit-floor.glb",Vector3(0,-2.1,0),Vector3(12,0.2,12)),false,GaussianSplat.ImportKind.ENVIRONMENT)
	for asset in viewer.managed_assets:
		if asset is GSSceneMesh and asset.file_path.get_file()=="solid-edit-wall.glb":wall=asset
	actor.position=Vector3(-2,-0.5,0);viewer.select_model_id(actor.model_id);await settle()
	if not await ready(viewer,actor):check(false,"reopened native model prepares shared solid geometry");scene.free();quit(1);return
	panel._numeric_edit("position",1,-5);await settle()
	check(actor.global_position.y>-2.03 and actor.global_position.y<-1.95,"numeric solid edits land on native floors below the grid without an invisible Y=0 blocker")
	actor.position=Vector3(0,0,0);await settle()
	panel._numeric_edit("scale",0,5);await settle()
	check(actor.scale.x>1.1 and actor.scale.x<4.9 and viewer.get_asset_world_bounds(actor).end.x<0.94,"numeric XYZ scale expansion stops at another GLB using prepared geometry")
	actor.global_transform=Transform3D.IDENTITY
	var tall:=await viewer.load_mesh_from_path(fixture("user://solid-edit-tall.glb",Vector3(0,1.1,0),Vector3(0.2,2.2,0.4)),false,GaussianSplat.ImportKind.OBJECT)
	actor.hide();viewer.select_model_id(tall.model_id);await settle()
	if not await ready(viewer,tall):check(false,"the rotation fixture prepares shared solid geometry");scene.free();quit(1);return
	panel._numeric_edit("rotation",2,-90);await settle()
	check(absf(tall.global_rotation_degrees.z)>5 and absf(tall.global_rotation_degrees.z)<89 and viewer.get_asset_world_bounds(tall).end.x<0.95,"numeric rotation stops before its true elongated shape crosses a native wall")
	check(environment.is_loaded,"the native environment remains loaded after shared editing")
	gs=viewer.managed_splats.keys()[0]
	check(viewer.total_splats_to_load==population and gs.global_transform.is_equal_approx(gs_pose),"solid native edits preserve the GS atlas population and independent pose")
	root.get_texture().get_image().save_png("user://solid-edit-controls.png")
	var args:=OS.get_cmdline_user_args()
	if args.size()>=2:
		for asset in viewer.managed_assets:
			if asset is GSSceneMesh and asset!=environment:asset.hide()
		var truck:=await viewer.load_mesh_from_path(args[1],false,GaussianSplat.ImportKind.OBJECT)
		viewer.begin_model_placement(args[0],Vector2.INF,GaussianSplat.ImportKind.OBJECT)
		var import_deadline:=Time.get_ticks_msec()+120000
		while viewer.placement_active and not viewer.get_placement_state().ready and Time.get_ticks_msec()<import_deadline:await process_frame
		var statue:GSSceneMesh=viewer._placement.model if viewer.placement_active and viewer.get_placement_state().ready else null
		if statue:viewer.confirm_model_placement(true)
		check(truck!=null and statue!=null,"the actual reported statue and truck import as native GLBs")
		if truck and statue:
			truck.position.y=-2-truck.bounds_local.position.y
			var bounds:=viewer.get_asset_world_bounds(truck)
			statue.position=Vector3(bounds.end.x-statue.bounds_local.position.x+0.6,-2-statue.bounds_local.position.y+0.03,0)
			viewer.select_model_id(statue.model_id);viewer.frame_models([truck.model_id,statue.model_id]);await settle()
			if await ready(viewer,statue):
				var from:=statue.global_transform
				# Native ray/plane dragging must target a point in front of the camera;
				# the old arbitrary 4000px offset crossed its perspective horizon.
				var target:=viewer.get_camera().unproject_position(controls.runtime.proxy.global_position-Vector3.RIGHT*6.0)
				controls.begin_drag(0,controls._center);controls.update_drag(target);controls.finish_drag(false)
				var deadline:=Time.get_ticks_msec()+60000
				while controls.dragging and Time.get_ticks_msec()<deadline:await process_frame
				await settle()
				print("REAL SOLID CONTACT from ",from.origin," to ",statue.global_position," truck ",bounds," pieces ",statue.motion_shapes.size())
				check(statue.global_position.x<from.origin.x-0.1 and statue.global_position.x>bounds.position.x,"the reported statue stops against actual truck triangles during ordinary gizmo movement")
				check(viewer.get_asset_world_bounds(statue).position.y>=-2.04,"the reported GLB remains above its native floor")
				root.get_texture().get_image().save_png("user://solid-edit-real-contact.png")
			else:check(false,"the reported statue prepares solid shapes")
			statue.hide();truck.position=Vector3(0,-1-truck.bounds_local.position.y,0)
			viewer.select_model_id(truck.model_id);viewer.frame_models([truck.model_id]);controls.set_mode(GSModelTransformControls.Mode.MOVE)
			var started:=Time.get_ticks_msec()
			if await ready(viewer,truck):
				print("INTERACTIVE TRUCK FAST ",truck.motion_metrics," ready_wall_ms=",Time.get_ticks_msec()-started)
				check(Time.get_ticks_msec()-started<10000,"selecting the actual truck for normal solid editing is ready within ten seconds")
				await settle();panel._numeric_edit("position",1,-20);await settle()
				# Rotated source-part AABBs can extend below the actual tire geometry.
				# Check rendered triangle vertices, independently of the convex helper.
				var bottom:=INF
				for part in truck.geometry_parts:
					var geometry:MeshInstance3D=part.node.get_ref()
					for vertex in geometry.mesh.get_faces():bottom=minf(bottom,(geometry.global_transform*vertex).y)
				print("FAST TRUCK FLOOR triangle_bottom=",bottom," loose_bounds_bottom=",viewer.get_asset_world_bounds(truck).position.y," root=",truck.global_position)
				check(bottom>=-2.03 and bottom<-1.95,"the actual Fast truck geometry stops on the native floor during ordinary numeric editing")
				check(controls.get_node("%ShapeQuality").selected==0,"the authored compact toolbar displays the active Fast policy")
				root.get_texture().get_image().save_png("user://motion-fast-truck-controls.png")
			else:check(false,"the actual truck prepares Fast solid geometry")
	scene.free();await process_frame
	print("SOLID EDIT CHECKS COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
