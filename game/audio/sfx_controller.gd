class_name SfxController
extends RefCounted

## Small fixed pool so short sounds can overlap. Four players are enough for a
## courtroom game; a real pool would only be needed if profiling said so.

const VOICE_COUNT: int = 4

var _voices: Array[AudioStreamPlayer] = []
var _next: int = 0


func _init(host: Node) -> void:
	for index: int in range(VOICE_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % index
		player.bus = AudioBusConfig.SFX
		host.add_child(player)
		_voices.append(player)


func play(audio_stream: AudioStream, volume_db: float = 0.0) -> bool:
	if audio_stream == null:
		return false
	var player: AudioStreamPlayer = _voices[_next]
	_next = (_next + 1) % VOICE_COUNT
	player.stream = audio_stream
	player.volume_db = volume_db
	player.play()
	return true


func stop_all() -> void:
	for player: AudioStreamPlayer in _voices:
		player.stop()


func active_count() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _voices:
		if player.playing:
			count += 1
	return count


func voice_count() -> int:
	return _voices.size()
