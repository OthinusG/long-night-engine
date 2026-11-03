class_name PresentRule
extends RefCounted

var evidence_id: StringName
var target_scene: StringName
var result_type: PresentResultType.Value
var source: SourceLocation
## Optional evidence version gate: when set, the rule only matches an evidence
## object that has reached exactly this version.
var required_version: StringName


func _init(
	rule_evidence_id: StringName = &"",
	rule_target_scene: StringName = &"",
	rule_result_type: PresentResultType.Value = PresentResultType.Value.CORRECT,
	rule_source: SourceLocation = null,
) -> void:
	evidence_id = rule_evidence_id
	target_scene = rule_target_scene
	result_type = rule_result_type
	source = rule_source


func matches_version(version: StringName) -> bool:
	return required_version.is_empty() or required_version == version
