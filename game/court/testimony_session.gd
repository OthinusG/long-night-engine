class_name TestimonySession
extends RefCounted

var testimony_id: StringName
var current_statement_id: StringName
var visited_statements: Array[StringName]
var pressed_statements: Array[StringName]
var completed: bool = false
var suspended: bool = false


func _init(session_testimony_id: StringName = &"") -> void:
	testimony_id = session_testimony_id
