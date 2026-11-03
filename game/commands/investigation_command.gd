class_name InvestigationCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	context: StoryRuntimeContext,
) -> CommandResult:
	match instruction.op:
		StoryInstruction.Op.INVESTIGATION:
			context.request_investigation(instruction.location_id)
			return CommandResult.new(CommandResult.Type.ENTER_INVESTIGATION)
		StoryInstruction.Op.INVESTIGATION_END:
			return CommandResult.new(CommandResult.Type.END_INVESTIGATION)
		StoryInstruction.Op.TALK_UNLOCK:
			context.request_talk_unlock(instruction.topic_id)
			return CommandResult.new(CommandResult.Type.CONTINUE)
	return CommandResult.new(CommandResult.Type.ERROR, &"", "Unsupported investigation instruction.")
