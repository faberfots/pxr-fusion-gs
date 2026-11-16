extends VBoxContainer
## Local file commands only. Models, view and operation state stay viewer-owned.
var viewer:GaussianSplattingViewer
func _ready()->void:
	%Open.pressed.connect(func():viewer.request_import(true))
	%Save.pressed.connect(func():
		viewer.set_camera_blocker("save_scene_dialog",true)
		%SaveDialog.popup_centered()
	)
	%SaveDialog.canceled.connect(func():viewer.set_camera_blocker("save_scene_dialog",false))
	%SaveDialog.file_selected.connect(func(path):
		viewer.set_camera_blocker("save_scene_dialog",false)
		if path.get_extension().is_empty():path+=".pxrscene"
		await viewer.save_composition(path,%IncludeAssets.button_pressed)
	)
	viewer.composition_progress.connect(func(message):%Status.text=message)
	viewer.error_occurred.connect(func(message,_code):%Status.text=message)
func _process(_delta:float)->void:
	var unavailable:=not is_instance_valid(viewer) or viewer.composition_busy or viewer.placement_active or viewer.is_loading() or viewer._atlas_migration!=null
	%Open.disabled=unavailable;%Save.disabled=unavailable
func _exit_tree()->void:
	if is_instance_valid(viewer):viewer.set_camera_blocker("save_scene_dialog",false)
