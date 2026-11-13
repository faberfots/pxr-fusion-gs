extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle()->void:
	await create_timer(1.3).timeout
	await RenderingServer.frame_post_draw
func center(viewer:GaussianSplattingViewer)->Color:
	var image:=viewer.render_texture.get_image()
	return image.get_pixel(image.get_width()/2,image.get_height()/2)
func run()->void:
	var viewer:=GaussianSplattingViewer.new()
	viewer.config=GaussianSplattingConfig.create_default()
	viewer.config.memory_max_vram_budget_mb=64
	GSColorSettings.apply(viewer.config,GSColorSettings.profile("Natural"))
	root.add_child(viewer)
	var model:=viewer.load_new_splat_from_path(Checks.fixture("user://hybrid.ply",1))
	for i in range(60):await process_frame
	viewer.camera_controller.position_camera_at(Vector3(0,0,2),Vector3.ZERO)
	await settle()
	var baseline:=center(viewer)
	check(baseline.r>baseline.b,"Gaussian baseline is visible before integration")
	var lab:Node3D=load("res://tests/scenes/hybrid_lab.tscn").instantiate()
	root.add_child(lab)
	var pane:GSAlphaMesh3D=lab.get_node("Pane")
	await settle()
	var front:=center(viewer)
	print("HYBRID COLORS baseline ",baseline," front ",front," reason ",pane.support_reason)
	check(viewer.rasterizer.transparency_active and pane.layers==0,"compatible alpha mesh enters the hardware fragment capture path once")
	check(front.b>baseline.b+0.2 and front.r<baseline.r*0.7,"front pane attenuates the actual Gaussian instead of merely sorting whole objects")
	pane.position.z=-0.5
	await settle()
	var behind:=center(viewer)
	print("HYBRID BEHIND ",behind)
	check(behind.r>front.r and behind.b<front.b,"moving the same pane behind the Gaussian changes per-pixel depth composition")
	pane.position.z=0.5
	pane.rotation.y=0.6
	await settle()
	check(viewer.rasterizer.transparency_active,"rotated rigid participant retains integrated rendering")
	GSColorSettings.apply(viewer.config,GSColorSettings.profile("Warm daylight"))
	await settle()
	check(center(viewer).b>0.2,"Gaussian color edits preserve the blue mesh contribution")
	GSColorSettings.apply(viewer.config,GSColorSettings.profile("Natural"))
	pane.rotation=Vector3.ZERO;pane.position.z=0.5
	var material:=pane.material_override as StandardMaterial3D
	var texture_image:=Image.create(2,2,false,Image.FORMAT_RGBA8);texture_image.fill(Color8(0,0,128,128))
	material.albedo_color=Color.WHITE;material.albedo_texture=ImageTexture.create_from_image(texture_image)
	model.hide();await settle()
	var textured:=center(viewer)
	print("HYBRID TEXTURE ",textured)
	check(textured.b>0.09 and textured.b<0.13 and absf(textured.a-0.502)<0.01,"albedo texture is sampled in linear color with independent alpha")
	material.albedo_texture=null;material.albedo_color=Color(0,0,1,0.5)
	var second:Node3D=load("res://tests/scenes/hybrid_lab.tscn").instantiate();root.add_child(second)
	var crossing:GSAlphaMesh3D=second.get_node("Pane")
	crossing.material_override=crossing.material_override.duplicate(true)
	(crossing.material_override as StandardMaterial3D).albedo_color=Color(0,1,0,0.5)
	pane.position.z=0;crossing.position.z=0
	pane.scale=Vector3.ONE*2;crossing.scale=Vector3.ONE*2
	pane.rotation.y=0.65;crossing.rotation.y=-0.65
	await settle()
	var crossed:=viewer.render_texture.get_image()
	var left:=crossed.get_pixel(crossed.get_width()/2-5,crossed.get_height()/2);var right:=crossed.get_pixel(crossed.get_width()/2+5,crossed.get_height()/2)
	print("INTERSECTION ",left," / ",right)
	check((left.b-left.g)*(right.b-right.g)<-0.01,"intersecting transparent surfaces exchange depth order across actual pixels")
	second.free();pane.scale=Vector3.ONE;pane.rotation=Vector3.ZERO;model.show();await settle()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
	await settle()
	check(not viewer.rasterizer.transparency_active and pane.layers!=0 and not pane.support_reason.is_empty(),"unsupported shaded material retains native Godot rendering with a support reason")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	await settle()
	var allocation:int=viewer.rasterizer.get_stats().tracked
	check(viewer.rasterizer.resize(Vector2i(96,64))==OK,"integrated renderer admits a viewport resize within the shared budget")
	await settle()
	check(viewer.rasterizer.transparency_active and pane.layers==0 and viewer.render_texture.get_width()==96,"viewport resize rebuilds dependent alpha targets and resumes integration")
	check(viewer.rasterizer.resize(Vector2i(64,64))==OK,"integrated renderer restores its original output size")
	await settle()
	pane.participate=false
	await settle()
	check(not viewer.rasterizer.transparency_active and pane.layers!=0,"opting out restores ordinary Godot mesh rendering")
	check(viewer.rasterizer.transparency==null and viewer.rasterizer.get_stats().tracked<=allocation,"opt-out releases the alpha cache and its tracked GPU allocation")
	lab.free();viewer.free()
	await process_frame
	print("HYBRID CHECKS COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
