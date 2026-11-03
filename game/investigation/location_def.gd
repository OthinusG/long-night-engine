class_name LocationDef
extends RefCounted

## Static investigation location. Contains no runtime completion state; that
## lives in LocationState.

var id: StringName
var display_name: String
var background: StringName
var characters: Array[StringName]
var moves: Array[StringName]
var present_reactions: Dictionary[StringName, StringName]
var generic_present: StringName
var hotspots: Array[HotspotDef]
var topics: Array[TalkTopicDef]
var source: SourceLocation


func _init(location_id: StringName = &"", location_source: SourceLocation = null) -> void:
	id = location_id
	display_name = String(location_id)
	source = location_source


func get_hotspot(hotspot_id: StringName) -> HotspotDef:
	for hotspot: HotspotDef in hotspots:
		if hotspot.id == hotspot_id:
			return hotspot
	return null


func get_topic(topic_id: StringName) -> TalkTopicDef:
	for topic: TalkTopicDef in topics:
		if topic.id == topic_id:
			return topic
	return null


## Hotspot under a normalized 0–1 point, or null when the click missed.
func hotspot_at(normalized_point: Vector2) -> HotspotDef:
	for hotspot: HotspotDef in hotspots:
		if hotspot.contains_point(normalized_point):
			return hotspot
	return null


## Story scene for an evidence reaction, falling back to the generic reaction.
func present_scene(evidence_id: StringName) -> StringName:
	var scene: StringName = present_reactions.get(evidence_id, &"")
	return scene if not scene.is_empty() else generic_present
