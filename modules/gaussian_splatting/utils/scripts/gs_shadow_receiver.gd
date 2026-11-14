class_name GSShadowReceiver3D
extends Node3D
## Explicit opacity-shadow participant. Original materials and next passes are retained.
@export var receiver:GeometryInstance3D
var support_reason:=""
var _passes:Array[Dictionary]=[]
func _ready()->void:
	add_to_group("gs_shadow_receivers")
	if not receiver:support_reason="Assign a geometry receiver.";return
	if receiver.material_override:
		_attach(receiver.material_override,-1)
	elif receiver is MeshInstance3D and receiver.mesh:
		for surface in range(receiver.mesh.get_surface_count()):_attach(receiver.get_active_material(surface),surface)
	else:support_reason="Assign material_override or use a MeshInstance3D receiver."
func _attach(original:Material,surface:int)->void:
	if original and not original is BaseMaterial3D:
		support_reason="Custom vertex shaders require a matching receiver adapter.";return
	var derived:Material=original.duplicate(false) if original else StandardMaterial3D.new()
	var shadow:=ShaderMaterial.new()
	shadow.shader=preload("res://modules/gaussian_splatting/shaders/spatial/gaussian_shadow_receiver.gdshader")
	shadow.render_priority=mini(127,derived.render_priority+1)
	shadow.next_pass=derived.next_pass;derived.next_pass=shadow
	var previous:Material=receiver.material_override if surface<0 else receiver.get_surface_override_material(surface)
	if surface<0:receiver.material_override=derived
	else:receiver.set_surface_override_material(surface,derived)
	_passes.append({"surface":surface,"previous":previous,"derived":derived,"shadow":shadow})
	support_reason="Gaussian opacity shadow receiver is ready."
func apply_shadow(frame:Dictionary,settings:GSLightingSettings)->void:
	for entry in _passes:
		var shadow:ShaderMaterial=entry.shadow
		shadow.set_shader_parameter("receiver_cull_mode",entry.derived.cull_mode)
		shadow.set_shader_parameter("shadow_enabled",not frame.is_empty() and settings.shadows_enabled)
		if frame.is_empty():continue
		shadow.set_shader_parameter("gaussian_shadow_map",frame.texture)
		shadow.set_shader_parameter("shadow_view",frame.view)
		shadow.set_shader_parameter("shadow_projection",frame.projection)
		shadow.set_shader_parameter("shadow_resolution",frame.resolution)
		shadow.set_shader_parameter("shadow_strength",settings.shadow_strength)
		shadow.set_shader_parameter("shadow_bias",settings.shadow_bias)
func _exit_tree()->void:
	if not is_instance_valid(receiver):return
	for entry in _passes:
		if entry.surface<0:
			if receiver.material_override==entry.derived:receiver.material_override=entry.previous
		elif receiver.get_surface_override_material(entry.surface)==entry.derived:
			receiver.set_surface_override_material(entry.surface,entry.previous)
	_passes.clear()
