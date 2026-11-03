class_name CommandResult
extends RefCounted

enum Type {
	CONTINUE,
	BLOCK,
	GOTO,
	CALL,
	RETURN,
	ENTER_COURT,
	ENTER_INVESTIGATION,
	END_INVESTIGATION,
	ENTER_PROCEDURE,
	END_PROCEDURE,
	FINISH,
	ERROR,
}

var type: Type
var target_scene: StringName
var error_message: String


func _init(
	result_type: Type,
	result_target_scene: StringName = &"",
	result_error_message: String = "",
) -> void:
	type = result_type
	target_scene = result_target_scene
	error_message = result_error_message
