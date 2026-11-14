extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(1.5).timeout;await RenderingServer.frame_post_draw
func sample(camera:Camera3D,world:Vector3)->Color:
	var image:=root.get_texture().get_image()
	var pixel:=Vector2i(camera.unproject_position(world)*Vector2(image.get_size())/root.get_visible_rect().size)
	return image.get_pixelv(pixel.clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
func run()->void:
	var lab:Node3D=load("res://tests/scenes/grid_shadow_lab.tscn").instantiate();root.add_child(lab)
	var floor:CSGBox3D=lab.get_node("Floor")
	var light:DirectionalLight3D=lab.get_node("Sun")
	var viewer:=GaussianSplattingViewer.new()
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=160
	viewer.shadow_light=light;root.add_child(viewer)
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://grid-shadow.ply",1))
	model.position.y=1;model.scale=Vector3.ONE*4
	for i in range(40):await process_frame
	viewer.camera_controller.position_camera_at(Vector3(4,5,6),Vector3(0,0,-1))
	viewer.lighting.shadow_strength=0.9;viewer.lighting.shadow_resolution=256
	var direction:Vector3=-light.global_basis.z
	var top:Vector3=model.global_position+direction*((-model.global_position.y)/direction.y)
	var underside:Vector3=model.global_position+direction*((-1-model.global_position.y)/direction.y)
	await settle()
	var original_top:=sample(viewer.get_camera(),top)
	var original_bottom:=sample(viewer.get_camera(),underside)
	viewer.lighting.shadows_enabled=true;await settle()
	var top_shadow:=sample(viewer.get_camera(),top)
	var bottom_shadow:=sample(viewer.get_camera(),underside)
	print("GRID SHADOW top ",original_top," -> ",top_shadow," underside ",original_bottom," -> ",bottom_shadow)
	check(top_shadow.r<original_top.r-0.15,"transparent closed grid receives one visible Gaussian shadow on its top surface")
	check(absf(bottom_shadow.r-original_bottom.r)<0.03,"hidden underside of transparent grid cannot add a displaced duplicate shadow")
	root.get_texture().get_image().save_png("user://grid-shadow-single.png")
	# Explicitly double-sided receivers retain their requested rendering contract.
	floor.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED;await settle()
	check(sample(viewer.get_camera(),underside).r<original_bottom.r-0.15,"explicit double-sided receiving remains available through the material's own cull mode")
	floor.material_override.cull_mode=BaseMaterial3D.CULL_BACK;await settle()
	check(absf(sample(viewer.get_camera(),underside).r-original_bottom.r)<0.03,"restoring material back-face culling immediately clears the underside shadow")
	viewer.lighting.shadows_enabled=false;await settle()
	check(absf(sample(viewer.get_camera(),top).r-original_top.r)<0.03,"disabling generated shadows restores the original captured appearance")
	check(floor.use_collision and floor.size==Vector3(12,1,12) and model.is_loaded and viewer.total_splats_to_load==1,"shadow correction preserves floor collision, floor thickness and the complete resident model")
	viewer.free();lab.free();await process_frame
	print("GRID SHADOW CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
