extends SceneTree

const DEMO_PATH: String = "res://story_build/story.json"

var _failures: int = 0
var _dialogues: Array[String]
var _dialogue_sources: Array[SourceLocation]
var _dialogue_states: Array[int]
var _courts: Array[StringName]
var _court_states: Array[int]
var _scene_changes: Array[StringName]
var _active_vm: StoryVM
var _pause_on_background: bool = false


func _initialize() -> void:
	_test_sequential_dialogue()
	_test_goto()
	_test_call_return()
	_test_nested_call()
	_test_invalid_return()
	_test_flags_and_branches()
	_test_evidence_commands()
	_test_court_blocking()
	_test_infinite_loop_guard()
	_test_invalid_program_counter()
	_test_pause_resume()
	_test_compiled_demo_integration()

	if _failures > 0:
		push_error("StoryVM tests failed: %d" % _failures)
		quit(1)
		return
	print("StoryVM tests passed")
	quit()


func _test_sequential_dialogue() -> void:
	var program := _program(&"main", [
		_scene(&"main", [_say("A", 10), _say("B", 11)]),
	])
	var vm := _vm(program)
	vm.start(&"main")

	_expect(_dialogues == ["A"], "First SAY blocks before second SAY")
	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE, "SAY enters WAIT_DIALOGUE")
	_expect(vm.game_state.story.current_instruction == 1, "SAY prepares next instruction")
	_expect(_dialogue_sources[0].file == "runtime_test.md", "Dialogue source file is preserved")
	_expect(_dialogue_sources[0].line == 10, "Dialogue source line is preserved")
	_expect(_dialogue_states[0] == StoryState.RuntimeState.WAIT_DIALOGUE, "Dialogue signal observes blocked state")

	vm.resume_dialogue()
	_expect(_dialogues == ["A", "B"], "resume_dialogue reaches second SAY")
	_expect(vm.game_state.story.current_instruction == 2, "Second SAY also prepares continuation")


func _test_goto() -> void:
	var program := _program(&"scene_a", [
		_scene(&"scene_a", [_flow(StoryInstruction.Op.GOTO, &"scene_b")]),
		_scene(&"scene_b", [_say("B")]),
	])
	var vm := _vm(program)
	vm.start(&"scene_a")

	_expect(vm.game_state.story.current_scene == &"scene_b", "GOTO changes scene")
	_expect(_dialogues == ["B"], "GOTO continues until target dialogue")


func _test_call_return() -> void:
	var program := _program(&"scene_a", [
		_scene(&"scene_a", [
			_say("A"),
			_flow(StoryInstruction.Op.CALL, &"scene_b"),
			_say("C"),
		]),
		_scene(&"scene_b", [
			_say("B"),
			_flow(StoryInstruction.Op.RETURN),
		]),
	])
	var vm := _vm(program)
	vm.start(&"scene_a")
	vm.resume_dialogue()
	_expect(vm.game_state.story.call_stack.size() == 1, "CALL pushes continuation frame")
	vm.resume_dialogue()

	_expect(_dialogues == ["A", "B", "C"], "CALL and RETURN restore dialogue order")
	_expect(vm.game_state.story.call_stack.is_empty(), "RETURN pops continuation frame")
	_expect(
		_scene_changes == [&"scene_a", &"scene_b", &"scene_a"],
		"Every scene boundary emits once: %s" % [_scene_changes],
	)


func _test_nested_call() -> void:
	var program := _program(&"scene_a", [
		_scene(&"scene_a", [
			_flow(StoryInstruction.Op.CALL, &"scene_b"),
			_say("A"),
		]),
		_scene(&"scene_b", [
			_flow(StoryInstruction.Op.CALL, &"scene_c"),
			_say("B"),
			_flow(StoryInstruction.Op.RETURN),
		]),
		_scene(&"scene_c", [
			_say("C"),
			_flow(StoryInstruction.Op.RETURN),
		]),
	])
	var vm := _vm(program)
	vm.start(&"scene_a")
	_expect(vm.game_state.story.call_stack.size() == 2, "Nested CALL uses a real stack")
	vm.resume_dialogue()
	vm.resume_dialogue()

	_expect(_dialogues == ["C", "B", "A"], "Nested RETURN restores each caller")
	_expect(vm.game_state.story.call_stack.is_empty(), "Nested stack fully unwinds")


func _test_invalid_return() -> void:
	var program := _program(&"main", [
		_scene(&"main", [_flow(StoryInstruction.Op.RETURN, &"", 42)]),
	])
	var vm := _vm(program)
	vm.start(&"main")

	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.ERROR, "Empty-stack RETURN enters ERROR")
	_expect("runtime_test.md:42" in vm.last_error, "Runtime error includes source location")


func _test_flags_and_branches() -> void:
	var true_program := _program(&"main", [
		_scene(&"main", [
			_flag(&"x", true),
			_condition(&"x", true, &"target"),
			_say("fallthrough"),
		]),
		_scene(&"target", [_say("target")]),
	])
	var true_vm := _vm(true_program)
	true_vm.start(&"main")
	_expect(true_vm.game_state.flags[&"x"] == true, "FLAG updates GameState.flags")
	_expect(_dialogues == ["target"], "True condition branches")

	var false_program := _program(&"main", [
		_scene(&"main", [
			_flag(&"x", false),
			_condition(&"x", true, &"target"),
			_say("fallthrough"),
		]),
		_scene(&"target", [_say("target")]),
	])
	var false_vm := _vm(false_program)
	false_vm.start(&"main")
	_expect(_dialogues == ["fallthrough"], "False condition continues normally")


func _test_evidence_commands() -> void:
	var add := _evidence(StoryInstruction.Op.EVIDENCE_ADD, &"record")
	var update := _evidence(StoryInstruction.Op.EVIDENCE_UPDATE, &"record")
	update.evidence_version = &"verified"
	var remove := _evidence(StoryInstruction.Op.EVIDENCE_REMOVE, &"record")
	var program := _program(&"main", [_scene(&"main", [add, update, remove])])
	var vm := _vm(program)
	vm.start(&"main")

	var state: EvidenceState = vm.game_state.evidence[&"record"]
	_expect(state.version == &"verified", "Evidence update changes typed version")
	_expect(not state.owned, "Evidence remove clears ownership")
	_expect(state.discovered, "Evidence add marks evidence discovered")
	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.FINISHED, "Top-level scene end finishes")

	var remove_missing_program := _program(&"main", [
		_scene(&"main", [_evidence(StoryInstruction.Op.EVIDENCE_REMOVE, &"absent")]),
	])
	var remove_missing_vm := _vm(remove_missing_program)
	remove_missing_vm.start(&"main")
	_expect(
		not remove_missing_vm.game_state.evidence[&"absent"].owned,
		"Evidence remove is idempotent for a validated ID",
	)


func _test_court_blocking() -> void:
	var program := _program(&"main", [
		_scene(&"main", [_start_testimony(&"zhao_demo_01"), _say("should_not_execute_yet")]),
	])
	program.add_testimony(TestimonyDef.new(
		&"zhao_demo_01",
		&"wrong",
		20,
		SourceLocation.new("runtime_test.md", 1),
	))
	var vm := _vm(program)
	vm.start(&"main")

	_expect(_courts == [&"zhao_demo_01"], "Court handoff emits testimony ID")
	_expect(_court_states[0] == StoryState.RuntimeState.WAIT_COURT, "Court signal observes WAIT_COURT")
	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_COURT, "Court handoff blocks VM")
	_expect(vm.game_state.story.current_instruction == 1, "Court handoff prepares continuation")
	_expect(_dialogues.is_empty(), "Instruction after court handoff does not execute")


func _test_infinite_loop_guard() -> void:
	var program := _program(&"loop", [
		_scene(&"loop", [_flow(StoryInstruction.Op.GOTO, &"loop", 77)]),
	])
	var vm := _vm(program)
	vm.start(&"loop")

	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.ERROR, "Loop budget enters ERROR")
	_expect("Instruction budget exceeded" in vm.last_error, "Loop budget reports useful error")
	_expect("runtime_test.md:77" in vm.last_error, "Loop error retains source location")


func _test_invalid_program_counter() -> void:
	var program := _program(&"main", [_scene(&"main", [_say("unused")])])
	var vm := _vm(program)
	vm.game_state.story.current_scene = &"main"
	vm.game_state.story.current_instruction = 99
	vm.game_state.story.runtime_state = StoryState.RuntimeState.RUNNING
	vm.run_until_blocked()

	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.ERROR, "Invalid PC enters ERROR")
	_expect("Invalid instruction index" in vm.last_error, "Invalid PC reports error")


func _test_pause_resume() -> void:
	var background := StoryInstruction.new(StoryInstruction.Op.BG, _source())
	background.background_id = &"court"
	var program := _program(&"main", [_scene(&"main", [background, _say("after_pause")])])
	var vm := _vm(program)
	_pause_on_background = true
	vm.start(&"main")
	_pause_on_background = false

	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.PAUSED, "pause() stops RUNNING execution")
	_expect(_dialogues.is_empty(), "Paused VM does not run the next instruction")
	vm.resume()
	_expect(_dialogues == ["after_pause"], "resume() continues paused execution")


func _test_compiled_demo_integration() -> void:
	var loader := StoryProgramLoader.new()
	var program: StoryProgram = loader.load_file(DEMO_PATH)
	_expect(program != null, "Demo loads for integration: %s" % loader.error_message)
	if program == null:
		return
	var vm := _vm(program)
	var demo_scene: StringName = &"ch01_demo_intro" if program.has_scene(&"ch01_demo_intro") else program.entry_scene
	vm.start(demo_scene)
	var resumed_dialogues: int = 0
	while vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		resumed_dialogues += 1
		if resumed_dialogues > 20:
			_expect(false, "Demo integration exceeded dialogue safety limit")
			return
		vm.resume_dialogue()

	_expect(vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_INVESTIGATION, "Demo reaches WAIT_INVESTIGATION")
	_expect(vm.game_state.evidence.has(&"attorney_badge") and vm.game_state.evidence[&"attorney_badge"].owned, "Demo evidence command executed")


func _vm(program: StoryProgram) -> StoryVM:
	_dialogues.clear()
	_dialogue_sources.clear()
	_dialogue_states.clear()
	_courts.clear()
	_court_states.clear()
	_scene_changes.clear()
	var vm := StoryVM.new()
	_active_vm = vm
	vm.scene_changed.connect(func(scene_id: StringName) -> void: _scene_changes.append(scene_id))
	vm.dialogue_requested.connect(_capture_dialogue)
	vm.court_requested.connect(_capture_court)
	vm.background_requested.connect(_capture_background)
	vm.load_program(program)
	return vm


func _program(entry_scene: StringName, scenes: Array) -> StoryProgram:
	var program := StoryProgram.new(entry_scene)
	for value: Variant in scenes:
		program.add_scene(value as StoryScene)
	return program


func _scene(scene_id: StringName, instructions: Array) -> StoryScene:
	var scene := StoryScene.new(scene_id, _source())
	for value: Variant in instructions:
		scene.instructions.append(value as StoryInstruction)
	return scene


func _say(text: String, line: int = 1) -> StoryInstruction:
	var instruction := StoryInstruction.new(StoryInstruction.Op.SAY, _source(line))
	instruction.speaker_id = &"speaker"
	instruction.expression_id = &"calm"
	instruction.text = text
	return instruction


func _flow(
	op: StoryInstruction.Op,
	target: StringName = &"",
	line: int = 1,
) -> StoryInstruction:
	var instruction := StoryInstruction.new(op, _source(line))
	instruction.target_scene = target
	return instruction


func _flag(flag_id: StringName, value: bool) -> StoryInstruction:
	var instruction := StoryInstruction.new(StoryInstruction.Op.FLAG, _source())
	instruction.flag_id = flag_id
	instruction.value = value
	return instruction


func _condition(
	flag_id: StringName,
	expected: bool,
	target: StringName,
) -> StoryInstruction:
	var instruction := StoryInstruction.new(StoryInstruction.Op.CONDITION, _source())
	instruction.flag_id = flag_id
	instruction.equals_value = expected
	instruction.target_scene = target
	return instruction


func _evidence(op: StoryInstruction.Op, evidence_id: StringName) -> StoryInstruction:
	var instruction := StoryInstruction.new(op, _source())
	instruction.evidence_id = evidence_id
	return instruction


func _start_testimony(testimony_id: StringName) -> StoryInstruction:
	var instruction := StoryInstruction.new(StoryInstruction.Op.START_TESTIMONY, _source())
	instruction.testimony_id = testimony_id
	return instruction


func _source(line: int = 1) -> SourceLocation:
	return SourceLocation.new("runtime_test.md", line)


func _capture_dialogue(
	_speaker_id: StringName,
	_expression_id: StringName,
	text: String,
	source: SourceLocation,
) -> void:
	_dialogues.append(text)
	_dialogue_sources.append(source)
	_dialogue_states.append(_active_vm.game_state.story.runtime_state)


func _capture_court(testimony_id: StringName) -> void:
	_courts.append(testimony_id)
	_court_states.append(_active_vm.game_state.story.runtime_state)


func _capture_background(_background_id: StringName) -> void:
	if _pause_on_background:
		_active_vm.pause()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
