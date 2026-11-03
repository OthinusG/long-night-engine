class_name LocationState
extends RefCounted

## Runtime progress for one visited location. Static expectations live in
## LocationDef; only completion state lives here.

var visited: bool = false
var examined_hotspots: Array[StringName]
var unlocked_topics: Array[StringName]
var completed_topics: Array[StringName]
var unlocked_moves: Array[StringName]


func has_examined(hotspot_id: StringName) -> bool:
	return examined_hotspots.has(hotspot_id)


func mark_examined(hotspot_id: StringName) -> void:
	if not examined_hotspots.has(hotspot_id):
		examined_hotspots.append(hotspot_id)


func has_unlocked_topic(topic_id: StringName) -> bool:
	return unlocked_topics.has(topic_id)


func unlock_topic(topic_id: StringName) -> void:
	if not unlocked_topics.has(topic_id):
		unlocked_topics.append(topic_id)


func has_completed_topic(topic_id: StringName) -> bool:
	return completed_topics.has(topic_id)


func complete_topic(topic_id: StringName) -> void:
	if not completed_topics.has(topic_id):
		completed_topics.append(topic_id)


func has_unlocked_move(destination_id: StringName) -> bool:
	return unlocked_moves.has(destination_id)


func unlock_move(destination_id: StringName) -> void:
	if not unlocked_moves.has(destination_id):
		unlocked_moves.append(destination_id)
