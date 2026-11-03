class_name ProcedureResult
extends RefCounted

## Outcome of selecting a procedural action. Carries the story branch scene the
## runtime must run; it never carries presentation instructions.

enum Type {
	CORRECT,
	WRONG,
	SPECIAL,
}

var type: Type
var context_id: StringName
var action_id: StringName
var target_scene: StringName


func _init(
	result_type: Type = Type.WRONG,
	result_context_id: StringName = &"",
	result_action_id: StringName = &"",
	result_target_scene: StringName = &"",
) -> void:
	type = result_type
	context_id = result_context_id
	action_id = result_action_id
	target_scene = result_target_scene
