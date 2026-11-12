# ViewportCapture.gd
class_name ViewportCapture
extends Node

## The "Visual Cortex" of the Spatial Intelligence System.
## Responsible for capturing, processing, and encoding the current view.

# --- Public API ---

## Captures the current viewport frame.
## Returns: An Image resource containing the screenshot.
static func capture_current_view(viewport: Viewport) -> Image:
	if not is_instance_valid(viewport):
		push_error("[ViewportCapture] Invalid viewport.")
		return null
	
	# Godot 4.5+ Optimization:
	# getting the texture is fast, get_image() triggers a GPU->CPU sync stall.
	# We accept this stall for Phase 1 as it's an "on-demand" action (user clicked "Look").
	var tex := viewport.get_texture()
	if not tex:
		return null
		
	return tex.get_image()

## Encodes an image to Base64 for LLM transmission.
## Returns: A Base64 string representation of the PNG/JPEG.
static func encode_image_to_base64(image: Image, use_jpeg: bool = true, quality: float = 0.75) -> String:
	if not image or image.is_empty():
		return ""
		
	var buffer: PackedByteArray
	if use_jpeg:
		buffer = image.save_jpg_to_buffer(quality)
	else:
		buffer = image.save_png_to_buffer()
		
	return Marshalls.raw_to_base64(buffer)

## Saves the captured image to disk (Debugging/Logging)
static func save_capture_to_disk(image: Image, context_id: String) -> void:
	var path = "user://captures/capture_%s_%d.jpg" % [context_id, Time.get_ticks_msec()]
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("captures"):
		dir.make_dir("captures")
	
	image.save_jpg(path)
	print("[VisualCortex] Saved capture to: %s" % path)

## One capture is shared by the preview and provider. Hide every canvas layer in this viewport.
static func capture_scene_only(viewport: Viewport) -> Image:
	if not is_instance_valid(viewport): return null
	var hidden: Array[CanvasLayer] = []
	var controls: Array[Control] = []
	_collect_overlays(viewport, viewport, hidden, controls)
	var debug := viewport.get_tree().get_first_node_in_group("gs_debug_ui")
	var debug_was_visible := false
	if debug and "show_ui" in debug:
		debug_was_visible = debug.show_ui
		debug.show_ui = false
	await RenderingServer.frame_post_draw
	var image := capture_current_view(viewport)
	for layer in hidden:
		if is_instance_valid(layer): layer.show()
	for control in controls:
		if is_instance_valid(control): control.show()
	if is_instance_valid(debug) and debug_was_visible: debug.show_ui = true
	if image and max(image.get_width(), image.get_height()) > 1280:
		var scale: float = 1280.0 / max(image.get_width(), image.get_height())
		image.resize(maxi(1, int(image.get_width() * scale)), maxi(1, int(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return image

static func _collect_overlays(node: Node, viewport: Viewport, layers: Array[CanvasLayer], controls: Array[Control]) -> void:
	for child in node.get_children():
		if child is Viewport and child != viewport: continue
		if child is CanvasLayer:
			if child.visible:
				layers.append(child)
				child.hide()
			continue
		if child is Control:
			if child.visible:
				controls.append(child)
				child.hide()
			continue
		_collect_overlays(child, viewport, layers, controls)
