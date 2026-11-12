extends Node3D

const Config = preload("res://modules/SpatialOS/core/spatial_config.gd")

var _index: SpatialIndex
var _immediate_mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D

func _ready():
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	
	# Create a simple unshaded material for wireframes
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	_mesh_instance.material_override = material
	
	add_child(_mesh_instance)
	print("SpatialIndexDebug: Ready")

## Visualize the spatial index grid
## @param index: The SpatialIndex object to visualize
## @param limit_cells: Max cells to draw (to prevent freezing on massive grids)
func visualize_grid(index: SpatialIndex, limit_cells: int = 50000) -> void:
	_index = index
	_immediate_mesh.clear_surfaces()
	
	if not _index:
		return
	
	var stats = _index.get_grid_stats()
	var bounds_min = stats["bounds_min"]
	var cell_size = stats["cell_size"]
	var grid_dim = stats["grid_dim"]
	
	# Explicitly sync data for visualization
	_index.ensure_cpu_sync()
	var table = _index._grid_table_cpu # Accessing internal for debug visualization
	
	if table.is_empty():
		print("SpatialIndexDebug: Index table empty (or not synced)")
		return
	
	print("SpatialIndexDebug: Visualizing grid...")
	
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var cells_drawn = 0
	var total_cells = grid_dim.x * grid_dim.y * grid_dim.z
	
	# Iterate all cells
	for z in range(grid_dim.z):
		for y in range(grid_dim.y):
			for x in range(grid_dim.x):
				var cell_id = x + (y * grid_dim.x) + (z * grid_dim.x * grid_dim.y)
				
				# Check if cell has points
				var start = table[cell_id]
				var count = table[cell_id+1] - start
				
				if count > 0:
					# Calculate cell bounds
					var cell_min = bounds_min + Vector3(x, y, z) * cell_size
					var cell_max = cell_min + Vector3(cell_size, cell_size, cell_size)
					
					# Color based on density (heat map)
					var density = clamp(float(count) / 20.0, 0.0, 1.0)
					var color = Color(0.0, 1.0, 0.0).lerp(Color(1.0, 0.0, 0.0), density)
					color.a = 0.5
					
					_draw_box(cell_min, cell_max, color)
					cells_drawn += 1
					
					if cells_drawn >= limit_cells:
						print("SpatialIndexDebug: Reached draw limit of ", limit_cells)
						_immediate_mesh.surface_end()
						return
	
	_immediate_mesh.surface_end()
	print("SpatialIndexDebug: Drew %d occupied cells" % cells_drawn)

func clear():
	_immediate_mesh.clear_surfaces()

func _draw_box(min_p: Vector3, max_p: Vector3, color: Color):
	# Bottom
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	
	# Top
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	
	# Verticals
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	_immediate_mesh.surface_add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
