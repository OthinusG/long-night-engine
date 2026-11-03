class_name EvidenceState
extends RefCounted

## Runtime state of one evidence object. Inspection progress lives here too: it
## is the same evidence object, not a parallel ownership system.

var id: StringName
var owned: bool
var version: StringName
var discovered: bool
var inspected_hotspots: Array[StringName]
var inspection_complete: bool


func _init(
	evidence_id: StringName = &"",
	is_owned: bool = false,
	evidence_version: StringName = &"",
	is_discovered: bool = false,
) -> void:
	id = evidence_id
	owned = is_owned
	version = evidence_version
	discovered = is_discovered


func has_inspected(hotspot_id: StringName) -> bool:
	return inspected_hotspots.has(hotspot_id)


func mark_inspected(hotspot_id: StringName) -> void:
	if not inspected_hotspots.has(hotspot_id):
		inspected_hotspots.append(hotspot_id)
