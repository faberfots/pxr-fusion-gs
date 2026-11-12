class_name SegmentData
extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## SEGMENT DATA - Metadata for a Segmented Object (Foundation 2)
## ═══════════════════════════════════════════════════════════════════════════
## 
## PURPOSE:
##   Stores computed metadata for each segment (object) in the scene graph.
##   Used for relationship inference and LLM queries.
##
## ATTRIBUTES:
##   - segment_id: Unique identifier for this segment
##   - centroid: Center of mass (average of all points)
##   - bbox: Axis-aligned bounding box
##   - point_count: Number of points in this segment
##   - point_indices: Array of point indices (optional, for detailed analysis)
##
## USAGE:
##   var seg = SegmentData.new()
##   seg.segment_id = 1
##   seg.add_point(pos)
##   seg.finalize()
##
## ═══════════════════════════════════════════════════════════════════════════

## Unique segment ID (1-indexed, 0 = noise/unclassified)
var segment_id: int = 0

## Center of mass (average position of all points)
var centroid: Vector3 = Vector3.ZERO

## Axis-aligned bounding box
var bbox: AABB = AABB()

## Number of points in this segment
var point_count: int = 0

## Semantic label (assigned by Foundation 3 agents, e.g., "chair", "desk")
var semantic_label: String = ""

## Confidence score for the semantic label (0.0 - 1.0)
var confidence: float = 0.0
var normal_count := 0
var evidence: Dictionary = {}

## Average normal direction (for geometric inference)
var average_normal: Vector3 = Vector3.ZERO

# Internal: Accumulator for centroid calculation
var _sum_positions: Vector3 = Vector3.ZERO
var _sum_normals: Vector3 = Vector3.ZERO
var _min_bounds: Vector3 = Vector3(INF, INF, INF)
var _max_bounds: Vector3 = Vector3(-INF, -INF, -INF)

## Add a point to this segment (called during accumulation)
## @param position: World position of the point
func add_point(position: Vector3) -> void:
	point_count += 1
	_sum_positions += position
	
	# Update bounds
	_min_bounds = _min_bounds.min(position)
	_max_bounds = _max_bounds.max(position)

## Add a point with normal to this segment
## @param position: World position of the point
## @param normal: Normal vector at the point
func add_point_with_normal(position: Vector3, normal: Vector3) -> void:
	add_point(position)
	if normal.is_finite() and normal.length_squared() > 0.0001:
		normal_count += 1
		_sum_normals += normal.normalized()

## Finalize the segment after all points have been added
## Computes centroid, bbox, and average_normal from accumulated data
func finalize() -> void:
	if point_count > 0:
		centroid = _sum_positions / float(point_count)
		bbox = AABB(_min_bounds, _max_bounds - _min_bounds)
		# Compute average normal (normalized)
		if _sum_normals.length_squared() > 0.001:
			average_normal = _sum_normals.normalized()
		else:
			average_normal = Vector3.ZERO
	else:
		centroid = Vector3.ZERO
		bbox = AABB()
		average_normal = Vector3.ZERO

## Get the volume of the bounding box (in cubic meters)
func get_volume() -> float:
	return bbox.get_volume()

## Get the longest dimension of the bounding box
func get_longest_axis_size() -> float:
	return bbox.get_longest_axis_size()

## Serialize to dictionary (for LLM/JSON export)
func to_dict() -> Dictionary:
	return {
		"segment_id": segment_id,
		"centroid": {"x": centroid.x, "y": centroid.y, "z": centroid.z},
		"bbox": {
			"min": {"x": bbox.position.x, "y": bbox.position.y, "z": bbox.position.z},
			"max": {"x": bbox.end.x, "y": bbox.end.y, "z": bbox.end.z}
		},
		"point_count": point_count,
		"semantic_label": semantic_label,
		"confidence": confidence,
		"evidence": evidence,
		"volume": get_volume()
	}

## String representation for debugging
func _to_string() -> String:
	return "Segment[%d]: %d pts, centroid=(%.2f, %.2f, %.2f)" % [
		segment_id, point_count, centroid.x, centroid.y, centroid.z
	]
