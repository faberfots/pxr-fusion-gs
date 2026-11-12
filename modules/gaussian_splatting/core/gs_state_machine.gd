# gs_state_machine.gd
# ════════════════════════════════════════════════════════════════════════════════
# FORMAL STATE MACHINE FOR GAUSSIAN SPLATTING VIEWER
# ════════════════════════════════════════════════════════════════════════════════
# PURPOSE: Enforces valid state transitions and prevents impossible states.
# SSOT: All valid state transitions are defined here in VALID_TRANSITIONS.
# DISRUPTIVE: Invalid transitions are REJECTED, not silently ignored.
# ════════════════════════════════════════════════════════════════════════════════
class_name GSStateMachine
extends RefCounted

# ════════════════════════════════════════════════════════════════════════════════
# STATE DEFINITIONS
# ════════════════════════════════════════════════════════════════════════════════
## Possible states for the Gaussian Splatting Viewer.
## These mirror the existing ViewerState enum for compatibility.
enum State {
	UNINITIALIZED,  ## Viewer is ready, but no file is loaded
	LOADING,        ## Splats are currently being loaded to GPU
	READY,          ## All splats loaded, rendering paused
	RENDERING,      ## Actively rendering frames
	ERROR           ## Unrecoverable error occurred
}

# ════════════════════════════════════════════════════════════════════════════════
# TRANSITION TABLE (SSOT)
# ════════════════════════════════════════════════════════════════════════════════
## Defines ALL valid state transitions.
## Key = current state, Value = array of valid target states.
## Uses Godot 4.4+ typed dictionary syntax for type safety.
## 
## Transition Diagram:
##   UNINITIALIZED ──► LOADING ──► READY ◄──► RENDERING
##          ▲              │         │              │
##          │              ▼         ▼              ▼
##          └────────── ERROR ◄──────┴──────────────┘
##
const VALID_TRANSITIONS: Dictionary = {
	State.UNINITIALIZED: [State.LOADING, State.READY, State.ERROR],
	State.LOADING: [State.READY, State.ERROR, State.UNINITIALIZED],
	State.READY: [State.RENDERING, State.LOADING, State.UNINITIALIZED, State.ERROR],
	State.RENDERING: [State.READY, State.LOADING, State.ERROR, State.UNINITIALIZED],
	State.ERROR: [State.UNINITIALIZED, State.READY, State.LOADING]
}

# ════════════════════════════════════════════════════════════════════════════════
# STATE TRACKING
# ════════════════════════════════════════════════════════════════════════════════
## Current state of the viewer.
var current_state: State = State.UNINITIALIZED

## Signal emitted when state changes. Provides both old and new state.
signal state_changed(from_state: State, to_state: State)

## Signal emitted when an invalid transition is attempted (for debugging).
signal invalid_transition_attempted(from_state: State, to_state: State)

## Enable verbose logging of state transitions.
var enable_logging: bool = false

# ════════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ════════════════════════════════════════════════════════════════════════════════

## Attempt a state transition.
## @param new_state: The target state to transition to
## @return: true if transition was valid and executed, false otherwise
func transition_to(new_state: State) -> bool:
	# No-op transitions are always valid (idempotent)
	if new_state == current_state:
		return true
	
	# Check if transition is valid according to SSOT table
	var valid_targets: Array = VALID_TRANSITIONS.get(current_state, [])
	
	if new_state in valid_targets:
		var old_state := current_state
		current_state = new_state
		
		if enable_logging:
			print("[GSStateMachine] Transition: %s -> %s" % [
				State.keys()[old_state], 
				State.keys()[new_state]
			])
		
		state_changed.emit(old_state, new_state)
		return true
	else:
		# Invalid transition - log warning and emit signal
		push_warning("[GSStateMachine] INVALID transition attempted: %s -> %s. Valid targets: %s" % [
			State.keys()[current_state], 
			State.keys()[new_state],
			_get_valid_target_names()
		])
		invalid_transition_attempted.emit(current_state, new_state)
		return false


## Force a state (bypasses validation). Use only for error recovery.
## @param new_state: The state to force
func force_state(new_state: State) -> void:
	var old_state := current_state
	current_state = new_state
	
	if enable_logging:
		print("[GSStateMachine] FORCED: %s -> %s" % [
			State.keys()[old_state], 
			State.keys()[new_state]
		])
	
	state_changed.emit(old_state, new_state)


## Reset the state machine to UNINITIALIZED.
func reset() -> void:
	force_state(State.UNINITIALIZED)


## Check if a transition to the given state would be valid.
## @param target_state: The state to check
## @return: true if transition would be valid
func can_transition_to(target_state: State) -> bool:
	if target_state == current_state:
		return true
	var valid_targets: Array = VALID_TRANSITIONS.get(current_state, [])
	return target_state in valid_targets


## Get the current state as a string (for debugging/UI).
func get_state_name() -> String:
	return State.keys()[current_state]


## Get list of valid target states from current state.
func get_valid_targets() -> Array[State]:
	var targets: Array[State] = []
	for t in VALID_TRANSITIONS.get(current_state, []):
		targets.append(t as State)
	return targets


# ════════════════════════════════════════════════════════════════════════════════
# CONVENIENCE STATE CHECKS
# ════════════════════════════════════════════════════════════════════════════════

## Returns true if currently in LOADING state.
func is_loading() -> bool:
	return current_state == State.LOADING


## Returns true if currently in RENDERING state.
func is_rendering() -> bool:
	return current_state == State.RENDERING


## Returns true if in a state where new files can be loaded.
func can_load_file() -> bool:
	return current_state in [State.UNINITIALIZED, State.READY, State.RENDERING]


## Returns true if in ERROR state.
func is_error() -> bool:
	return current_state == State.ERROR


# ════════════════════════════════════════════════════════════════════════════════
# INTERNAL HELPERS
# ════════════════════════════════════════════════════════════════════════════════

## Get valid target state names as a string (for error messages).
func _get_valid_target_names() -> String:
	var valid_targets: Array = VALID_TRANSITIONS.get(current_state, [])
	var names: Array[String] = []
	for t in valid_targets:
		names.append(State.keys()[t])
	return ", ".join(names)
