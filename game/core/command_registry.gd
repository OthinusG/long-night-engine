class_name CommandRegistry
extends RefCounted

var _handlers: Dictionary[int, StoryCommand]


func register(op: StoryInstruction.Op, handler: StoryCommand) -> void:
	assert(handler != null, "Command handler is required")
	assert(not _handlers.has(op), "Story instruction is already registered: %d" % op)
	_handlers[op] = handler


func get_handler(op: StoryInstruction.Op) -> StoryCommand:
	return _handlers.get(op) as StoryCommand


static func create_default() -> CommandRegistry:
	var registry := CommandRegistry.new()
	var dialogue := DialogueCommand.new()
	var flow := FlowCommand.new()
	var state := StateCommand.new()
	var evidence := EvidenceCommand.new()
	var court := CourtCommand.new()
	var presentation := PresentationCommand.new()
	var investigation := InvestigationCommand.new()
	var procedure := ProcedureCommand.new()

	registry.register(StoryInstruction.Op.SAY, dialogue)
	registry.register(StoryInstruction.Op.GOTO, flow)
	registry.register(StoryInstruction.Op.CALL, flow)
	registry.register(StoryInstruction.Op.RETURN, flow)
	registry.register(StoryInstruction.Op.FLAG, state)
	registry.register(StoryInstruction.Op.CONDITION, state)
	registry.register(StoryInstruction.Op.BG, presentation)
	registry.register(StoryInstruction.Op.BGM, presentation)
	registry.register(StoryInstruction.Op.SFX, presentation)
	registry.register(StoryInstruction.Op.STAGE, presentation)
	registry.register(StoryInstruction.Op.START_TESTIMONY, court)
	registry.register(StoryInstruction.Op.EVIDENCE_ADD, evidence)
	registry.register(StoryInstruction.Op.EVIDENCE_UPDATE, evidence)
	registry.register(StoryInstruction.Op.EVIDENCE_REMOVE, evidence)
	registry.register(StoryInstruction.Op.INVESTIGATION, investigation)
	registry.register(StoryInstruction.Op.INVESTIGATION_END, investigation)
	registry.register(StoryInstruction.Op.TALK_UNLOCK, investigation)
	registry.register(StoryInstruction.Op.PROCEDURE, procedure)
	registry.register(StoryInstruction.Op.PROCEDURE_END, procedure)
	return registry
