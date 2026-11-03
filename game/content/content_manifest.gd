class_name ContentManifest
extends RefCounted

## Read-side view of story_build/manifest.json. The compiler owns the file; the
## runtime only uses it to verify that the build it loaded is the build it
## expects.

const FORMAT_VERSION: int = 1
const DEFAULT_PATH: String = "res://story_build/manifest.json"

var error_message: String = ""
var format_version: int = 0
var chapters: PackedStringArray = PackedStringArray()
var scenes: PackedStringArray = PackedStringArray()
var testimonies: PackedStringArray = PackedStringArray()
var characters: PackedStringArray = PackedStringArray()
var evidence: PackedStringArray = PackedStringArray()
var locations: PackedStringArray = PackedStringArray()
var backgrounds: PackedStringArray = PackedStringArray()
var bgm: PackedStringArray = PackedStringArray()
var sfx: PackedStringArray = PackedStringArray()


func load_file(path: String = DEFAULT_PATH) -> bool:
	error_message = ""
	if not FileAccess.file_exists(path):
		return _fail("Content manifest does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open content manifest: %s" % path)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return _fail("Malformed content manifest: %s" % path)
	var data: Dictionary = json.data
	var version: Variant = data.get("format_version")
	if not version is float and not version is int:
		return _fail("Content manifest requires an integer format_version.")
	if float(version) != floorf(float(version)):
		return _fail("Content manifest format_version must be an integer.")
	format_version = int(version)
	if format_version > FORMAT_VERSION:
		return _fail(
			"Content manifest format %d is newer than this build supports (%d)."
			% [format_version, FORMAT_VERSION]
		)
	chapters = _strings(data.get("chapters"))
	scenes = _strings(data.get("scenes"))
	testimonies = _strings(data.get("testimonies"))
	characters = _strings(data.get("characters"))
	evidence = _strings(data.get("evidence"))
	locations = _strings(data.get("locations"))
	backgrounds = _strings(data.get("backgrounds"))
	bgm = _strings(data.get("bgm"))
	sfx = _strings(data.get("sfx"))
	return true


func has_scene(scene_id: StringName) -> bool:
	return scenes.has(String(scene_id))


func summary() -> String:
	return "%d scenes / %d testimonies / %d characters / %d evidence / %d locations" % [
		scenes.size(),
		testimonies.size(),
		characters.size(),
		evidence.size(),
		locations.size(),
	]


func _strings(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is Array:
		for entry: Variant in value:
			if entry is String:
				result.append(entry)
	return result


func _fail(message: String) -> bool:
	error_message = message
	return false
