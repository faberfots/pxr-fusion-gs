extends SceneTree
const Checks=preload("res://tests/core_checks.gd")
class UnavailableRenderer extends GaussianSplattingRasterizer:
	func init_gpu()->Error:return ERR_UNAVAILABLE
class RecoveringViewer extends GaussianSplattingViewer:
	var fail_next := false
	func _make_migration_renderer(settings:GaussianSplattingConfig)->GaussianSplattingRasterizer:
		if fail_next:
			fail_next=false
			return UnavailableRenderer.new(get_viewport().size,Texture2DRD.new(),get_camera(),settings)
		return super._make_migration_renderer(settings)
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func settle(viewer:GaussianSplattingViewer)->void:
	var started:=Time.get_ticks_msec()
	var i:=0
	while Time.get_ticks_msec()-started<15000:
		await process_frame
		i+=1
		if i>2 and not viewer.is_loading() and not viewer._applying_config and not viewer._queued_configuration:return
func bytes_for(viewer:GaussianSplattingViewer,node:GaussianSplat)->PackedByteArray:
	return viewer.rasterizer._sync(func():return viewer.rasterizer.context.device.buffer_get_data(viewer.rasterizer.descriptors.splats.rid,node.buffer_offset,node.splat_count*240))
func run()->void:
	var viewer:=RecoveringViewer.new()
	viewer.config=GaussianSplattingConfig.create_default();viewer.config.memory_max_vram_budget_mb=32
	root.add_child(viewer)
	var a:=viewer.load_new_splat_from_path(Checks.fixture("user://migration-a.ply",7))
	var b:=viewer.load_new_splat_from_path(Checks.fixture("user://migration-b.ply",40000))
	viewer.config.tile_size=8
	await settle(viewer)
	check(a.is_loaded and b.is_loaded and viewer.config.tile_size==8,"configuration requested during loading applies after the full batch")
	viewer.select_model_id(b.model_id)
	var original:=bytes_for(viewer,b)
	var signature:=viewer.config.gpu_signature()
	viewer.fail_next=true
	viewer.config.tile_size=32
	await settle(viewer)
	check(viewer.config.gpu_signature()==signature and viewer.rasterizer.gpu_init_complete,"failed GPU rebuild restores the previous working layout")
	check(bytes_for(viewer,b)==original and viewer.get_selected_model()==b and a.is_loaded,"failed rebuild preserves both Gaussian populations and stable selection")
	viewer.config.memory_max_instances=1
	await settle(viewer)
	check(viewer.config.memory_max_instances>1 and a.is_loaded and b.is_loaded,"valid configuration with insufficient instance capacity is rejected before modifying residency")
	var once:=[false]
	var deleted:WeakRef=weakref(a)
	viewer.configuration_migration_changed.connect(func(active):
		if active and not once[0]:once[0]=true;deleted.get_ref().queue_free()
	)
	viewer.config.tile_size=32
	await settle(viewer)
	check(viewer.total_splats_to_load==40000 and b.is_loaded and viewer.get_selected_model()==b,"deletion during migration preserves the remaining model")
	var after:=bytes_for(viewer,b)
	for i in range(b.splat_count):
		original.encode_float(i*240+44,after.decode_float(i*240+44))
	check(after==original,"compacted instance IDs do not change remaining Gaussian geometry or radiance")
	viewer.free()
	print("MIGRATION RECOVERY COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
