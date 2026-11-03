class_name DialogueCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	context: StoryRuntimeContext,
) -> CommandResult:
	context.request_dialogue(instruction)
	return CommandResult.new(CommandResult.Type.BLOCK)
