extends Button

## Smart Camera Switcher - Simple Safe Camera Button
## Minimal implementation to prevent freezing

# Camera data
var camera_id: String = ""
var camera_name: String = ""
var is_camera_active: bool = false

# Signals
signal camera_selected(camera_id: String)

func _ready():
	"""Simple initialization"""
	print("[CameraButton] Ready: %s" % name)
	
	# Set basic properties
	custom_minimum_size = Vector2(140, 50)
	
	# Connect the pressed signal manually if not connected
	if not pressed.is_connected(_on_button_pressed):
		pressed.connect(_on_button_pressed)

func setup_camera(p_camera_id: String, p_camera_name: String, p_metadata: Dictionary = {}):
	"""Setup button for a specific camera - SIMPLE VERSION"""
	camera_id = p_camera_id
	camera_name = p_camera_name
	
	# Update button text
	text = camera_name
	
	# Simple tooltip
	if "description" in p_metadata:
		tooltip_text = p_metadata["description"]
	else:
		tooltip_text = "Camera: " + camera_name
	
	print("[CameraButton] Setup: %s (ID: %s)" % [camera_name, camera_id])

func set_active(active: bool):
	"""Set active state - SIMPLE VERSION"""
	if is_camera_active == active:
		return
	
	is_camera_active = active
	
	# Simple visual feedback using built-in button states
	if active:
		# Use built-in pressed style for active
		button_pressed = true
		modulate = Color(1.2, 1.2, 1.4, 1.0)  # Slight blue tint
	else:
		button_pressed = false
		modulate = Color.WHITE
	
	print("[CameraButton] Active state: %s for %s" % [active, camera_name])

func _on_button_pressed():
	"""Handle button press - FIXED VERSION"""
	print("[CameraButton] === BUTTON PRESSED ===")
	print("[CameraButton] Camera: %s" % camera_name)
	print("[CameraButton] Camera ID: %s" % camera_id)
	
	# Immediate visual feedback
	modulate = Color(0.8, 0.8, 0.8, 1.0)
	
	# Emit signal IMMEDIATELY
	print("[CameraButton] Emitting camera_selected signal...")
	camera_selected.emit(camera_id)
	print("[CameraButton] Signal emitted!")
	
	# Reset modulate after short delay
	await get_tree().create_timer(0.1).timeout
	if is_camera_active:
		modulate = Color(1.2, 1.2, 1.4, 1.0)
	else:
		modulate = Color.WHITE
