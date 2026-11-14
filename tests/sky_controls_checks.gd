extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
func click(control:Control,ratio:Vector2=Vector2(0.5,0.5))->void:
	var point:=control.get_global_transform_with_canvas()*(control.size*ratio)
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func run()->void:
	var scene:Node=load("res://main.tscn").instantiate()
	scene.get_node("DemoUIController").show_ui=false
	var viewer:GaussianSplattingViewer=scene.get_node("GaussianSplattingViewer")
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	var sky:Sky3D=scene.get_node("Sky3D")
	var before:=GSSkySettings.snapshot(sky)
	root.add_child(scene);scene.get_node("DemoUIController").set_process(false)
	await settle()
	var ui=scene.get_node("ProductionUI")
	var panel:GSFloatingPanel=ui.get_node("%LightingPanel")
	var controls=panel.get_node("%SkyControls")
	check(controls.sky==sky and controls.controls.size()==GSSkySettings.BOOLS.size()+GSSkySettings.RANGES.size(),"all authored sky controls bind to the existing Sky3D owner")
	var original:=GSSkySettings.snapshot(sky)
	check(original.current_time==before.current_time and original.fog_enabled==before.fog_enabled and original.auto_exposure==before.auto_exposure,"opening the application preserves authored atmosphere settings")
	var grade:=GSColorSettings.snapshot(viewer.config)
	var lighting:=viewer.lighting.shadows_enabled
	ui.get_node("%MainControls").set_expanded(false)
	ui._toggle_panel(panel);panel.get_node("%Tabs").current_tab=1
	await settle()
	controls.get_node("%Preset").item_selected.emit(2)
	check(sky.current_time==12 and not sky.enable_game_time,"Daylight preset controls solar time and pauses animation")
	var sun_pose:=sky.sun.global_transform
	click(controls.controls.current_time,Vector2(0.72,0.5));await settle()
	check(sky.current_time>15 and not sky.sun.global_transform.is_equal_approx(sun_pose),"scaled time slider pointer input updates the live sun direction")
	check(controls.get_node("%Clock").text!="12:00","time readout follows the authoritative Sky3D time")
	controls.get_node("Scroll").ensure_control_visible(controls.controls.fog_enabled)
	await settle()
	var fog:=sky.fog_enabled
	click(controls.controls.fog_enabled);await settle()
	check(sky.fog_enabled!=fog and sky.sky.fog_visible==sky.fog_enabled,"fog switch controls the existing atmospheric effect")
	controls.controls.sun_energy.value=2.0
	check(is_equal_approx(sky.sun_energy,2) and is_equal_approx(sky.sky.sun_light_energy,2),"sun energy slider updates Sky3D's real light driver")
	controls.controls.enable_game_time.button_pressed=true
	var time:=sky.current_time
	await create_timer(0.4).timeout
	check(sky.enable_game_time and sky.current_time>time,"day-night animation advances the live clock")
	controls.controls.enable_game_time.button_pressed=false
	check(GSColorSettings.snapshot(viewer.config)==grade and viewer.lighting.shadows_enabled==lighting,"sky controls preserve GS colour grading and Gaussian-shadow opt-in")
	controls.get_node("%Advanced").button_pressed=true;await settle()
	check(controls.get_node("%AdvancedFields").visible,"advanced atmosphere controls expand within the same scrollable tab")
	root.get_texture().get_image().save_png("user://sky-controls-advanced.png")
	controls.get_node("%Advanced").button_pressed=false
	controls.get_node("Scroll").scroll_vertical=0
	controls.get_node("%Reset").pressed.emit();await settle()
	check(GSSkySettings.snapshot(sky)==original,"Restore scene atmosphere returns to the original authored settings")
	var invalid:=original.duplicate(true);invalid.current_time=999
	check(not GSSkySettings.apply(sky,invalid) and GSSkySettings.snapshot(sky)==original,"invalid saved settings are rejected without partial mutation")
	check(not GSSkySettings.set_value(sky,"script","res://other.gd"),"sky commands reject properties outside the explicit settings contract")
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://sky-source.ply",3))
	while not model.is_loaded:await process_frame
	GSSkySettings.preset(sky,"Sunset");sky.clouds_enabled=false;sky.fog_enabled=true
	var saved:=GSSkySettings.snapshot(sky)
	var path:="user://sky-scene.pxrscene"
	check(await viewer.save_composition(path)==OK,"composition saves the current atmosphere")
	GSSkySettings.preset(sky,"Night");sky.clouds_enabled=true;sky.fog_enabled=false
	check(await viewer.open_composition(path)==OK and GSSkySettings.snapshot(sky)==saved,"reopening the scene restores time, visibility, lighting, exposure and calendar")
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	document.view.erase("sky")
	check(not GSComposition.validate(document).has("error"),"older scene files without Sky3D data remain valid")
	controls.get_node("%Reset").pressed.emit();await settle()
	root.get_texture().get_image().save_png("user://sky-controls-default.png")
	var empty:Control=load("res://modules/gaussian_splatting/UI/SkyControls.tscn").instantiate()
	root.add_child(empty);await settle()
	check(empty.get_node("%Unavailable").visible and not empty.get_node("%Content").visible,"a scene without Sky3D exposes an unavailable state without a crash")
	empty.free();scene.free();await process_frame
	print("SKY CONTROLS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
