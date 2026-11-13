extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle(seconds:float=1.3)->void:
	await create_timer(seconds).timeout;await RenderingServer.frame_post_draw
func sample(viewer:GaussianSplattingViewer,point:Vector3)->Color:
	var image:=root.get_texture().get_image()
	var pixel:Vector2=viewer.get_camera().unproject_position(point)*Vector2(image.get_size())/root.get_visible_rect().size
	return image.get_pixelv(Vector2i(pixel).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
func run()->void:
	var lab:Node3D=load("res://tests/scenes/shadow_lab.tscn").instantiate();root.add_child(lab)
	var viewer:=GaussianSplattingViewer.new()
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=128
	viewer.shadow_light=lab.get_node("Sun")
	root.add_child(viewer)
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://shadow.ply",1));model.position.y=1;model.scale=Vector3.ONE*4
	for i in range(60):await process_frame
	viewer.camera_controller.position_camera_at(Vector3(0,3,5),Vector3.ZERO)
	await settle()
	var original:=sample(viewer,Vector3.ZERO)
	viewer.lighting.shadow_strength=1.0;viewer.lighting.shadow_resolution=256;viewer.lighting.shadows_enabled=true
	await settle(2.0)
	var shadowed:=sample(viewer,Vector3.ZERO)
	print("SHADOW PIXELS original ",original," shadowed ",shadowed)
	check(viewer.rasterizer.shadow_pass!=null and not viewer.rasterizer.shadow_pass.snapshot().is_empty(),"directional shadow map is built from the existing Gaussian atlas")
	check(shadowed.r<original.r-0.15,"actual Gaussian opacity casts a visible shadow onto the ordinary receiver material")
	model.position.x=0.7
	await settle(2.0)
	var old_location:=sample(viewer,Vector3.ZERO)
	var moved:=sample(viewer,Vector3(0.7,0,0))
	print("SHADOW MOVED ",old_location," new ",moved)
	check(old_location.r>shadowed.r+0.15 and moved.r<original.r-0.15,"shadow follows the model transform and clears its former location")
	model.cast_gaussian_shadows=false
	await settle(2.0)
	check(sample(viewer,Vector3(0.7,0,0)).r>moved.r+0.15,"per-model cast toggle removes its shadow without changing Gaussian residency")
	lab.get_node("Floor").hide()
	model.position.x=0;model.cast_gaussian_shadows=true
	var receiver_model:=viewer.load_new_splat_from_path(Checks.fixture("user://shadow-receiver.ply",1))
	receiver_model.position.y=0.1;receiver_model.cast_gaussian_shadows=false;receiver_model.scale=Vector3.ONE*2
	for i in range(60):await process_frame
	viewer.camera_controller.position_camera_at(Vector3(0,0.1,3),Vector3(0,0.1,0))
	await settle(2.0)
	var buffer:=viewer.render_texture.get_image()
	var pixel:=Vector2i(buffer.get_width()/2,buffer.get_height()/2)
	print("RECEIVER SCENE ",receiver_model.global_transform," size ",buffer.get_size()," stats ",viewer.rasterizer.get_stats().get("splats_rendered_frame")," active ",viewer.current_state)
	var captured:Color=buffer.get_pixelv(pixel)
	receiver_model.receive_gaussian_shadows=true
	await settle(2.0)
	var received:Color=viewer.render_texture.get_image().get_pixelv(pixel)
	print("GAUSSIAN RECEIVER ",captured," shaded ",received)
	check(received.r<captured.r*0.65 and absf(received.a-captured.a)<0.01,"opt-in Gaussian receiver darkens captured radiance while preserving opacity")
	receiver_model.receive_gaussian_shadows=false
	await settle()
	check(viewer.render_texture.get_image().get_pixelv(pixel).is_equal_approx(captured),"disabling Gaussian receiving restores captured radiance")
	viewer.lighting.shadows_enabled=false
	await settle()
	check(viewer.total_splats_to_load==2 and model.is_loaded,"shadow changes preserve the full source model")
	root.get_texture().get_image().save_png("user://shadow-lab.png")
	viewer.free();lab.free();await process_frame
	print("SHADOW CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
