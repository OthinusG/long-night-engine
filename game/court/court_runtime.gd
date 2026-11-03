class_name CourtRuntime
extends RefCounted

enum RuntimeState {
	INACTIVE,
	TESTIMONY_PREVIEW,
	TESTIMONY_ACTIVE,
	WAIT_STORY_BRANCH,
	COMPLETED,
	FAILED,
	ERROR,
}

signal testimony_started(testimony_id: StringName)
signal preview_statement_changed(statement_id: StringName)
signal preview_finished(testimony_id: StringName)
signal statement_changed(statement_id: StringName)
signal statement_pressed(statement_id: StringName, target_scene: StringName)
signal evidence_presented(result: PresentResult)
signal present_correct(statement_id: StringName, evidence_id: StringName)
signal present_wrong(statement_id: StringName, evidence_id: StringName)
signal penalty_changed(previous: int, current: int)
signal testimony_suspended(context: CourtBranchContext)
signal testimony_resumed(testimony_id: StringName, statement_id: StringName)
signal testimony_completed(testimony_id: StringName)
signal court_failed(testimony_id: StringName)
signal story_branch_requested(target_scene: StringName)
signal action_rejected(message: String)

var game_state: GameState
var state: CourtState:
	get:
		return game_state.court if game_state != null else null
var runtime_state: RuntimeState = RuntimeState.INACTIVE
var last_error: String = ""
var debug_logging: bool = false

var _definition: TestimonyDef
var _evidence_repository: EvidenceRepository
var _pending_branch: CourtBranchContext
var _preview_index: int = 0


func _init(
	runtime_game_state: GameState = null,
	evidence_repository: EvidenceRepository = null,
) -> void:
	game_state = runtime_game_state if runtime_game_state != null else GameState.new()
	_evidence_repository = evidence_repository


func start_testimony(definition: TestimonyDef) -> bool:
	if runtime_state != RuntimeState.INACTIVE or state.active_testimony != null:
		return _reject("Cannot start a testimony while another testimony is active.")
	if definition == null or definition.statements.is_empty():
		return _fail("Testimony definition requires at least one statement.")

	_definition = definition
	state.penalty = CourtState.DEFAULT_PENALTY
	state.active_testimony = TestimonySession.new(definition.id)
	state.active_testimony.current_statement_id = definition.statements[0].id
	runtime_state = RuntimeState.TESTIMONY_PREVIEW
	_preview_index = 0
	_log("START %s" % definition.id)
	testimony_started.emit(definition.id)
	preview_statement_changed.emit(definition.statements[0].id)
	return true


func preview_statement() -> StatementDef:
	if runtime_state != RuntimeState.TESTIMONY_PREVIEW or _definition == null:
		return null
	return _definition.statements[_preview_index]


func advance_preview() -> bool:
	if runtime_state != RuntimeState.TESTIMONY_PREVIEW or _definition == null:
		return false
	if _preview_index + 1 < _definition.statements.size():
		_preview_index += 1
		preview_statement_changed.emit(_definition.statements[_preview_index].id)
		return true
	state.active_testimony.current_statement_id = _definition.statements[0].id
	_mark_current_statement_visited()
	runtime_state = RuntimeState.TESTIMONY_ACTIVE
	preview_finished.emit(_definition.id)
	statement_changed.emit(state.active_testimony.current_statement_id)
	return true


func has_active_testimony() -> bool:
	return state.active_testimony != null


func get_current_statement() -> StatementDef:
	var session: TestimonySession = _active_session()
	if session == null:
		return null
	var statement: StatementDef = _find_statement(session.current_statement_id)
	if statement == null:
		_fail("Unknown current statement: %s" % session.current_statement_id)
	return statement


func current_statement() -> StatementDef:
	return get_current_statement()


func next_statement() -> StatementDef:
	if not _can_interact("next_statement"):
		return null
	var current_index: int = _find_statement_index(state.active_testimony.current_statement_id)
	return _select_statement(mini(current_index + 1, _definition.statements.size() - 1))


func previous_statement() -> StatementDef:
	if not _can_interact("previous_statement"):
		return null
	var current_index: int = _find_statement_index(state.active_testimony.current_statement_id)
	return _select_statement(maxi(current_index - 1, 0))


func press_current_statement() -> StringName:
	if not _can_interact("press_current_statement"):
		return &""
	var statement: StatementDef = get_current_statement()
	if statement == null or statement.press_target_scene.is_empty():
		return &""
	if not state.active_testimony.pressed_statements.has(statement.id):
		state.active_testimony.pressed_statements.append(statement.id)
	_prepare_branch(CourtBranchContext.new(
		CourtBranchContext.Type.PRESS,
		statement.id,
		statement.press_target_scene,
	))
	statement_pressed.emit(statement.id, statement.press_target_scene)
	_log("PRESS %s -> %s" % [statement.id, statement.press_target_scene])
	_request_story_branch()
	return statement.press_target_scene


func present_evidence(statement_id: StringName, evidence_id: StringName) -> PresentResult:
	if not _can_interact("present_evidence"):
		return _invalid_present(statement_id, evidence_id)
	var statement: StatementDef = get_current_statement()
	if statement == null or statement.id != statement_id:
		_reject("Evidence must be presented against the current statement.")
		return _invalid_present(statement_id, evidence_id)
	var definition: EvidenceDef = (
		_evidence_repository.get_evidence(evidence_id)
		if _evidence_repository != null
		else null
	)
	var evidence_state: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if definition == null:
		_reject("Unknown evidence definition: %s" % evidence_id)
		return _invalid_present(statement_id, evidence_id)
	if evidence_state == null or not evidence_state.owned:
		_reject("Evidence is not owned: %s" % evidence_id)
		return _invalid_present(statement_id, evidence_id)
	if not definition.presentable:
		_reject("Evidence is not presentable: %s" % evidence_id)
		return _invalid_present(statement_id, evidence_id)

	# A rule with a version gate only answers for that exact evidence version; a
	# version-specific rule therefore wins over the generic rule for the same
	# evidence, and a mismatched version falls through as wrong.
	var matched_rule: PresentRule = null
	for rule: PresentRule in statement.present_rules:
		if rule.evidence_id != evidence_id:
			continue
		if not rule.matches_version(evidence_state.version):
			continue
		if matched_rule == null or not rule.required_version.is_empty():
			matched_rule = rule
		if not rule.required_version.is_empty():
			break

	if matched_rule != null:
		var correct := PresentResult.new(
			matched_rule.result_type,
			matched_rule.target_scene,
			0,
			statement_id,
			evidence_id,
		)
		_prepare_branch(CourtBranchContext.new(
			CourtBranchContext.Type.CORRECT_PRESENT,
			statement_id,
			matched_rule.target_scene,
			evidence_id,
		))
		evidence_presented.emit(correct)
		present_correct.emit(statement_id, evidence_id)
		_log("PRESENT %s on %s -> %s" % [
			evidence_id,
			statement_id,
			PresentResultType.Value.keys()[matched_rule.result_type],
		])
		_request_story_branch()
		return correct

	var wrong := PresentResult.new(
		PresentResultType.Value.WRONG,
		_definition.wrong_target_scene,
		_definition.wrong_penalty,
		statement_id,
		evidence_id,
	)
	var previous_penalty: int = state.penalty
	PenaltySystem.apply(state, _definition.wrong_penalty)
	if state.penalty == 0:
		state.active_testimony.suspended = true
		runtime_state = RuntimeState.FAILED
	elif not _definition.wrong_target_scene.is_empty():
		_prepare_branch(CourtBranchContext.new(
			CourtBranchContext.Type.WRONG_PRESENT,
			statement_id,
			_definition.wrong_target_scene,
			evidence_id,
		))
	evidence_presented.emit(wrong)
	present_wrong.emit(statement_id, evidence_id)
	penalty_changed.emit(previous_penalty, state.penalty)
	_log("PRESENT %s on %s -> WRONG" % [evidence_id, statement_id])
	_log("PENALTY %d -> %d" % [previous_penalty, state.penalty])
	if runtime_state == RuntimeState.FAILED:
		court_failed.emit(_definition.id)
	elif runtime_state == RuntimeState.WAIT_STORY_BRANCH:
		_request_story_branch()
	return wrong


func resume_after_story_branch() -> bool:
	if runtime_state != RuntimeState.WAIT_STORY_BRANCH or _pending_branch == null:
		return _reject("No court story branch is pending.")
	var branch_type: CourtBranchContext.Type = _pending_branch.type
	_pending_branch = null
	if branch_type == CourtBranchContext.Type.CORRECT_PRESENT:
		return complete_testimony()
	state.active_testimony.suspended = false
	runtime_state = RuntimeState.TESTIMONY_ACTIVE
	_log("RESUME statement=%s" % state.active_testimony.current_statement_id)
	testimony_resumed.emit(_definition.id, state.active_testimony.current_statement_id)
	return true


func complete_testimony() -> bool:
	if not runtime_state in [RuntimeState.TESTIMONY_ACTIVE, RuntimeState.WAIT_STORY_BRANCH]:
		return _reject("No completable testimony is active.")
	var testimony_id: StringName = _definition.id
	state.active_testimony.completed = true
	runtime_state = RuntimeState.COMPLETED
	state.active_testimony = null
	_definition = null
	_pending_branch = null
	_log("COMPLETE %s" % testimony_id)
	testimony_completed.emit(testimony_id)
	runtime_state = RuntimeState.INACTIVE
	return true


func abort_testimony() -> bool:
	if state.active_testimony == null:
		return _reject("No testimony is active.")
	state.active_testimony = null
	_definition = null
	_pending_branch = null
	runtime_state = RuntimeState.INACTIVE
	return true


## Drops transient court runtime ownership before a save file is applied.
## Canonical CourtState is replaced by the serializer, not here.
func clear_runtime() -> void:
	_definition = null
	_pending_branch = null
	runtime_state = RuntimeState.INACTIVE
	last_error = ""


## Reattaches a testimony definition to the session already placed in
## CourtState by SaveSerializer. Presentation rebuild is the caller's job.
func restore_active_testimony(definition: TestimonyDef) -> bool:
	if state.active_testimony == null:
		return _reject("No testimony session is stored in CourtState.")
	if definition == null or definition.id != state.active_testimony.testimony_id:
		return _fail("Unknown testimony session: %s" % state.active_testimony.testimony_id)
	if definition.statements.is_empty():
		return _fail("Testimony '%s' has no statements." % definition.id)
	_definition = definition
	_pending_branch = null
	state.active_testimony.suspended = false
	runtime_state = RuntimeState.TESTIMONY_ACTIVE
	_log("RESTORE %s statement=%s" % [definition.id, state.active_testimony.current_statement_id])
	return true


## Debug-only: selects a statement directly. Reads through the same path as
## next_statement()/previous_statement() so visited state and events stay exact.
func debug_select_statement(statement_id: StringName) -> bool:
	if not _can_interact("debug_select_statement"):
		return false
	for index: int in _definition.statements.size():
		if _definition.statements[index].id == statement_id:
			_select_statement(index)
			return true
	return _reject("Unknown statement: %s" % statement_id)


## Pending Press/Present branch, or null when the testimony is not suspended.
func pending_branch() -> CourtBranchContext:
	return _pending_branch


func _can_interact(action: String) -> bool:
	if runtime_state != RuntimeState.TESTIMONY_ACTIVE or state.active_testimony == null:
		return _reject("%s requires TESTIMONY_ACTIVE." % action)
	return true


func _active_session() -> TestimonySession:
	if state.active_testimony == null or _definition == null:
		_reject("No testimony session is active.")
		return null
	return state.active_testimony


func _select_statement(index: int) -> StatementDef:
	state.active_testimony.current_statement_id = _definition.statements[index].id
	_mark_current_statement_visited()
	var statement: StatementDef = get_current_statement()
	_log("STATEMENT %s" % statement.id)
	statement_changed.emit(statement.id)
	return statement


func _find_statement(statement_id: StringName) -> StatementDef:
	if _definition == null:
		return null
	for statement: StatementDef in _definition.statements:
		if statement.id == statement_id:
			return statement
	return null


func _find_statement_index(statement_id: StringName) -> int:
	for index: int in _definition.statements.size():
		if _definition.statements[index].id == statement_id:
			return index
	_fail("Unknown statement: %s" % statement_id)
	return 0


func _mark_current_statement_visited() -> void:
	var statement_id: StringName = state.active_testimony.current_statement_id
	if not state.active_testimony.visited_statements.has(statement_id):
		state.active_testimony.visited_statements.append(statement_id)


func _prepare_branch(context: CourtBranchContext) -> void:
	state.active_testimony.suspended = true
	_pending_branch = context
	runtime_state = RuntimeState.WAIT_STORY_BRANCH
	testimony_suspended.emit(context)


func _request_story_branch() -> void:
	story_branch_requested.emit(_pending_branch.target_scene)


func _invalid_present(statement_id: StringName, evidence_id: StringName) -> PresentResult:
	return PresentResult.new(
		PresentResultType.Value.INVALID,
		&"",
		0,
		statement_id,
		evidence_id,
	)


func _reject(message: String) -> bool:
	last_error = message
	action_rejected.emit(message)
	if debug_logging:
		push_warning("[Court] %s" % message)
	return false


func _fail(message: String) -> bool:
	last_error = message
	runtime_state = RuntimeState.ERROR
	action_rejected.emit(message)
	if debug_logging:
		push_error("[Court] %s" % message)
	return false


func _log(message: String) -> void:
	if debug_logging:
		print("[Court] %s" % message)
