extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	_test_story_ir()
	_test_game_state()
	_test_testimony_navigation()
	_test_press()
	_test_present_evidence()
	_test_headless_runtime()

	if _failures > 0:
		push_error("Core interface tests failed: %d" % _failures)
		quit(1)
		return

	print("Core interface tests passed")
	quit()


func _test_story_ir() -> void:
	var source := SourceLocation.new("chapter_01/demo.md", 4)
	var instruction := StoryInstruction.new(StoryInstruction.Op.SAY, source)
	instruction.speaker_id = &"lu_changgeng"
	instruction.expression_id = &"thinking"
	instruction.text = "Demo dialogue"

	var scene := StoryScene.new(&"demo_start", source)
	scene.instructions.append(instruction)
	var background := StoryInstruction.new(StoryInstruction.Op.BG, source)
	background.background_id = &"county_court_day"
	scene.instructions.append(background)
	var program := StoryProgram.new(&"demo_start")
	program.add_scene(scene)
	var testimony_source := SourceLocation.new("chapter_01/demo.md", 7)
	var testimony := TestimonyDef.new(&"zhao_demo_01", &"demo_wrong", 20, testimony_source)
	var statement := StatementDef.new(
		&"zhao_demo_s01",
		&"zhao_tinglu",
		"Demo statement",
		&"demo_press",
		&"calm",
		testimony_source,
	)
	statement.add_present_rule(PresentRule.new(
		&"night_duty_log",
		&"demo_break",
		PresentResultType.Value.CORRECT,
		testimony_source,
	))
	testimony.add_statement(statement)
	program.add_testimony(testimony)

	_expect(program.get_scene(&"demo_start") == scene, "Story IR preserves scenes")
	_expect(scene.instructions[0].op == StoryInstruction.Op.SAY, "Story IR preserves operations")
	_expect(scene.instructions[0].source.file == "chapter_01/demo.md", "Source file is preserved")
	_expect(scene.instructions[0].source.line == 4, "Source line is preserved")
	_expect(scene.source.line == 4, "Scene source is preserved")
	_expect(scene.instructions[1].background_id == &"county_court_day", "Stage IDs are explicit")
	_expect(program.get_testimony(&"zhao_demo_01").source.line == 7, "Testimony source is preserved")
	_expect(statement.expression_id == &"calm", "Statement expression is preserved")
	_expect(statement.present_rules[0].source.line == 7, "Present rule source is preserved")


func _test_game_state() -> void:
	var game_state := GameState.new()

	_expect(game_state.story != null, "GameState initializes StoryState")
	_expect(game_state.court != null, "GameState initializes CourtState")
	_expect(game_state.investigation != null, "GameState initializes InvestigationState")
	_expect(game_state.court.active_testimony == null, "GameState starts without testimony")
	_expect(game_state.court.penalty == 100, "GameState initializes court penalty")


func _test_testimony_navigation() -> void:
	var runtime := _build_runtime()
	runtime.start_testimony(_build_testimony())
	while runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		runtime.advance_preview()

	_expect(runtime.current_statement().id == &"zhao_demo_01_s01", "Testimony starts at statement 1")
	_expect(runtime.next_statement().id == &"zhao_demo_01_s02", "Testimony moves right")
	runtime.previous_statement()
	_expect(runtime.previous_statement().id == &"zhao_demo_01_s01", "Left boundary clamps")

	runtime.next_statement()
	runtime.next_statement()
	runtime.next_statement()
	_expect(runtime.next_statement().id == &"zhao_demo_01_s04", "Right boundary clamps")


func _test_press() -> void:
	var runtime := _build_runtime()
	runtime.start_testimony(_build_testimony())
	while runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		runtime.advance_preview()

	var target: StringName = runtime.press_current_statement()
	_expect(target == &"zhao_demo_01_s01_press", "Press returns its target scene")
	_expect(
		runtime.state.active_testimony.pressed_statements.has(&"zhao_demo_01_s01"),
		"Press records the statement",
	)


func _test_present_evidence() -> void:
	var runtime := _build_runtime()
	runtime.start_testimony(_build_testimony())
	while runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		runtime.advance_preview()
	runtime.next_statement()
	runtime.next_statement()

	var correct := runtime.present_evidence(&"zhao_demo_01_s03", &"night_duty_log")
	_expect(correct.type == PresentResultType.Value.CORRECT, "Correct evidence returns CORRECT")
	_expect(correct.target_scene == &"zhao_demo_01_break", "Correct evidence returns its scene")

	var wrong_runtime := _build_runtime()
	wrong_runtime.start_testimony(_build_testimony())
	while wrong_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		wrong_runtime.advance_preview()
	wrong_runtime.next_statement()
	wrong_runtime.next_statement()
	var wrong := wrong_runtime.present_evidence(&"zhao_demo_01_s03", &"wrong_evidence")
	_expect(wrong.type == PresentResultType.Value.WRONG, "Wrong evidence returns WRONG")
	_expect(wrong.penalty == 20, "Wrong evidence returns penalty 20")
	_expect(wrong_runtime.state.penalty == 80, "Wrong evidence updates canonical court state")


func _test_headless_runtime() -> void:
	var runtime := _build_runtime()
	_expect(runtime is RefCounted, "CourtRuntime is headless")
	_expect(not runtime.has_method("get_tree"), "CourtRuntime does not require a UI scene")


func _build_runtime() -> CourtRuntime:
	var game_state := GameState.new()
	game_state.evidence[&"night_duty_log"] = EvidenceState.new(&"night_duty_log", true)
	game_state.evidence[&"wrong_evidence"] = EvidenceState.new(&"wrong_evidence", true)
	var repository := EvidenceRepository.new()
	repository.add_definition(EvidenceDef.new(&"night_duty_log"))
	repository.add_definition(EvidenceDef.new(&"wrong_evidence"))
	return CourtRuntime.new(game_state, repository)


func _build_testimony() -> TestimonyDef:
	var testimony := TestimonyDef.new(&"zhao_demo_01", &"zhao_demo_01_wrong", 20)
	testimony.add_statement(StatementDef.new(
		&"zhao_demo_01_s01",
		&"zhao_tinglu",
		"Demo statement 1",
		&"zhao_demo_01_s01_press",
	))
	testimony.add_statement(StatementDef.new(
		&"zhao_demo_01_s02",
		&"zhao_tinglu",
		"Demo statement 2",
	))
	var statement_3 := StatementDef.new(
		&"zhao_demo_01_s03",
		&"zhao_tinglu",
		"Demo statement 3",
		&"zhao_demo_01_s03_press",
	)
	statement_3.add_present_rule(PresentRule.new(
		&"night_duty_log",
		&"zhao_demo_01_break",
		PresentResultType.Value.CORRECT,
	))
	testimony.add_statement(statement_3)
	testimony.add_statement(StatementDef.new(
		&"zhao_demo_01_s04",
		&"zhao_tinglu",
		"Demo statement 4",
	))
	return testimony


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
