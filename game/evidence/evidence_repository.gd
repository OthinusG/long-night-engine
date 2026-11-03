class_name EvidenceRepository
extends RefCounted

var error_message: String = ""
var _definitions: Dictionary[StringName, EvidenceDef]


func load_file(path: String) -> bool:
	error_message = ""
	_definitions.clear()
	if not FileAccess.file_exists(path):
		return _fail("Evidence registry does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open evidence registry: %s" % path)
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	if parse_error != OK:
		return _fail("Malformed evidence registry at line %d: %s" % [
			json.get_error_line(),
			json.get_error_message(),
		])
	if not json.data is Dictionary:
		return _fail("Evidence registry root must be an object.")
	var entries: Variant = (json.data as Dictionary).get("evidence")
	if not entries is Array:
		return _fail("Evidence registry requires an 'evidence' array.")
	for value: Variant in entries:
		if not value is Dictionary:
			return _fail("Each evidence definition must be an object.")
		var data: Dictionary = value
		if (
			not data.get("id") is String
			or not data.get("name") is String
			or not data.get("description") is String
			or not data.get("presentable") is bool
		):
			return _fail(
				"Each evidence definition requires string id/name/description and bool presentable."
			)
		var evidence_id := StringName(data["id"])
		if evidence_id.is_empty() or _definitions.has(evidence_id):
			return _fail("Invalid or duplicate evidence ID: %s" % evidence_id)
		var definition := EvidenceDef.new(
			evidence_id,
			data["presentable"],
			data["name"],
			data["description"],
		)
		if data.get("versions") is Dictionary:
			var versions: Dictionary = data["versions"]
			for version_key: Variant in versions:
				if not version_key is String or not versions[version_key] is Dictionary:
					return _fail("Evidence versions must map version IDs to objects.")
				definition.versions[StringName(version_key)] = versions[version_key]
		add_definition(definition)
	return true


func add_definition(definition: EvidenceDef) -> void:
	assert(definition != null, "Evidence definition is required")
	_definitions[definition.id] = definition


func get_evidence(evidence_id: StringName) -> EvidenceDef:
	return _definitions.get(evidence_id) as EvidenceDef


## Name of an evidence object at a given runtime version.
func display_name_for(evidence_id: StringName, version: StringName) -> String:
	var definition: EvidenceDef = get_evidence(evidence_id)
	if definition == null:
		return "[MISSING EVIDENCE: %s]" % evidence_id
	return definition.display_name_for(version)


## Description of an evidence object at a given runtime version.
func description_for(evidence_id: StringName, version: StringName) -> String:
	var definition: EvidenceDef = get_evidence(evidence_id)
	if definition == null:
		return ""
	return definition.description_for(version)


func get_all() -> Array[EvidenceDef]:
	var result: Array[EvidenceDef]
	for definition: EvidenceDef in _definitions.values():
		result.append(definition)
	result.sort_custom(
		func(left: EvidenceDef, right: EvidenceDef) -> bool:
			return String(left.id) < String(right.id)
	)
	return result


func _fail(message: String) -> bool:
	error_message = message
	return false
