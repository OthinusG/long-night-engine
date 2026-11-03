class_name ProcedureState
extends RefCounted

## Canonical procedure state. Static contexts and actions live in
## ProcedureContext; only progress lives here.

var active: bool = false
var context_id: StringName
var resolved: bool = false
var resolved_action_id: StringName
var visited_actions: Array[StringName]


func mark_visited(action_id: StringName) -> void:
	if not visited_actions.has(action_id):
		visited_actions.append(action_id)
