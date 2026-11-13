extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var viewer:=GaussianSplattingViewer.new()
	viewer.config=GaussianSplattingConfig.create_default()
	viewer.config.memory_max_vram_budget_mb=32
	root.add_child(viewer)
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://selection-color.ply",1))
	for i in range(60):await process_frame
	while viewer.is_loading():await process_frame
	viewer.camera_controller.position_camera_at(Vector3(0,0,1),Vector3.ZERO)
	await create_timer(1.3).timeout
	await RenderingServer.frame_post_draw
	var image:=viewer.render_texture.get_image()
	var pixel:=Vector2i(image.get_width()/2,image.get_height()/2)
	var neutral:=image.get_pixelv(pixel)
	viewer.select_model_id(model.model_id)
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var selected:=viewer.render_texture.get_image().get_pixelv(pixel)
	print("UNSELECTED ",neutral," SELECTED ",selected)
	var same:=neutral.a>0.1 and Vector3(neutral.r,neutral.g,neutral.b).distance_to(Vector3(selected.r,selected.g,selected.b))<0.002
	print("PASS " if same else "FAIL ","model selection preserves source color")
	viewer.free()
	quit(0 if same else 1)
