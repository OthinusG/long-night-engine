extends SceneTree

## Procedure runtime tests: authored context, action availability,
## correctness resolution, wrong/correct flow, and state transitions.

const STORY_PATH: String = "res://story_build/story.json"
const EVIDENCE_PATH: String = "res://data/evidence.json"
const PROCEDURE_PATH: String = "res://data/procedure.json"
const CONTEXT_ID: StringName = &"court_procedural_crisis"

var _failures: int = 0
var _program: StoryProgram
var _evidence_repository: EvidenceRepository
var _procedure_repository: ProcedureRepository
var _dialogues: Array[String]


class Harness:
	extends RefCounted

	var game_state: GameState
	var story_vm: StoryVM
	var court_runtime: CourtRuntime
	var procedure_runtime: ProcedureRuntime
	var coordinator: GameCoordinator


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _load_data():
		quit(1)
		return
	_test_context_and_availability()
	_test_wrong_action()
	_test_correct_action()
	_test_invalid_actions()
	_finish()


func _load_data() -> bool:
	var loader := StoryProgramLoader.new()
	_program = loader.load_file(STORY_PATH)
	if _program == null:
		push_error(loader.error_message)
		return false
	_evidence_repository = EvidenceRepository.new()
	if not _evidence_repository.load_file(EVIDENCE_PATH):
		push_error(_evidence_repository.error_message)
		return false
	_procedure_repository = ProcedureRepository.new()
	if not _procedure_repository.load_file(PROCEDURE_PATH):
		push_error(_procedure_repository.error_message)
		return false
	return true


func _new_harness() -> Harness:
	var harness := Harness.new()
	harness.game_state = GameState.new()
	harness.story_vm = StoryVM.new(harness.game_state)
	harness.court_runtime = CourtRuntime.new(harness.game_state, _evidence_repository)
	harness.procedure_runtime = ProcedureRuntime.new(harness.game_state, _procedure_repository)
	harness.coordinator = GameCoordinator.new(
		harness.story_vm,
		harness.court_runtime,
		null,
		harness.procedure_runtime,
	)
	harness.story_vm.load_program(_program)
	_dialogues = []
	harness.story_vm.dialogue_requested.connect(_record_dialogue)
	return harness


func _procedure_harness() -> Harness:
	var harness := _new_harness()
	harness.game_state.story.runtime_state = StoryState.RuntimeState.WAIT_PROCEDURE
	harness.procedure_runtime.start_context(CONTEXT_ID)
	return harness


func _test_context_and_availability() -> void:
	var harness := _procedure_harness()
	_expect(harness.procedure_runtime.state.active, "Procedure context activates")
	_expect(
		harness.procedure_runtime.state.context_id == CONTEXT_ID,
		"Authored context ID is recorded"
	)
	var context: ProcedureContext = harness.procedure_runtime.current_context()
	_expect(context != null and context.actions.size() == 2, "Context loads its authored actions")
	_expect(
		harness.procedure_runtime.available_actions().size() == 2,
		"All available actions are offered"
	)


func _test_wrong_action() -> void:
	var harness := _procedure_harness()
	var result: ProcedureResult = harness.procedure_runtime.select_action(&"action_accept_decision")
	_expect(result != null, "Action resolves")
	_expect(
		result.type == ProcedureResult.Type.WRONG,
		"Wrong action resolves as wrong"
	)
	_expect(
		result.target_scene == &"scene_procedure_fail",
		"Carries authored failure branch scene"
	)
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"Action runs its branch scene"
	)
	harness.story_vm.resume_dialogue()
	_expect(
		harness.procedure_runtime.state.visited_actions == [&"action_accept_decision"],
		"Visited action is recorded"
	)
	_expect(not harness.procedure_runtime.state.resolved, "Wrong action does not resolve context")


func _test_correct_action() -> void:
	var harness := _procedure_harness()
	var result: ProcedureResult = harness.procedure_runtime.select_action(&"action_demand_inquiry")
	_expect(result != null and result.type == ProcedureResult.Type.CORRECT, "Correct action resolves as correct")
	_expect(result.target_scene == &"scene_procedure_continue", "Carries authored success branch scene")
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"Action runs its branch scene"
	)
	harness.story_vm.resume_dialogue()
	_expect(not harness.procedure_runtime.state.active, "@procedure_end deactivates procedure")
	_expect(
		harness.procedure_runtime.state.resolved
		and harness.procedure_runtime.state.resolved_action_id == &"action_demand_inquiry",
		"Correct action records resolution"
	)


func _test_invalid_actions() -> void:
	var harness := _procedure_harness()
	_expect(
		harness.procedure_runtime.select_action(&"no_such_action") == null,
		"Unknown action is rejected"
	)
	_expect(
		not harness.procedure_runtime.last_error.is_empty(),
		"Rejected action explains itself"
	)


func _record_dialogue(
	_speaker_id: StringName,
	_expression_id: StringName,
	text: String,
	_source: SourceLocation,
) -> void:
	_dialogues.append(text)


func _finish() -> void:
	if _failures > 0:
		push_error("Procedure tests failed: %d" % _failures)
		quit(1)
		return
	print("Procedure tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
