extends "res://tests/native_gizmo_checks.gd"
## Real authored controls, renderer materials, hit tests and independent restart.
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate();scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer");viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	var ui=scene.get_node("ProductionUI");ui.get_node("%MainControls").set_expanded(false)
	var tools:GSModelTransformControls=ui.transform_controls;var prefs:=tools.gizmo_preferences
	var settings:Control=ui.get_node("%SettingsPanel");var controls:Control=settings.get_node("%GizmoSettings")
	if OS.get_cmdline_user_args().has("--reopen"):
		check(is_equal_approx(prefs.values.size,125.0) and is_equal_approx(prefs.values.translate_snap,0.25) and prefs.values.color_x==Color(0.8,0.15,0.25),"a new application process restores the exact saved appearance and snapping preferences")
		check(is_equal_approx(controls.get_node("%Size").value,125.0),"restarted authored settings project the same preference owner")
		prefs.apply_preset("Godot Classic");scene.free();await process_frame
		print("GIZMO PREFERENCES RESTART COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1);return
	prefs.apply_preset("Godot Classic",false)
	var gs:=viewer.load_new_splat_from_path(Checks.fixture("user://gizmo-preferences-gs.ply",3));gs.position=Vector3(-3,1,0)
	while viewer.is_loading():await process_frame
	var mesh:=await viewer.load_mesh_from_path(box_fixture(),false,GaussianSplat.ImportKind.OBJECT)
	viewer.select_model_id(mesh.model_id);viewer.camera_controller.position_camera_at(Vector3(4,3,7),Vector3(0,1,0));viewer.mesh_edit_collisions_enabled=false;await settle()
	var pose:=mesh.global_transform;var population:=viewer.total_splats_to_load
	check(controls.preferences==prefs,"the authored controls and runtime share one preference owner")
	ui._toggle_panel(settings);settings.get_node("%GizmoSection").button_pressed=true;await settle()
	controls.get_node("%Size").value=125;controls.get_node("%Opacity").value=0.65
	controls.get_node("%ColorX").color_changed.emit(Color(0.8,0.15,0.25));await settle()
	check(is_equal_approx(tools.runtime.native.size,125*GSUiScale.FACTOR),"the authored size control immediately resizes the actual native handles")
	var color:Color=tools.runtime.native._gizmo_color[0].albedo_color
	check(color.is_equal_approx(Color(0.8,0.15,0.25,0.65)),"live colour and opacity reach the actual native material without a one-change lag")
	check(is_equal_approx(tools.runtime.native.get_node("%ScaleCenter").material_override.albedo_color.a,0.65),"the shared opacity also reaches the authored center handles")
	controls.get_node("%Bounds").button_pressed=true;await settle()
	check(tools.runtime.selection_bounds.is_equal_approx(viewer.get_asset_world_bounds(mesh)) and tools.runtime.native._calculate_spatial_bounds(tools.runtime.proxy).size.length()>1,"the outline uses real imported geometry bounds instead of the empty proxy")
	viewer.select_model_ids([mesh.model_id,gs.model_id]);await settle()
	check(tools.runtime.selection_bounds.is_equal_approx(viewer.get_asset_world_bounds(mesh).merge(viewer.get_asset_world_bounds(gs))),"a mixed GS/GLB selection outline covers both real world bounds")
	viewer.select_model_id(mesh.model_id);await settle()
	root.get_texture().get_image().save_png("user://gizmo-settings-appearance.png")
	# Close the panel before real pointer input and keep a known Classic handle size.
	settings.hide();prefs.set_value("size",80.0,false);tools.set_mode(GSModelTransformControls.Mode.MOVE);await settle()
	var native:Node3D=tools.runtime.native
	var point:=tools.runtime.camera.unproject_position(native.global_position+(Vector3.RIGHT+Vector3.UP)*native._gizmo_scale*0.4)
	prefs.set_value("show_planes",false,false);await settle();motion(point);click(point,true)
	check(not tools.dragging,"hidden plane handles cannot start a drag")
	click(point,false);prefs.set_value("show_planes",true,false);prefs.set_value("move_axes",6,false);await settle()
	point=tools.runtime.camera.unproject_position(native.global_position+(Vector3.UP+Vector3.BACK)*native._gizmo_scale*0.4)
	motion(point);click(point,true)
	check(tools.dragging and native._edit.plane==Gizmo3D.TransformPlane.YZ,"the allowed YZ plane stays usable when the unrelated X axis is disabled")
	if tools.dragging:tools.finish_drag(true)
	prefs.set_value("move_axes",0,false);await settle()
	check(not tools.runtime.hit_test(tools._center) and not tools.runtime.hit_test(tools.runtime.axis_screen(0)),"disabled axes also disable the free center and axis hit targets")
	prefs.set_value("move_axes",7,false);controls.get_node("%MoveSnap").value=0.25;await settle()
	point=tools.runtime.axis_screen(0);motion(point);click(point,true,true);motion(point+(point-tools._center).normalized()*90,true);click(point,false);await settle()
	check(mesh.global_position.x>pose.origin.x+0.1 and absf((mesh.global_position.x-pose.origin.x)/0.25-roundf((mesh.global_position.x-pose.origin.x)/0.25))<0.002,"custom snapping intervals affect real native pointer movement")
	var accepted:=mesh.global_transform
	point=tools.runtime.axis_screen(0);motion(point);click(point,true);motion(point+(point-tools._center).normalized()*25,true)
	prefs.set_value("opacity",0.7,false);await settle()
	check(not tools.dragging and mesh.global_transform.is_equal_approx(accepted) and not viewer.camera_controller.has_movement_blocker("model_transform"),"changing preferences during a drag restores its exact starting pose and releases camera ownership")
	mesh.global_transform=pose
	var file:="user://gizmo-validation.cfg";var invalid:=ConfigFile.new();invalid.set_value("gizmo","size","invalid");invalid.set_value("gizmo","opacity",-10);invalid.set_value("gizmo","color_x","invalid");invalid.set_value("gizmo","move_axes",999);invalid.save(file)
	var loaded:=GSGizmoPreferences.new();loaded.load_preferences(file)
	loaded.set_value("size",NAN,false)
	check(loaded.values.size==80.0 and is_equal_approx(loaded.values.opacity,0.1) and loaded.values.color_x==GSGizmoPreferences.DEFAULTS.color_x and loaded.values.move_axes==7,"invalid saved preferences are bounded and recover to safe defaults")
	var about:Control=settings.get_node("%AboutLicenses")
	check(not about._loaded and not about._notices_loaded,"credit and full licence data remain unloaded during normal scene editing")
	ui._toggle_panel(settings);settings.get_node("%AboutSection").button_pressed=true;await settle()
	check(not controls.visible and about._loaded and not about._notices_loaded,"credits open compactly while the customization section collapses and full notices stay lazy")
	check(about.get_node("%Credits").text.contains("Ethan Truong") and about.get_node("%Credits").text.contains("Christopher Charbonneau") and about.get_node("%Credits").text.contains("POLYGONICS SAS"),"the app visibly credits the original GS and gizmo authors alongside Polygonics")
	root.get_texture().get_image().save_png("user://gizmo-credits.png")
	about.current_tab=1;await settle()
	check(about._notices_loaded and about.get_node("%Notices").text.contains("ACTUAL RUNNING GODOT ENGINE") and about.get_node("%Notices").text.contains("Copyright (c) 2024 Ethan Truong"),"the explicit licence tab exposes retained original notices and the running engine notices")
	check(viewer.total_splats_to_load==population and gs.global_transform.origin==Vector3(-3,1,0),"customization and credits preserve GS residency and independent transforms")
	# Keep a known preference for the independent process restart check, then that
	# process resets the isolated workspace to Classic for other preservation suites.
	prefs.set_value("size",125.0,false);prefs.set_value("translate_snap",0.25,false);prefs.set_value("color_x",Color(0.8,0.15,0.25),false)
	check(prefs.save_preferences()==OK,"custom preferences save through their single local owner")
	scene.free();await process_frame
	print("GIZMO PREFERENCES COMPLETE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
