class_name HotspotDef
extends RefCounted

## Authored examine target. `rect` uses normalized 0–1 coordinates so authored
## hotspots survive any viewport size.

var id: StringName
var rect: Rect2
var scene: StringName
var source: SourceLocation


func _init(
	hotspot_id: StringName = &"",
	hotspot_rect: Rect2 = Rect2(),
	hotspot_scene: StringName = &"",
	hotspot_source: SourceLocation = null,
) -> void:
	id = hotspot_id
	rect = hotspot_rect
	scene = hotspot_scene
	source = hotspot_source


func contains_point(normalized_point: Vector2) -> bool:
	return rect.has_point(normalized_point)
