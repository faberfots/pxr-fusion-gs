@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type("Advanced Free Fly camera", "CharacterBody3D", preload("Src/advanced_free_fly_startup.gd"), preload("Assets/icon.png"))

func _exit_tree():
	remove_custom_type("Advanced Free Fly camera")
