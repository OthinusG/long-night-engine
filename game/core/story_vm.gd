class_name StoryVM
extends RefCounted

signal dialogue_requested(
	speaker_id: StringName,
	expression_id: StringName,
	text: String,
	source: SourceLocation,
)
signal scene_changed(scene_id: StringName)
signal background_requested(background_id: StringName)
signal bgm_requested(bgm_id: StringName)
signal sfx_requested(sfx_id: StringName)
signal court_requested(testimony_id: StringName)
signal court_branch_finished
signal investigation_requested(location_id: StringName)
signal investigation_branch_finished
signal investigation_finished
signal talk_unlock_requested(topic_id: StringName)
signal procedure_requested(context_id: StringName)
signal character_requested(
	character_id: StringName,
	slot: StringName,
	expression_id: StringName,
)
signal character_hidden(character_id: StringName)
signal procedure_branch_finished
signal procedure_finished
signal inspection_branch_finished
signal runtime_error(message: String)

const MAX_INSTRUCTIONS_PER_RUN: int = 10_000

## Which gameplay subsystem owns the current CALL/RETURN branch. Only one branch
## can be active, so court and investigation share one mechanism.
enum BranchKind {
	NONE,
	COURT,
	INVESTIGATION,
}

## Nested branches run *inside* an outer branch (a procedure raised during a
## press, an evidence inspection opened from the Court Record). They push their
## own call frame, so the outer branch survives untouched.
enum NestedKind {
	NONE,
	PROCEDURE,
	INSPECTION,
}

var game_state: GameState
var program: StoryProgram
var debug_logging: bool = false
var last_error: String = ""

var _registry: CommandRegistry
var _context: StoryRuntimeContext
var _pending_dialogue_speaker: StringName
var _pending_dialogue_expression: StringName
var _pending_dialogue_text: String
var _pending_dialogue_source: SourceLocation
var _pending_court_id: StringName
var _pending_investigation_id: StringName
var _pending_procedure_id: StringName
var _branch_kind: BranchKind = BranchKind.NONE
var _branch_continuation_scene: StringName
var _branch_continuation_instruction: int = 0
var _branch_stack_depth: int = 0
var _nested_kind: NestedKind = NestedKind.NONE
var _nested_return_state: StoryState.RuntimeState = StoryState.RuntimeState.RUNNING
var _nested_continuation_scene: StringName
var _nested_continuation_instruction: int = 0
var _nested_frame_depth: int = 0
var _investigation_completion_guard: Callable


func _init(
	runtime_game_state: GameState = null,
	command_registry: CommandRegistry = null,
) -> void:
	game_state = runtime_game_state if runtime_game_state != null else GameState.new()
	_registry = command_registry if command_registry != null else CommandRegistry.create_default()
	_context = StoryRuntimeContext.new(game_state)
	_context.dialogue_requested.connect(_capture_dialogue_request)
	_context.background_requested.connect(_forward_background_request)
	_context.bgm_requested.connect(_forward_bgm_request)
	_context.sfx_requested.connect(_forward_sfx_request)
	_context.court_requested.connect(_capture_court_request)
	_context.investigation_requested.connect(_capture_investigation_request)
	_context.talk_unlock_requested.connect(_forward_talk_unlock_request)
	_context.procedure_requested.connect(_capture_procedure_request)
	_context.character_requested.connect(_forward_character_request)
	_context.character_hidden.connect(_forward_character_hidden)


func load_program(story_program: StoryProgram) -> void:
	if story_program == null:
		_fail_runtime("Cannot load a null StoryProgram.")
		return
	program = story_program
	last_error = ""
	game_state.story.current_chapter = &""
	game_state.story.current_scene = &""
	game_state.story.current_instruction = 0
	game_state.story.call_stack.clear()
	game_state.story.runtime_state = StoryState.RuntimeState.PAUSED
	_clear_story_branch()
	_clear_nested_branch()


func set_investigation_completion_guard(guard: Callable) -> void:
	_investigation_completion_guard = guard


func start(scene_id: StringName) -> void:
	if program == null:
		_fail_runtime("Cannot start without a loaded StoryProgram.")
		return
	var scene: StoryScene = program.get_scene(scene_id)
	if scene == null:
		_fail_runtime("Unknown start scene: %s" % scene_id)
		return
	if scene.source == null:
		_fail_runtime("Start scene '%s' has no source location." % scene_id)
		return

	last_error = ""
	_clear_pending_dialogue()
	_pending_court_id = &""
	_pending_investigation_id = &""
	_pending_procedure_id = &""
	_set_story_position(scene_id, 0)
	game_state.story.call_stack.clear()
	_clear_story_branch()
	_clear_nested_branch()
	game_state.story.current_chapter = StringName(scene.source.file.get_slice("/", 0))
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	_log("START scene=%s" % scene_id)
	run_until_blocked()


func run_until_blocked() -> void:
	if game_state.story.runtime_state != StoryState.RuntimeState.RUNNING:
		return
	if program == null:
		_fail_runtime("Cannot run without a loaded StoryProgram.")
		return

	var executed_count: int = 0
	while game_state.story.runtime_state == StoryState.RuntimeState.RUNNING:
		executed_count += 1
		if executed_count > MAX_INSTRUCTIONS_PER_RUN:
			_fail_runtime("Instruction budget exceeded; possible infinite story loop.", _current_instruction())
			return

		var scene: StoryScene = program.get_scene(game_state.story.current_scene)
		if scene == null:
			_fail_runtime("Current scene does not exist: %s" % game_state.story.current_scene)
			return
		var index: int = game_state.story.current_instruction
		if index < 0 or index > scene.instructions.size():
			_fail_runtime("Invalid instruction index %d in scene '%s'." % [index, scene.id])
			return
		if index == scene.instructions.size():
			if _branch_kind != BranchKind.NONE:
				_fail_runtime("%s story branch '%s' ended without RETURN." % [
					BranchKind.keys()[_branch_kind],
					scene.id,
				])
				return
			if game_state.story.call_stack.is_empty():
				game_state.story.runtime_state = StoryState.RuntimeState.FINISHED
				_log("FINISHED")
			else:
				_fail_runtime("Called scene '%s' ended without RETURN." % scene.id)
			return

		var instruction: StoryInstruction = scene.instructions[index]
		if instruction == null:
			_fail_runtime("Scene '%s' contains a null instruction at index %d." % [scene.id, index])
			return
		var handler: StoryCommand = _registry.get_handler(instruction.op)
		if handler == null:
			_fail_runtime("No handler registered for instruction op %d." % instruction.op, instruction)
			return

		_log_instruction(instruction)
		var result: CommandResult = handler.execute(instruction, _context)
		if result == null:
			_fail_runtime("Command returned no result.", instruction)
			return
		_apply_command_result(result, instruction)


func resume_dialogue() -> void:
	if game_state.story.runtime_state != StoryState.RuntimeState.WAIT_DIALOGUE:
		_fail_runtime("resume_dialogue() requires WAIT_DIALOGUE.")
		return
	_log("RESUME_DIALOGUE")
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	run_until_blocked()


func call_court_branch(scene_id: StringName) -> bool:
	return _call_story_branch(
		scene_id,
		BranchKind.COURT,
		StoryState.RuntimeState.WAIT_COURT,
	)


func call_investigation_branch(scene_id: StringName) -> bool:
	return _call_story_branch(
		scene_id,
		BranchKind.INVESTIGATION,
		StoryState.RuntimeState.WAIT_INVESTIGATION,
	)


## Runs a gameplay branch with CALL/RETURN semantics: the story position is kept
## aside, the branch scene executes, and RETURN restores it.
func _call_story_branch(
	scene_id: StringName,
	kind: BranchKind,
	expected_state: StoryState.RuntimeState,
) -> bool:
	if game_state.story.runtime_state != expected_state:
		_fail_runtime("A %s branch requires %s." % [
			BranchKind.keys()[kind],
			StoryState.RuntimeState.keys()[expected_state],
		])
		return false
	if _branch_kind != BranchKind.NONE:
		_fail_runtime("A story branch is already active.")
		return false
	if program == null or program.get_scene(scene_id) == null:
		_fail_runtime("Unknown story branch scene: %s" % scene_id)
		return false
	_branch_kind = kind
	_branch_continuation_scene = game_state.story.current_scene
	_branch_continuation_instruction = game_state.story.current_instruction
	_branch_stack_depth = game_state.story.call_stack.size()
	_set_story_position(scene_id, 0)
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	_log("%s_BRANCH %s" % [BranchKind.keys()[kind], scene_id])
	run_until_blocked()
	return game_state.story.runtime_state != StoryState.RuntimeState.ERROR


func resume_from_court() -> bool:
	if game_state.story.runtime_state != StoryState.RuntimeState.WAIT_COURT:
		_fail_runtime("resume_from_court() requires WAIT_COURT.")
		return false
	if _branch_kind != BranchKind.NONE:
		_fail_runtime("Cannot resume main story while a story branch is active.")
		return false
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	_log("RESUME_COURT")
	run_until_blocked()
	return game_state.story.runtime_state != StoryState.RuntimeState.ERROR


## True while a gameplay branch (or a nested branch inside it) owns the
## instruction pointer. Such a position is intentionally not saveable.
func is_in_story_branch() -> bool:
	return _branch_kind != BranchKind.NONE or _nested_kind != NestedKind.NONE


## Runs a procedure action scene as a nested branch and returns to WAIT_PROCEDURE.
func call_procedure_branch(scene_id: StringName) -> bool:
	return _call_nested_branch(
		scene_id,
		NestedKind.PROCEDURE,
		[StoryState.RuntimeState.WAIT_PROCEDURE],
		StoryState.RuntimeState.WAIT_PROCEDURE,
	)


## Runs an inspection hotspot scene as a nested branch and returns to whichever
## state hosted the inspection (court or investigation).
func call_inspection_branch(scene_id: StringName) -> bool:
	return _call_nested_branch(
		scene_id,
		NestedKind.INSPECTION,
		[
			StoryState.RuntimeState.WAIT_COURT,
			StoryState.RuntimeState.WAIT_INVESTIGATION,
		],
		game_state.story.runtime_state,
	)


## Nested branches push their own call frame, so an enclosing branch keeps its
## continuation and `@return` inside the nested scene lands back where it started.
func _call_nested_branch(
	scene_id: StringName,
	kind: NestedKind,
	expected_states: Array,
	return_state: StoryState.RuntimeState,
) -> bool:
	if _nested_kind != NestedKind.NONE:
		_fail_runtime("A nested story branch is already active.")
		return false
	if game_state.story.runtime_state not in expected_states:
		_fail_runtime("A %s branch requires %s." % [
			NestedKind.keys()[kind],
			StoryState.RuntimeState.keys()[expected_states[0]],
		])
		return false
	if program == null or program.get_scene(scene_id) == null:
		_fail_runtime("Unknown story branch scene: %s" % scene_id)
		return false
	_nested_kind = kind
	_nested_return_state = return_state
	_nested_continuation_scene = game_state.story.current_scene
	_nested_continuation_instruction = game_state.story.current_instruction
	_nested_frame_depth = game_state.story.call_stack.size()
	game_state.story.call_stack.append(StoryStackFrame.new(
		_nested_continuation_scene,
		_nested_continuation_instruction,
	))
	_set_story_position(scene_id, 0)
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	_log("NESTED_%s %s" % [NestedKind.keys()[kind], scene_id])
	run_until_blocked()
	return game_state.story.runtime_state != StoryState.RuntimeState.ERROR


func resume_from_investigation() -> bool:
	if game_state.story.runtime_state != StoryState.RuntimeState.WAIT_INVESTIGATION:
		_fail_runtime("resume_from_investigation() requires WAIT_INVESTIGATION.")
		return false
	if _branch_kind != BranchKind.NONE:
		_fail_runtime("Cannot resume main story while a story branch is active.")
		return false
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	_log("RESUME_INVESTIGATION")
	run_until_blocked()
	return game_state.story.runtime_state != StoryState.RuntimeState.ERROR


func pause() -> void:
	if game_state.story.runtime_state == StoryState.RuntimeState.RUNNING:
		game_state.story.runtime_state = StoryState.RuntimeState.PAUSED
		_log("PAUSED")


func resume() -> void:
	if game_state.story.runtime_state != StoryState.RuntimeState.PAUSED:
		_fail_runtime("resume() requires PAUSED.")
		return
	if game_state.story.current_scene.is_empty():
		_fail_runtime("resume() requires an active scene.")
		return
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	_log("RESUMED")
	run_until_blocked()


## Restores a saved story position. Canonical scene/instruction/call stack data
## must already be present in game_state.story.
##
## WAIT_DIALOGUE is reconstructed by re-executing the SAY instruction that
## blocked the VM, so the visible line is reproduced without repeating or
## skipping story text. WAIT_COURT is restored as-is because the main story must
## not run while a testimony is active.
func restore_position(
	target_state: StoryState.RuntimeState,
	reexecute_blocking_instruction: bool,
) -> bool:
	_clear_pending_dialogue()
	_pending_court_id = &""
	_pending_investigation_id = &""
	_pending_procedure_id = &""
	_clear_story_branch()
	_clear_nested_branch()
	if target_state == StoryState.RuntimeState.WAIT_COURT:
		game_state.story.runtime_state = StoryState.RuntimeState.WAIT_COURT
		_log("RESTORE WAIT_COURT")
		return true
	if target_state == StoryState.RuntimeState.WAIT_INVESTIGATION:
		game_state.story.runtime_state = StoryState.RuntimeState.WAIT_INVESTIGATION
		_log("RESTORE WAIT_INVESTIGATION")
		return true
	if target_state == StoryState.RuntimeState.WAIT_PROCEDURE:
		game_state.story.runtime_state = StoryState.RuntimeState.WAIT_PROCEDURE
		_log("RESTORE WAIT_PROCEDURE")
		return true
	if not reexecute_blocking_instruction:
		game_state.story.runtime_state = target_state
		return true
	if game_state.story.current_instruction <= 0:
		_fail_runtime("Cannot reconstruct dialogue at instruction 0.")
		return false
	game_state.story.current_instruction -= 1
	game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	_log("RESTORE %s" % StoryState.RuntimeState.keys()[target_state])
	run_until_blocked()
	if game_state.story.runtime_state != target_state:
		_fail_runtime(
			"Restored position did not block in %s."
			% StoryState.RuntimeState.keys()[target_state]
		)
		return false
	return true


func _apply_command_result(result: CommandResult, instruction: StoryInstruction) -> void:
	match result.type:
		CommandResult.Type.CONTINUE:
			game_state.story.current_instruction += 1
		CommandResult.Type.BLOCK:
			game_state.story.current_instruction += 1
			game_state.story.runtime_state = StoryState.RuntimeState.WAIT_DIALOGUE
			if _pending_dialogue_source == null:
				_fail_runtime("Dialogue command did not provide a dialogue request.", instruction)
				return
			_log("WAIT_DIALOGUE")
			dialogue_requested.emit(
				_pending_dialogue_speaker,
				_pending_dialogue_expression,
				_pending_dialogue_text,
				_pending_dialogue_source,
			)
			_clear_pending_dialogue()
		CommandResult.Type.GOTO:
			_enter_scene(result.target_scene, instruction)
		CommandResult.Type.CALL:
			if program.get_scene(result.target_scene) == null:
				_fail_runtime("CALL target does not exist: %s" % result.target_scene, instruction)
				return
			game_state.story.call_stack.append(StoryStackFrame.new(
				game_state.story.current_scene,
				game_state.story.current_instruction + 1,
			))
			_log("CALL %s" % result.target_scene)
			_set_story_position(result.target_scene, 0)
		CommandResult.Type.RETURN:
			if _nested_kind != NestedKind.NONE and game_state.story.call_stack.size() == _nested_frame_depth + 1:
				_finish_nested_branch()
				return
			if (
				_branch_kind != BranchKind.NONE
				and game_state.story.call_stack.size() == _branch_stack_depth
			):
				_finish_story_branch()
				return
			if game_state.story.call_stack.is_empty():
				_fail_runtime("RETURN requires a non-empty call stack.", instruction)
				return
			var frame: StoryStackFrame = game_state.story.call_stack.pop_back() as StoryStackFrame
			_set_story_position(frame.scene_id, frame.instruction_index)
			_log("RETURN %s:%d" % [frame.scene_id, frame.instruction_index])
		CommandResult.Type.ENTER_COURT:
			game_state.story.current_instruction += 1
			game_state.story.runtime_state = StoryState.RuntimeState.WAIT_COURT
			if _pending_court_id.is_empty():
				_fail_runtime("Court command did not provide a testimony ID.", instruction)
				return
			if program.get_testimony(_pending_court_id) == null:
				_fail_runtime("Court testimony does not exist: %s" % _pending_court_id, instruction)
				return
			_log("ENTER_COURT %s" % _pending_court_id)
			court_requested.emit(_pending_court_id)
			_pending_court_id = &""
		CommandResult.Type.ENTER_INVESTIGATION:
			game_state.story.current_instruction += 1
			game_state.story.runtime_state = StoryState.RuntimeState.WAIT_INVESTIGATION
			if _pending_investigation_id.is_empty():
				_fail_runtime("Investigation command did not provide a location ID.", instruction)
				return
			if program.get_location(_pending_investigation_id) == null:
				_fail_runtime(
					"Investigation location does not exist: %s" % _pending_investigation_id,
					instruction,
				)
				return
			_log("ENTER_INVESTIGATION %s" % _pending_investigation_id)
			investigation_requested.emit(_pending_investigation_id)
			_pending_investigation_id = &""
		CommandResult.Type.END_INVESTIGATION:
			if _branch_kind != BranchKind.INVESTIGATION:
				_fail_runtime(
					"@investigation_end requires an active investigation branch.",
					instruction,
				)
				return
			if (
				_investigation_completion_guard.is_valid()
				and not bool(_investigation_completion_guard.call())
			):
				# Return to the investigation without ending it. This lets the
				# player collect the missing clues and retry the authored hotspot.
				_finish_story_branch()
				_log("INVESTIGATION_END_BLOCKED")
				return
			# The main story continues where @investigation left it, exactly once.
			_finish_story_branch()
			game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
			_log("END_INVESTIGATION")
			investigation_finished.emit()
		CommandResult.Type.ENTER_PROCEDURE:
			game_state.story.current_instruction += 1
			game_state.story.runtime_state = StoryState.RuntimeState.WAIT_PROCEDURE
			if _pending_procedure_id.is_empty():
				_fail_runtime("Procedure command did not provide a context ID.", instruction)
				return
			_log("ENTER_PROCEDURE %s" % _pending_procedure_id)
			procedure_requested.emit(_pending_procedure_id)
			_pending_procedure_id = &""
		CommandResult.Type.END_PROCEDURE:
			if _nested_kind != NestedKind.PROCEDURE:
				_fail_runtime(
					"@procedure_end requires an active procedure branch.",
					instruction,
				)
				return
			if game_state.story.call_stack.size() != _nested_frame_depth + 1:
				_fail_runtime(
					"@procedure_end must run at the procedure branch level.",
					instruction,
				)
				return
			# The main story continues where @procedure left it, exactly once.
			_restore_nested_continuation()
			game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
			_log("END_PROCEDURE")
			procedure_finished.emit()
		CommandResult.Type.FINISH:
			game_state.story.runtime_state = StoryState.RuntimeState.FINISHED
		CommandResult.Type.ERROR:
			_fail_runtime(result.error_message, instruction)
		_:
			_fail_runtime("Unknown CommandResult type: %d" % result.type, instruction)


func _enter_scene(scene_id: StringName, instruction: StoryInstruction) -> void:
	if program.get_scene(scene_id) == null:
		_fail_runtime("GOTO target does not exist: %s" % scene_id, instruction)
		return
	_set_story_position(scene_id, 0)


func _set_story_position(scene_id: StringName, instruction_index: int) -> void:
	var changed: bool = game_state.story.current_scene != scene_id
	game_state.story.current_scene = scene_id
	game_state.story.current_instruction = instruction_index
	if changed:
		scene_changed.emit(scene_id)


func _current_instruction() -> StoryInstruction:
	if program == null:
		return null
	var scene: StoryScene = program.get_scene(game_state.story.current_scene)
	if scene == null:
		return null
	var index: int = game_state.story.current_instruction
	if index < 0 or index >= scene.instructions.size():
		return null
	return scene.instructions[index]


func _fail_runtime(message: String, instruction: StoryInstruction = null) -> void:
	var location: String = ""
	if instruction != null and instruction.source != null:
		location = "%s:%d " % [instruction.source.file, instruction.source.line]
	last_error = "%s%s" % [location, message]
	game_state.story.runtime_state = StoryState.RuntimeState.ERROR
	if debug_logging:
		push_error("[StoryVM] %s" % last_error)
	runtime_error.emit(last_error)


func _capture_dialogue_request(
	speaker_id: StringName,
	expression_id: StringName,
	text: String,
	source: SourceLocation,
) -> void:
	_pending_dialogue_speaker = speaker_id
	_pending_dialogue_expression = expression_id
	_pending_dialogue_text = text
	_pending_dialogue_source = source


func _clear_pending_dialogue() -> void:
	_pending_dialogue_speaker = &""
	_pending_dialogue_expression = &""
	_pending_dialogue_text = ""
	_pending_dialogue_source = null


## Restores the caller position and releases the branch. The caller decides which
## runtime state follows (a RETURN resumes its subsystem; @investigation_end
## resumes the main story).
func _finish_story_branch() -> void:
	_set_story_position(_branch_continuation_scene, _branch_continuation_instruction)
	var finished_kind: BranchKind = _branch_kind
	_clear_story_branch()
	if finished_kind == BranchKind.COURT:
		game_state.story.runtime_state = StoryState.RuntimeState.WAIT_COURT
		_log("RETURN_COURT")
		court_branch_finished.emit()
	else:
		game_state.story.runtime_state = StoryState.RuntimeState.WAIT_INVESTIGATION
		_log("RETURN_INVESTIGATION")
		investigation_branch_finished.emit()


func _clear_story_branch() -> void:
	_branch_kind = BranchKind.NONE
	_branch_continuation_scene = &""
	_branch_continuation_instruction = 0
	_branch_stack_depth = 0


## Pops the nested branch frame and puts the story back where the nested branch
## was requested. The caller decides which runtime state follows.
func _restore_nested_continuation() -> void:
	var frame: StoryStackFrame = game_state.story.call_stack.pop_back() as StoryStackFrame
	if frame != null:
		_set_story_position(frame.scene_id, frame.instruction_index)
	_clear_nested_branch()


func _finish_nested_branch() -> void:
	var kind: NestedKind = _nested_kind
	var return_state: StoryState.RuntimeState = _nested_return_state
	_restore_nested_continuation()
	game_state.story.runtime_state = return_state
	if kind == NestedKind.PROCEDURE:
		_log("RETURN_PROCEDURE")
		procedure_branch_finished.emit()
	else:
		_log("RETURN_INSPECTION")
		inspection_branch_finished.emit()


func _clear_nested_branch() -> void:
	_nested_kind = NestedKind.NONE
	_nested_return_state = StoryState.RuntimeState.RUNNING
	_nested_continuation_scene = &""
	_nested_continuation_instruction = 0
	_nested_frame_depth = 0


func _capture_procedure_request(context_id: StringName) -> void:
	_pending_procedure_id = context_id


func _capture_court_request(testimony_id: StringName) -> void:
	_pending_court_id = testimony_id


func _capture_investigation_request(location_id: StringName) -> void:
	_pending_investigation_id = location_id


func _forward_talk_unlock_request(topic_id: StringName) -> void:
	talk_unlock_requested.emit(topic_id)


func _forward_background_request(background_id: StringName) -> void:
	background_requested.emit(background_id)


func _forward_bgm_request(bgm_id: StringName) -> void:
	bgm_requested.emit(bgm_id)


func _forward_sfx_request(sfx_id: StringName) -> void:
	sfx_requested.emit(sfx_id)


func _forward_character_request(
	character_id: StringName,
	slot: StringName,
	expression_id: StringName,
) -> void:
	character_requested.emit(character_id, slot, expression_id)


func _forward_character_hidden(character_id: StringName) -> void:
	character_hidden.emit(character_id)


func _log_instruction(instruction: StoryInstruction) -> void:
	if not debug_logging:
		return
	print(
		"[StoryVM] %s:%d %s"
		% [instruction.source.file, instruction.source.line, _op_name(instruction.op)]
	)


func _log(message: String) -> void:
	if debug_logging:
		print("[StoryVM] %s" % message)


func _op_name(op: StoryInstruction.Op) -> String:
	return StoryInstruction.Op.keys()[op]
