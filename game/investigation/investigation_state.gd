class_name InvestigationState
extends RefCounted

## Canonical investigation state. Static definitions live in LocationDef; this
## object is the only source of truth for progress and is what gets saved.

enum Mode {
	INACTIVE,
	DEFAULT,
	LOCATION_ACTIVE,
	WAIT_STORY_BRANCH,
	TALK_MODE,
	MOVE_MODE,
	PRESENT_MODE,
	ERROR,
}

var active: bool = false
var mode: Mode = Mode.INACTIVE
var current_location: StringName
var current_character: StringName
var visited_locations: Array[StringName]
var location_states: Dictionary[StringName, LocationState]


func get_location_state(location_id: StringName) -> LocationState:
	return location_states.get(location_id) as LocationState


func ensure_location_state(location_id: StringName) -> LocationState:
	var location_state: LocationState = location_states.get(location_id) as LocationState
	if location_state == null:
		location_state = LocationState.new()
		location_states[location_id] = location_state
	return location_state


func mark_visited(location_id: StringName) -> void:
	if not visited_locations.has(location_id):
		visited_locations.append(location_id)
