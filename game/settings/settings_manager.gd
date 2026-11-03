class_name SettingsManager
extends RefCounted

## Owns the live GameSettings, their file, and their projection onto the
## AudioServer buses and the main window.
##
## Settings are stored separately from game saves and are allowed to fall back
## to defaults, so a broken settings file can never block the game.

signal settings_changed(settings: GameSettings)

const DEFAULT_PATH: String = "user://settings.json"
const AUDIO_BUSES: Array[StringName] = [
	AudioBusConfig.MASTER,
	AudioBusConfig.BGM,
	AudioBusConfig.SFX,
	AudioBusConfig.VOICE,
]

var settings: GameSettings
var path: String = DEFAULT_PATH
var last_error: String = ""


func _init(settings_path: String = DEFAULT_PATH) -> void:
	path = settings_path
	settings = GameSettings.new()
	load_settings()


## Returns false when the stored file could not be read and defaults were used.
func load_settings() -> bool:
	var has_file := FileAccess.file_exists(path)
	settings = SettingsSerializer.load_file(path)
	last_error = "" if has_file else "settings file missing: %s" % path
	apply_all()
	return has_file


func save() -> bool:
	if SettingsSerializer.save_file(path, settings):
		last_error = ""
		return true
	last_error = "cannot write settings file: %s" % path
	return false


## Creates the BGM/SFX/Voice buses if the audio layout does not define them yet
## and pushes all four volumes onto the AudioServer.
func apply_audio() -> void:
	# AudioBusConfig owns the bus layout and the dB conversion.
	AudioBusConfig.ensure_buses()
	for bus_name: StringName in AUDIO_BUSES:
		AudioBusConfig.set_volume(bus_name, get_volume(bus_name))


func apply_display() -> void:
	DisplaySettings.apply(settings.display_mode, settings.window_width, settings.window_height)


func apply_all() -> void:
	apply_audio()
	apply_display()


## Updates one bus setting, applies it immediately, and notifies listeners.
func set_volume(bus_name: StringName, linear: float) -> void:
	var value := clampf(linear, GameSettings.MIN_VOLUME, GameSettings.MAX_VOLUME)
	match bus_name:
		&"Master":
			settings.master_volume = value
		&"BGM":
			settings.bgm_volume = value
		&"SFX":
			settings.sfx_volume = value
		&"Voice":
			settings.voice_volume = value
		_:
			push_warning("[Settings] Unknown audio bus: %s" % bus_name)
			return
	AudioBusConfig.set_volume(bus_name, value)
	settings_changed.emit(settings)


func get_volume(bus_name: StringName) -> float:
	match bus_name:
		&"Master":
			return settings.master_volume
		&"BGM":
			return settings.bgm_volume
		&"SFX":
			return settings.sfx_volume
		&"Voice":
			return settings.voice_volume
	push_warning("[Settings] Unknown audio bus: %s" % bus_name)
	return 0.0


## Text speed only affects presentation, so there is no AudioServer projection.
func set_text_speed(characters_per_second: float) -> void:
	settings.text_speed = clampf(characters_per_second, 0.0, GameSettings.MAX_TEXT_SPEED)
	settings_changed.emit(settings)


func set_auto_speed(speed: float) -> void:
	settings.auto_speed = clampf(speed, GameSettings.MIN_AUTO_SPEED, GameSettings.MAX_AUTO_SPEED)
	settings_changed.emit(settings)


func reset_to_defaults() -> void:
	settings = GameSettings.new()
	apply_all()
	settings_changed.emit(settings)


