class_name StateCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	context: StoryRuntimeContext,
) -> CommandResult:
	match instruction.op:
		StoryInstruction.Op.FLAG:
			context.game_state.flags[instruction.flag_id] = instruction.value
			return CommandResult.new(CommandResult.Type.CONTINUE)
		StoryInstruction.Op.CONDITION:
			var actual: Variant = context.game_state.flags.get(instruction.flag_id, false)
			if actual == instruction.equals_value:
				return CommandResult.new(CommandResult.Type.GOTO, instruction.target_scene)
			return CommandResult.new(CommandResult.Type.CONTINUE)
	return CommandResult.new(CommandResult.Type.ERROR, &"", "Unsupported state instruction.")
