class_name CourtCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	context: StoryRuntimeContext,
) -> CommandResult:
	context.request_court(instruction.testimony_id)
	return CommandResult.new(CommandResult.Type.ENTER_COURT)
