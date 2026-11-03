class_name StatementDef
extends RefCounted

var id: StringName
var speaker_id: StringName
var expression_id: StringName
var text: String
var press_target_scene: StringName
var present_rules: Array[PresentRule]
var source: SourceLocation


func _init(
	statement_id: StringName = &"",
	statement_speaker_id: StringName = &"",
	statement_text: String = "",
	statement_press_target_scene: StringName = &"",
	statement_expression_id: StringName = &"",
	statement_source: SourceLocation = null,
) -> void:
	id = statement_id
	speaker_id = statement_speaker_id
	text = statement_text
	press_target_scene = statement_press_target_scene
	expression_id = statement_expression_id
	source = statement_source


func add_present_rule(rule: PresentRule) -> void:
	present_rules.append(rule)
