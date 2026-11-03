class_name FlowCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	_context: StoryRuntimeContext,
) -> CommandResult:
	match instruction.op:
		StoryInstruction.Op.GOTO:
			return CommandResult.new(CommandResult.Type.GOTO, instruction.target_scene)
		StoryInstruction.Op.CALL:
			return CommandResult.new(CommandResult.Type.CALL, instruction.target_scene)
		StoryInstruction.Op.RETURN:
			return CommandResult.new(CommandResult.Type.RETURN)
	return CommandResult.new(CommandResult.Type.ERROR, &"", "Unsupported flow instruction.")
