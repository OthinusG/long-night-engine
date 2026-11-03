class_name GameCoordinator
extends RefCounted

## Bridges StoryVM and the gameplay runtimes through explicit signals. It owns no
## gameplay rules of its own.

var story_vm: StoryVM
var court_runtime: CourtRuntime
var investigation_runtime: InvestigationRuntime
var procedure_runtime: ProcedureRuntime
var inspection_runtime: EvidenceInspectionRuntime


func _init(
	vm: StoryVM,
	court: CourtRuntime,
	investigation: InvestigationRuntime = null,
	procedure: ProcedureRuntime = null,
	inspection: EvidenceInspectionRuntime = null,
) -> void:
	assert(vm != null, "StoryVM is required")
	assert(court != null, "CourtRuntime is required")
	assert(vm.game_state == court.game_state, "StoryVM and CourtRuntime must share GameState")
	story_vm = vm
	court_runtime = court
	story_vm.court_requested.connect(_on_court_requested)
	story_vm.court_branch_finished.connect(_on_court_branch_finished)
	court_runtime.story_branch_requested.connect(_on_court_story_branch_requested)
	court_runtime.testimony_completed.connect(_on_testimony_completed)

	investigation_runtime = investigation
	if investigation_runtime != null:
		assert(
			vm.game_state == investigation_runtime.game_state,
			"StoryVM and InvestigationRuntime must share GameState",
		)
		story_vm.investigation_requested.connect(_on_investigation_requested)
		story_vm.investigation_branch_finished.connect(_on_investigation_branch_finished)
		story_vm.investigation_finished.connect(_on_investigation_finished)
		story_vm.talk_unlock_requested.connect(_on_talk_unlock_requested)
		investigation_runtime.story_branch_requested.connect(
			_on_investigation_story_branch_requested
		)
		story_vm.set_investigation_completion_guard(
			investigation_runtime.can_complete_pending_branch
		)

	procedure_runtime = procedure
	if procedure_runtime != null:
		assert(
			vm.game_state == procedure_runtime.game_state,
			"StoryVM and ProcedureRuntime must share GameState",
		)
		story_vm.procedure_requested.connect(_on_procedure_requested)
		story_vm.procedure_branch_finished.connect(_on_procedure_branch_finished)
		story_vm.procedure_finished.connect(_on_procedure_finished)
		procedure_runtime.story_branch_requested.connect(_on_procedure_story_branch_requested)

	inspection_runtime = inspection
	if inspection_runtime != null:
		assert(
			vm.game_state == inspection_runtime.game_state,
			"StoryVM and EvidenceInspectionRuntime must share GameState",
		)
		story_vm.inspection_branch_finished.connect(_on_inspection_branch_finished)
		inspection_runtime.story_branch_requested.connect(
			_on_inspection_story_branch_requested
		)


func _on_court_requested(testimony_id: StringName) -> void:
	var definition: TestimonyDef = story_vm.program.get_testimony(testimony_id)
	if court_runtime.start_testimony(definition):
		return
	# StoryVM has already blocked at WAIT_COURT; never leave that state looking
	# valid when the court runtime rejected the hand-off.
	story_vm.runtime_error.emit(
		"Cannot start testimony '%s': %s" % [testimony_id, court_runtime.last_error]
	)


func _on_court_story_branch_requested(target_scene: StringName) -> void:
	story_vm.call_court_branch(target_scene)


func _on_court_branch_finished() -> void:
	court_runtime.resume_after_story_branch()


func _on_testimony_completed(_testimony_id: StringName) -> void:
	story_vm.resume_from_court()


func _on_investigation_requested(location_id: StringName) -> void:
	investigation_runtime.start_investigation(location_id)


func _on_investigation_story_branch_requested(target_scene: StringName) -> void:
	story_vm.call_investigation_branch(target_scene)


func _on_investigation_branch_finished() -> void:
	investigation_runtime.resume_after_story_branch()


func _on_investigation_finished() -> void:
	investigation_runtime.end_investigation()


func _on_talk_unlock_requested(topic_id: StringName) -> void:
	investigation_runtime.unlock_topic(topic_id)


func _on_procedure_requested(context_id: StringName) -> void:
	procedure_runtime.start_context(context_id)


func _on_procedure_story_branch_requested(target_scene: StringName) -> void:
	story_vm.call_procedure_branch(target_scene)


func _on_procedure_branch_finished() -> void:
	procedure_runtime.resume_after_story_branch()


func _on_procedure_finished() -> void:
	procedure_runtime.end_procedure()


func _on_inspection_story_branch_requested(target_scene: StringName) -> void:
	story_vm.call_inspection_branch(target_scene)


func _on_inspection_branch_finished() -> void:
	inspection_runtime.resume_after_story_branch()
