class_name SaveSerializer
extends RefCounted

## Converts canonical domain state to and from JSON-safe dictionaries.
##
## Only GameState crosses this boundary. Nodes, NodePaths, and presentation
## node properties are never part of a save payload.

const DOCUMENT_SECTIONS: Array[String] = [
	"story",
	"flags",
	"evidence",
	"court",
	"investigation",
	"procedure",
]


static func to_dict(state: GameState) -> Dictionary:
	var call_stack: Array[Dictionary] = []
	for frame: StoryStackFrame in state.story.call_stack:
		call_stack.append({
			"scene": String(frame.scene_id),
			"instruction": frame.instruction_index,
		})

	var evidence: Dictionary = {}
	for evidence_id: StringName in state.evidence:
		var entry: EvidenceState = state.evidence[evidence_id]
		evidence[String(evidence_id)] = {
			"owned": entry.owned,
			"version": String(entry.version),
			"discovered": entry.discovered,
			"inspected_hotspots": _to_strings(entry.inspected_hotspots),
			"inspection_complete": entry.inspection_complete,
		}

	var court: Dictionary = {
		"active": state.court.active_testimony != null,
		"penalty": state.court.penalty,
	}
	if state.court.active_testimony != null:
		var session: TestimonySession = state.court.active_testimony
		court["testimony_id"] = String(session.testimony_id)
		court["current_statement_id"] = String(session.current_statement_id)
		court["visited_statements"] = _to_strings(session.visited_statements)
		court["pressed_statements"] = _to_strings(session.pressed_statements)

	var flags: Dictionary = {}
	for flag_id: StringName in state.flags:
		flags[String(flag_id)] = state.flags[flag_id]

	return {
		"schema_version": state.schema_version,
		"game_version": state.game_version,
		"story": {
			"chapter": String(state.story.current_chapter),
			"scene": String(state.story.current_scene),
			"instruction_index": state.story.current_instruction,
			"runtime_state": StoryState.RuntimeState.keys()[state.story.runtime_state],
			"background": String(state.story.current_background),
			"call_stack": call_stack,
		},
		"flags": flags,
		"evidence": evidence,
		"court": court,
		"investigation": _investigation_to_dict(state.investigation),
		"procedure": _procedure_to_dict(state.procedure),
		"playtime": state.playtime_seconds,
	}


## Replaces the canonical state in place. The payload must pass SaveValidator
## first; this function assumes its shape.
static func apply_dict(state: GameState, data: Dictionary) -> void:
	var story: Dictionary = data["story"]
	state.schema_version = int(data["schema_version"])
	if data.get("game_version") is String:
		state.game_version = String(data["game_version"])
	state.story.current_chapter = StringName(story["chapter"])
	state.story.current_scene = StringName(story["scene"])
	state.story.current_instruction = int(story["instruction_index"])
	state.story.current_background = StringName(story["background"])
	state.story.runtime_state = StoryState.RuntimeState[story["runtime_state"]]
	state.story.call_stack.clear()
	for frame: Variant in story["call_stack"]:
		var frame_data: Dictionary = frame
		state.story.call_stack.append(StoryStackFrame.new(
			StringName(frame_data["scene"]),
			int(frame_data["instruction"]),
		))

	state.flags.clear()
	var flag_data: Dictionary = data["flags"]
	for flag_key: Variant in flag_data:
		state.flags[StringName(flag_key)] = flag_data[flag_key]

	state.evidence.clear()
	var evidence_data: Dictionary = data["evidence"]
	for evidence_key: Variant in evidence_data:
		var entry_data: Dictionary = evidence_data[evidence_key]
		var evidence_state := EvidenceState.new(
			StringName(evidence_key),
			entry_data["owned"],
			StringName(entry_data["version"]),
			entry_data["discovered"],
		)
		evidence_state.inspected_hotspots = _to_name_array(
			entry_data.get("inspected_hotspots", [])
		)
		evidence_state.inspection_complete = bool(entry_data.get("inspection_complete", false))
		state.evidence[StringName(evidence_key)] = evidence_state

	var court_data: Dictionary = data["court"]
	state.court.penalty = int(court_data["penalty"])
	state.court.active_testimony = null
	if court_data["active"]:
		var session := TestimonySession.new(StringName(court_data["testimony_id"]))
		session.current_statement_id = StringName(court_data["current_statement_id"])
		session.visited_statements = _to_name_array(court_data["visited_statements"])
		session.pressed_statements = _to_name_array(court_data["pressed_statements"])
		state.court.active_testimony = session

	state.playtime_seconds = float(data["playtime"])
	_apply_investigation(state.investigation, data["investigation"])
	_apply_procedure(state.procedure, data["procedure"])


static func _procedure_to_dict(state: ProcedureState) -> Dictionary:
	return {
		"active": state.active,
		"context_id": String(state.context_id),
		"resolved": state.resolved,
		"resolved_action_id": String(state.resolved_action_id),
		"visited_actions": _to_strings(state.visited_actions),
	}


static func _apply_procedure(state: ProcedureState, data: Dictionary) -> void:
	state.active = data["active"]
	state.context_id = StringName(data["context_id"])
	state.resolved = data["resolved"]
	state.resolved_action_id = StringName(data["resolved_action_id"])
	state.visited_actions = _to_name_array(data["visited_actions"])


static func _investigation_to_dict(state: InvestigationState) -> Dictionary:
	var locations: Dictionary = {}
	for location_id: StringName in state.location_states:
		var location_state: LocationState = state.location_states[location_id]
		locations[String(location_id)] = {
			"examined_hotspots": _to_strings(location_state.examined_hotspots),
			"unlocked_topics": _to_strings(location_state.unlocked_topics),
			"completed_topics": _to_strings(location_state.completed_topics),
			"unlocked_moves": _to_strings(location_state.unlocked_moves),
		}
	return {
		"active": state.active,
		"mode": InvestigationState.Mode.keys()[state.mode],
		"location": String(state.current_location),
		"character": String(state.current_character),
		"visited_locations": _to_strings(state.visited_locations),
		"locations": locations,
	}


static func _apply_investigation(state: InvestigationState, data: Dictionary) -> void:
	state.active = data["active"]
	state.mode = InvestigationState.Mode[data["mode"]]
	state.current_location = StringName(data["location"])
	state.current_character = StringName(data["character"])
	state.visited_locations = _to_name_array(data["visited_locations"])
	state.location_states.clear()
	var locations: Dictionary = data["locations"]
	for location_key: Variant in locations:
		var entry: Dictionary = locations[location_key]
		var location_state := LocationState.new()
		# A location only enters the save once it has been visited.
		location_state.visited = true
		location_state.examined_hotspots = _to_name_array(entry["examined_hotspots"])
		location_state.unlocked_topics = _to_name_array(entry["unlocked_topics"])
		location_state.completed_topics = _to_name_array(entry["completed_topics"])
		location_state.unlocked_moves = _to_name_array(entry["unlocked_moves"])
		state.location_states[StringName(location_key)] = location_state


static func _to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String]
	for value: StringName in values:
		result.append(String(value))
	return result


static func _to_name_array(values: Variant) -> Array[StringName]:
	var result: Array[StringName]
	for value: Variant in values:
		result.append(StringName(value))
	return result
