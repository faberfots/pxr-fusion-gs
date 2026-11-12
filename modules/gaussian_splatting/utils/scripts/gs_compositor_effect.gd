class_name GSCompositorEffect
extends CompositorEffect
## Runs GS compute after opaque depth is resolved and before transparent presentation.
var rasterizer_ref: WeakRef
var _unsupported_view_reported := false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	access_resolved_depth = true

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT or not rasterizer_ref:
		return
	var rasterizer = rasterizer_ref.get_ref()
	if not rasterizer or not rasterizer.gpu_init_complete:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not buffers:return
	if buffers.get_view_count()!=1:
		if not _unsupported_view_reported:
			_unsupported_view_reported=true
			rasterizer.call_deferred("emit_signal","frame_failed","Stereo XR rendering is not supported by the current renderer.",ERR_UNAVAILABLE)
		return
	rasterizer.render_on_render_thread(buffers.get_depth_layer(0), true)
