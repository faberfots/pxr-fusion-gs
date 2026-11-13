@tool
class_name GSPXRBrandMark
extends Control
## Presentation of the existing Polygonics mark, with an adaptive white/red wordmark.
func _ready()->void:
	resized.connect(_fit)
	_fit()
func _fit()->void:
	var side:=minf(size.x,size.y)
	var logo_size:=side*0.38
	$Diamond.size=Vector2.ONE*logo_size
	$Diamond.position=Vector2(size.x*0.5-logo_size*0.5,size.y*0.43-logo_size*0.5)
	$Wordmark.position=Vector2(size.x*0.06,size.y*0.63)
	$Wordmark.size=Vector2(size.x*0.88,size.y*0.22)
	$Wordmark.add_theme_font_size_override("normal_font_size",maxi(10,roundi(side*0.11)))
