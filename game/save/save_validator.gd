class_name SaveValidator
extends RefCounted

## Rejects malformed or inconsistent save payloads before any runtime state is
## touched. Every rejection leaves error_message describing the first defect.

var error_message: String = ""


func validate(
	data: Dictionary,
	program: StoryProgram,
	evidence_repository: EvidenceRepository,
	procedure_repository: ProcedureRepository = null,
) -> bool:
	error_message = ""
	if program == null:
		return _fail("A loaded StoryProgram is required to validate a save.")
	if evidence_repository == null:
		return _fail("An EvidenceRepository is required to validate a save.")

	var version: Variant = data.get("schema_version")
	if not _is_number(version):
		return _fail("Save requires a numeric schema_version.")
	if int(version) < 1 or int(version) > GameState.SAVE_SCHEMA_VERSION:
		return _fail("Unsupported save schema_version: %s" % version)
	if not data.get("game_version") is String:
		return _fail("Save requires a game_version string.")
	if not _is_number(data.get("playtime")) or float(data["playtime"]) < 0.0:
		return _fail("Save requires a non-negative numeric playtime.")
	for section: String in SaveSerializer.DOCUMENT_SECTIONS:
		if not data.get(section) is Dictionary:
			return _fail("Save requires a '%s' object." % section)

	var story: Dictionary = data["story"]
	var flags: Dictionary = data["flags"]
	var evidence: Dictionary = data["evidence"]
	var court: Dictionary = data["court"]
	var investigation: Dictionary = data["investigation"]
	var procedure: Dictionary = data["procedure"]

	if not _validate_story(story, program):
		return false
	if not _validate_flags(flags):
		return false
	if not _validate_evidence(evidence, evidence_repository):
		return false
	if not _validate_court(court, program):
		return false
	if not _validate_investigation(investigation, program):
		return false
	if not _validate_procedure(procedure, procedure_repository):
		return false
	var story_state: String = str(story.get("runtime_state"))
	if story_state == "WAIT_COURT" and not court["active"]:
		return _fail("Save waits for court without an active testimony.")
	if (story_state == "WAIT_INVESTIGATION") != bool(investigation["active"]):
		return _fail("Save story state and investigation state disagree.")
	if (story_state == "WAIT_PROCEDURE") != bool(procedure["active"]):
		return _fail("Save story state and procedure state disagree.")
	return true


func _validate_story(story: Dictionary, program: StoryProgram) -> bool:
	var scene_id := StringName(str(story.get("scene", "")))
	var scene: StoryScene = program.get_scene(scene_id)
	if scene == null:
		return _fail("Save references an unknown scene: '%s'." % scene_id)
	var index: Variant = story.get("instruction_index")
	if not _is_number(index) or int(index) < 0 or int(index) > scene.instructions.size():
		return _fail(
			"Save instruction_index %s is out of range for scene '%s'." % [index, scene_id]
		)
	if not story.get("chapter") is String or not story.get("background") is String:
		return _fail("Save requires string story.chapter and story.background.")
	var state_name: Variant = story.get("runtime_state")
	if not state_name is String or not StoryState.RuntimeState.has(state_name):
		return _fail("Save has an unknown story runtime state: '%s'." % state_name)
	var restore_state: StoryState.RuntimeState = StoryState.RuntimeState[state_name]
	if restore_state not in [
		StoryState.RuntimeState.WAIT_DIALOGUE,
		StoryState.RuntimeState.WAIT_COURT,
		StoryState.RuntimeState.WAIT_INVESTIGATION,
		StoryState.RuntimeState.WAIT_PROCEDURE,
	]:
		return _fail("Save story runtime state cannot be restored: '%s'." % state_name)
	if not story.get("call_stack") is Array:
		return _fail("Save requires a story.call_stack array.")
	for frame: Variant in story["call_stack"]:
		if not frame is Dictionary:
			return _fail("Save call stack frames must be objects.")
		var frame_data: Dictionary = frame
		if not frame_data.get("scene") is String or not _is_number(frame_data.get("instruction")):
			return _fail("Save call stack frames require scene and instruction.")
		var frame_scene: StoryScene = program.get_scene(StringName(frame_data["scene"]))
		if frame_scene == null:
			return _fail("Save call stack references an unknown scene: '%s'." % frame_data["scene"])
		var frame_index: int = int(frame_data["instruction"])
		if frame_index < 0 or frame_index > frame_scene.instructions.size():
			return _fail(
				"Save call stack instruction %d is out of range for scene '%s'."
				% [frame_index, frame_data["scene"]]
			)
	return true


func _validate_flags(flags: Dictionary) -> bool:
	for flag_key: Variant in flags:
		if not flag_key is String:
			return _fail("Flag names must be strings.")
	return true


func _validate_evidence(
	evidence: Dictionary,
	evidence_repository: EvidenceRepository,
) -> bool:
	for evidence_key: Variant in evidence:
		if evidence_repository.get_evidence(StringName(evidence_key)) == null:
			return _fail("Save references an unknown evidence ID: '%s'." % evidence_key)
		var entry: Variant = evidence[evidence_key]
		if not entry is Dictionary:
			return _fail("Save evidence entry '%s' must be an object." % evidence_key)
		var entry_data: Dictionary = entry
		if (
			not entry_data.get("owned") is bool
			or not entry_data.get("discovered") is bool
			or not entry_data.get("version") is String
		):
			return _fail(
				"Save evidence entry '%s' requires bool owned/discovered and string version."
				% evidence_key
			)
		if not entry_data.get("inspected_hotspots") is Array:
			return _fail("Save evidence entry '%s' requires an inspected_hotspots array." % evidence_key)
		for hotspot: Variant in entry_data["inspected_hotspots"]:
			if not hotspot is String:
				return _fail("Save evidence entry '%s' hotspot IDs must be strings." % evidence_key)
		if not entry_data.get("inspection_complete") is bool:
			return _fail("Save evidence entry '%s' requires bool inspection_complete." % evidence_key)
	return true


func _validate_court(court: Dictionary, program: StoryProgram) -> bool:
	var penalty: Variant = court.get("penalty")
	if not _is_number(penalty) or int(penalty) < 0 or int(penalty) > CourtState.DEFAULT_PENALTY:
		return _fail("Save court.penalty is out of range: %s." % penalty)
	if not court.get("active") is bool:
		return _fail("Save requires a bool court.active.")
	if not court["active"]:
		return true

	var testimony_id := StringName(str(court.get("testimony_id", "")))
	var testimony: TestimonyDef = program.get_testimony(testimony_id)
	if testimony == null:
		return _fail("Save references an unknown testimony: '%s'." % testimony_id)
	var statement_id := StringName(str(court.get("current_statement_id", "")))
	if _find_statement(testimony, statement_id) == null:
		return _fail("Save references an unknown statement: '%s'." % statement_id)
	for field: String in ["visited_statements", "pressed_statements"]:
		var value: Variant = court.get(field)
		if not value is Array:
			return _fail("Save requires a court.%s array." % field)
		for entry: Variant in value:
			if not entry is String:
				return _fail("Save court.%s must contain statement ID strings." % field)
			if _find_statement(testimony, StringName(entry)) == null:
				return _fail("Save court.%s references an unknown statement: '%s'." % [field, entry])
	return true


func _validate_investigation(investigation: Dictionary, program: StoryProgram) -> bool:
	if not investigation.get("active") is bool:
		return _fail("Save requires a bool investigation.active.")
	var mode_name: Variant = investigation.get("mode")
	if not mode_name is String or not InvestigationState.Mode.has(mode_name):
		return _fail("Save has an unknown investigation mode: '%s'." % mode_name)
	if not investigation.get("location") is String or not investigation.get("character") is String:
		return _fail("Save requires string investigation.location and investigation.character.")
	if not investigation.get("visited_locations") is Array:
		return _fail("Save requires an investigation.visited_locations array.")
	if not investigation.get("locations") is Dictionary:
		return _fail("Save requires an investigation.locations object.")

	for visited: Variant in investigation["visited_locations"]:
		if not visited is String or program.get_location(StringName(visited)) == null:
			return _fail("Save references an unknown visited location: '%s'." % visited)

	var locations: Dictionary = investigation["locations"]
	for location_key: Variant in locations:
		var location: LocationDef = program.get_location(StringName(location_key))
		if location == null:
			return _fail("Save references an unknown investigation location: '%s'." % location_key)
		if not locations[location_key] is Dictionary:
			return _fail("Save investigation location '%s' must be an object." % location_key)
		var entry: Dictionary = locations[location_key]
		for field: String in [
			"examined_hotspots",
			"unlocked_topics",
			"completed_topics",
			"unlocked_moves",
		]:
			if not entry.get(field) is Array:
				return _fail("Save requires an investigation location '%s' array." % field)
			for value: Variant in entry[field]:
				if not value is String:
					return _fail("Save investigation '%s' entries must be strings." % field)
				if field == "examined_hotspots" and location.get_hotspot(StringName(value)) == null:
					return _fail("Save references an unknown hotspot: '%s'." % value)
				if field in ["unlocked_topics", "completed_topics"] and location.get_topic(StringName(value)) == null:
					return _fail("Save references an unknown topic: '%s'." % value)

	if not investigation["active"]:
		if mode_name != InvestigationState.Mode.keys()[InvestigationState.Mode.INACTIVE]:
			return _fail("An inactive investigation cannot be in mode '%s'." % mode_name)
		return true
	# Transient modes are never saved: they own a running story branch.
	var mode: InvestigationState.Mode = InvestigationState.Mode[mode_name]
	if mode in [
		InvestigationState.Mode.INACTIVE,
		InvestigationState.Mode.WAIT_STORY_BRANCH,
		InvestigationState.Mode.ERROR,
	]:
		return _fail("Active investigation cannot be restored from mode '%s'." % mode_name)
	var current: LocationDef = program.get_location(StringName(investigation["location"]))
	if current == null:
		return _fail("Save references an unknown current location: '%s'." % investigation["location"])
	if not locations.has(String(current.id)):
		return _fail("Save has no progress for the current location: '%s'." % current.id)
	return true


func _validate_procedure(
	procedure: Dictionary,
	procedure_repository: ProcedureRepository,
) -> bool:
	if not procedure.get("active") is bool:
		return _fail("Save requires a bool procedure.active.")
	if not procedure.get("context_id") is String:
		return _fail("Save requires a string procedure.context_id.")
	if not procedure.get("resolved") is bool:
		return _fail("Save requires a bool procedure.resolved.")
	if not procedure.get("resolved_action_id") is String:
		return _fail("Save requires a string procedure.resolved_action_id.")
	if not procedure.get("visited_actions") is Array:
		return _fail("Save requires a procedure.visited_actions array.")
	var visited: Array = procedure["visited_actions"]
	for action_id: Variant in visited:
		if not action_id is String:
			return _fail("Save procedure.visited_actions entries must be strings.")
	if not procedure["active"]:
		# `resolved` and `visited_actions` stay as history after a context ends.
		return true
	if procedure_repository == null:
		return true
	var context: ProcedureContext = procedure_repository.get_context(
		StringName(procedure["context_id"])
	)
	if context == null:
		return _fail("Save references an unknown procedure context: '%s'." % procedure["context_id"])
	for action_id: Variant in visited:
		if context.get_action(StringName(action_id)) == null:
			return _fail("Save references an unknown procedure action: '%s'." % action_id)
	var resolved_id: String = procedure["resolved_action_id"]
	if procedure["resolved"] and context.get_action(StringName(resolved_id)) == null:
		return _fail("Save references an unknown resolved action: '%s'." % resolved_id)
	return true


func _find_statement(testimony: TestimonyDef, statement_id: StringName) -> StatementDef:
	for statement: StatementDef in testimony.statements:
		if statement.id == statement_id:
			return statement
	return null


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _fail(message: String) -> bool:
	error_message = message
	return false
