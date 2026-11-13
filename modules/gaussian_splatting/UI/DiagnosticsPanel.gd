class_name GSDiagnosticsPanel
extends GSFloatingPanel
var viewer:GaussianSplattingViewer
var _elapsed:=0.0
func _ready()->void:
	super._ready()
	%Close.pressed.connect(func():get_parent().show_ui=false)
	%Fov.value_changed.connect(func(value):
		if viewer and viewer.get_camera():viewer.get_camera().fov=value
	)
	%ResetFov.pressed.connect(func():
		if viewer and viewer.get_camera():viewer.get_camera().fov=viewer.config.camera_default_fov
	)
	%Override.pressed.connect(func():
		if viewer and viewer.rasterizer:viewer.rasterizer.basis_override=viewer.get_camera().global_basis.inverse()
	)
	%ResetBasis.pressed.connect(func():
		if viewer and viewer.rasterizer:viewer.rasterizer.basis_override=Basis.IDENTITY
	)
	%EnableStats.toggled.connect(func(enabled):
		if viewer:viewer.enable_debug_stats=enabled
	)
	%Load.pressed.connect(func():
		if viewer:viewer.show_load_zone=true
	)
	if not _placed:position=Vector2(24,24)
func _process(delta:float)->void:
	_elapsed+=delta
	if not visible or _elapsed<0.2 or not is_instance_valid(viewer):return
	_elapsed=0.0
	var stats:=viewer.get_stats()
	%Stats.text="[color=#81e6ce]%s[/color]  ·  %d FPS\n%d models · %s splats\nGPU allocation: %.1f MiB\nResources: %d\n%s" % [stats.viewer_state,Engine.get_frames_per_second(),viewer.get_model_snapshot().size(),str(viewer.total_splats_to_load),float(stats.get("tracked",0))/1048576.0,int(stats.get("resource_count",0)),viewer.last_error]
	var pipeline:Dictionary=stats.get("pipeline_stats",{})
	%Stats.text+="\nRendered: %d  ·  target %s\nPipelines: %d valid / %d dirty / %d errors" % [int(stats.get("splats_rendered_frame",0)),str(stats.get("texture_size",Vector2i.ZERO)),int(pipeline.get("valid",0)),int(pipeline.get("dirty",0)),int(pipeline.get("error",0))]
	if viewer.get_camera():
		%Fov.set_value_no_signal(viewer.get_camera().fov)
		%Stats.text+="\nCamera: %s\nPosition: %s" % [viewer.get_camera().name,str(viewer.get_camera().global_position)]

	%EnableStats.set_pressed_no_signal(viewer.enable_debug_stats)
	%Override.disabled=not viewer.rasterizer or viewer.rasterizer.basis_override!=Basis.IDENTITY
	%ResetBasis.disabled=not viewer.rasterizer or viewer.rasterizer.basis_override==Basis.IDENTITY
