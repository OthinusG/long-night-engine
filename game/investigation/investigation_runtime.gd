class_name InvestigationRuntime
extends RefCounted

## Investigation gameplay rules. Owns canonical InvestigationState and never
## touches UI nodes; presentation rebuilds from state and events.
##
## Story branches (examine/talk/present) run through StoryVM CALL/RETURN exactly
## like court branches, so the investigation survives them untouched.

signal investigation_started(location_id: StringName)
signal location_changed(location_id: StringName)
signal mode_changed(mode: InvestigationState.Mode)
signal tools_changed
signal story_branch_requested(target_scene: StringName)
signal branch_resumed(context: InvestigationBranchContext)
signal investigation_completed
signal action_rejected(message: String)

var game_state: GameState
var state: InvestigationState:
	get:
		return game_state.investigation if game_state != null else null
var last_error: String = ""
var debug_logging: bool = false

var _program: StoryProgram
var _evidence_repository: EvidenceRepository
var _pending_branch: InvestigationBranchContext


func _init(
	runtime_game_state: GameState = null,
	program: StoryProgram = null,
	evidence_repository: EvidenceRepository = null,
) -> void:
	game_state = runtime_game_state if runtime_game_state != null else GameState.new()
	_program = program
	_evidence_repository = evidence_repository


# --- lifecycle ---------------------------------------------------------------

func start_investigation(location_id: StringName) -> bool:
	if state.active:
		return _reject("An investigation is already active.")
	var location: LocationDef = _get_location(location_id)
	if location == null:
		return _fail("Unknown investigation location: %s" % location_id)
	state.active = true
	_pending_branch = null
	_enter_location(location)
	_set_mode(InvestigationState.Mode.DEFAULT)
	_log("START %s" % location_id)
	investigation_started.emit(location_id)
	return true


func end_investigation() -> bool:
	if not state.active:
		return _reject("No investigation is active.")
	state.active = false
	state.current_location = &""
	state.current_character = &""
	_pending_branch = null
	_set_mode(InvestigationState.Mode.INACTIVE)
	_log("END")
	investigation_completed.emit()
	return true


## Reattaches runtime ownership to an investigation restored from a save file.
## Presentation rebuild is the caller's job.
func restore_active_investigation() -> bool:
	_pending_branch = null
	if not state.active:
		_set_mode(InvestigationState.Mode.INACTIVE)
		return true
	var location: LocationDef = _get_location(state.current_location)
	if location == null:
		return _fail("Saved location does not exist: %s" % state.current_location)
	if state.mode == InvestigationState.Mode.WAIT_STORY_BRANCH:
		state.mode = InvestigationState.Mode.DEFAULT
	_log("RESTORE %s mode=%s" % [
		state.current_location,
		InvestigationState.Mode.keys()[state.mode],
	])
	return true


## Drops transient runtime ownership before a save file is applied.
func clear_runtime() -> void:
	_pending_branch = null
	last_error = ""


# --- actions -----------------------------------------------------------------

## Returns the story branch scene to run, or an empty name when rejected.
func examine(hotspot_id: StringName) -> StringName:
	if not _can_act("examine"):
		return &""
	var location: LocationDef = current_location()
	var hotspot: HotspotDef = location.get_hotspot(hotspot_id) if location != null else null
	if hotspot == null or hotspot.scene.is_empty():
		_reject("Unknown hotspot: %s" % hotspot_id)
		return &""
	_prepare_branch(InvestigationBranchContext.new(
		InvestigationBranchContext.Type.EXAMINE,
		hotspot.scene,
		hotspot.id,
	))
	return hotspot.scene


## Returns the story branch scene to run, or an empty name when rejected.
func talk(topic_id: StringName) -> StringName:
	if not _can_act("talk"):
		return &""
	var location: LocationDef = current_location()
	var topic: TalkTopicDef = location.get_topic(topic_id) if location != null else null
	if topic == null or topic.scene.is_empty():
		_reject("Unknown topic: %s" % topic_id)
		return &""
	if not is_topic_available(topic_id):
		_reject("Topic is not available: %s" % topic_id)
		return &""
	_prepare_branch(InvestigationBranchContext.new(
		InvestigationBranchContext.Type.TALK,
		topic.scene,
		&"",
		topic.id,
		&"",
		state.current_character,
	))
	return topic.scene


func move(destination_id: StringName) -> bool:
	if not _can_act("move"):
		return false
	var location: LocationDef = current_location()
	if location == null:
		return _fail("No investigation location is active.")
	if not location.moves.has(destination_id):
		return _reject("'%s' cannot be reached from '%s'." % [destination_id, location.id])
	if not is_move_available(destination_id):
		return _reject("Move to '%s' is locked." % destination_id)
	var destination: LocationDef = _get_location(destination_id)
	if destination == null:
		return _fail("Unknown investigation location: %s" % destination_id)
	_log("MOVE %s -> %s" % [location.id, destination_id])
	_enter_location(destination)
	_set_mode(InvestigationState.Mode.DEFAULT)
	tools_changed.emit()
	return true


## Returns the story branch scene to run, or an empty name when rejected.
func present(evidence_id: StringName) -> StringName:
	if not _can_act("present"):
		return &""
	var location: LocationDef = current_location()
	if location == null:
		_fail("No investigation location is active.")
		return &""
	if state.current_character.is_empty() or not location.characters.has(state.current_character):
		_reject("There is nobody here to present evidence to.")
		return &""
	var definition: EvidenceDef = (
		_evidence_repository.get_evidence(evidence_id)
		if _evidence_repository != null
		else null
	)
	var evidence: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if definition == null or evidence == null or not evidence.owned:
		_reject("Evidence is not available: %s" % evidence_id)
		return &""
	if not definition.presentable:
		_reject("Evidence is not presentable: %s" % evidence_id)
		return &""
	# ponytail: reactions are keyed by evidence per location because the demo has
	# one character per location. Key them by (character, evidence) once a
	# location actually holds two speaking characters.
	var scene: StringName = location.present_scene(evidence_id)
	if scene.is_empty():
		_reject("No present reaction is authored in '%s'." % location.id)
		return &""
	_prepare_branch(InvestigationBranchContext.new(
		InvestigationBranchContext.Type.PRESENT,
		scene,
		&"",
		&"",
		evidence_id,
		state.current_character,
	))
	return scene


## Called by the story branch runner (@talk_unlock) to reveal a hidden topic.
func unlock_topic(topic_id: StringName) -> bool:
	if not state.active:
		return _reject("@talk_unlock requires an active investigation.")
	var cur_loc: LocationDef = current_location()
	if cur_loc != null and cur_loc.get_topic(topic_id) != null:
		state.ensure_location_state(cur_loc.id).unlock_topic(topic_id)
		_log("UNLOCK %s in %s" % [topic_id, cur_loc.id])
		tools_changed.emit()
		return true
	for location: LocationDef in _all_locations():
		if location.get_topic(topic_id) == null:
			continue
		state.ensure_location_state(location.id).unlock_topic(topic_id)
		_log("UNLOCK %s in %s" % [topic_id, location.id])
		tools_changed.emit()
		return true
	return _fail("Unknown talk topic: %s" % topic_id)


func resume_after_story_branch() -> bool:
	if _pending_branch == null:
		return _reject("No investigation story branch is pending.")
	var context: InvestigationBranchContext = _pending_branch
	_pending_branch = null
	var location_state: LocationState = state.get_location_state(state.current_location)
	if location_state != null:
		match context.type:
			InvestigationBranchContext.Type.EXAMINE:
				location_state.mark_examined(context.hotspot_id)
			InvestigationBranchContext.Type.TALK:
				location_state.complete_topic(context.topic_id)
			_:
				pass
	_set_mode(
		InvestigationState.Mode.LOCATION_ACTIVE
		if context.type == InvestigationBranchContext.Type.EXAMINE
		else InvestigationState.Mode.DEFAULT
	)
	_log("RESUME %s" % InvestigationBranchContext.Type.keys()[context.type])
	branch_resumed.emit(context)
	tools_changed.emit()
	return true


func set_mode(mode: InvestigationState.Mode) -> bool:
	if not state.active:
		return _reject("No investigation is active.")
	if mode in [
		InvestigationState.Mode.INACTIVE,
		InvestigationState.Mode.WAIT_STORY_BRANCH,
		InvestigationState.Mode.ERROR,
	]:
		return _reject("Mode %s is owned by the runtime." % InvestigationState.Mode.keys()[mode])
	if mode == state.mode:
		return true
	_set_mode(mode)
	tools_changed.emit()
	return true


# --- queries -----------------------------------------------------------------

func current_location() -> LocationDef:
	return _get_location(state.current_location)


func available_topics() -> Array[TalkTopicDef]:
	var result: Array[TalkTopicDef]
	var location: LocationDef = current_location()
	if location == null:
		return result
	var location_state: LocationState = state.get_location_state(location.id)
	if location_state == null:
		return result
	for topic: TalkTopicDef in location.topics:
		if location_state.has_unlocked_topic(topic.id):
			result.append(topic)
	return result


func is_topic_available(topic_id: StringName) -> bool:
	var location_state: LocationState = state.get_location_state(state.current_location)
	return location_state != null and location_state.has_unlocked_topic(topic_id)


func is_topic_completed(topic_id: StringName) -> bool:
	var location_state: LocationState = state.get_location_state(state.current_location)
	return location_state != null and location_state.has_completed_topic(topic_id)


func is_hotspot_examined(hotspot_id: StringName) -> bool:
	var location_state: LocationState = state.get_location_state(state.current_location)
	return location_state != null and location_state.has_examined(hotspot_id)


func is_move_available(destination_id: StringName) -> bool:
	var location_state: LocationState = state.get_location_state(state.current_location)
	return location_state != null and location_state.has_unlocked_move(destination_id)


func available_moves() -> Array[StringName]:
	var result: Array[StringName]
	var location: LocationDef = current_location()
	if location == null:
		return result
	for destination: StringName in location.moves:
		if is_move_available(destination):
			result.append(destination)
	return result


func can_talk() -> bool:
	return _can_act("talk") and not available_topics().is_empty()


func can_present() -> bool:
	var location: LocationDef = current_location()
	return (
		_can_act("present")
		and location != null
		and not state.current_character.is_empty()
		and location.characters.has(state.current_character)
	)


## The authored @investigation_end is allowed only after every evidence clue
## exposed by the visited investigation hotspots is owned.
func can_complete_pending_branch() -> bool:
	var missing: Array[StringName]
	for evidence_id: StringName in _required_investigation_evidence():
		var evidence: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
		if evidence == null or not evidence.owned:
			missing.append(evidence_id)
	if missing.is_empty():
		return true
	_reject("Investigation is incomplete; missing evidence: %s" % ", ".join(missing))
	return false


func pending_branch() -> InvestigationBranchContext:
	return _pending_branch


# --- internals ---------------------------------------------------------------

func _get_location(location_id: StringName) -> LocationDef:
	if _program == null or location_id.is_empty():
		return null
	return _program.get_location(location_id)


func _all_locations() -> Array[LocationDef]:
	if _program == null:
		return []
	return _program.locations.values()


func _required_investigation_evidence() -> Array[StringName]:
	var required: Array[StringName]
	for location_id: StringName in state.visited_locations:
		var location: LocationDef = _get_location(location_id)
		if location == null:
			continue
		for hotspot: HotspotDef in location.hotspots:
			var scene: StoryScene = _program.get_scene(hotspot.scene)
			if scene == null:
				continue
			for instruction: StoryInstruction in scene.instructions:
				if instruction.op == StoryInstruction.Op.EVIDENCE_ADD and not required.has(instruction.evidence_id):
					required.append(instruction.evidence_id)
	return required


## Moves the investigation to a location and initializes its first-visit state.
func _enter_location(location: LocationDef) -> void:
	state.current_location = location.id
	state.mark_visited(location.id)
	state.current_character = (
		location.characters[0] if not location.characters.is_empty() else &""
	)
	var location_state: LocationState = state.ensure_location_state(location.id)
	if not location_state.visited:
		location_state.visited = true
		# Authored content is available from the first visit; @talk_unlock adds the
		# topics that start hidden, and every authored move starts unlocked.
		for topic: TalkTopicDef in location.topics:
			if not topic.locked:
				location_state.unlock_topic(topic.id)
		for destination: StringName in location.moves:
			location_state.unlock_move(destination)
	_log("LOCATION %s" % location.id)
	location_changed.emit(location.id)


func _prepare_branch(context: InvestigationBranchContext) -> void:
	_pending_branch = context
	last_error = ""
	_set_mode(InvestigationState.Mode.WAIT_STORY_BRANCH)
	_log("BRANCH %s -> %s" % [
		InvestigationBranchContext.Type.keys()[context.type],
		context.target_scene,
	])
	story_branch_requested.emit(context.target_scene)


func _can_act(action: String) -> bool:
	if not state.active:
		return _reject("%s requires an active investigation." % action)
	if state.mode in [
		InvestigationState.Mode.WAIT_STORY_BRANCH,
		InvestigationState.Mode.ERROR,
		InvestigationState.Mode.INACTIVE,
	]:
		_reject("%s is unavailable while the investigation is in %s." % [
			action,
			InvestigationState.Mode.keys()[state.mode],
		])
		return false
	return true


func _set_mode(mode: InvestigationState.Mode) -> void:
	if state.mode == mode:
		return
	state.mode = mode
	mode_changed.emit(mode)


func _reject(message: String) -> bool:
	last_error = message
	action_rejected.emit(message)
	if debug_logging:
		push_warning("[Investigation] %s" % message)
	return false


func _fail(message: String) -> bool:
	last_error = message
	state.mode = InvestigationState.Mode.ERROR
	action_rejected.emit(message)
	if debug_logging:
		push_error("[Investigation] %s" % message)
	return false


func _log(message: String) -> void:
	if debug_logging:
		print("[Investigation] %s" % message)
