class_name CourtBranchContext
extends RefCounted

enum Type {
	PRESS,
	WRONG_PRESENT,
	CORRECT_PRESENT,
}

var type: Type
var statement_id: StringName
var evidence_id: StringName
var target_scene: StringName


func _init(
	branch_type: Type,
	branch_statement_id: StringName,
	branch_target_scene: StringName,
	branch_evidence_id: StringName = &"",
) -> void:
	type = branch_type
	statement_id = branch_statement_id
	target_scene = branch_target_scene
	evidence_id = branch_evidence_id
