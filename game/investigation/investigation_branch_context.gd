class_name InvestigationBranchContext
extends RefCounted

## Why a story branch is running. When it returns, InvestigationRuntime knows
## which action to finish (mark a hotspot examined, a topic completed).

enum Type {
	EXAMINE,
	TALK,
	PRESENT,
}

var type: Type
var target_scene: StringName
var hotspot_id: StringName
var topic_id: StringName
var evidence_id: StringName
var character_id: StringName


func _init(
	branch_type: Type,
	branch_target_scene: StringName,
	branch_hotspot_id: StringName = &"",
	branch_topic_id: StringName = &"",
	branch_evidence_id: StringName = &"",
	branch_character_id: StringName = &"",
) -> void:
	type = branch_type
	target_scene = branch_target_scene
	hotspot_id = branch_hotspot_id
	topic_id = branch_topic_id
	evidence_id = branch_evidence_id
	character_id = branch_character_id
