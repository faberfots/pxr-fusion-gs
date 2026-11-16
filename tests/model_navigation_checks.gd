extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func box(parent:Node3D,position:Vector3,size:Vector3)->void:
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new();node.mesh.size=size;node.position=position;parent.add_child(node)
func export_model(path:String,parts:Array)->String:
	var content:=Node3D.new()
	if path.contains("drive-arch"):
		# A single concave mesh with disconnected legs: a single convex envelope
		# would incorrectly block the post passing between them.
		var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in parts:
			var mesh:=BoxMesh.new();mesh.size=part[1]
			for vertex in mesh.get_faces():builder.add_vertex(vertex+part[0])
		builder.generate_normals()
		var node:=MeshInstance3D.new();node.mesh=builder.commit();content.add_child(node)
	else:
		for part in parts:box(content,part[0],part[1])
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	check(document.append_from_scene(content,state)==OK and document.write_to_filesystem(state,path)==OK,"native navigation GLB fixture exports")
	content.free();return path
func key(code:Key,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;root.push_input(event,true)
func settle()->void:await create_timer(0.2).timeout;await RenderingServer.frame_post_draw
func wait_drive(viewer:GaussianSplattingViewer)->bool:
	var deadline:=Time.get_ticks_msec()+120000
	while viewer.get_model_navigation_state().preparing and Time.get_ticks_msec()<deadline:await process_frame
	return viewer.get_model_navigation_state().walking
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var room_path:=export_model("user://drive-room.glb",[[Vector3(0,-0.1,0),Vector3(10,0.2,12)],[Vector3(0,1.5,-3),Vector3(8,3,0.2)],[Vector3(-1.5,1.5,0),Vector3(1,3,0.25)],[Vector3(1.5,1.5,0),Vector3(1,3,0.25)],[Vector3(0,2.75,0),Vector3(2,0.5,0.25)]])
	var model_path:=export_model("user://drive-arch.glb",[[Vector3(-0.65,0.75,0),Vector3(0.3,1.5,0.4)],[Vector3(0.65,0.75,0),Vector3(0.3,1.5,0.4)],[Vector3(0,1.65,0),Vector3(1.6,0.3,0.4)]])
	var obstacle_path:=export_model("user://drive-post.glb",[[Vector3(0,0.4,0),Vector3(0.2,0.8,0.2)]])
	var room:=await viewer.load_mesh_from_path(room_path,false,GaussianSplat.ImportKind.ENVIRONMENT)
	var actor:=await viewer.load_mesh_from_path(model_path,false,GaussianSplat.ImportKind.OBJECT)
	var obstacle:=await viewer.load_mesh_from_path(obstacle_path,false,GaussianSplat.ImportKind.OBJECT);obstacle.position=Vector3(0,0,-1.3)
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://drive-gs.ply",3));gs.position=Vector3(-4,1,0)
	while viewer.is_loading():await process_frame
	actor.position=Vector3(0,0.025,2)
	var population:int=viewer.total_splats_to_load;var gs_pose:=gs.global_transform
	var controller:=viewer.camera_controller;var ground:=controller.ground;ground.use_collision=false;controller.ground=null
	actor.hide()
	await physics_frame;await physics_frame
	var pass_pose:=controller.constrain_pose(Transform3D(Basis.IDENTITY,Vector3(0,1.7,3)),Transform3D(Basis.IDENTITY,Vector3(0,1.7,-2)))
	var block_pose:=controller.constrain_pose(Transform3D(Basis.IDENTITY,Vector3(1.5,1.7,3)),Transform3D(Basis.IDENTITY,Vector3(1.5,1.7,-2)))
	var floor_pose:=controller.constrain_pose(Transform3D(Basis.IDENTITY,Vector3(3,2,1)),Transform3D(Basis.IDENTITY,Vector3(3,-2,1)))
	check(pass_pose.origin.z<-1.9 and block_pose.origin.z>0.25,"native camera passes a real doorway and stops at its wall using triangle geometry")
	check(floor_pose.origin.y>0.15,"native GLB floor collision works even without the prototype ground reference")
	actor.show()
	ground.use_collision=true;controller.ground=ground;controller.position_camera_at(Vector3(0,3,7),Vector3(0,0.8,2))
	viewer.select_model_id(actor.model_id);var before:=actor.global_transform
	var ui=scene.get_node("ProductionUI");ui.get_node("%MainControls").set_expanded(false)
	ui.get_node("%CameraPanel").get_node("%DriveModel").button_pressed=true
	check(await wait_drive(viewer),"the authored Drive selected GLB control prepares and starts native shape movement")
	if not viewer.get_model_navigation_state().walking:print(viewer.get_model_navigation_state());scene.free();quit(1);return
	check(actor.motion_shapes.size()>=3,"moving model uses several mesh-derived convex pieces rather than a bounding box")
	check(not ui.transform_controls.begin_drag(0,Vector2.ZERO),"drive mode isolates physical movement from free transform dragging")
	var camera_point:=controller.get_camera().global_position
	var contact:=KinematicCollision3D.new()
	var probe_pose:=Transform3D(Basis.IDENTITY,camera_point+Vector3(-0.65,-0.75,3))
	check(viewer._model_navigation._body.test_move(probe_pose,Vector3(0,0,-6),contact) and contact.get_collider()==controller._model_camera_body,"the actual driven geometry collides with the physical camera volume")
	controller.set_movement_blocker("navigation-ui-check",true);key(KEY_W,true);var parked:=actor.global_position
	await create_timer(0.25).timeout;key(KEY_W,false)
	check(Vector2(actor.global_position.x,actor.global_position.z).distance_to(Vector2(parked.x,parked.z))<0.02,"existing UI camera blockers also pause Drive input without disabling solid floor contact")
	controller.set_movement_blocker("navigation-ui-check",false)
	key(KEY_W,true);await create_timer(2.1).timeout;key(KEY_W,false);await settle()
	print("WALK THROUGH DOOR AND POST ",actor.global_position)
	check(actor.global_position.z<-1.9 and actor.global_position.z>-2.9,"the model passes the doorway and a post between its legs, then stops at the back wall")
	check(actor.global_position.y>-0.05 and actor.global_position.y<0.15,"gravity settles real model geometry on the GLB floor")
	key(KEY_W,true);key(KEY_D,true);await create_timer(0.4).timeout;key(KEY_W,false);key(KEY_D,false);await settle()
	check(actor.global_position.x>0.25 and actor.global_position.z>-2.9,"shape-based motion slides along the wall rather than tunnelling through it")
	check(viewer.total_splats_to_load==population and gs.global_transform.is_equal_approx(gs_pose),"physical model navigation preserves GS residency and transforms")
	key(KEY_ESCAPE,true);key(KEY_ESCAPE,false);await settle()
	check(not viewer.model_navigation_active and viewer.undo_transform() and actor.global_transform.is_equal_approx(before),"Esc exits and a single existing undo restores the complete walk")
	obstacle.position.x=0.65;controller.position_camera_at(Vector3(0,3,7),Vector3(0,0.8,2));await settle()
	viewer.start_model_navigation();check(await wait_drive(viewer),"repeat driving reuses prepared collision geometry")
	key(KEY_W,true);await create_timer(2.0).timeout;key(KEY_W,false);await settle()
	check(actor.global_position.z>-1.1 and actor.global_position.z<0,"another GLB stops a limb while the open space between limbs remained passable")
	viewer.stop_model_navigation();viewer.undo_transform();await settle()
	obstacle.hide();actor.global_transform=Transform3D(Basis.from_euler(Vector3(0,0.2,0)).scaled_local(Vector3(0.7,1.4,0.6)),Vector3(2.8,0.5,2))
	var scaled_basis:=actor.global_basis
	controller.position_camera_at(Vector3(2.8,3.5,7),Vector3(2.8,1.2,2));viewer.start_model_navigation();await wait_drive(viewer)
	key(KEY_W,true);await create_timer(1.8).timeout;key(KEY_W,false);await settle()
	check(actor.global_basis.is_equal_approx(scaled_basis) and actor.global_position.y>-0.05 and actor.global_position.y<0.15 and actor.global_position.z>-3 and actor.global_position.z<-2.3,"rotated nonuniformly scaled geometry keeps its authored basis and collides with native walls and floors")
	key(KEY_D,true);viewer._model_navigation.release_input();var idle_position:=actor.global_position
	await create_timer(0.25).timeout
	check(actor.global_position.distance_to(idle_position)<0.02,"focus-loss input release prevents continued movement")
	viewer.stop_model_navigation();actor.global_transform=before;obstacle.show()
	actor.motion_shapes.clear();viewer.start_model_navigation();viewer.stop_model_navigation()
	check(not viewer.model_navigation_active and not controller._movement_blockers.has("model_navigation"),"cancelling shape preparation releases the mode and its camera blocker")
	viewer.start_model_navigation();await wait_drive(viewer)
	var action:=ActionController.new();action.policy=AIAccessPolicy.new();root.add_child(action)
	check(action.execute_action("reset_view",{}).status=="error" and viewer.model_navigation_active,"denied Cortex camera actions leave physical navigation untouched")
	action.policy.role=AIAccessPolicy.Role.OPERATOR;action.policy.actions_enabled=true
	check(action.execute_action("move_camera",{"position":[0,0,0],"look_at":[0,0,0]}).status=="error" and viewer.model_navigation_active,"invalid authorized camera arguments cannot interrupt physical navigation")
	check(action.execute_action("reset_view",{}).status=="success" and not viewer.model_navigation_active,"authorized scene framing exits physical navigation before moving the camera")
	action.free();controller.position_camera_at(Vector3(0,3,7),Vector3(0,0.8,2))
	actor.transform_locked=true
	check(viewer.start_model_navigation()!=OK and not viewer.model_navigation_active,"transform locks deny model navigation")
	actor.transform_locked=false
	viewer.select_model_id(room.model_id);check(viewer.start_model_navigation()!=OK,"an environment cannot accidentally become the driven model")
	viewer.select_model_id(actor.model_id);viewer.start_model_navigation();await wait_drive(viewer)
	check(await viewer.save_composition("user://driven-scene.pxrscene")==OK and not viewer.model_navigation_active,"saving stops physical movement and commits through the existing scene transaction")
	var pose:=actor.global_transform;var id:=actor.model_id
	check(await viewer.open_composition("user://driven-scene.pxrscene")==OK and viewer.get_asset_by_id(id).global_transform.is_equal_approx(pose),"the driven pose round-trips exactly without enabling simulation on reopen")
	# Move the actual floor below the decorative grid: a native environment must
	# remain walkable below the old reference plane without hovering on that plane.
	actor=viewer.get_asset_by_id(id) as GSSceneMesh
	for asset in viewer.managed_assets:
		if asset.file_path.get_file()==room_path.get_file():asset.position.y=-2
		if asset.file_path.get_file()==obstacle_path.get_file():asset.hide()
	actor.position=Vector3(3,-1.5,2);controller.position_camera_at(Vector3(3,0.5,7),Vector3(3,-1,2));viewer.select_model_id(actor.model_id)
	viewer.start_model_navigation();check(await wait_drive(viewer),"native floor navigation remains available below the reference grid")
	await create_timer(0.8).timeout
	print("NATIVE FLOOR BELOW GRID actor ",actor.global_position," camera ",controller.get_camera().global_position)
	check(actor.global_position.y<-1.8 and actor.global_position.y>-2.05 and controller.get_camera().global_position.y<1,"the GLB floor controls model height without an invisible reference-plane blocker")
	viewer.stop_model_navigation()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		var real:=await viewer.load_mesh_from_path(args[0],false,GaussianSplat.ImportKind.OBJECT)
		real.position=Vector3(0,0.05,2);viewer.select_model_id(real.model_id);controller.position_camera_at(Vector3(0,3,7),Vector3(0,0.8,2))
		viewer.start_model_navigation();check(await wait_drive(viewer),"the provided Jesus GLB prepares real compound geometry in the worker")
		print("REAL MODEL COLLISION PIECES ",real.motion_shapes.size())
		await settle();root.get_texture().get_image().save_png("user://driven-real-model.png");viewer.stop_model_navigation()
	root.get_texture().get_image().save_png("user://model-navigation.png")
	ui.get_node("%CameraPanel").show();await settle()
	root.get_texture().get_image().save_png("user://model-navigation-controls.png")
	actor.motion_shapes.clear();viewer.select_model_id(actor.model_id);viewer.start_model_navigation()
	scene.free();await process_frame
	print("MODEL NAVIGATION COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
