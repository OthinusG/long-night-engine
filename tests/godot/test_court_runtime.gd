extends SceneTree

const STORY_PATH: String = "res://story_build/story.json"
const EVIDENCE_PATH: String = "res://data/evidence.json"

var _failures: int = 0
var _events: Dictionary[StringName, int]


func _initialize() -> void:
	_test_session_and_navigation()
	_test_press_and_reentrancy()
	_test_present_and_penalty()
	_test_invalid_evidence()
	_test_invalid_transitions()

	if _failures > 0:
		push_error("CourtRuntime tests failed: %d" % _failures)
		quit(1)
		return
	print("CourtRuntime tests passed")
	quit()


func _test_session_and_navigation() -> void:
	_reset_events()
	var runtime := _runtime()
	_connect_events(runtime)
	var testimony := _testimony()
	_expect(runtime.start_testimony(testimony), "Testimony starts")
	_expect(runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW, "Testimony starts in preview")
	while runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		runtime.advance_preview()
	_expect(runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_ACTIVE, "Court becomes active after preview")
	_expect(runtime.state.active_testimony.testimony_id == &"testimony_demo_01", "Session keeps testimony ID")
	_expect(runtime.get_current_statement().id == &"demo_s01", "First statement is current")
	_expect(runtime.state.penalty == 100, "Penalty initializes to 100")
	_expect(not runtime.state.active_testimony.completed, "Session starts incomplete")
	_expect(runtime.next_statement().id == &"demo_s02", "Next selects s02")
	_expect(runtime.previous_statement().id == &"demo_s01", "Previous selects s01")
	runtime.previous_statement()
	_expect(runtime.get_current_statement().id == &"demo_s01", "Left boundary clamps")
	for index: int in 5:
		runtime.next_statement()
	_expect(runtime.get_current_statement().id == &"demo_s04", "Right boundary clamps")
	_expect(runtime.state.active_testimony.visited_statements == [
		&"demo_s01",
		&"demo_s02",
		&"demo_s03",
		&"demo_s04",
	], "Visited statements are stable and unique")
	_expect(_event_count(&"testimony_started") == 1, "testimony_started emits once")
	_expect(_event_count(&"statement_changed") >= 1, "statement_changed emits")


func _test_press_and_reentrancy() -> void:
	_reset_events()
	var runtime := _runtime()
	_connect_events(runtime)
	_start_active(runtime)
	runtime.next_statement()
	var statement_id: StringName = runtime.get_current_statement().id
	var target: StringName = runtime.press_current_statement()
	_expect(target == &"scene_press_s02", "Press resolves authored target")
	_expect(runtime.runtime_state == CourtRuntime.RuntimeState.WAIT_STORY_BRANCH, "Press suspends court")
	_expect(runtime.state.active_testimony.suspended, "Session records suspension")
	_expect(runtime.state.active_testimony.pressed_statements == [&"demo_s02"], "Press is recorded")
	_expect(runtime.next_statement() == null, "Navigation is rejected during branch")
	_expect(runtime.previous_statement() == null, "Previous is rejected during branch")
	_expect(runtime.press_current_statement().is_empty(), "Second press is rejected during branch")
	var invalid := runtime.present_evidence(statement_id, &"attorney_badge")
	_expect(invalid.type == PresentResultType.Value.INVALID, "Present is rejected during branch")
	_expect(runtime.resume_after_story_branch(), "Press branch resumes")
	_expect(runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_ACTIVE, "Court becomes active again")
	_expect(runtime.get_current_statement().id == statement_id, "Press resumes same statement")
	_expect(runtime.state.penalty == 100, "Press does not change penalty")
	_expect(_event_count(&"statement_pressed") == 1, "statement_pressed emits once")
	_expect(_event_count(&"testimony_resumed") == 1, "testimony_resumed emits once")


func _test_present_and_penalty() -> void:
	_reset_events()
	var runtime := _runtime()
	_connect_events(runtime)
	_start_active(runtime)
	runtime.next_statement()
	runtime.next_statement()
	var statement_id: StringName = runtime.get_current_statement().id

	for expected_penalty: int in [80, 60, 40]:
		var wrong := runtime.present_evidence(statement_id, &"attorney_badge")
		_expect(wrong.type == PresentResultType.Value.WRONG, "Owned incorrect evidence returns WRONG")
		_expect(wrong.penalty == 20, "Wrong result reports deduction")
		_expect(runtime.state.penalty == expected_penalty, "Repeated wrong penalty is deterministic")
		_expect(runtime.get_current_statement().id == statement_id, "Wrong present keeps statement")
		runtime.resume_after_story_branch()
	_expect(_event_count(&"present_wrong") == 3, "present_wrong emits for each wrong answer")
	_expect(_event_count(&"penalty_changed") == 3, "penalty_changed emits for each deduction")

	var correct := runtime.present_evidence(statement_id, &"crime_report")
	_expect(correct.type == PresentResultType.Value.CORRECT, "Rule match returns CORRECT")
	_expect(correct.target_scene == &"scene_break_testimony", "Correct result returns authored target")
	_expect(runtime.state.penalty == 40, "Correct evidence does not deduct penalty")
	_expect(runtime.runtime_state == CourtRuntime.RuntimeState.WAIT_STORY_BRANCH, "Correct waits for story branch")
	_expect(_event_count(&"present_correct") == 1, "present_correct emits once")
	_expect(runtime.resume_after_story_branch(), "Correct branch completes testimony")
	_expect(runtime.runtime_state == CourtRuntime.RuntimeState.INACTIVE, "Completion returns court to inactive")
	_expect(runtime.state.active_testimony == null, "Completion clears active session")
	_expect(_event_count(&"testimony_completed") == 1, "testimony_completed emits once")

	var depleted := _runtime()
	_start_active(depleted)
	depleted.next_statement()
	depleted.next_statement()
	depleted.state.penalty = 10
	var final_wrong := depleted.present_evidence(&"demo_s03", &"attorney_badge")
	_expect(final_wrong.type == PresentResultType.Value.WRONG, "Depleting answer is still WRONG")
	_expect(depleted.state.penalty == 0, "Penalty clamps at zero")
	_expect(depleted.runtime_state == CourtRuntime.RuntimeState.FAILED, "Zero penalty enters FAILED")
	_expect(depleted.state.active_testimony.suspended, "Failed testimony is not interactive")


func _test_invalid_evidence() -> void:
	var runtime := _runtime(false)
	_start_active(runtime)
	runtime.next_statement()
	runtime.next_statement()
	var unowned := runtime.present_evidence(&"demo_s03", &"attorney_badge")
	_expect(unowned.type == PresentResultType.Value.INVALID, "Unowned evidence is invalid")
	_expect(runtime.state.penalty == 100, "Unowned evidence does not deduct penalty")

	runtime.game_state.evidence[&"temporary_note"] = EvidenceState.new(&"temporary_note", true)
	var not_presentable := runtime.present_evidence(&"zhao_demo_s03", &"temporary_note")
	_expect(not_presentable.type == PresentResultType.Value.INVALID, "Non-presentable evidence is invalid")
	_expect(runtime.state.penalty == 100, "Non-presentable evidence does not deduct penalty")

	var unknown := runtime.present_evidence(&"zhao_demo_s03", &"missing")
	_expect(unknown.type == PresentResultType.Value.INVALID, "Unknown evidence is invalid")


func _test_invalid_transitions() -> void:
	var runtime := _runtime()
	var inactive := runtime.present_evidence(&"demo_s01", &"attorney_badge")
	_expect(inactive.type == PresentResultType.Value.INVALID, "Inactive present is rejected")
	_expect(not runtime.start_testimony(null), "Null testimony is rejected")
	_expect(runtime.runtime_state == CourtRuntime.RuntimeState.ERROR, "Malformed definition enters ERROR")

	var active := _runtime()
	var testimony := _testimony()
	active.start_testimony(testimony)
	while active.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		active.advance_preview()
	_expect(not active.start_testimony(testimony), "Double start is rejected")
	_expect(active.get_current_statement().id == &"demo_s01", "Double start does not overwrite session")
	_expect(active.complete_testimony(), "Active testimony can complete explicitly")
	_expect(not active.complete_testimony(), "Double completion is rejected")


func _runtime(own_wrong_evidence: bool = true) -> CourtRuntime:
	var game_state := GameState.new()
	game_state.evidence[&"crime_report"] = EvidenceState.new(&"crime_report", true, &"", true)
	game_state.evidence[&"attorney_badge"] = EvidenceState.new(&"attorney_badge", own_wrong_evidence, &"", true)
	var repository := EvidenceRepository.new()
	_expect(repository.load_file(EVIDENCE_PATH), repository.error_message)
	return CourtRuntime.new(game_state, repository)


func _testimony() -> TestimonyDef:
	var loader := StoryProgramLoader.new()
	var program: StoryProgram = loader.load_file(STORY_PATH)
	_expect(program != null, loader.error_message)
	return program.get_testimony(&"testimony_demo_01")


func _connect_events(runtime: CourtRuntime) -> void:
	runtime.testimony_started.connect(func(_id: StringName) -> void: _record(&"testimony_started"))
	runtime.statement_changed.connect(func(_id: StringName) -> void: _record(&"statement_changed"))
	runtime.statement_pressed.connect(func(_id: StringName, _target: StringName) -> void: _record(&"statement_pressed"))
	runtime.present_correct.connect(func(_statement: StringName, _evidence: StringName) -> void: _record(&"present_correct"))
	runtime.present_wrong.connect(func(_statement: StringName, _evidence: StringName) -> void: _record(&"present_wrong"))
	runtime.penalty_changed.connect(func(_previous: int, _current: int) -> void: _record(&"penalty_changed"))
	runtime.testimony_completed.connect(func(_id: StringName) -> void: _record(&"testimony_completed"))
	runtime.testimony_resumed.connect(func(_id: StringName, _statement: StringName) -> void: _record(&"testimony_resumed"))


func _reset_events() -> void:
	_events.clear()


func _record(event_name: StringName) -> void:
	_events[event_name] = _event_count(event_name) + 1


func _event_count(event_name: StringName) -> int:
	return _events.get(event_name, 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _start_active(runtime: CourtRuntime) -> void:
	runtime.start_testimony(_testimony())
	while runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		runtime.advance_preview()
