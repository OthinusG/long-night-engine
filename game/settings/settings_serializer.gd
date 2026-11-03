class_name SettingsSerializer
extends RefCounted

## JSON persistence for GameSettings.
##
## The document carries a format version and a deterministic key order, and
## reading it can never fail: a missing, malformed, or unreadable file yields
## defaults with a warning (unlike structural story IR, which must fail loudly).

const FORMAT_VERSION: int = 1


## Keys are written in Godot's sorted order, so the file is byte-stable for the
## same settings no matter how the dictionary was built.
static func to_json(settings: GameSettings) -> String:
	var document: Dictionary = {"format_version": FORMAT_VERSION}
	document.merge(settings.to_dictionary())
	return JSON.stringify(document, "  ") + "\n"


static func from_json(text: String) -> GameSettings:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return GameSettings.from_dictionary(parsed)
	push_warning("[Settings] Invalid settings JSON, using defaults")
	return GameSettings.new()


static func load_file(path: String) -> GameSettings:
	if not FileAccess.file_exists(path):
		push_warning("[Settings] Settings file missing, using defaults: %s" % path)
		return GameSettings.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning(
			"[Settings] Cannot read settings file, using defaults: %s (error %d)"
			% [path, FileAccess.get_open_error()]
		)
		return GameSettings.new()
	var text := file.get_as_text()
	file.close()
	return from_json(text)


static func save_file(path: String, settings: GameSettings) -> bool:
	var directory := path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning(
			"[Settings] Cannot write settings file: %s (error %d)"
			% [path, FileAccess.get_open_error()]
		)
		return false
	file.store_string(to_json(settings))
	file.close()
	return true
