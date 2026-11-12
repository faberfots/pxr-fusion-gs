extends ColorRect
class_name LoadingBar
## Loading progress bar for GaussianSplattingViewer
## Displays file loading progress at the top of the viewport
## Automatically fades in/out based on loading state

const MAX_ALPHA := 0.6

@onready var fade_tween : Tween

## Show or hide the loading bar with fade animation
func set_visibility(is_visible : bool) -> void:
	if fade_tween:
		fade_tween.kill()
	
	if is_visible:
		# Fade in immediately
		color.a = MAX_ALPHA
	else:
		# Fade out smoothly
		fade_tween = get_tree().create_tween()
		fade_tween.tween_property(self, 'color:a', 0.0, 0.4)

## Update loading progress (0.0 to 1.0)
func update_progress(progress : float) -> void:
	# Clamp progress to valid range
	progress = clampf(progress, 0.0, 1.0)
	
	# Get viewport width
	var viewport := get_viewport()
	if not viewport:
		return
	
	var width := float(viewport.size.x)
	
	# Update bar size and position
	size.x = width
	position.x = -width + width * progress
	
	# Ensure bar is visible during loading
	if progress > 0.0 and progress < 1.0:
		if color.a < MAX_ALPHA:
			set_visibility(true)
