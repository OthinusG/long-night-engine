class_name ContentRegistry
extends RefCounted

## Canonical runtime lookup for authored content. It owns the data/*.json
## catalogs that presentation needs (characters, expressions, backgrounds, BGM,
## SFX) and delegates evidence and locations to the systems that already own
## them, so no catalog is loaded twice.

const DEFAULT_DATA_ROOT: String = "res://data"

var error_message: String = ""

var _display_names: Dictionary[StringName, String] = {}
var _expressions: Dictionary[StringName, PackedStringArray] = {}
var _portrait_paths: Dictionary[StringName, String] = {}
var _background_paths: Dictionary[StringName, String] = {}
var _bgm_paths: Dictionary[StringName, String] = {}
var _sfx_paths: Dictionary[StringName, String] = {}
var _program: StoryProgram
var _evidence: EvidenceRepository


## Attaches the systems that already own evidence and locations.
func attach(program: StoryProgram, evidence: EvidenceRepository) -> void:
	_program = program
	_evidence = evidence


func load_catalogs(data_root: String = DEFAULT_DATA_ROOT) -> bool:
	error_message = ""
	_display_names.clear()
	_expressions.clear()
	_portrait_paths.clear()
	_background_paths.clear()
	_bgm_paths.clear()
	_sfx_paths.clear()
	if not _load_characters(data_root.path_join("characters.json")):
		return false
	if not _load_expressions(data_root.path_join("expressions.json")):
		return false
	if not _load_asset_catalog(data_root.path_join("backgrounds.json"), "backgrounds", _background_paths):
		return false
	if not _load_asset_catalog(data_root.path_join("bgm.json"), "bgm", _bgm_paths):
		return false
	if not _load_asset_catalog(data_root.path_join("sfx.json"), "sfx", _sfx_paths):
		return false
	return true


# --- characters ---------------------------------------------------------------

func has_character(character_id: StringName) -> bool:
	return _display_names.has(character_id)


func character_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for character_id: StringName in _display_names:
		ids.append(character_id)
	ids.sort()
	return ids


func get_display_name(character_id: StringName) -> String:
	return _display_names.get(character_id, "[MISSING CHARACTER: %s]" % character_id)


func expressions_for(character_id: StringName) -> PackedStringArray:
	return _expressions.get(character_id, PackedStringArray())


func has_expression(character_id: StringName, expression_id: StringName) -> bool:
	return expressions_for(character_id).has(String(expression_id))


## The expression to fall back to when a request names none or an unknown one.
func default_expression(character_id: StringName) -> StringName:
	var expressions: PackedStringArray = expressions_for(character_id)
	for candidate: String in expressions:
		if candidate == "calm":
			return &"calm"
	return StringName(expressions[0]) if not expressions.is_empty() else &""


## Explicit portrait override authored in expressions.json, empty when the
## convention in AssetRegistry should be used instead.
func portrait_override(character_id: StringName, expression_id: StringName) -> String:
	return _portrait_paths.get(_portrait_key(character_id, expression_id), "")


# --- assets -------------------------------------------------------------------

func has_background(background_id: StringName) -> bool:
	return _background_paths.has(background_id)


func background_ids() -> Array[StringName]:
	return _sorted_keys(_background_paths)


func background_path(background_id: StringName) -> String:
	return _background_paths.get(background_id, "")


func has_bgm(bgm_id: StringName) -> bool:
	return _bgm_paths.has(bgm_id)


func bgm_ids() -> Array[StringName]:
	return _sorted_keys(_bgm_paths)


func bgm_path(bgm_id: StringName) -> String:
	return _bgm_paths.get(bgm_id, "")


func has_sfx(sfx_id: StringName) -> bool:
	return _sfx_paths.has(sfx_id)


func sfx_ids() -> Array[StringName]:
	return _sorted_keys(_sfx_paths)


func sfx_path(sfx_id: StringName) -> String:
	return _sfx_paths.get(sfx_id, "")


# --- delegated content --------------------------------------------------------

func get_evidence(evidence_id: StringName) -> EvidenceDef:
	return _evidence.get_evidence(evidence_id) if _evidence != null else null


func get_location(location_id: StringName) -> LocationDef:
	return _program.get_location(location_id) if _program != null else null


func program() -> StoryProgram:
	return _program


func evidence_repository() -> EvidenceRepository:
	return _evidence


# --- loading ------------------------------------------------------------------

func _load_characters(path: String) -> bool:
	var data: Variant = _read_json(path)
	if data == null:
		return false
	var entries: Variant = (data as Dictionary).get("characters")
	if not entries is Array:
		return _fail("Character registry requires a 'characters' array: %s" % path)
	for value: Variant in entries:
		if not value is Dictionary:
			return _fail("Each character definition must be an object: %s" % path)
		var entry: Dictionary = value
		var id_value: Variant = entry.get("id")
		var name_value: Variant = entry.get("display_name")
		if not id_value is String or not name_value is String:
			return _fail("Each character requires string id and display_name: %s" % path)
		var character_id := StringName(id_value)
		if character_id.is_empty() or _display_names.has(character_id):
			return _fail("Invalid or duplicate character ID: %s" % character_id)
		_display_names[character_id] = name_value
		var portraits: Variant = entry.get("portraits")
		if portraits is Dictionary:
			for expression: Variant in (portraits as Dictionary):
				var portrait_path: Variant = (portraits as Dictionary)[expression]
				if not portrait_path is String:
					return _fail("Portrait override must be a string path: %s" % character_id)
				_portrait_paths[_portrait_key(character_id, StringName(expression))] = portrait_path
	return true


func _load_expressions(path: String) -> bool:
	var data: Variant = _read_json(path)
	if data == null:
		return false
	var entries: Variant = (data as Dictionary).get("expressions")
	if not entries is Dictionary:
		return _fail("Expression registry requires an 'expressions' object: %s" % path)
	for key: Variant in (entries as Dictionary):
		var character_id := StringName(key)
		if not _display_names.has(character_id):
			return _fail("Expressions reference unknown character ID: %s" % character_id)
		var values: Variant = (entries as Dictionary)[key]
		if not values is Array:
			return _fail("Expressions for %s must be an array: %s" % [character_id, path])
		var expressions := PackedStringArray()
		for value: Variant in values:
			var expression_id: String = ""
			var portrait_path: String = ""
			if value is String:
				expression_id = value
			elif value is Dictionary and (value as Dictionary).get("id") is String:
				expression_id = (value as Dictionary)["id"]
				var authored: Variant = (value as Dictionary).get("portrait")
				portrait_path = authored if authored is String else ""
			else:
				return _fail("Expression entries must be IDs or objects with an id: %s" % character_id)
			if expression_id.is_empty() or expressions.has(expression_id):
				return _fail("Invalid or duplicate expression ID: %s / %s" % [character_id, expression_id])
			expressions.append(expression_id)
			if not portrait_path.is_empty():
				_portrait_paths[_portrait_key(character_id, StringName(expression_id))] = portrait_path
		_expressions[character_id] = expressions
	return true


func _load_asset_catalog(
	path: String,
	key: String,
	target: Dictionary[StringName, String],
) -> bool:
	var data: Variant = _read_json(path)
	if data == null:
		return false
	var entries: Variant = (data as Dictionary).get(key)
	if not entries is Array:
		return _fail("Asset catalog requires a '%s' array: %s" % [key, path])
	for value: Variant in entries:
		if not value is Dictionary:
			return _fail("Each '%s' entry must be an object: %s" % [key, path])
		var entry: Dictionary = value
		var id_value: Variant = entry.get("id")
		if not id_value is String or String(id_value).is_empty():
			return _fail("Each '%s' entry requires a string id: %s" % [key, path])
		var asset_id := StringName(id_value)
		if target.has(asset_id):
			return _fail("Duplicate '%s' ID: %s" % [key, asset_id])
		var authored: Variant = entry.get("path")
		if authored != null and not authored is String:
			return _fail("Asset path must be a string: %s / %s" % [key, asset_id])
		target[asset_id] = authored if authored is String else ""
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail("Content catalog does not exist: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Cannot open content catalog: %s" % path)
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_fail("Malformed content catalog: %s" % path)
		return null
	return json.data


func _sorted_keys(source: Dictionary[StringName, String]) -> Array[StringName]:
	var keys: Array[StringName] = []
	for key: StringName in source:
		keys.append(key)
	keys.sort()
	return keys


func _portrait_key(character_id: StringName, expression_id: StringName) -> StringName:
	return StringName("%s_%s" % [character_id, expression_id])


func _fail(message: String) -> bool:
	error_message = message
	return false
