class_name TalkTopicDef
extends RefCounted

## Authored conversation topic. `locked` topics stay hidden until a story branch
## unlocks them with @talk_unlock.

var id: StringName
var title: String
var scene: StringName
var locked: bool
var source: SourceLocation


func _init(
	topic_id: StringName = &"",
	topic_title: String = "",
	topic_scene: StringName = &"",
	topic_locked: bool = false,
	topic_source: SourceLocation = null,
) -> void:
	id = topic_id
	title = topic_title if not topic_title.is_empty() else String(topic_id)
	scene = topic_scene
	locked = topic_locked
	source = topic_source
