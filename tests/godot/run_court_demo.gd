extends SceneTree

var _vm: StoryVM
var _court: CourtRuntime
var _procedure: ProcedureRuntime
var _coordinator: GameCoordinator
var _failed: bool = false


func _initialize() -> void:
	var loader := StoryProgramLoader.new()
	var program: StoryProgram = loader.load_file("res://story_build/story.json")
	var evidence_repository := EvidenceRepository.new()
	if program == null or not evidence_repository.load_file("res://data/evidence.json"):
		_fail(loader.error_message if program == null else evidence_repository.error_message)
		return
	var procedure_repository := ProcedureRepository.new()
	if not procedure_repository.load_file("res://data/procedure.json"):
		_fail(procedure_repository.error_message)
		return

	var game_state := GameState.new()
	game_state.evidence[&"crime_report"] = EvidenceState.new(&"crime_report", true)
	game_state.evidence[&"attorney_badge"] = EvidenceState.new(&"attorney_badge", true)
	_vm = StoryVM.new(game_state)
	_court = CourtRuntime.new(game_state, evidence_repository)
	_procedure = ProcedureRuntime.new(game_state, procedure_repository)
	_coordinator = GameCoordinator.new(_vm, _court, null, _procedure)
	_vm.debug_logging = true
	_court.debug_logging = true
	_vm.dialogue_requested.connect(_on_dialogue)
	_vm.load_program(program)
	var demo_scene: StringName = &"scene_court_testimony" if program.has_scene(&"scene_court_testimony") else program.entry_scene
	_vm.start(demo_scene)
	while _vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		_vm.resume_dialogue()
	while _court.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		_court.advance_preview()

	_check(_court.get_current_statement().id == &"demo_s01", "Court did not start at s01")
	_court.next_statement()
	_court.press_current_statement()
	_check(_court.runtime_state == CourtRuntime.RuntimeState.WAIT_STORY_BRANCH, "Press did not suspend court")
	while _vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		_vm.resume_dialogue()
	_check(_court.get_current_statement().id == &"demo_s02", "Press did not resume s02")

	var wrong := _court.present_evidence(&"demo_s02", &"attorney_badge")
	_check(wrong.type == PresentResultType.Value.WRONG, "Attorney badge was not WRONG")
	_check(_court.state.penalty == 80, "Penalty did not become 80")
	while _vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		_vm.resume_dialogue()
	_check(_court.get_current_statement().id == &"demo_s02", "Wrong branch did not resume s02")

	_court.next_statement()
	var correct := _court.present_evidence(&"demo_s03", &"crime_report")
	_check(correct.type == PresentResultType.Value.CORRECT, "Crime report was not CORRECT")
	while _vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		_vm.resume_dialogue()
	_check(_court.runtime_state == CourtRuntime.RuntimeState.INACTIVE, "Testimony did not complete")
	if _failed:
		quit(1)
		return
	print("[CourtDemo] PASS penalty=80 testimony=complete")
	quit()


func _on_dialogue(
	speaker_id: StringName,
	_expression_id: StringName,
	text: String,
	_source: SourceLocation,
) -> void:
	print("[CourtDemo] %s: %s" % [speaker_id, text.replace("\n", " / ")])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
