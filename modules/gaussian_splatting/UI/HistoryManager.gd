extends Node

const MAX_HISTORY = 10
const HISTORY_FILE = "user://splat_history.cfg"

var recent_files: Array[String] = []

func _ready() -> void:
	load_history()

func load_history() -> void:
	var config_file = ConfigFile.new()
	var err = config_file.load(HISTORY_FILE)
	if err == OK:
		recent_files = config_file.get_value("history", "files", [])

func save_history() -> void:
	var config_file = ConfigFile.new()
	config_file.set_value("history", "files", recent_files)
	config_file.save(HISTORY_FILE)

# Called by the viewer when a file is successfully loaded
func add_file(file_path: String) -> void:
	# If the path is already in the list, remove it to move it to the top
	if file_path in recent_files:
		recent_files.erase(file_path)
	
	# Add the new path to the front of the list
	recent_files.insert(0, file_path)
	
	# Trim the list if it's too long
	if recent_files.size() > MAX_HISTORY:
		recent_files.resize(MAX_HISTORY)
		
	save_history()

func clear_history() -> void:
	recent_files.clear()
	save_history()
