class_name GPUPipelineManager extends RefCounted
## Manages GPU compute pipeline lifecycle, state tracking, and lazy recreation
## Centralizes pipeline creation/destruction to prevent leaks and improve maintainability

enum PipelineState {
	UNINITIALIZED,  ## Pipeline has never been created
	VALID,          ## Pipeline exists and is ready to use
	DIRTY,          ## Pipeline needs recreation (dependencies changed)
	ERROR           ## Pipeline creation failed
}

class PipelineInfo:
	var callable : Callable           ## The dispatch callable
	var rid : RID                      ## The pipeline RID for cleanup
	var state : PipelineState          ## Current state
	var descriptor_sets : Array        ## Descriptor sets used by this pipeline
	var shader : RID                   ## Shader RID
	var block_dimensions : Array       ## Dispatch dimensions [x, y, z]
	var debug_name : String            ## Name for debugging
	var last_error : String = ""       ## Last error message if state == ERROR
	
	func _init(name: String) -> void:
		debug_name = name
		state = PipelineState.UNINITIALIZED
	
	func is_valid() -> bool:
		return state == PipelineState.VALID and rid.is_valid()
	
	func mark_dirty() -> void:
		if state == PipelineState.VALID:
			state = PipelineState.DIRTY

var context : RenderingContext
var pipelines : Dictionary  ## Maps String -> PipelineInfo
var verbose_logging := false

## Create pipeline manager with rendering context
func _init(render_context: RenderingContext, enable_logging := false) -> void:
	context = render_context
	verbose_logging = enable_logging
	
	if verbose_logging:
		print("[GPUPipelineManager] Initialized")

## Register a new pipeline (doesn't create it yet - lazy creation)
func register_pipeline(
	name: String,
	block_dims: Array,
	descriptor_sets: Array,
	shader: RID,
	create_immediately := false
) -> bool:
	if pipelines.has(name):
		push_warning("[GPUPipelineManager] Pipeline '%s' already registered, replacing" % name)
	
	var info := PipelineInfo.new(name)
	info.block_dimensions = block_dims
	info.descriptor_sets = descriptor_sets
	info.shader = shader
	pipelines[name] = info
	
	if create_immediately:
		return _create_pipeline(info)
	
	return true

## Get a pipeline callable (creates on first access if needed)
func get_pipeline(name: String) -> Callable:
	if not pipelines.has(name):
		push_error("[GPUPipelineManager] Pipeline '%s' not registered" % name)
		return Callable()
	
	var info : PipelineInfo = pipelines[name]
	
	# Create if needed
	if info.state == PipelineState.UNINITIALIZED or info.state == PipelineState.DIRTY:
		if not _create_pipeline(info):
			push_error("[GPUPipelineManager] Failed to create pipeline '%s': %s" % [name, info.last_error])
			return Callable()
	
	if info.state != PipelineState.VALID:
		push_error("[GPUPipelineManager] Pipeline '%s' is in error state" % name)
		return Callable()
	
	return info.callable

## Check if pipeline exists and is valid
func is_pipeline_valid(name: String) -> bool:
	if not pipelines.has(name):
		return false
	return pipelines[name].is_valid()

## Mark pipeline as dirty (needs recreation)
func mark_dirty(name: String) -> void:
	if pipelines.has(name):
		pipelines[name].mark_dirty()
		if verbose_logging:
			print("[GPUPipelineManager] Marked pipeline '%s' as dirty" % name)

## Mark all pipelines dirty
func mark_all_dirty() -> void:
	for name in pipelines:
		pipelines[name].mark_dirty()
	if verbose_logging:
		print("[GPUPipelineManager] Marked all %d pipelines as dirty" % pipelines.size())

## Update descriptor sets for a pipeline (marks it dirty)
func update_descriptor_sets(name: String, new_sets: Array) -> void:
	if not pipelines.has(name):
		push_error("[GPUPipelineManager] Cannot update unknown pipeline '%s'" % name)
		return
	
	var info : PipelineInfo = pipelines[name]
	info.descriptor_sets = new_sets
	info.mark_dirty()

## Update block dimensions for a pipeline (marks it dirty)
func update_block_dimensions(name: String, new_dims: Array) -> void:
	if not pipelines.has(name):
		push_error("[GPUPipelineManager] Cannot update unknown pipeline '%s'" % name)
		return
	
	var info : PipelineInfo = pipelines[name]
	if info.block_dimensions == new_dims:
		return
	info.block_dimensions = new_dims
	info.mark_dirty()

## Recreate all dirty pipelines
func recreate_dirty_pipelines() -> int:
	var recreated := 0
	for name in pipelines:
		var info : PipelineInfo = pipelines[name]
		if info.state == PipelineState.DIRTY:
			if _create_pipeline(info):
				recreated += 1
	
	if verbose_logging and recreated > 0:
		print("[GPUPipelineManager] Recreated %d dirty pipelines" % recreated)
	
	return recreated

## Internal: Actually create/recreate a pipeline
## Internal: Actually create/recreate a pipeline
func _create_pipeline(info: PipelineInfo) -> bool:
	if not context or not context.is_initialized:
		info.state = PipelineState.ERROR
		info.last_error = "Context not initialized"
		push_error("[GPUPipelineManager] Cannot create pipeline '%s': %s" % [info.debug_name, info.last_error])
		return false
	
	# Validate inputs
	if not info.shader.is_valid():
		info.state = PipelineState.ERROR
		info.last_error = "Invalid shader RID"
		push_error("[GPUPipelineManager] Cannot create pipeline '%s': %s" % [info.debug_name, info.last_error])
		return false
	
	if info.descriptor_sets.is_empty():
		info.state = PipelineState.ERROR
		info.last_error = "No descriptor sets provided"
		push_error("[GPUPipelineManager] Cannot create pipeline '%s': %s" % [info.debug_name, info.last_error])
		return false
	
	# BUGFIX: Validate all descriptor sets are valid BEFORE attempting pipeline creation
	for i in range(info.descriptor_sets.size()):
		if not info.descriptor_sets[i].is_valid():
			info.state = PipelineState.ERROR
			info.last_error = "Descriptor set %d is invalid" % i
			push_error("[GPUPipelineManager] Cannot create pipeline '%s': %s" % [info.debug_name, info.last_error])
			return false
	
	# BUGFIX: Only validate block dimensions if not using indirect dispatch
	if not info.block_dimensions.is_empty():
		if info.block_dimensions.size() != 3:
			info.state = PipelineState.ERROR
			info.last_error = "Invalid block dimensions (expected 3 values, got %d)" % info.block_dimensions.size()
			push_error("[GPUPipelineManager] Cannot create pipeline '%s': %s" % [info.debug_name, info.last_error])
			return false
	
	# Free old pipeline if exists
	if info.rid.is_valid():
		context.deletion_queue.free_rid(context.device, info.rid)
		info.rid = RID()
	
	# Create new pipeline
	var pipeline_data = context.create_pipeline(
		info.block_dimensions,
		info.descriptor_sets,
		info.shader,
		info.debug_name
	)
	
	# BUGFIX: Check if pipeline_data is valid before accessing
	if not pipeline_data or not pipeline_data.has("rid") or not pipeline_data.has("callable"):
		info.state = PipelineState.ERROR
		info.last_error = "create_pipeline returned invalid data"
		push_error("[GPUPipelineManager] Failed to create pipeline '%s': %s" % [info.debug_name, info.last_error])
		return false
	
	if not pipeline_data.rid.is_valid():
		info.state = PipelineState.ERROR
		info.last_error = "RenderingDevice.compute_pipeline_create failed - shader may be incompatible with descriptor layout"
		push_error("[GPUPipelineManager] Failed to create pipeline '%s': %s" % [info.debug_name, info.last_error])
		
		# DIAGNOSTIC: Print shader and descriptor info for debugging
		if verbose_logging:
			print("[GPUPipelineManager] Debug info for failed pipeline '%s':" % info.debug_name)
			print("  Shader RID valid: %s" % info.shader.is_valid())
			print("  Descriptor set count: %d" % info.descriptor_sets.size())
			print("  Block dimensions: %s" % str(info.block_dimensions))
			for i in range(info.descriptor_sets.size()):
				print("  Descriptor set %d valid: %s" % [i, info.descriptor_sets[i].is_valid()])
		
		return false
	
	info.callable = pipeline_data.callable
	info.rid = pipeline_data.rid
	info.state = PipelineState.VALID
	info.last_error = ""
	
	if verbose_logging:
		print("[GPUPipelineManager] Created pipeline '%s' successfully" % info.debug_name)
	
	return true

## Destroy a specific pipeline
func destroy_pipeline(name: String) -> void:
	if not pipelines.has(name):
		return
	
	var info : PipelineInfo = pipelines[name]
	if info.rid.is_valid():
		context.deletion_queue.free_rid(context.device, info.rid)
		info.rid = RID()
	
	info.state = PipelineState.UNINITIALIZED
	if verbose_logging:
		print("[GPUPipelineManager] Destroyed pipeline '%s'" % name)

## Destroy all pipelines
func destroy_all() -> void:
	for name in pipelines:
		destroy_pipeline(name)
	
	if verbose_logging:
		print("[GPUPipelineManager] Destroyed all %d pipelines" % pipelines.size())

## Clear all pipeline registrations
func clear() -> void:
	destroy_all()
	pipelines.clear()
	
	if verbose_logging:
		print("[GPUPipelineManager] Cleared all pipeline registrations")

## Get statistics about current pipelines
func get_stats() -> Dictionary:
	var stats := {
		"total": pipelines.size(),
		"valid": 0,
		"dirty": 0,
		"uninitialized": 0,
		"error": 0
	}
	
	for name in pipelines:
		var info : PipelineInfo = pipelines[name]
		match info.state:
			PipelineState.VALID: stats.valid += 1
			PipelineState.DIRTY: stats.dirty += 1
			PipelineState.UNINITIALIZED: stats.uninitialized += 1
			PipelineState.ERROR: stats.error += 1
	
	return stats

## Debug: Print all pipeline states
func debug_print_pipelines() -> void:
	print("[GPUPipelineManager] === Pipeline Status ===")
	var stats = get_stats()
	print("  Total: %d | Valid: %d | Dirty: %d | Uninitialized: %d | Error: %d" % [
		stats.total, stats.valid, stats.dirty, stats.uninitialized, stats.error
	])
	
	for name in pipelines:
		var info : PipelineInfo = pipelines[name]
		var state_str = PipelineState.keys()[info.state]
		var error_str := " - ERROR: %s" % info.last_error if info.state == PipelineState.ERROR else ""
		print("  - %s: %s%s" % [name, state_str, error_str])
