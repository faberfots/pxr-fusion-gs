class_name CortexSegmentationCanvas
extends Control
## Snapshot-space input, independent of HUD density and letterboxing.
signal point_added(pixel:Vector2,foreground:bool)
signal box_added(rectangle:Rect2)
var image:Image
var texture:ImageTexture
var mask:ImageTexture
var points:=PackedVector2Array()
var labels:=PackedInt32Array()
var rectangle:=Rect2()
var has_box:=false
var box_mode:=false
var mask_opacity:=0.45
var _box_start:=Vector2.INF
func set_image(value:Image)->void:
	image=value;texture=ImageTexture.create_from_image(value) if value else null;mask=null;queue_redraw()
func set_mask(value:Image)->void:
	mask=ImageTexture.create_from_image(value) if value else null;queue_redraw()
func image_rect()->Rect2:
	if not image:return Rect2()
	var ratio:=minf(size.x/image.get_width(),size.y/image.get_height())
	var extent:=Vector2(image.get_size())*ratio
	return Rect2((size-extent)*0.5,extent)
func image_pixel(position:Vector2)->Vector2:
	var area:=image_rect()
	if not image or not area.has_point(position):return Vector2.INF
	return ((position-area.position)/area.size*Vector2(image.get_size())).clamp(Vector2.ZERO,Vector2(image.get_size())-Vector2.ONE)
func _gui_input(event:InputEvent)->void:
	if not image:return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		var pixel:=image_pixel(event.position)
		if not pixel.is_finite():return
		if box_mode and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_box_start=pixel
			elif _box_start.is_finite():
				var box:=Rect2(_box_start,pixel-_box_start).abs();_box_start=Vector2.INF
				if box.size.x>=2 and box.size.y>=2:box_added.emit(box)
		elif event.pressed:point_added.emit(pixel,event.button_index==MOUSE_BUTTON_LEFT and not event.shift_pressed)
		accept_event()
func _draw()->void:
	draw_style_box(get_theme_stylebox("normal","LineEdit"),Rect2(Vector2.ZERO,size))
	if not texture:return
	var area:=image_rect();draw_texture_rect(texture,area,false)
	if mask:draw_texture_rect(mask,area,false,Color(1,1,1,mask_opacity))
	var ratio:=area.size/Vector2(image.get_size())
	for i in range(points.size()):
		var at:=area.position+points[i]*ratio
		draw_circle(at,5,Color(0.05,0.07,0.1,1));draw_circle(at,3,Color(0.3,1,0.7) if labels[i]==1 else Color(1,0.3,0.3))
	if has_box:draw_rect(Rect2(area.position+rectangle.position*ratio,rectangle.size*ratio),Color(1,0.3,0.3),false,2)
