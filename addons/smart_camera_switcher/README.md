# Smart Camera Switcher Plugin for Godot 4.4.1

A beautiful, intuitive camera switching system with modern UI. Features smooth transitions, auto-discovery, and flexible configuration. Perfect for games with multiple camera angles.

## ✨ Features

- **🎯 Intuitive Button UI** - Clean horizontal button interface with smooth animations
- **🔄 Smooth Transitions** - Multiple transition types (instant, smooth, fade)
- **🎮 Multiple Input Methods** - Mouse, keyboard shortcuts, and mouse wheel support
- **🔍 Auto-Discovery** - Automatically finds and registers cameras
- **⚙️ Flexible Configuration** - Extensive customization through Project Settings
- **🎨 Modern Design** - Glassmorphism-inspired UI with dark theme
- **♿ Accessibility** - Keyboard navigation and high contrast support
- **📦 Plugin Architecture** - Easy to install, enable, and integrate

## 🚀 Quick Start

### Installation

1. **Download the Plugin**
   ```
   Clone or download this repository to:
   your_project/addons/smart_camera_switcher/
   ```

2. **Enable the Plugin**
   - Go to `Project → Project Settings → Plugins`
   - Find "Smart Camera Switcher" and enable it
   - The plugin will automatically set up autoloads and project settings

3. **Add Camera Selector to Your Scene**
   ```gdscript
   # Method 1: Instantiate the selector UI scene
   var camera_selector = preload("res://addons/smart_camera_switcher/scenes/camera_selector_ui.tscn").instantiate()
   add_child(camera_selector)
   
   # Method 2: Auto-instantiate (add to your main scene's _ready)
   if not has_node("CameraSelectorUI"):
	   var camera_selector = preload("res://addons/smart_camera_switcher/scenes/camera_selector_ui.tscn").instantiate()
	   camera_selector.name = "CameraSelectorUI"
	   add_child(camera_selector)
   ```

### Camera Registration

Choose from three easy methods to register your cameras:

#### Method 1: Smart Camera Nodes (Recommended)
1. **Attach the Helper Script**
   - Select your Camera3D node
   - In the Inspector, click "Attach Script"
   - Choose `res://addons/smart_camera_switcher/scripts/camera_registration_helper.gd`
   - Or change the script to extend `SmartCameraNode`

2. **Configure in Inspector**
   ```
   Smart Camera Settings:
   ├── Camera Display Name: "Player Camera"
   ├── Camera Description: "Main player view"
   ├── Camera Icon: [your_icon.png/.svg]
   ├── Camera Priority: 0
   ├── Transition Type: Smooth
   ├── Transition Duration: 0.5
   └── Auto Register: ✓
   
   Camera Type:
   └── Camera Type: Main
   ```

3. **Done!** The camera registers automatically when the scene loads.

#### Method 2: Manual Registration
```gdscript
extends Node

func _ready():
	# Wait for CameraManager to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Register cameras manually
	var main_camera = $MainCamera
	var debug_camera = $DebugCamera
	
	# Simple registration
	CameraManager.register_camera(main_camera, "main_cam")
	
	# Advanced registration with metadata
	CameraManager.register_camera(debug_camera, "debug_cam", {
		"name": "Debug View",
		"description": "Development camera for debugging",
		"icon": "res://icons/debug_camera.png",
		"transition_type": "instant",
		"priority": 1
	})
```

#### Method 3: Auto-Discovery
```gdscript
extends Node

func _ready():
	# Wait for CameraManager to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Automatically find and register all Camera3D nodes
	CameraManager.auto_register_cameras_in_scene()
	
	# Or use the static helper
	SmartCameraNode.auto_register_scene_cameras()
```

## 🎮 Usage

### Default Controls

| Input | Action |
|-------|--------|
| **Right Click** | Toggle camera selector |
| **Mouse Wheel** | Cycle through cameras (when selector hidden) |
| **1-9 Keys** | Quick switch to camera by number (when selector visible) |
| **ESC** | Hide camera selector |
| **Click Outside** | Hide camera selector |

### Programmatic Control

```gdscript
# Switch to specific camera
CameraManager.set_active_camera("main_cam")

# Cycle through cameras
CameraManager.cycle_cameras(1)  # Next camera
CameraManager.cycle_cameras(-1) # Previous camera

# Get current camera
var active_camera = CameraManager.get_active_camera()
var active_id = CameraManager.get_active_camera_id()

# Check what cameras are registered
var cameras = CameraManager.get_registered_cameras()
for camera_id in cameras:
	print("Camera: ", camera_id)
```

### Smart Camera Node Methods

```gdscript
# For cameras using SmartCameraNode script
extends SmartCameraNode

func _ready():
	# Set this camera as active
	set_as_active()
	
	# Check if this is the active camera
	if is_active_camera():
		print("I'm the active camera!")
	
	# Update metadata after changes
	camera_display_name = "New Name"
	update_metadata()
```

## ⚙️ Configuration

### Project Settings

After enabling the plugin, configure it in `Project → Project Settings → Smart Camera Switcher`:

| Setting | Default | Options | Description |
|---------|---------|---------|-------------|
| **Activation Key** | `mouse_right` | `mouse_right`, `mouse_middle`, `key_tab`, `key_c`, `key_v` | How to show/hide the selector |
| **UI Style** | `buttons` | `buttons`, `tabs`, `dropdown`, `grid` | UI layout style |
| **Transition Duration** | `0.5` | `0.1` - `2.0` | Default camera transition time |
| **Auto Hide Delay** | `3.0` | `1.0` - `10.0` | Seconds before auto-hiding selector |
| **Enable Shortcuts** | `true` | `true`, `false` | Enable 1-9 key shortcuts |
| **Auto Register** | `true` | `true`, `false` | Auto-discover cameras on scene load |

### Camera Metadata

Each camera can have rich metadata:

```gdscript
{
	"name": "Display Name",           # Shown in UI
	"description": "Detailed info",   # Tooltip text
	"icon": "path/to/icon.png",      # Custom icon (PNG/SVG)
	"priority": 0,                    # Sort order
	"transition_type": "smooth",      # "instant", "smooth", "fade"
	"transition_duration": 0.5,       # Override default duration
	"camera_type": "main"            # "default", "main", "secondary", etc.
}
```

## 🎨 Customization

### Custom Icons

1. **Create Your Icons**
   - Use PNG or SVG format for best quality
   - Recommended size: 32x32 pixels
   - Place in `res://icons/` or your preferred folder

2. **Assign Icons**
   ```gdscript
   # Via metadata
   CameraManager.register_camera(camera, "my_cam", {
	   "icon": "res://icons/my_camera_icon.png"
   })
   
   # Via SmartCameraNode inspector
   # Set the "Camera Icon" property
   ```

### UI Position

You can change the UI position by modifying the `CameraSelectorUI` scene:

```gdscript
# In your scene script
@onready var camera_selector = $CameraSelectorUI

func _ready():
	# Change UI position: 0=Top, 1=Center, 2=Bottom
	camera_selector.ui_position = 0  # Top
```

### Custom Transitions

```gdscript
# Add custom transition types in camera metadata
CameraManager.register_camera(camera, "special_cam", {
	"transition_type": "fade",
	"transition_duration": 1.0
})
```

## 🔧 API Reference

### CameraManager (Autoload)

#### Core Methods
- `register_camera(camera: Camera3D, camera_id: String, metadata: Dictionary = {}) -> bool`
- `unregister_camera(camera_id: String) -> bool`
- `set_active_camera(camera_id: String, use_transition: bool = true) -> bool`
- `cycle_cameras(direction: int = 1) -> bool`
- `auto_register_cameras_in_scene(scene_root: Node = null) -> int`

#### Getters
- `get_registered_cameras() -> Dictionary`
- `get_camera_metadata(camera_id: String) -> Dictionary`
- `get_active_camera() -> Camera3D`
- `get_active_camera_id() -> String`
- `get_camera_list() -> Dictionary`
- `get_settings() -> Dictionary`

#### Signals
- `camera_registered(camera: Camera3D, camera_id: String)`
- `camera_unregistered(camera_id: String)`
- `camera_switched(from_camera: Camera3D, to_camera: Camera3D)`
- `camera_switch_started(target_camera: Camera3D)`
- `camera_switch_completed(active_camera: Camera3D)`
- `camera_list_changed`
- `active_camera_changed(camera: Camera3D)`

### SmartCameraNode (Helper Class)

#### Instance Methods
- `register_camera(custom_id: String = "", force_register: bool = false) -> bool`
- `unregister_camera() -> bool`
- `set_as_active() -> bool`
- `is_active_camera() -> bool`
- `update_metadata() -> bool`
- `get_camera_info() -> Dictionary`

#### Static Methods
- `register_camera_node(camera: Camera3D, camera_id: String = "", metadata: Dictionary = {}) -> bool`
- `auto_register_scene_cameras(scene_root: Node = null) -> int`

## 🎯 Examples

### Basic 3D Game Setup

```gdscript
# MainScene.gd
extends Node3D

@onready var player_camera = $Player/Camera3D
@onready var overview_camera = $OverviewCamera
@onready var debug_camera = $DebugCamera

func _ready():
	# Add camera selector UI
	var camera_selector = preload("res://addons/smart_camera_switcher/scenes/camera_selector_ui.tscn").instantiate()
	add_child(camera_selector)
	
	# Wait for CameraManager
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Register cameras with metadata
	CameraManager.register_camera(player_camera, "player", {
		"name": "Player View",
		"description": "Follow the player character",
		"icon": "res://icons/player_camera.png",
		"transition_type": "smooth"
	})
	
	CameraManager.register_camera(overview_camera, "overview", {
		"name": "Overview",
		"description": "Bird's eye view of the level",
		"icon": "res://icons/overview_camera.png",
		"transition_type": "smooth"
	})
	
	CameraManager.register_camera(debug_camera, "debug", {
		"name": "Debug",
		"description": "Development camera for debugging",
		"icon": "res://icons/debug_camera.png",
		"transition_type": "instant"
	})
```

### 2D Game with Multiple Views

```gdscript
# Game2D.gd
extends Node2D

func _ready():
	# Add camera selector UI
	var camera_selector = preload("res://addons/smart_camera_switcher/scenes/camera_selector_ui.tscn").instantiate()
	add_child(camera_selector)
	
	# Auto-register all cameras
	await get_tree().process_frame
	await get_tree().process_frame
	SmartCameraNode.auto_register_scene_cameras()
	
	# Connect to camera switch events
	CameraManager.camera_switched.connect(_on_camera_switched)

func _on_camera_switched(from_camera: Camera2D, to_camera: Camera2D):
	print("Switched from ", from_camera.name, " to ", to_camera.name)
	
	# Update UI based on camera
	match CameraManager.get_active_camera_id():
		"player":
			show_player_ui()
		"map":
			show_map_ui()
		"inventory":
			show_inventory_ui()
```

### Using SmartCameraNode Helper

```gdscript
# Attach this script to your Camera3D node
extends SmartCameraNode

func _ready():
	# Configuration is done in the inspector
	# Camera will auto-register if auto_register is enabled
	super._ready()
	
	# Optional: Set as active camera on scene start
	await get_tree().process_frame
	await get_tree().process_frame
	set_as_active()
```

## 🐛 Troubleshooting

### Common Issues

1. **"CameraManager not found" Error**
   - Ensure the plugin is enabled in Project Settings
   - Check that autoloads were added properly
   - Restart Godot after enabling the plugin

2. **Camera Selector Doesn't Appear**
   - Make sure you instantiated the `camera_selector_ui.tscn` scene
   - Check that the activation key is correct in Project Settings
   - Verify cameras are registered (check debug output)

3. **Cameras Not Registering**
   - Ensure CameraManager autoload is ready before registration
   - Add proper `await get_tree().process_frame` delays before registering
   - Check for error messages in the output

4. **UI Positioning Issues**
   - Check the `ui_position` property in CameraSelectorUI
   - Adjust panel positioning in the scene if needed

### Debug Information

```gdscript
# Add to your scene for debugging
func _ready():
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Print all registered cameras
	print("Registered cameras: ", CameraManager.get_registered_cameras().keys())
	
	# Monitor camera switches
	CameraManager.camera_switched.connect(func(from, to): 
		print("Camera switched: ", from.name, " -> ", to.name)
	)
	
	# Check active camera
	print("Active camera: ", CameraManager.get_active_camera_id())
	
	# Verify plugin installation
	var plugin_node = EditorInterface.get_editor_main_screen().get_plugin("Smart Camera Switcher")
	if plugin_node and plugin_node.has_method("verify_installation"):
		var status = plugin_node.verify_installation()
		print("Plugin status: ", status)
```

## 📁 File Structure

```
addons/smart_camera_switcher/
├── plugin.cfg                                    # Plugin configuration
├── plugin.gd                                     # Main plugin controller
├── scripts/
│   ├── camera_manager.gd                         # Core camera management (autoload)
│   ├── camera_registration_helper.gd             # SmartCameraNode helper class
│   ├── camera_selector_ui.gd                     # Main UI controller
│   └── camera_button.gd                          # Individual camera button
├── scenes/
│   ├── camera_selector_ui.tscn                   # Main UI scene
│   └── camera_button.tscn                        # Camera button scene
└── README.md                                     # This file
```

## 📄 License

This plugin is released under the MIT License. See LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to:
- Report bugs and issues
- Suggest new features
- Submit pull requests
- Improve documentation

## 📞 Support

- **Documentation**: Check this README and code comments
- **Issues**: Report bugs on the GitHub repository
- **Community**: Share your experience and get help from other users

---

**Made with ❤️ for the Godot community**

*Smart Camera Switcher - Making camera management effortless in Godot 4.4.1*
