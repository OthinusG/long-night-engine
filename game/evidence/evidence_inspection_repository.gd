class_name EvidenceInspectionRepository
extends RefCounted

## Loads authored evidence inspection layouts. The compiler validates the same
## file; this loader reports what is wrong instead of repairing it.

var error_message: String = ""
var _definitions: Dictionary[StringName, EvidenceInspectionDef]


func load_file(path: String) -> bool:
	error_message = ""
	_definitions.clear()
	if not FileAccess.file_exists(path):
		return _fail("Inspection registry does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open inspection registry: %s" % path)
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _fail("Malformed inspection registry at line %d: %s" % [
			json.get_error_line(),
			json.get_error_message(),
		])
	if not json.data is Dictionary:
		return _fail("Inspection registry root must be an object.")
	var entries: Variant = (json.data as Dictionary).get("inspections")
	if not entries is Array:
		return _fail("Inspection registry requires an 'inspections' array.")
	for value: Variant in entries:
		if not value is Dictionary:
			return _fail("Each inspection definition must be an object.")
		var data: Dictionary = value
		if (
			not data.get("evidence_id") is String
			or not data.get("image") is String
			or not data.get("hotspots") is Array
		):
			return _fail("Each inspection requires string evidence_id/image and a hotspots array.")
		var evidence_id := StringName(data["evidence_id"])
		if evidence_id.is_empty() or _definitions.has(evidence_id):
			return _fail("Invalid or duplicate inspection evidence ID: %s" % evidence_id)
		var definition := EvidenceInspectionDef.new(evidence_id, StringName(data["image"]))
		for hotspot_value: Variant in data["hotspots"]:
			var hotspot: EvidenceHotspotDef = _parse_hotspot(hotspot_value, evidence_id)
			if hotspot == null:
				return false
			definition.hotspots.append(hotspot)
		_definitions[evidence_id] = definition
	return true


func get_inspection(evidence_id: StringName) -> EvidenceInspectionDef:
	return _definitions.get(evidence_id) as EvidenceInspectionDef


func has_inspection(evidence_id: StringName) -> bool:
	return _definitions.has(evidence_id)


func _parse_hotspot(value: Variant, evidence_id: StringName) -> EvidenceHotspotDef:
	if not value is Dictionary:
		return _fail_hotspot("Each inspection hotspot must be an object.")
	var data: Dictionary = value
	if (
		not data.get("id") is String
		or not data.get("scene") is String
		or not data.get("rect") is Array
	):
		return _fail_hotspot("Inspection hotspot requires string id/scene and a rect array.")
	var rect_data: Array = data["rect"]
	if rect_data.size() != 4:
		return _fail_hotspot("Inspection hotspot rect requires four numbers.")
	var values: Array[float] = []
	for entry: Variant in rect_data:
		if not (entry is float or entry is int):
			return _fail_hotspot("Inspection hotspot rect values must be numbers.")
		values.append(float(entry))
	var hotspot_id := StringName(data["id"])
	if hotspot_id.is_empty():
		return _fail_hotspot("Inspection hotspot for '%s' has an empty ID." % evidence_id)
	var hotspot := EvidenceHotspotDef.new(
		hotspot_id,
		Rect2(values[0], values[1], values[2], values[3]),
		StringName(data["scene"]),
	)
	if data.get("unlocked_by") is String:
		hotspot.unlocked_by = StringName(data["unlocked_by"])
	return hotspot


func _fail(message: String) -> bool:
	error_message = message
	return false


func _fail_hotspot(message: String) -> EvidenceHotspotDef:
	error_message = message
	return null
