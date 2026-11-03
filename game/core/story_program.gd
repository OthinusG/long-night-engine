class_name StoryProgram
extends RefCounted

const SCHEMA_VERSION: int = 1

var schema_version: int = SCHEMA_VERSION
var entry_scene: StringName
var scenes: Dictionary[StringName, StoryScene]
var testimonies: Dictionary[StringName, TestimonyDef]
var locations: Dictionary[StringName, LocationDef]


func _init(program_entry_scene: StringName = &"") -> void:
	entry_scene = program_entry_scene


func add_scene(scene: StoryScene) -> void:
	scenes[scene.id] = scene


func has_scene(scene_id: StringName) -> bool:
	return scenes.has(scene_id)


func get_scene(scene_id: StringName) -> StoryScene:
	return scenes.get(scene_id) as StoryScene


func add_testimony(testimony: TestimonyDef) -> void:
	testimonies[testimony.id] = testimony


func get_testimony(testimony_id: StringName) -> TestimonyDef:
	return testimonies.get(testimony_id) as TestimonyDef


func add_location(location: LocationDef) -> void:
	locations[location.id] = location


func get_location(location_id: StringName) -> LocationDef:
	return locations.get(location_id) as LocationDef
