extends SceneTree

## Investigation runtime tests: story handoff, examine, talk, topic unlock,
## present (specific + fallback), move, reentrancy, and completion.

const STORY_PATH: String = "res://story_build/story.json"
const EVIDENCE_PATH: String = "res://data/evidence.json"

var _failures: int = 0
var _program: StoryProgram
var _repository: EvidenceRepository
var _dialogues: Array[String]


class Harness:
	extends RefCounted

	var game_state: GameState
	var story_vm: StoryVM
	var court_runtime: CourtRuntime
	var investigation: InvestigationRuntime
	var coordinator: GameCoordinator


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _load_registries():
		quit(1)
		return
	_test_story_handoff()
	_test_examine()
	_test_talk_and_unlock()
	_test_present()
	_test_move_and_invalid_move()
	_test_completion()
	_finish()


func _load_registries() -> bool:
	var loader := StoryProgramLoader.new()
	_program = loader.load_file(STORY_PATH)
	if _program == null:
		push_error(loader.error_message)
		return false
	_repository = EvidenceRepository.new()
	if not _repository.load_file(EVIDENCE_PATH):
		push_error(_repository.error_message)
		return false
	return true


func _investigating_harness() -> Harness:
	var harness := _new_harness()
	harness.story_vm.start(&"scene_investigation_start")
	harness.story_vm.resume_dialogue()
	return harness


func _new_harness() -> Harness:
	var harness := Harness.new()
	harness.game_state = GameState.new()
	harness.story_vm = StoryVM.new(harness.game_state)
	harness.court_runtime = CourtRuntime.new(harness.game_state, _repository)
	harness.investigation = InvestigationRuntime.new(
		harness.game_state,
		_program,
		_repository,
	)
	harness.coordinator = GameCoordinator.new(
		harness.story_vm,
		harness.court_runtime,
		harness.investigation,
	)
	harness.story_vm.load_program(_program)
	_dialogues = []
	harness.story_vm.dialogue_requested.connect(_record_dialogue)
	return harness


func _test_story_handoff() -> void:
	var harness := _new_harness()
	harness.story_vm.start(&"scene_investigation_start")
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"Pre-investigation dialogue waits before investigation"
	)
	_expect(not harness.investigation.state.active, "Investigation is inactive before handoff")
	harness.story_vm.resume_dialogue()
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_INVESTIGATION,
		"@investigation puts StoryVM into WAIT_INVESTIGATION"
	)
	_expect(harness.investigation.state.active, "Investigation runtime becomes active")
	_expect(
		harness.investigation.state.mode == InvestigationState.Mode.DEFAULT,
		"Investigation starts in DEFAULT mode"
	)
	_expect(
		harness.investigation.state.current_location == &"location_office",
		"Investigation starts in authored location"
	)
	_expect(
		harness.game_state.investigation.visited_locations == [&"location_office"],
		"Starting location is marked visited"
	)


func _test_examine() -> void:
	var harness := _investigating_harness()
	_expect(harness.investigation.move(&"location_crime_scene"), "Move to crime scene")
	_expect(
		harness.investigation.examine(&"window") == &"scene_examine_window",
		"Examine returns authored branch scene"
	)
	_expect(
		harness.investigation.state.mode == InvestigationState.Mode.WAIT_STORY_BRANCH,
		"Examine suspends investigation"
	)
	_expect(
		harness.investigation.examine(&"window").is_empty(),
		"Cannot examine while story branch is running"
	)
	_expect(
		not harness.investigation.move(&"location_office"),
		"Cannot move while story branch is running"
	)
	# Complete examine dialogue line in scene_examine_window
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"Examine branch shows dialogue"
	)
	harness.story_vm.resume_dialogue()
	_expect(
		harness.investigation.is_hotspot_examined(&"window"),
		"Hotspot is marked examined"
	)
	_expect(
		harness.investigation.state.mode == InvestigationState.Mode.LOCATION_ACTIVE,
		"Investigation resumes after examine"
	)


func _test_talk_and_unlock() -> void:
	var harness := _investigating_harness()
	_expect(
		not harness.investigation.is_topic_available(&"suspect_alibi"),
		"@locked topic starts unavailable"
	)
	_expect(
		harness.investigation.available_topics().size() == 1,
		"Only unlocked topics are offered"
	)
	_expect(
		harness.investigation.talk(&"case_overview") == &"scene_topic_overview",
		"Talk returns authored topic scene"
	)
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"Topic branch shows dialogue"
	)
	harness.story_vm.resume_dialogue()
	_expect(
		harness.investigation.is_topic_completed(&"case_overview"),
		"Topic is completed on return"
	)
	_expect(
		harness.investigation.is_topic_available(&"suspect_alibi"),
		"@talk_unlock reveals hidden topic"
	)
	_expect(
		harness.investigation.state.mode == InvestigationState.Mode.DEFAULT,
		"Talk resumes investigation"
	)


func _test_present() -> void:
	var harness := _investigating_harness()
	_expect(
		harness.investigation.present(&"pocket_watch").is_empty(),
		"Presenting unowned evidence is rejected"
	)

	_own_evidence(harness, &"attorney_badge")
	_expect(
		harness.investigation.present(&"attorney_badge") == &"scene_present_badge_office",
		"Specific reaction wins over fallback"
	)
	harness.story_vm.resume_dialogue()
	_expect(
		harness.investigation.state.mode == InvestigationState.Mode.DEFAULT,
		"Present resumes investigation"
	)

	_own_evidence(harness, &"pocket_watch")
	_expect(
		harness.investigation.present(&"pocket_watch") == &"scene_present_generic_office",
		"Unauthored evidence falls back to generic reaction"
	)
	harness.story_vm.resume_dialogue()

	# Move to location without character
	harness.investigation.move(&"location_crime_scene")
	_expect(
		harness.investigation.present(&"attorney_badge").is_empty(),
		"Present is rejected where no character is present"
	)
	_expect(not harness.investigation.can_present(), "Present availability follows character presence")


func _test_move_and_invalid_move() -> void:
	var harness := _investigating_harness()
	_expect(
		not harness.investigation.move(&"invalid_location"),
		"Unauthored move destination is rejected"
	)
	_expect(
		harness.investigation.state.current_location == &"location_office",
		"Rejected move keeps current location"
	)
	_expect(harness.investigation.move(&"location_crime_scene"), "Authored move succeeds")
	_expect(
		harness.investigation.state.current_location == &"location_crime_scene",
		"Move changes current location"
	)
	_expect(
		harness.game_state.investigation.visited_locations.has(&"location_crime_scene"),
		"Visited locations are tracked"
	)
	_expect(
		harness.investigation.current_location().display_name == "案发现场",
		"Move loads destination definition"
	)
	_expect(harness.investigation.move(&"location_office"), "Return move succeeds")
	_expect(
		harness.investigation.state.current_location == &"location_office",
		"Returned to office"
	)


func _test_completion() -> void:
	var harness := _investigating_harness()
	harness.investigation.move(&"location_crime_scene")
	_expect(
		harness.investigation.examine(&"table_report") == &"scene_examine_table",
		"Examine table report triggers end"
	)
	# 1st line of scene_examine_table
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"1st examine dialogue waiting"
	)
	harness.story_vm.resume_dialogue()
	# 2nd line of scene_examine_table
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"2nd examine dialogue waiting"
	)
	harness.story_vm.resume_dialogue()

	# Now @investigation_end has fired and resumed main story
	_expect(not harness.game_state.investigation.active, "@investigation_end deactivates runtime")
	_expect(
		harness.investigation.state.mode == InvestigationState.Mode.INACTIVE,
		"Investigation returns to INACTIVE"
	)
	_expect(
		harness.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE,
		"Main story resumes after investigation"
	)
	_expect(
		harness.game_state.story.current_scene == &"scene_court_intro",
		"Main story proceeds to scene_court_intro"
	)


func _own_evidence(harness: Harness, evidence_id: StringName) -> void:
	harness.game_state.evidence[evidence_id] = EvidenceState.new(evidence_id, true, &"", true)


func _record_dialogue(
	_speaker_id: StringName,
	_expression_id: StringName,
	text: String,
	_source: SourceLocation,
) -> void:
	_dialogues.append(text)


func _finish() -> void:
	if _failures > 0:
		push_error("Investigation runtime tests failed: %d" % _failures)
		quit(1)
		return
	print("Investigation runtime tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
