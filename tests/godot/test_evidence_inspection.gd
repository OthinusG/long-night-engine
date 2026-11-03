extends SceneTree

## Evidence inspection tests: definitions, normalized hotspots, branch
## flow, versioned descriptions, and debugger inspection controls.

const STORY_PATH: String = "res://story_build/story.json"
const EVIDENCE_PATH: String = "res://data/evidence.json"
const INSPECTION_PATH: String = "res://data/evidence_inspections.json"
const PROCEDURE_PATH: String = "res://data/procedure.json"

var _failures: int = 0
var _program: StoryProgram
var _evidence_repository: EvidenceRepository
var _inspection_repository: EvidenceInspectionRepository


class Harness:
	extends RefCounted

	var game_state: GameState
	var story_vm: StoryVM
	var court_runtime: CourtRuntime
	var investigation_runtime: InvestigationRuntime
	var inspection_runtime: EvidenceInspectionRuntime
	var coordinator: GameCoordinator
	var debugger: StoryDebugger


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _load_data():
		quit(1)
		return
	_test_definitions()
	_test_branch_flow()
	_test_versioned_evidence()
	_test_debugger_visibility()
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
	_inspection_repository = EvidenceInspectionRepository.new()
	if not _inspection_repository.load_file(INSPECTION_PATH):
		push_error(_inspection_repository.error_message)
		return false
	return true


func _new_harness() -> Harness:
	var harness := Harness.new()
	harness.game_state = GameState.new()
	harness.story_vm = StoryVM.new(harness.game_state)
	harness.court_runtime = CourtRuntime.new(harness.game_state, _evidence_repository)
	harness.investigation_runtime = InvestigationRuntime.new(
		harness.game_state,
		_program,
		_evidence_repository,
	)
	harness.inspection_runtime = EvidenceInspectionRuntime.new(
		harness.game_state,
		_inspection_repository,
	)
	var procedure_repository := ProcedureRepository.new()
	procedure_repository.load_file(PROCEDURE_PATH)
	harness.coordinator = GameCoordinator.new(
		harness.story_vm,
		harness.court_runtime,
		harness.investigation_runtime,
		ProcedureRuntime.new(harness.game_state, procedure_repository),
		harness.inspection_runtime,
	)
	harness.debugger = StoryDebugger.new(
		harness.game_state,
		harness.story_vm,
		harness.court_runtime,
		harness.investigation_runtime,
		harness.coordinator.procedure_runtime,
		harness.inspection_runtime,
		_program,
		_evidence_repository,
	)
	harness.story_vm.load_program(_program)
	return harness


func _investigating_harness() -> Harness:
	var harness := _new_harness()
	harness.story_vm.start(&"scene_investigation_start")
	harness.story_vm.resume_dialogue()
	return harness


func _own(harness: Harness, evidence_id: StringName, version: StringName = &"") -> void:
	harness.game_state.evidence[evidence_id] = EvidenceState.new(evidence_id, true, version, true)


func _test_definitions() -> void:
	_expect(
		_inspection_repository.has_inspection(&"pocket_watch"),
		"Authored inspection definition loads"
	)
	_expect(
		not _inspection_repository.has_inspection(&"attorney_badge"),
		"Evidence without authored inspection is not inspectable"
	)
	var definition: EvidenceInspectionDef = _inspection_repository.get_inspection(&"pocket_watch")
	_expect(definition.image == &"pocket_watch_detail", "Detail image matches authored data")
	_expect(definition.hotspots.size() == 1, "Authored hotspot loads")
	_expect(
		definition.hotspot_at(Vector2(0.45, 0.45)).id == &"watch_glass",
		"Normalized point resolves to authored hotspot"
	)
	_expect(
		definition.hotspot_at(Vector2(0.9, 0.9)) == null,
		"Points outside hotspot miss"
	)

	var harness := _investigating_harness()
	_own(harness, &"pocket_watch")
	_expect(harness.inspection_runtime.can_inspect(&"pocket_watch"), "Owned inspectable evidence opens")
	_expect(
		not harness.inspection_runtime.open(&"attorney_badge"),
		"Non-inspectable evidence is rejected"
	)
	_expect(harness.inspection_runtime.open(&"pocket_watch"), "Inspection opens")
	_expect(
		harness.inspection_runtime.current_definition().evidence_id == &"pocket_watch",
		"Open inspection tracks evidence"
	)


func _test_branch_flow() -> void:
	var harness := _investigating_harness()
	_own(harness, &"pocket_watch")
	harness.inspection_runtime.open(&"pocket_watch")
	_expect(
		harness.inspection_runtime.available_hotspots().size() == 1,
		"Hotspot is offered"
	)
	_expect(
		harness.inspection_runtime.inspect(&"watch_glass") == &"scene_inspect_watch_glass",
		"Hotspot resolves to authored branch scene"
	)
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"Inspection branch runs dialogue"
	)
	harness.story_vm.resume_dialogue()
	_expect(
		harness.inspection_runtime.is_hotspot_inspected(&"watch_glass"),
		"Hotspot is marked inspected when branch returns"
	)
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_INVESTIGATION,
		"Return restores hosting state"
	)
	_expect(
		harness.inspection_runtime.is_open(),
		"Inspection stays open across branches"
	)
	_expect(
		harness.inspection_runtime.is_complete(&"pocket_watch"),
		"Inspection is complete when all hotspots are visited"
	)


func _test_versioned_evidence() -> void:
	_expect(
		_evidence_repository.display_name_for(&"crime_report", &"verified") == "案发报告（核验）",
		"Versioned evidence name resolves"
	)
	_expect(
		_evidence_repository.display_name_for(&"crime_report", &"") == "案发报告",
		"Base evidence name resolves"
	)
	_expect(
		_evidence_repository.description_for(&"crime_report", &"verified").contains("核实"),
		"Versioned evidence description resolves"
	)


func _test_debugger_visibility() -> void:
	var harness := _investigating_harness()
	_own(harness, &"pocket_watch")
	var dump: String = harness.debugger.describe_state()
	_expect(dump.contains("EVIDENCE INSPECTION"), "Debugger reports inspection section")
	_expect(dump.contains("pocket_watch"), "Debugger lists inspectable evidence")
	_expect(
		harness.debugger.set_hotspot_inspected(&"pocket_watch", &"watch_glass", true),
		"Debugger marks hotspot inspected"
	)
	_expect(
		harness.inspection_runtime.inspected_hotspots(&"pocket_watch") == [&"watch_glass"],
		"Debug edit lands in typed state"
	)
	_expect(
		harness.debugger.set_hotspot_inspected(&"pocket_watch", &"watch_glass", false),
		"Debugger clears hotspot"
	)
	_expect(
		harness.inspection_runtime.inspected_hotspots(&"pocket_watch").is_empty(),
		"Cleared hotspot is gone"
	)


func _finish() -> void:
	if _failures > 0:
		push_error("Evidence inspection tests failed: %d" % _failures)
		quit(1)
		return
	print("Evidence inspection tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
