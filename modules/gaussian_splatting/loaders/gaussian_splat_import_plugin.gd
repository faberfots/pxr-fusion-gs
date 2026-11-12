# gaussian_splat_import_plugin.gd
@tool
extends EditorImportPlugin

## Discovers and processes .ply files into optimized .gsres resources.
## Part of Phase 1: Splat Atlas & Streaming Core.

enum Presets { DEFAULT }

func _get_importer_name() -> String:
	return "gaussian_splatting.ply_importer"

func _get_visible_name() -> String:
	return "Gaussian Splat Resource (.gsres)"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["ply"])

func _get_save_extension() -> String:
	return "res"

func _get_resource_type() -> String:
	return "Resource"

func _get_priority() -> float:
	# Give this priority over generic mesh importers for PLY files
	return 1.0

func _get_import_order() -> int:
	return 0

func _get_preset_count() -> int:
	return Presets.size()

func _get_preset_name(preset_index: int) -> String:
	match preset_index:
		Presets.DEFAULT:
			return "Default"
		_:
			return "Unknown"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	# Future-proof: We can add compression or SH-band dropping options here later.
	return []

# --- FIX: option_name must be StringName in Godot 4.x ---
func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var dest_path = "%s.%s" % [save_path, _get_save_extension()]
	
	# Call the disruptive PlyConverter we built in Phase 1
	var err = PlyConverter.convert_ply_to_gsres(source_file, dest_path)
	
	if err != OK:
		push_error("Failed to import PLY: %s" % source_file)
		return err
		
	return OK
