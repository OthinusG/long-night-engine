class_name StoryCommand
extends RefCounted


func execute(
	_instruction: StoryInstruction,
	_context: StoryRuntimeContext,
) -> CommandResult:
	return CommandResult.new(
		CommandResult.Type.ERROR,
		&"",
		"Story command does not implement execute().",
	)
