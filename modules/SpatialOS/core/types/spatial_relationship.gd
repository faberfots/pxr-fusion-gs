class_name SpatialRelationship
extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## SPATIAL RELATIONSHIP - Edge in the Scene Graph (Foundation 2)
## ═══════════════════════════════════════════════════════════════════════════
## 
## PURPOSE:
##   Represents a spatial relationship between two segments.
##   Forms the edges of the scene graph for LLM reasoning.
##
## RELATIONSHIP TYPES (8 standard types from spec):
##   - ABOVE: Segment A is above Segment B (centroid Y comparison)
##   - BELOW: Segment A is below Segment B
##   - ADJACENT_TO: Bounding boxes overlap or touch
##   - NEAR: Within a threshold distance
##   - SUPPORTS: A supports B (vertical contact, A below B)
##   - SUPPORTED_BY: A is supported by B
##   - CONTAINS: A's bbox fully contains B's bbox
##   - CONTAINED_BY: A is inside B's bbox
##
## ═══════════════════════════════════════════════════════════════════════════

## Relationship types enum
enum RelationType {
	ABOVE,
	BELOW,
	ADJACENT_TO,
	NEAR,
	SUPPORTS,
	SUPPORTED_BY,
	CONTAINS,
	CONTAINED_BY
}

## Source segment ID
var from_segment_id: int = 0

## Target segment ID
var to_segment_id: int = 0

## Type of relationship
var relationship_type: int = RelationType.NEAR

## Confidence score (0.0 - 1.0)
var confidence: float = 1.0

## Distance between centroids (for NEAR relationships)
var distance: float = 0.0

## Constructor
func _init(from_id: int = 0, to_id: int = 0, rel_type: int = RelationType.NEAR, conf: float = 1.0):
	from_segment_id = from_id
	to_segment_id = to_id
	relationship_type = rel_type
	confidence = conf

## Get relationship type as string
func get_type_name() -> String:
	match relationship_type:
		RelationType.ABOVE: return "above"
		RelationType.BELOW: return "below"
		RelationType.ADJACENT_TO: return "adjacent_to"
		RelationType.NEAR: return "near"
		RelationType.SUPPORTS: return "supports"
		RelationType.SUPPORTED_BY: return "supported_by"
		RelationType.CONTAINS: return "contains"
		RelationType.CONTAINED_BY: return "contained_by"
		_: return "unknown"

## Serialize to dictionary (for LLM/JSON export)
func to_dict() -> Dictionary:
	return {
		"from": from_segment_id,
		"to": to_segment_id,
		"type": get_type_name(),
		"confidence": confidence,
		"evidence": "bounding_box_heuristic; not physical contact verification",
		"distance": distance
	}

## String representation for debugging
func _to_string() -> String:
	return "Relationship: Seg[%d] --%s--> Seg[%d] (%.2f)" % [
		from_segment_id, get_type_name(), to_segment_id, confidence
	]

# ═══════════════════════════════════════════════════════════════════════════
# STATIC INFERENCE METHODS
# ═══════════════════════════════════════════════════════════════════════════

## Infer all relationships between segments
## @param segments: Dictionary of segment_id -> SegmentData
## @param near_threshold: Distance threshold for NEAR relationship
## @return: Array of SpatialRelationship
static func infer_all(segments: Dictionary, near_threshold: float = 2.0) -> Array[SpatialRelationship]:
	var relationships: Array[SpatialRelationship] = []
	var segment_ids = segments.keys()
	segment_ids.sort_custom(func(a, b):
		var left: SegmentData = segments[a]
		var right: SegmentData = segments[b]
		return left.bbox.position.x < right.bbox.position.x or (left.bbox.position.x == right.bbox.position.x and int(a) < int(b))
	)
	
	# Compare all pairs of segments
	for i in range(segment_ids.size()):
		for j in range(i + 1, segment_ids.size()):
			var id_a = segment_ids[i]
			var id_b = segment_ids[j]
			var seg_a: SegmentData = segments[id_a]
			var seg_b: SegmentData = segments[id_b]
			
			# Only local bounding-box pairs imply geometric relationships.
			if seg_b.bbox.position.x > seg_a.bbox.end.x + near_threshold: break
			if seg_a.bbox.grow(near_threshold).intersection(seg_b.bbox).size == Vector3.ZERO and not seg_a.bbox.grow(near_threshold).intersects(seg_b.bbox): continue
			# Check each relationship type
			var rels = _infer_pair(seg_a, seg_b, near_threshold)
			relationships.append_array(rels)
	
	return relationships

## Infer relationships between a pair of segments
static func _infer_pair(a: SegmentData, b: SegmentData, near_threshold: float) -> Array[SpatialRelationship]:
	var results: Array[SpatialRelationship] = []
	
	var centroid_dist = a.centroid.distance_to(b.centroid)
	var y_diff = a.centroid.y - b.centroid.y
	
	# ─────────────────────────────────────────────────────────────────
	# NEAR: Within threshold distance
	# ─────────────────────────────────────────────────────────────────
	if centroid_dist <= near_threshold:
		var rel = SpatialRelationship.new(a.segment_id, b.segment_id, RelationType.NEAR)
		rel.distance = centroid_dist
		rel.confidence = 1.0 - (centroid_dist / near_threshold)
		results.append(rel)
	
	# ─────────────────────────────────────────────────────────────────
	# ABOVE / BELOW: Vertical relationship
	# ─────────────────────────────────────────────────────────────────
	var vertical_threshold = 0.3  # Minimum vertical separation to count
	if y_diff > vertical_threshold:
		# A is above B
		var rel = SpatialRelationship.new(a.segment_id, b.segment_id, RelationType.ABOVE)
		rel.confidence = min(1.0, abs(y_diff) / 1.0)
		results.append(rel)
	elif y_diff < -vertical_threshold:
		# A is below B
		var rel = SpatialRelationship.new(a.segment_id, b.segment_id, RelationType.BELOW)
		rel.confidence = min(1.0, abs(y_diff) / 1.0)
		results.append(rel)
	
	# ─────────────────────────────────────────────────────────────────
	# ADJACENT_TO: Bounding boxes overlap or nearly touch
	# ─────────────────────────────────────────────────────────────────
	var expanded_a = a.bbox.grow(0.1)  # Expand by 10cm for "near touch"
	if expanded_a.intersects(b.bbox):
		var rel = SpatialRelationship.new(a.segment_id, b.segment_id, RelationType.ADJACENT_TO)
		rel.confidence = 0.9
		results.append(rel)
	
	# ─────────────────────────────────────────────────────────────────
	# CONTAINS / CONTAINED_BY: One bbox inside another
	# ─────────────────────────────────────────────────────────────────
	if a.bbox.encloses(b.bbox):
		var rel = SpatialRelationship.new(a.segment_id, b.segment_id, RelationType.CONTAINS)
		rel.confidence = 1.0
		results.append(rel)
	elif b.bbox.encloses(a.bbox):
		var rel = SpatialRelationship.new(a.segment_id, b.segment_id, RelationType.CONTAINED_BY)
		rel.confidence = 1.0
		results.append(rel)
	
	# ─────────────────────────────────────────────────────────────────
	# SUPPORTS: A supports B (A below B, close horizontally, vertical contact)
	# ─────────────────────────────────────────────────────────────────
	var lower := a if a.centroid.y <= b.centroid.y else b
	var upper := b if lower == a else a
	var gap := upper.bbox.position.y - lower.bbox.end.y
	var overlap_x := minf(a.bbox.end.x, b.bbox.end.x) - maxf(a.bbox.position.x, b.bbox.position.x)
	var overlap_z := minf(a.bbox.end.z, b.bbox.end.z) - maxf(a.bbox.position.z, b.bbox.position.z)
	if gap >= -0.1 and gap <= 0.1 and overlap_x > 0.0 and overlap_z > 0.0 and lower != upper:
		var relation := SpatialRelationship.new(lower.segment_id, upper.segment_id, RelationType.SUPPORTS)
		relation.confidence = 0.0
		results.append(relation)
		var inverse := SpatialRelationship.new(upper.segment_id, lower.segment_id, RelationType.SUPPORTED_BY)
		inverse.confidence = 0.0
		results.append(inverse)
	return results
