class_name ProcedureRuntime
extends RefCounted

## Procedure-support rules. The context, its actions and their correctness are
## authored data; this runtime only resolves an action into a story branch.
##
## Branches run through StoryVM as a nested CALL, so a procedure can be raised
## from inside a court or investigation branch without disturbing it.

signal procedure_started(context_id: StringName)
signal action_resolved(result: ProcedureResult)
signal story_branch_requested(target_scene: StringName)
signal branch_resumed(action_id: StringName)
signal procedure_completed
signal action_rejected(message: String)

var game_state: GameState
var state: ProcedureState:
	get:
		return game_state.procedure if game_state != null else null
var last_error: String = ""
var last_result: ProcedureResult
var debug_logging: bool = false

var _repository: ProcedureRepository
var _pending_action: ProcedureActionDef


func _init(
	runtime_game_state: GameState = null,
	procedure_repository: ProcedureRepository = null,
) -> void:
	game_state = runtime_game_state if runtime_game_state != null else GameState.new()
	_repository = procedure_repository


func start_context(context_id: StringName) -> bool:
	if state.active:
		return _reject("A procedure context is already active.")
	var context: ProcedureContext = _repository.get_context(context_id) if _repository != null else null
	if context == null:
		return _fail("Unknown procedure context: %s" % context_id)
	if context.actions.is_empty():
		return _fail("Procedure context '%s' has no actions." % context_id)
	state.active = true
	state.context_id = context_id
	state.resolved = false
	state.resolved_action_id = &""
	state.visited_actions.clear()
	_pending_action = null
	last_result = null
	_log("START %s" % context_id)
	procedure_started.emit(context_id)
	return true


func end_procedure() -> bool:
	if not state.active:
		return _reject("No procedure context is active.")
	# An action scene may end the procedure instead of returning to it.
	if _pending_action != null:
		_finalize_action(_pending_action)
		_pending_action = null
	state.active = false
	state.context_id = &""
	_log("END")
	procedure_completed.emit()
	return true


## Reattaches runtime ownership to a context restored from a save file.
func restore_active_procedure() -> bool:
	_pending_action = null
	last_result = null
	if not state.active:
		return true
	if _get_context() == null:
		return _fail("Saved procedure context does not exist: %s" % state.context_id)
	_log("RESTORE %s" % state.context_id)
	return true


## Drops transient runtime ownership before a save file is applied.
func clear_runtime() -> void:
	_pending_action = null
	last_result = null
	last_error = ""


func current_context() -> ProcedureContext:
	return _get_context()


## Authored procedure data, read-only for callers (save validation, debugger).
func repository() -> ProcedureRepository:
	return _repository


## Actions the player may pick right now: authored actions whose minimal
## requirements are met and, once resolved, only that resolved action.
func available_actions() -> Array[ProcedureActionDef]:
	var result: Array[ProcedureActionDef]
	var context: ProcedureContext = _get_context()
	if context == null:
		return result
	for action: ProcedureActionDef in context.actions:
		if state.resolved and action.id != state.resolved_action_id:
			continue
		if is_action_available(action):
			result.append(action)
	return result


func is_action_available(action: ProcedureActionDef) -> bool:
	if action == null:
		return false
	if not action.required_flag.is_empty():
		if game_state.flags.get(action.required_flag, false) != true:
			return false
	if not action.required_evidence.is_empty():
		var evidence: EvidenceState = game_state.evidence.get(action.required_evidence) as EvidenceState
		if evidence == null or not evidence.owned:
			return false
	return true


## Resolves an action into a story branch. Returns null when rejected.
func select_action(action_id: StringName) -> ProcedureResult:
	if not state.active:
		_reject("No procedure context is active.")
		return null
	if _pending_action != null:
		_reject("A procedure action is already running.")
		return null
	var context: ProcedureContext = _get_context()
	var action: ProcedureActionDef = context.get_action(action_id) if context != null else null
	if action == null:
		_reject("Unknown procedure action: %s" % action_id)
		return null
	if state.resolved and action.id != state.resolved_action_id:
		_reject("This context is already resolved.")
		return null
	if not is_action_available(action):
		_reject("Procedure action requirements are not met: %s" % action_id)
		return null

	var result := ProcedureResult.new(
		action.result_type,
		context.id,
		action.id,
		action.target_scene,
	)
	_pending_action = action
	last_result = result
	_log("ACTION %s -> %s" % [action.id, ProcedureResult.Type.keys()[action.result_type]])
	action_resolved.emit(result)
	story_branch_requested.emit(action.target_scene)
	return result


func resume_after_story_branch() -> bool:
	if _pending_action == null:
		return _reject("No procedure story branch is pending.")
	var action: ProcedureActionDef = _pending_action
	_pending_action = null
	_finalize_action(action)
	_log("RESUME %s visited=%d" % [action.id, state.visited_actions.size()])
	branch_resumed.emit(action.id)
	return true


## Records that an action ran; a CORRECT action resolves the context.
func _finalize_action(action: ProcedureActionDef) -> void:
	state.mark_visited(action.id)
	if action.result_type == ProcedureResult.Type.CORRECT:
		state.resolved = true
		state.resolved_action_id = action.id


func _get_context() -> ProcedureContext:
	if _repository == null or state.context_id.is_empty():
		return null
	return _repository.get_context(state.context_id)


func _reject(message: String) -> bool:
	last_error = message
	action_rejected.emit(message)
	if debug_logging:
		push_warning("[Procedure] %s" % message)
	return false


func _fail(message: String) -> bool:
	last_error = message
	action_rejected.emit(message)
	if debug_logging:
		push_error("[Procedure] %s" % message)
	return false


func _log(message: String) -> void:
	if debug_logging:
		print("[Procedure] %s" % message)
