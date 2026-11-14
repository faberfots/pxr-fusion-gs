extends SceneTree
## Opt-in, local full-resolution review; datasets are not redistributed.
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:quit(1);return
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default()
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	viewer.set_camera_blocker("qualification",true)
	var ui=scene.get_node("ProductionUI")
	ui.get_node("%MainControls").set_expanded(false)
	ui.color_panel.apply_profile("Natural")
	var started:=Time.get_ticks_msec()
	check(viewer.begin_model_placement(args[0],Vector2(600,500))==OK,"full Bali enters the default Auto import route")
	var environment:GaussianSplat=viewer._placement.model
	while (not environment.is_loaded or viewer.is_loading() or viewer.placement_active) and Time.get_ticks_msec()-started<240000:await process_frame
	check(environment.is_loaded and not viewer.placement_active and viewer.total_splats_to_load==7739833,"all 7,739,833 Bali splats load without entering object placement")
	check(environment.global_transform.is_equal_approx(Transform3D.IDENTITY),"Bali retains its exact original source transform")
	if not environment.is_loaded:scene.free();quit(1);return
	var view:=viewer.get_camera().global_transform
	check(viewer.current_scene_mode==GaussianSplattingViewer.SceneMode.ENVIRONMENT_MODE and viewer.get_camera() is FreeLookCamera,"Bali starts in the environment walkthrough camera")
	await create_timer(2).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://environment-bali-entry.png")
	var pixel:=root.get_visible_rect().size*Vector2(0.5,0.78)
	check(viewer.begin_model_placement(args[1],pixel,GaussianSplat.ImportKind.OBJECT)==OK,"Suzuki can still be placed as an object inside Bali")
	var object:GaussianSplat=viewer._placement.model
	while (not object.is_loaded or viewer.is_loading()) and Time.get_ticks_msec()-started<300000:await process_frame
	await create_timer(2).timeout
	var state:=viewer.get_placement_state()
	check(not state.is_empty() and state.ready and state.valid,"full Suzuki reaches a valid placement preview")
	if state.get("valid",false):
		viewer.request_model_placement()
		var deadline:=Time.get_ticks_msec()+15000
		while viewer.placement_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not viewer.placement_active and object.visible and viewer.total_splats_to_load==7959786,"Bali plus Suzuki retain all 7,959,786 splats after confirmation")
	check(environment.global_transform.is_equal_approx(Transform3D.IDENTITY) and viewer.get_camera().global_transform.is_equal_approx(view),"object placement preserves Bali and its walkthrough view")
	viewer.camera_controller.go_home();viewer.home_view()
	check(viewer.get_camera().global_transform.is_equal_approx(view),"Home restores Bali entry even with Suzuki selected")
	await create_timer(1).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://environment-bali-and-object.png")
	var lighting_panel:GSFloatingPanel=ui.get_node("%LightingPanel")
	ui._toggle_panel(lighting_panel);lighting_panel.get_node("%Tabs").current_tab=1
	await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://environment-bali-sky-panel.png")
	lighting_panel.hide()
	ui._toggle_panel(ui.get_node("%SettingsPanel"))
	await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://environment-loading-settings.png")
	ui.get_node("%SettingsPanel").hide()
	ui.load_zone_panel.show();await process_frame
	await create_timer(0.2).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://environment-import-selector.png")
	print("REAL ENVIRONMENT EVIDENCE ",JSON.stringify({"splats":viewer.total_splats_to_load,"bali_pose":GSComposition.matrix(environment.global_transform),"camera_pose":GSComposition.matrix(view),"load_and_review_ms":Time.get_ticks_msec()-started}))
	scene.free();await process_frame
	print("REAL ENVIRONMENT COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
