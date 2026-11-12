@tool
extends EditorPlugin

## Smart Camera Switcher Plugin - Fixed Main Controller
## Handles initialization, cleanup, and editor integration with proper error handling

const PLUGIN_NAME = "Smart Camera Switcher"
const AUTOLOAD_NAME = "CameraManager"
const AUTOLOAD_PATH = "res://addons/smart_camera_switcher/autoload/camera_manager.gd"

# Project settings paths
const SETTINGS_BASE = "smart_camera_switcher/"
const SETTING_ACTIVATION_KEY = SETTINGS_BASE + "activation_key"
const SETTING_UI_STYLE = SETTINGS_BASE + "ui_style"
const SETTING_TRANSITION_DURATION = SETTINGS_BASE + "transition_duration"
const SETTING_AUTO_HIDE_DELAY = SETTINGS_BASE + "auto_hide_delay"
const SETTING_ENABLE_SHORTCUTS = SETTINGS_BASE + "enable_keyboard_shortcuts"
const SETTING_AUTO_REGISTER = SETTINGS_BASE + "auto_register_cameras"
const SETTING_AUTO_INSTANTIATE_UI = SETTINGS_BASE + "auto_instantiate_ui"  # [NEW] Plug & Play

# Plugin state
var plugin_enabled: bool = false

func _enter_tree():
	"""Called when plugin is enabled - Setup everything needed"""
	print("[%s] Initializing plugin..." % PLUGIN_NAME)
	
	if plugin_enabled:
		print("[%s] Plugin already enabled, skipping initialization" % PLUGIN_NAME)
		return
	
	# Setup project settings with default values
	if not _setup_project_settings():
		push_error("[%s] Failed to setup project settings" % PLUGIN_NAME)
		return
	
	# Add the camera manager as autoload singleton
	if not _setup_autoload():
		push_error("[%s] Failed to setup autoload" % PLUGIN_NAME)
		return
	
	plugin_enabled = true
	print("[%s] Plugin initialized successfully!" % PLUGIN_NAME)

func _exit_tree():
	"""Called when plugin is disabled - Clean up everything"""
	print("[%s] Cleaning up plugin..." % PLUGIN_NAME)
	
	if not plugin_enabled:
		print("[%s] Plugin not enabled, skipping cleanup" % PLUGIN_NAME)
		return
	
	# Remove the autoload singleton
	_cleanup_autoload()
	
	plugin_enabled = false
	print("[%s] Plugin cleanup complete!" % PLUGIN_NAME)

func _setup_autoload() -> bool:
	"""Setup the CameraManager autoload with error handling"""
	# Check if autoload already exists
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		print("[%s] Autoload already exists, updating path..." % PLUGIN_NAME)
		remove_autoload_singleton(AUTOLOAD_NAME)
	
	# Verify the script file exists
	if not FileAccess.file_exists(AUTOLOAD_PATH):
		push_error("[%s] CameraManager script not found at: %s" % [PLUGIN_NAME, AUTOLOAD_PATH])
		return false
	
	# Add the autoload
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	print("[%s] Added autoload singleton: %s" % [PLUGIN_NAME, AUTOLOAD_NAME])
	return true

func _cleanup_autoload():
	"""Clean up the autoload singleton"""
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
		print("[%s] Removed autoload singleton: %s" % [PLUGIN_NAME, AUTOLOAD_NAME])

func _setup_project_settings() -> bool:
	"""Setup project settings with default values and proper hints"""
	print("[%s] Setting up project settings..." % PLUGIN_NAME)
	
	# Setup input actions first
	_setup_input_actions()
	
	# Activation key setting
	_setup_activation_key_setting()
	
	# UI Style setting
	_setup_ui_style_setting()
	
	# Transition duration setting
	_setup_transition_duration_setting()
	
	# Auto hide delay setting
	_setup_auto_hide_delay_setting()
	
	# Enable keyboard shortcuts setting
	_setup_enable_shortcuts_setting()
	
	# Auto register cameras setting
	_setup_auto_register_setting()
	
	# [NEW] Auto instantiate UI setting (Plug & Play)
	_setup_auto_instantiate_ui_setting()
	
	# Save the settings
	var save_result = ProjectSettings.save()
	if save_result != OK:
		push_error("[%s] Failed to save project settings: Error %d" % [PLUGIN_NAME, save_result])
		return false
	
	print("[%s] Project settings configured successfully!" % PLUGIN_NAME)
	return true

func _setup_input_actions():
	"""Setup input map actions for camera switching"""
	print("[%s] Setting up input actions..." % PLUGIN_NAME)
	
	# Camera cycle next action
	if not InputMap.has_action("camera_cycle_next"):
		InputMap.add_action("camera_cycle_next")
		var event_tab = InputEventKey.new()
		event_tab.keycode = KEY_TAB
		InputMap.action_add_event("camera_cycle_next", event_tab)
		print("[%s] Added camera_cycle_next action (Tab key)" % PLUGIN_NAME)
	
	# Camera cycle previous action
	if not InputMap.has_action("camera_cycle_previous"):
		InputMap.add_action("camera_cycle_previous")
		var event_shift_tab = InputEventKey.new()
		event_shift_tab.keycode = KEY_TAB
		event_shift_tab.shift_pressed = true
		InputMap.action_add_event("camera_cycle_previous", event_shift_tab)
		print("[%s] Added camera_cycle_previous action (Shift+Tab)" % PLUGIN_NAME)
	
	# Camera selector toggle action
	if not InputMap.has_action("camera_selector_toggle"):
		InputMap.add_action("camera_selector_toggle")
		var event_right_click = InputEventMouseButton.new()
		event_right_click.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("camera_selector_toggle", event_right_click)
		print("[%s] Added camera_selector_toggle action (Right Click)" % PLUGIN_NAME)

func _setup_activation_key_setting():
	"""Setup activation key setting"""
	if not ProjectSettings.has_setting(SETTING_ACTIVATION_KEY):
		ProjectSettings.set_setting(SETTING_ACTIVATION_KEY, "mouse_right")
	
	var activation_hint = {
		"name": SETTING_ACTIVATION_KEY,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "mouse_right,mouse_middle,key_tab,key_c,key_v"
	}
	ProjectSettings.add_property_info(activation_hint)

func _setup_ui_style_setting():
	"""Setup UI style setting"""
	if not ProjectSettings.has_setting(SETTING_UI_STYLE):
		ProjectSettings.set_setting(SETTING_UI_STYLE, "buttons")  # Changed from "wheel" to "buttons"
	
	var ui_style_hint = {
		"name": SETTING_UI_STYLE,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "buttons,tabs,dropdown,grid"  # Removed "wheel" since we don't have wheel UI
	}
	ProjectSettings.add_property_info(ui_style_hint)

func _setup_transition_duration_setting():
	"""Setup transition duration setting"""
	if not ProjectSettings.has_setting(SETTING_TRANSITION_DURATION):
		ProjectSettings.set_setting(SETTING_TRANSITION_DURATION, 0.5)
	
	var duration_hint = {
		"name": SETTING_TRANSITION_DURATION,
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.1,2.0,0.1"
	}
	ProjectSettings.add_property_info(duration_hint)

func _setup_auto_hide_delay_setting():
	"""Setup auto hide delay setting"""
	if not ProjectSettings.has_setting(SETTING_AUTO_HIDE_DELAY):
		ProjectSettings.set_setting(SETTING_AUTO_HIDE_DELAY, 3.0)
	
	var hide_delay_hint = {
		"name": SETTING_AUTO_HIDE_DELAY,
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "1.0,10.0,0.5"
	}
	ProjectSettings.add_property_info(hide_delay_hint)

func _setup_enable_shortcuts_setting():
	"""Setup enable keyboard shortcuts setting"""
	if not ProjectSettings.has_setting(SETTING_ENABLE_SHORTCUTS):
		ProjectSettings.set_setting(SETTING_ENABLE_SHORTCUTS, true)
	
	var shortcuts_hint = {
		"name": SETTING_ENABLE_SHORTCUTS,
		"type": TYPE_BOOL
	}
	ProjectSettings.add_property_info(shortcuts_hint)

func _setup_auto_register_setting():
	"""Setup auto register cameras setting"""
	if not ProjectSettings.has_setting(SETTING_AUTO_REGISTER):
		ProjectSettings.set_setting(SETTING_AUTO_REGISTER, true)
	
	var auto_register_hint = {
		"name": SETTING_AUTO_REGISTER,
		"type": TYPE_BOOL
	}
	ProjectSettings.add_property_info(auto_register_hint)

func _setup_auto_instantiate_ui_setting():
	"""[NEW] Setup auto instantiate UI setting for Plug & Play"""
	if not ProjectSettings.has_setting(SETTING_AUTO_INSTANTIATE_UI):
		ProjectSettings.set_setting(SETTING_AUTO_INSTANTIATE_UI, true)
	
	var auto_ui_hint = {
		"name": SETTING_AUTO_INSTANTIATE_UI,
		"type": TYPE_BOOL
	}
	ProjectSettings.add_property_info(auto_ui_hint)

func get_plugin_name() -> String:
	"""Return the plugin name for identification"""
	return PLUGIN_NAME

func _has_main_screen() -> bool:
	"""Plugin doesn't have a main screen"""
	return false

func _get_plugin_name() -> String:
	"""Get plugin name for editor"""
	return PLUGIN_NAME

func _disable_plugin():
	"""Handle plugin disable"""
	_exit_tree()

func _enable_plugin():
	"""Handle plugin enable"""
	_enter_tree()

# Utility functions for checking plugin state
func is_plugin_enabled() -> bool:
	"""Check if plugin is properly enabled"""
	return plugin_enabled and ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME)

func get_camera_manager_path() -> String:
	"""Get the path to the camera manager script"""
	return AUTOLOAD_PATH

func verify_installation() -> Dictionary:
	"""Verify plugin installation and return status"""
	var status = {
		"plugin_enabled": plugin_enabled,
		"autoload_exists": ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME),
		"script_exists": FileAccess.file_exists(AUTOLOAD_PATH),
		"settings_configured": true,
		"errors": []
	}
	
	# Check settings
	var required_settings = [
		SETTING_ACTIVATION_KEY,
		SETTING_UI_STYLE,
		SETTING_TRANSITION_DURATION,
		SETTING_AUTO_HIDE_DELAY,
		SETTING_ENABLE_SHORTCUTS,
		SETTING_AUTO_REGISTER
	]
	
	for setting in required_settings:
		if not ProjectSettings.has_setting(setting):
			status.settings_configured = false
			status.errors.append("Missing setting: " + setting)
	
	# Check autoload path
	if status.autoload_exists:
		var autoload_path = ProjectSettings.get_setting("autoload/" + AUTOLOAD_NAME)
		if autoload_path != AUTOLOAD_PATH:
			status.errors.append("Autoload path mismatch: expected %s, got %s" % [AUTOLOAD_PATH, autoload_path])
	
	return status
