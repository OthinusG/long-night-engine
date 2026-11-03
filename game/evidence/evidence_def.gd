class_name EvidenceDef
extends RefCounted

## Static evidence information. Version-dependent presentation is authored under
## `versions` and resolved through display_name_for()/description_for().

var id: StringName
var display_name: String
var description: String
var presentable: bool
var versions: Dictionary[StringName, Dictionary]


func _init(
	evidence_id: StringName = &"",
	is_presentable: bool = true,
	evidence_display_name: String = "",
	evidence_description: String = "",
) -> void:
	id = evidence_id
	display_name = evidence_display_name if not evidence_display_name.is_empty() else String(evidence_id)
	description = evidence_description
	presentable = is_presentable


## Name for the current evidence version, falling back to the base name.
func display_name_for(version: StringName) -> String:
	var variant: Dictionary = versions.get(version, {})
	var name: Variant = variant.get("name")
	return name if name is String and not String(name).is_empty() else display_name


## Description for the current evidence version, falling back to the base text.
func description_for(version: StringName) -> String:
	var variant: Dictionary = versions.get(version, {})
	var text: Variant = variant.get("description")
	return text if text is String and not String(text).is_empty() else description


func has_version(version: StringName) -> bool:
	return versions.has(version)
