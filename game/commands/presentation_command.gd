class_name PresentationCommand
extends StoryCommand


func execute(
	instruction: StoryInstruction,
	context: StoryRuntimeContext,
) -> CommandResult:
	match instruction.op:
		StoryInstruction.Op.BG:
			context.game_state.story.current_background = instruction.background_id
			context.request_background(instruction.background_id)
		StoryInstruction.Op.BGM:
			context.request_bgm(instruction.bgm_id)
		StoryInstruction.Op.SFX:
			context.request_sfx(instruction.sfx_id)
		StoryInstruction.Op.STAGE:
			if instruction.visible:
				context.request_character(
					instruction.character_id,
					instruction.stage_slot,
					instruction.expression_id,
				)
			else:
				context.request_hide(instruction.character_id)
		_:
			return CommandResult.new(CommandResult.Type.ERROR, &"", "Unsupported presentation instruction.")
	return CommandResult.new(CommandResult.Type.CONTINUE)
