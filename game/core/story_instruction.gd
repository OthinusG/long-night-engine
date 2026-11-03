class_name StoryInstruction
extends RefCounted

enum Op {
	SAY,
	GOTO,
	CALL,
	RETURN,
	FLAG,
	CONDITION,
	BG,
	BGM,
	SFX,
	START_TESTIMONY,
	EVIDENCE_ADD,
	EVIDENCE_UPDATE,
	EVIDENCE_REMOVE,
	INVESTIGATION,
	INVESTIGATION_END,
	TALK_UNLOCK,
	PROCEDURE,
	PROCEDURE_END,
	STAGE,
}

var op: Op
var source: SourceLocation
var speaker_id: StringName
var expression_id: StringName
var text: String
var target_scene: StringName
var flag_id: StringName
var value: Variant
var equals_value: Variant
var background_id: StringName
var bgm_id: StringName
var sfx_id: StringName
var testimony_id: StringName
var evidence_id: StringName
var evidence_version: StringName
var location_id: StringName
var topic_id: StringName
var context_id: StringName
var character_id: StringName
var stage_slot: StringName
var visible: bool = true


func _init(instruction_op: Op, instruction_source: SourceLocation) -> void:
	op = instruction_op
	source = instruction_source
