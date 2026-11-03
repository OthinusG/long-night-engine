class_name ProcedureRepository
extends RefCounted

## Loads authored procedure contexts. The compiler validates the same file, so
## this loader only defends against a data file that changed after the build.

var error_message: String = ""
var _contexts: Dictionary[StringName, ProcedureContext]


func load_file(path: String) -> bool:
	error_message = ""
	_contexts.clear()
	if not FileAccess.file_exists(path):
		return _fail("Procedure registry does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open procedure registry: %s" % path)
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _fail("Malformed procedure registry at line %d: %s" % [
			json.get_error_line(),
			json.get_error_message(),
		])
	if not json.data is Dictionary:
		return _fail("Procedure registry root must be an object.")
	var entries: Variant = (json.data as Dictionary).get("contexts")
	if not entries is Array:
		return _fail("Procedure registry requires a 'contexts' array.")
	for value: Variant in entries:
		if not value is Dictionary:
			return _fail("Each procedure context must be an object.")
		var data: Dictionary = value
		if (
			not data.get("id") is String
			or not data.get("title") is String
			or not data.get("description") is String
			or not data.get("actions") is Array
		):
			return _fail("Each procedure context requires string id/title/description and actions.")
		var context_id := StringName(data["id"])
		if context_id.is_empty() or _contexts.has(context_id):
			return _fail("Invalid or duplicate procedure context ID: %s" % context_id)
		var context := ProcedureContext.new(
			context_id,
			data["title"],
			data["description"],
		)
		for action_value: Variant in data["actions"]:
			var action: ProcedureActionDef = _parse_action(action_value, context_id)
			if action == null:
				return false
			context.actions.append(action)
		_contexts[context_id] = context
	return true


func get_context(context_id: StringName) -> ProcedureContext:
	return _contexts.get(context_id) as ProcedureContext


func get_all() -> Array[ProcedureContext]:
	var result: Array[ProcedureContext]
	for context: ProcedureContext in _contexts.values():
		result.append(context)
	result.sort_custom(func(left: ProcedureContext, right: ProcedureContext) -> bool:
		return String(left.id) < String(right.id)
	)
	return result


func _parse_action(value: Variant, context_id: StringName) -> ProcedureActionDef:
	if not value is Dictionary:
		return _fail_action("Each procedure action must be an object.")
	var data: Dictionary = value
	if (
		not data.get("id") is String
		or not data.get("name") is String
		or not data.get("description") is String
		or not data.get("scene") is String
		or not data.get("result") is String
	):
		return _fail_action(
			"Procedure action in '%s' requires string id/name/description/scene/result." % context_id
		)
	var action_id := StringName(data["id"])
	if action_id.is_empty():
		return _fail_action("Procedure action in '%s' has an empty ID." % context_id)
	var result_name: String = data["result"]
	var result_type: ProcedureResult.Type
	match result_name:
		"correct":
			result_type = ProcedureResult.Type.CORRECT
		"wrong":
			result_type = ProcedureResult.Type.WRONG
		"special":
			result_type = ProcedureResult.Type.SPECIAL
		_:
			return _fail_action("Procedure action '%s' has unknown result '%s'." % [
				action_id,
				result_name,
			])
	var action := ProcedureActionDef.new(
		action_id,
		data["name"],
		data["description"],
		StringName(data["scene"]),
		result_type,
	)
	if data.get("required_evidence") is String:
		action.required_evidence = StringName(data["required_evidence"])
	if data.get("required_flag") is String:
		action.required_flag = StringName(data["required_flag"])
	return action


func _fail(message: String) -> bool:
	error_message = message
	return false


func _fail_action(message: String) -> ProcedureActionDef:
	error_message = message
	return null
