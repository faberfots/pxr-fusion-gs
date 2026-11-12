class_name PointCloudResource
extends Resource

# SSOT: This resource represents the "Understood" environment.
# LLM Ready: Can be passed to agents for analysis.

var _points := PackedVector3Array()
@export var points: PackedVector3Array:
	get: return _points.duplicate()
	set(value):
		_points = value.duplicate()
		invalidate_derived()
		recalculate_bounds()
@export var colors: PackedColorArray
var _bounds := AABB()
var aabb: AABB:
	get: return _bounds
var point_count: int:
	get: return _points.size()
@export var voxel_size: float = 0.0

# Foundation 2: Graph Intelligence Data
@export var segments: PackedInt32Array # Segment ID for each point (0 = unclassified/noise)
@export var segment_count: int = 0

# Foundation 2.5: Geometric Intelligence Data
# Computed via Covariance Analysis (PCA)
@export var normals: PackedVector3Array # Surface orientation
@export var curvature: PackedFloat32Array # Surface variation (0=flat, 1=sharp edge)

# Foundation 2: Scene Graph (Nodes and Edges)
# Segment metadata: Dictionary of segment_id -> SegmentData
var segments_metadata: Dictionary = {}  # int -> SegmentData

# Spatial relationships between segments (edges in scene graph)
var relationships: Array[SpatialRelationship] = []

# Business Minded: Metadata for facility management
@export var metadata: Dictionary = {
	"source_file": "",
	"processed_date": "",
	"scan_location": ""
}

func _init(p_points: PackedVector3Array = PackedVector3Array(), p_colors: PackedColorArray = PackedColorArray()):
	points = p_points
	colors = p_colors

func recalculate_bounds():
	if _points.is_empty():
		_bounds = AABB()
		return
	# Simple AABB calculation
	var min_vec = Vector3(INF, INF, INF)
	var max_vec = Vector3(-INF, -INF, -INF)
	for p in _points:
		min_vec = min_vec.min(p)
		max_vec = max_vec.max(p)
	_bounds = AABB(min_vec, max_vec - min_vec)

var geometry_revision := 0
func invalidate_derived() -> void:
	geometry_revision += 1
	if metadata.has("spatial_index"):
		var index: SpatialIndex = metadata.spatial_index
		if index: index.cleanup_gpu_resources()
		metadata.erase("spatial_index")
	metadata.erase("graph_built")
	segments = PackedInt32Array()
	segment_count = 0
	normals = PackedVector3Array()
	curvature = PackedFloat32Array()
	segments_metadata.clear()
	relationships.clear()
	metadata["geometry_revision"] = geometry_revision

func get_context_snapshot() -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	for segment in segments_metadata.values(): nodes.append(segment.to_dict())
	for relationship in relationships: edges.append(relationship.to_dict())
	return {"geometry_revision": geometry_revision, "segments": nodes, "relationships": edges}
