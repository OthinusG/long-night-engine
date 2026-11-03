class_name PresentResult
extends RefCounted

var type: PresentResultType.Value
var target_scene: StringName
var penalty: int
var statement_id: StringName
var evidence_id: StringName


func _init(
	result_type: PresentResultType.Value,
	result_target_scene: StringName = &"",
	result_penalty: int = 0,
	result_statement_id: StringName = &"",
	result_evidence_id: StringName = &"",
) -> void:
	type = result_type
	target_scene = result_target_scene
	penalty = result_penalty
	statement_id = result_statement_id
	evidence_id = result_evidence_id
