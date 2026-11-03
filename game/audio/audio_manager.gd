class_name AudioManager
extends RefCounted

## Audio facade. Story source and gameplay pass stable IDs only; resolution to a
## file happens here through AssetRegistry.

signal playback_failed(kind: StringName, id: StringName, message: String)

var _assets: AssetRegistry
var _bgm: BgmController
var _sfx: SfxController


func _init(host: Node, assets: AssetRegistry) -> void:
	AudioBusConfig.ensure_buses()
	_assets = assets
	_bgm = BgmController.new(host)
	_sfx = SfxController.new(host)


func play_bgm(bgm_id: StringName) -> bool:
	return fade_bgm(bgm_id, 0.0)


## Fades in the requested track. Repeating the active track is a no-op.
func fade_bgm(bgm_id: StringName, duration: float) -> bool:
	var stream: AudioStream = _assets.resolve_stream(AssetRegistry.Kind.BGM, bgm_id)
	if stream == null:
		return _fail(&"bgm", bgm_id, "Unknown or missing BGM asset.")
	return _bgm.play(bgm_id, stream, duration)


func stop_bgm(fade_seconds: float = 0.0) -> void:
	_bgm.stop(fade_seconds)


func play_sfx(sfx_id: StringName) -> bool:
	var stream: AudioStream = _assets.resolve_stream(AssetRegistry.Kind.SFX, sfx_id)
	if stream == null:
		return _fail(&"sfx", sfx_id, "Unknown or missing SFX asset.")
	return _sfx.play(stream)


func stop_all_sfx() -> void:
	_sfx.stop_all()


func set_bus_volume(bus_name: StringName, linear: float) -> void:
	AudioBusConfig.set_volume(bus_name, linear)


func get_bus_volume(bus_name: StringName) -> float:
	return AudioBusConfig.get_volume(bus_name)


func current_bgm() -> StringName:
	return _bgm.current_bgm


func is_bgm_playing(bgm_id: StringName) -> bool:
	return _bgm.is_playing(bgm_id)


func _fail(kind: StringName, id: StringName, message: String) -> bool:
	# An unknown audio ID is a content error the compiler already rejects; at
	# runtime it must not stop the story, but it is never silent.
	push_warning("[Audio] %s" % message)
	playback_failed.emit(kind, id, message)
	return false
