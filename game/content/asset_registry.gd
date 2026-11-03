class_name AssetRegistry
extends RefCounted

## Maps stable authored IDs to resource paths. Story source and gameplay only
## ever see IDs; this is the single place that knows the file convention.
##
## Convention: `<root><id>.<extension>`, searched in the order below. An explicit
## path authored in the data catalogs always wins (see ContentRegistry).

enum Kind { BACKGROUND, PORTRAIT, ICON, DETAIL, BGM, SFX }

const PLACEHOLDER_PATH: String = "res://assets/placeholders/missing_art.png"

var missing_ids: Array[String] = []

var _content: ContentRegistry


func _init(content: ContentRegistry = null) -> void:
	_content = content


static func root_for(kind: Kind) -> String:
	match kind:
		Kind.BACKGROUND:
			return "res://assets/backgrounds/"
		Kind.PORTRAIT:
			return "res://assets/portraits/"
		Kind.ICON:
			return "res://assets/evidence/"
		Kind.DETAIL:
			return "res://assets/evidence/detail/"
		Kind.BGM:
			return "res://assets/audio/bgm/"
		_:
			return "res://assets/audio/sfx/"


static func extensions_for(kind: Kind) -> PackedStringArray:
	match kind:
		Kind.BACKGROUND:
			return PackedStringArray(["webp", "png", "jpg", "jpeg"])
		Kind.PORTRAIT, Kind.ICON, Kind.DETAIL:
			return PackedStringArray(["webp", "png"])
		Kind.BGM:
			return PackedStringArray(["ogg", "mp3", "wav"])
		_:
			return PackedStringArray(["ogg", "wav", "mp3"])


## The paths the convention would try, in order. Pure, so it is testable without
## shipping art.
static func candidate_paths(kind: Kind, id: StringName) -> PackedStringArray:
	var paths := PackedStringArray()
	if id.is_empty():
		return paths
	for extension: String in extensions_for(kind):
		paths.append("%s%s.%s" % [root_for(kind), id, extension])
	return paths


static func portrait_id(character_id: StringName, expression_id: StringName) -> StringName:
	return StringName("%s_%s" % [character_id, expression_id])


## Resolved resource path, or "" when the asset does not exist. A missing asset
## is recorded so development builds can report it once.
func resolve(kind: Kind, id: StringName) -> String:
	var authored: String = _authored_path(kind, id)
	if not authored.is_empty():
		if ResourceLoader.exists(authored):
			return authored
		_record_missing(kind, id, authored)
		return ""
	for candidate: String in candidate_paths(kind, id):
		if ResourceLoader.exists(candidate):
			return candidate
	_record_missing(kind, id, "")
	return ""


func resolve_portrait(character_id: StringName, expression_id: StringName) -> String:
	return resolve(Kind.PORTRAIT, portrait_id(character_id, expression_id))


func resolve_texture(kind: Kind, id: StringName) -> Texture2D:
	var path: String = resolve(kind, id)
	return load(path) as Texture2D if not path.is_empty() else null


func resolve_stream(kind: Kind, id: StringName) -> AudioStream:
	var path: String = resolve(kind, id)
	return load(path) as AudioStream if not path.is_empty() else null


## Placeholder shown while real art is still in production.
func placeholder_texture() -> Texture2D:
	return load(PLACEHOLDER_PATH) as Texture2D


func missing_asset_count() -> int:
	return missing_ids.size()


func reset_missing() -> void:
	missing_ids.clear()


func _authored_path(kind: Kind, id: StringName) -> String:
	if _content == null:
		return ""
	match kind:
		Kind.BACKGROUND:
			return _content.background_path(id)
		Kind.BGM:
			return _content.bgm_path(id)
		Kind.SFX:
			return _content.sfx_path(id)
		_:
			# ponytail: portraits/icons/detail art use the convention only; add an
			# authored override when a real asset needs a path the convention cannot
			# express.
			return ""


func _record_missing(kind: Kind, id: StringName, authored: String) -> void:
	var entry: String = "%s:%s" % [Kind.keys()[kind].to_lower(), id]
	if authored.is_empty():
		missing_ids.append(entry)
	else:
		missing_ids.append("%s (authored %s)" % [entry, authored])
