extends SceneTree
## Exercise the real main-scene sibling ready order, without injecting a config.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func run() -> void:
	var preferences := GaussianSplattingConfig.create_default()
	GSColorSettings.apply(preferences, GSColorSettings.profile("Warm daylight"))
	check(GSColorSettings.save_preferences(preferences) == OK, "saved preferences exist before normal scene startup")
	var scene: Node = load("res://main.tscn").instantiate()
	var viewer: GaussianSplattingViewer = scene.get_node("GaussianSplattingViewer")
	check(viewer.config == null, "real main scene begins with its original null configuration")
	scene.get_node("DemoUIController").show_ui = false
	root.add_child(scene)
	scene.get_node("DemoUIController").set_process(false)
	for i in range(8): await process_frame
	# Load ProductionUI through the scene after autoload singletons are registered.
	var ui = scene.get_node("ProductionUI")
	check(viewer.config != null, "viewer owns a default configuration after ready")
	check(GSColorSettings.snapshot(viewer.config) == GSColorSettings.profile("Warm daylight"), "early UI restores preferences after viewer initialization")
	ui.color_panel.show_panel()
	check(is_equal_approx(ui.color_panel.sliders.post_temperature.value, 0.3), "color panel synchronizes the initialized configuration")
	check(ui.color_panel.apply_profile("Natural"), "color controls remain usable after normal startup")
	ui.color_panel.hide_panel()
	check(ui.transform_controls != null and ui.quality_selector.item_count == 5, "existing transform and quality controls initialize")
	scene.queue_free()
	for i in range(5): await process_frame
	check(true, "normal scene teardown completes")
	print("STARTUP COMPLETE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
