class_name TestimonyDef
extends RefCounted

var id: StringName
var statements: Array[StatementDef]
var wrong_target_scene: StringName
var wrong_penalty: int
var source: SourceLocation


func _init(
	testimony_id: StringName = &"",
	testimony_wrong_target_scene: StringName = &"",
	testimony_wrong_penalty: int = 0,
	testimony_source: SourceLocation = null,
) -> void:
	id = testimony_id
	wrong_target_scene = testimony_wrong_target_scene
	wrong_penalty = testimony_wrong_penalty
	source = testimony_source


func add_statement(statement: StatementDef) -> void:
	statements.append(statement)
