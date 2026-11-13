@tool
class_name GSAlphaMesh3D
extends MeshInstance3D
## Explicit rigid, unshaded StandardMaterial3D alpha participant.
## Unsupported materials retain their ordinary Godot path with a visible reason.
@export var participate := true
var support_reason := ""
var _native_layers := 1
var _source:Mesh
var _revision:=0
var _geometry: Array[Dictionary] = []
func _enter_tree() -> void:
	if Engine.is_editor_hint():return
	_native_layers=layers
	add_to_group("gs_alpha_meshes")
func _exit_tree() -> void:
	if not Engine.is_editor_hint():layers=_native_layers
func capture() -> Array[Dictionary]:
	if not participate or not is_visible_in_tree() or not mesh:
		layers=_native_layers;return []
	if _source!=mesh:
		if _source and _source.changed.is_connected(_invalidate_geometry):_source.changed.disconnect(_invalidate_geometry)
		_source=mesh;_source.changed.connect(_invalidate_geometry);_invalidate_geometry()
	var result: Array[Dictionary]=[]
	for surface in range(mesh.get_surface_count()):
		var mat:=get_active_material(surface) as StandardMaterial3D
		if not mat or mat.transparency!=BaseMaterial3D.TRANSPARENCY_ALPHA or mat.shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED or mat.blend_mode!=BaseMaterial3D.BLEND_MODE_MIX or mat.next_pass or mat.emission_enabled or mat.detail_enabled or mat.uv1_triplanar or skin!=null or get_blend_shape_count()>0 or mat.billboard_mode!=BaseMaterial3D.BILLBOARD_DISABLED or mat.grow or mat.proximity_fade_enabled or mat.distance_fade_mode!=BaseMaterial3D.DISTANCE_FADE_DISABLED or mat.uv1_scale!=Vector3.ONE or mat.uv1_offset!=Vector3.ZERO:
			support_reason="Requires rigid unshaded StandardMaterial3D with Alpha/Mix."
			layers=_native_layers;return []
		if (mesh is ArrayMesh and mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES) or mesh is PointMesh or (not mesh is ArrayMesh and not mesh is PrimitiveMesh):
			support_reason="Only triangle surfaces participate.";layers=_native_layers;return []
		var key:=hash([mesh.get_instance_id(),_revision,surface,mat.vertex_color_use_as_albedo,mat.vertex_color_is_srgb])
		var cached:Dictionary={}
		for entry in _geometry:
			if entry.key==key:cached=entry;break
		if cached.is_empty():
			var arrays:=mesh.surface_get_arrays(surface)
			var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			var count:=indices.size() if not indices.is_empty() else points.size()
			var packed:=PackedFloat32Array()
			for vertex in range(count):
				var i:=indices[vertex] if not indices.is_empty() else vertex
				var texcoord:=uv[i] if uv.size()>i else Vector2.ZERO
				var color:=colors[i] if colors.size()>i and mat.vertex_color_use_as_albedo else Color.WHITE
				if mat.vertex_color_is_srgb:
					var alpha:=color.a;color=color.srgb_to_linear();color.a=alpha
				packed.append_array(PackedFloat32Array([points[i].x,points[i].y,points[i].z,0,texcoord.x,texcoord.y,color.r,color.g,color.b,color.a,0,0]))
			cached={"key":key,"vertices":packed.to_byte_array(),"count":count};_geometry.append(cached)
		var color:=mat.albedo_color.srgb_to_linear()
		color.a=mat.albedo_color.a
		result.append({"key":key,"vertices":cached.vertices,"count":cached.count,"transform":global_transform,"color":color,"texture":mat.albedo_texture,"cull":mat.cull_mode})
	support_reason="Rigid unshaded alpha material participates."
	return result

func set_integrated(enabled:bool)->void:
	layers=0 if enabled else _native_layers

func _invalidate_geometry()->void:
	_revision+=1;_geometry.clear()
