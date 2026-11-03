class_name ProcedureCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	context: StoryRuntimeContext,
) -> CommandResult:
	match instruction.op:
		StoryInstruction.Op.PROCEDURE:
			context.request_procedure(instruction.context_id)
			return CommandResult.new(CommandResult.Type.ENTER_PROCEDURE)
		StoryInstruction.Op.PROCEDURE_END:
			return CommandResult.new(CommandResult.Type.END_PROCEDURE)
	return CommandResult.new(CommandResult.Type.ERROR, &"", "Unsupported procedure instruction.")
