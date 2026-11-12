# CognitivePanel.gd
class_name CognitivePanel
extends CanvasLayer

## The "Neural HUD" Interface for Project CORTEX.
## Handles user interaction, chat history, and vision preview.

# --- Components ---
@onready var draggable_container: Control = %DraggableContainer
@onready var chat_feed: RichTextLabel = %ChatFeed
@onready var input_field: LineEdit = %InputField
@onready var analyze_button: Button = %AnalyzeButton
@onready var status_light: ColorRect = %StatusLight
@onready var vision_preview: TextureRect = %VisionPreview
@onready var close_button: Button = %CloseButton

# --- State ---
var _is_visible: bool = false

func _ready() -> void:
	# Initialize UI State
	status_light.color = Color.DIM_GRAY # Idle
	chat_feed.text = ""
	_print_system_message("CORTEX SYSTEMS ONLINE. Ready for visual analysis.")
	
	var privacy_box := VBoxContainer.new()
	input_field.get_parent().get_parent().add_child(privacy_box)
	input_field.get_parent().get_parent().move_child(privacy_box, input_field.get_parent().get_index())
	var consent := CheckButton.new()
	consent.text = "Send view + context to " + SIConfig.get_provider()
	consent.tooltip_text = "Cloud analysis transmits the 3D view, model names, bounds and your prompt."
	privacy_box.add_child(consent)
	consent.add_theme_font_size_override("font_size", 13)
	consent.toggled.connect(func(enabled):
		SpatialIntelligence.policy.cloud_enabled = enabled
		if not enabled: SpatialIntelligence.cancel_analysis()
	)
	var actions := CheckButton.new()
	actions.text = "Allow camera and selection actions"
	privacy_box.add_child(actions)
	actions.add_theme_font_size_override("font_size", 13)
	actions.toggled.connect(func(enabled):
		SpatialIntelligence.policy.role = AIAccessPolicy.Role.OPERATOR if enabled else AIAccessPolicy.Role.ANALYST
		SpatialIntelligence.policy.actions_enabled = enabled
	)
	SpatialIntelligence.capture_ready.connect(func(image): vision_preview.texture = ImageTexture.create_from_image(image))
	# Connect Signals
	analyze_button.pressed.connect(_on_analyze_pressed)
	close_button.pressed.connect(_on_close_pressed)
	input_field.text_submitted.connect(_on_input_submitted)
	
	# Connect to The Brain
	SpatialIntelligence.analysis_started.connect(_on_brain_thinking)
	SpatialIntelligence.analysis_completed.connect(_on_brain_responded)
	SpatialIntelligence.analysis_failed.connect(_on_brain_failed)

# --- Public API ---
func show_panel() -> void:
	visible = true
	_is_visible = true
	
func hide_panel() -> void:
	input_field.release_focus()
	visible = false
	_is_visible = false

# --- Interaction Handlers ---
func _on_analyze_pressed() -> void:
	_submit_request()

func _on_input_submitted(_text: String) -> void:
	_submit_request()

func _on_close_pressed() -> void:
	hide_panel()

func _submit_request() -> void:
	var prompt = input_field.text.strip_edges()
	if prompt.is_empty():
		return
		
	# 1. Update UI immediately
	_print_user_message(prompt)
	input_field.clear()
	
	SpatialIntelligence.analyze_scene(prompt)

# --- Brain Signal Handlers ---
func _on_brain_thinking() -> void:
	status_light.color = Color.YELLOW # Thinking
	analyze_button.disabled = true
	input_field.editable = false
	analyze_button.text = "Thinking..."

func _on_brain_responded(response: String) -> void:
	status_light.color = Color.GREEN # Success
	_reset_ui_state()
	_print_ai_message(response)
	
	# Return to idle after a moment
	await get_tree().create_timer(1.0).timeout
	status_light.color = Color.DIM_GRAY

func _on_brain_failed(error: String) -> void:
	status_light.color = Color.RED # Error
	_reset_ui_state()
	_print_system_message("ERROR: " + error)

func _reset_ui_state() -> void:
	analyze_button.disabled = false
	input_field.editable = true
	analyze_button.text = "Analyze"
	input_field.grab_focus()

# --- Chat Feed Formatting ---
func _print_user_message(msg: String) -> void:
	chat_feed.append_text("\n[color=#88ccff][b]YOU:[/b][/color] %s" % msg.replace("[", "[lb]"))

func _print_ai_message(msg: String) -> void:
	chat_feed.append_text("\n[color=#aaffaa][b]CORTEX:[/b][/color] %s" % msg.replace("[", "[lb]"))

func _print_system_message(msg: String) -> void:
	chat_feed.append_text("\n[color=#888888][i]%s[/i][/color]" % msg.replace("[", "[lb]"))
