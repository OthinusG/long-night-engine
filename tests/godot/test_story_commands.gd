extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var registry := CommandRegistry.create_default()
	for op: StoryInstruction.Op in StoryInstruction.Op.values():
		_expect(registry.get_handler(op) != null, "Instruction op is explicitly registered: %d" % op)

	var game_state := GameState.new()
	var context := StoryRuntimeContext.new(game_state)
	var source := SourceLocation.new("test.md", 1)

	var flag := StoryInstruction.new(StoryInstruction.Op.FLAG, source)
	flag.flag_id = &"x"
	flag.value = true
	_expect(
		registry.get_handler(flag.op).execute(flag, context).type == CommandResult.Type.CONTINUE,
		"Flag command continues",
	)
	_expect(game_state.flags[&"x"] == true, "Flag command updates canonical GameState")

	var condition := StoryInstruction.new(StoryInstruction.Op.CONDITION, source)
	condition.flag_id = &"x"
	condition.equals_value = true
	condition.target_scene = &"target"
	var branch := registry.get_handler(condition.op).execute(condition, context)
	_expect(branch.type == CommandResult.Type.GOTO, "True condition returns GOTO")
	_expect(branch.target_scene == &"target", "Condition preserves target")

	var evidence_add := StoryInstruction.new(StoryInstruction.Op.EVIDENCE_ADD, source)
	evidence_add.evidence_id = &"record"
	registry.get_handler(evidence_add.op).execute(evidence_add, context)
	_expect(game_state.evidence[&"record"].owned, "Evidence add updates typed state")

	if _failures > 0:
		push_error("Story command tests failed: %d" % _failures)
		quit(1)
		return
	print("Story command tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
