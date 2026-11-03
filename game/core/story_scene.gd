class_name StoryScene
extends RefCounted

var id: StringName
var instructions: Array[StoryInstruction]
var source: SourceLocation


func _init(scene_id: StringName = &"", scene_source: SourceLocation = null) -> void:
	id = scene_id
	source = scene_source
