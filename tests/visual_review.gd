extends SceneTree
const Checks = preload("res://tests/core_checks.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var viewer: GaussianSplattingViewer = scene.get_node("GaussianSplattingViewer")
	viewer.config = GaussianSplattingConfig.create_default()
	viewer.config.memory_max_vram_budget_mb = 128
	root.add_child(scene)
	var fixture := Checks.fixture("user://visual.ply", 3)
	var source := FileAccess.open(fixture, FileAccess.READ)
	var text := source.get_as_text().replace(" 0 0 -3", " -1 0 -3")
	source.close()
	source = FileAccess.open(fixture, FileAccess.WRITE)
	source.store_string(text)
	source.close()
	viewer.load_new_splat_from_path(fixture)
	for i in range(100): await process_frame
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://main-review.png")
	var ui: CanvasLayer = scene.get_node("ProductionUI")
	ui._on_cognitive_button_pressed()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://ai-review.png")
	ui.cognitive_panel.input_field.grab_focus()
	ui.cognitive_panel.hide_panel()
	if root.gui_get_focus_owner() == ui.cognitive_panel.input_field:
		printerr("Hidden AI panel retained keyboard focus")
		quit(1)
		return
	print("VISUAL_ARTIFACTS ", ProjectSettings.globalize_path("user://"))
	scene.free()
	await process_frame
	quit()
