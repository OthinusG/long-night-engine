class_name BgmController
extends RefCounted

## One-track BGM playback. Requesting the track that is already playing is a
## no-op unless `restart` is set, so repeated `@bgm` lines never restart the
## music from the top.

const FADE_TWEEN_NAME: String = "bgm_fade"

var current_bgm: StringName = &""
var _player: AudioStreamPlayer
var _tween: Tween


func _init(host: Node) -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BgmPlayer"
	_player.bus = AudioBusConfig.BGM
	host.add_child(_player)


func is_playing(bgm_id: StringName) -> bool:
	return not bgm_id.is_empty() and bgm_id == current_bgm and _player.playing


func stream() -> AudioStream:
	return _player.stream


## Returns false when the request was a deliberate no-op (same track already
## playing) or could not be played.
func play(
	bgm_id: StringName,
	audio_stream: AudioStream,
	fade_seconds: float = 0.0,
	restart: bool = false,
) -> bool:
	if bgm_id.is_empty() or audio_stream == null:
		return false
	if not restart and is_playing(bgm_id) and _player.stream == audio_stream:
		return false
	_kill_tween()
	current_bgm = bgm_id
	_player.stream = audio_stream
	if fade_seconds > 0.0 and _can_tween():
		_player.volume_db = linear_to_db(0.001)
		_player.play()
		_tween = _player.create_tween()
		_tween.tween_property(_player, "volume_db", 0.0, fade_seconds)
	else:
		_player.volume_db = 0.0
		_player.play()
	return true


func stop(fade_seconds: float = 0.0) -> void:
	_kill_tween()
	if fade_seconds > 0.0 and _player.playing and _can_tween():
		_tween = _player.create_tween()
		_tween.tween_property(_player, "volume_db", linear_to_db(0.001), fade_seconds)
		_tween.tween_callback(_player.stop)
	else:
		_player.stop()
	current_bgm = &""


func is_fading() -> bool:
	return _tween != null and _tween.is_valid()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _can_tween() -> bool:
	return _player.is_inside_tree()
