class_name SourceLocation
extends RefCounted

var file: String
var line: int


func _init(source_file: String = "", source_line: int = 0) -> void:
	file = source_file
	line = source_line
