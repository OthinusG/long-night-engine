extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var result := CommandResult.new(CommandResult.Type.GOTO, &"target_scene")
	_expect(result.type == CommandResult.Type.GOTO, "CommandResult preserves type")
	_expect(result.target_scene == &"target_scene", "CommandResult preserves target")

	var game_state := GameState.new()
	var context := StoryRuntimeContext.new(game_state)
	_expect(context.game_state == game_state, "RuntimeContext preserves canonical GameState")
	_expect(game_state.story.call_stack.is_empty(), "Story call stack initializes empty")

	if _failures > 0:
		push_error("Story runtime model tests failed: %d" % _failures)
		quit(1)
		return
	print("Story runtime model tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
