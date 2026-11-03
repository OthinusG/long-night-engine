class_name EvidenceCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	context: StoryRuntimeContext,
) -> CommandResult:
	var evidence: EvidenceState = context.game_state.evidence.get(instruction.evidence_id) as EvidenceState
	if evidence == null:
		evidence = EvidenceState.new(instruction.evidence_id)
		context.game_state.evidence[instruction.evidence_id] = evidence
	match instruction.op:
		StoryInstruction.Op.EVIDENCE_ADD:
			evidence.owned = true
			evidence.discovered = true
			return CommandResult.new(CommandResult.Type.CONTINUE)
		StoryInstruction.Op.EVIDENCE_UPDATE:
			evidence.version = instruction.evidence_version
			evidence.discovered = true
			return CommandResult.new(CommandResult.Type.CONTINUE)
		StoryInstruction.Op.EVIDENCE_REMOVE:
			evidence.owned = false
			return CommandResult.new(CommandResult.Type.CONTINUE)
	return CommandResult.new(CommandResult.Type.ERROR, &"", "Unsupported evidence instruction.")
