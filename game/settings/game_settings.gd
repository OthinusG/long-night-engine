class_name GameSettings
extends RefCounted

## Player-adjustable settings as typed data.
##
## Settings are never story flags and never part of a save slot: they live in
## their own file (see SettingsManager) and only affect presentation.

const DEFAULT_VOLUME: float = 0.8
const MIN_VOLUME: float = 0.0
const MAX_VOLUME: float = 1.0
## Characters per second; 0.0 means "reveal the whole line instantly".
const DEFAULT_TEXT_SPEED: float = 30.0
const MAX_TEXT_SPEED: float = 30.0
const DEFAULT_AUTO_SPEED: float = 4.0
const MIN_AUTO_SPEED: float = 0.0
const MAX_AUTO_SPEED: float = 8.0
const TEXT_SPEED_LEVELS: Array[float] = [10.0, 18.0, 30.0, 0.0]
const AUTO_SPEED_LEVELS: Array[float] = [8.0, 6.0, 4.0, 0.0]
const DEFAULT_WINDOW_WIDTH: int = 1920
const DEFAULT_WINDOW_HEIGHT: int = 1080

var master_volume: float = DEFAULT_VOLUME
var bgm_volume: float = DEFAULT_VOLUME
var sfx_volume: float = DEFAULT_VOLUME
var voice_volume: float = DEFAULT_VOLUME
var text_speed: float = DEFAULT_TEXT_SPEED
var auto_speed: float = DEFAULT_AUTO_SPEED
var display_mode: DisplaySettings.Mode = DisplaySettings.Mode.WINDOWED
var window_width: int = DEFAULT_WINDOW_WIDTH
var window_height: int = DEFAULT_WINDOW_HEIGHT


func to_dictionary() -> Dictionary:
	return {
		"master_volume": master_volume,
		"bgm_volume": bgm_volume,
		"sfx_volume": sfx_volume,
		"voice_volume": voice_volume,
		"text_speed": text_speed,
		"auto_speed": auto_speed,
		"display_mode": DisplaySettings.mode_to_string(display_mode),
		"window_width": window_width,
		"window_height": window_height,
	}


## Reads settings from an untrusted dictionary. Missing, wrongly typed, or
## out-of-range values fall back to defaults or are clamped; this never fails.
static func from_dictionary(data: Dictionary) -> GameSettings:
	var settings := GameSettings.new()
	settings.master_volume = _read_float(data, "master_volume", DEFAULT_VOLUME, MIN_VOLUME, MAX_VOLUME)
	settings.bgm_volume = _read_float(data, "bgm_volume", DEFAULT_VOLUME, MIN_VOLUME, MAX_VOLUME)
	settings.sfx_volume = _read_float(data, "sfx_volume", DEFAULT_VOLUME, MIN_VOLUME, MAX_VOLUME)
	settings.voice_volume = _read_float(data, "voice_volume", DEFAULT_VOLUME, MIN_VOLUME, MAX_VOLUME)
	settings.text_speed = nearest_level(_read_float(data, "text_speed", DEFAULT_TEXT_SPEED, 0.0, MAX_TEXT_SPEED), TEXT_SPEED_LEVELS)
	settings.auto_speed = nearest_level(_read_float(data, "auto_speed", DEFAULT_AUTO_SPEED, MIN_AUTO_SPEED, MAX_AUTO_SPEED), AUTO_SPEED_LEVELS)
	settings.display_mode = DisplaySettings.mode_from_string(_read_string(data, "display_mode"))
	settings.window_width = _read_int(
		data,
		"window_width",
		DEFAULT_WINDOW_WIDTH,
		DisplaySettings.MIN_WIDTH,
		DisplaySettings.MAX_WIDTH,
	)
	settings.window_height = _read_int(
		data,
		"window_height",
		DEFAULT_WINDOW_HEIGHT,
		DisplaySettings.MIN_HEIGHT,
		DisplaySettings.MAX_HEIGHT,
	)
	return settings


static func nearest_level(value: float, levels: Array[float]) -> float:
	var nearest: float = levels[0]
	var distance: float = absf(value - nearest)
	for level: float in levels:
		if absf(value - level) < distance:
			nearest = level
			distance = absf(value - level)
	return nearest


func duplicate_settings() -> GameSettings:
	return from_dictionary(to_dictionary())


static func _read_float(
	data: Dictionary,
	key: String,
	fallback: float,
	minimum: float,
	maximum: float,
) -> float:
	var value: Variant = data.get(key)
	if value is float or value is int:
		return clampf(float(value), minimum, maximum)
	return fallback


static func _read_int(
	data: Dictionary,
	key: String,
	fallback: int,
	minimum: int,
	maximum: int,
) -> int:
	var value: Variant = data.get(key)
	if value is float or value is int:
		return clampi(int(value), minimum, maximum)
	return fallback


static func _read_string(data: Dictionary, key: String) -> String:
	var value: Variant = data.get(key)
	if value is String:
		return value
	return ""
