class_name ProcedureContext
extends RefCounted

## One authored legal problem: what it is and which procedural actions answer it.

var id: StringName
var title: String
var description: String
var actions: Array[ProcedureActionDef]
var source: SourceLocation


func _init(
	context_id: StringName = &"",
	context_title: String = "",
	context_description: String = "",
	context_source: SourceLocation = null,
) -> void:
	id = context_id
	title = context_title if not context_title.is_empty() else String(context_id)
	description = context_description
	source = context_source


func get_action(action_id: StringName) -> ProcedureActionDef:
	for action: ProcedureActionDef in actions:
		if action.id == action_id:
			return action
	return null
