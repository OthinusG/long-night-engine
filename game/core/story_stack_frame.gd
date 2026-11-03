class_name StoryStackFrame
extends RefCounted

var scene_id: StringName
var instruction_index: int


func _init(frame_scene_id: StringName = &"", frame_instruction_index: int = 0) -> void:
	scene_id = frame_scene_id
	instruction_index = frame_instruction_index
