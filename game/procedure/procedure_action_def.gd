class_name ProcedureActionDef
extends RefCounted

## Static procedural action. Correctness is authored data, never runtime logic.

var id: StringName
var display_name: String
var description: String
var target_scene: StringName
var result_type: ProcedureResult.Type
var required_evidence: StringName
var required_flag: StringName
var source: SourceLocation


func _init(
	action_id: StringName = &"",
	action_display_name: String = "",
	action_description: String = "",
	action_target_scene: StringName = &"",
	action_result_type: ProcedureResult.Type = ProcedureResult.Type.WRONG,
	action_source: SourceLocation = null,
) -> void:
	id = action_id
	display_name = action_display_name if not action_display_name.is_empty() else String(action_id)
	description = action_description
	target_scene = action_target_scene
	result_type = action_result_type
	source = action_source
