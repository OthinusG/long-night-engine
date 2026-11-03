class_name EvidenceInspectionDef
extends RefCounted

## Static inspection layout for one evidence object.

var evidence_id: StringName
var image: StringName
var hotspots: Array[EvidenceHotspotDef]
var source: SourceLocation


func _init(
	inspection_evidence_id: StringName = &"",
	inspection_image: StringName = &"",
	inspection_source: SourceLocation = null,
) -> void:
	evidence_id = inspection_evidence_id
	image = inspection_image
	source = inspection_source


func get_hotspot(hotspot_id: StringName) -> EvidenceHotspotDef:
	for hotspot: EvidenceHotspotDef in hotspots:
		if hotspot.id == hotspot_id:
			return hotspot
	return null


func hotspot_at(normalized_point: Vector2) -> EvidenceHotspotDef:
	for hotspot: EvidenceHotspotDef in hotspots:
		if hotspot.contains_point(normalized_point):
			return hotspot
	return null
