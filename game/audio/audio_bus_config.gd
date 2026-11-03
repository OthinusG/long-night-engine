class_name AudioBusConfig
extends RefCounted

## Owns the logical audio channels. The routing is created in code so the project
## needs no bus layout resource.

const MASTER: StringName = &"Master"
const BGM: StringName = &"BGM"
const SFX: StringName = &"SFX"
const VOICE: StringName = &"Voice"
## linear_to_db(0.0) is -inf, which is a poor value to hand to the mixer.
const SILENT_DB: float = -80.0


static func buses() -> Array[StringName]:
	return [MASTER, BGM, SFX, VOICE]


## Creates the non-master buses when missing and routes them to Master.
static func ensure_buses() -> void:
	for bus_name: StringName in buses():
		if bus_name == MASTER:
			continue
		if bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, MASTER)


static func bus_index(bus_name: StringName) -> int:
	return AudioServer.get_bus_index(bus_name)


static func set_volume(bus_name: StringName, linear: float) -> void:
	var index: int = bus_index(bus_name)
	if index == -1:
		return
	var value: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(value) if value > 0.0 else SILENT_DB)


static func get_volume(bus_name: StringName) -> float:
	var index: int = bus_index(bus_name)
	if index == -1:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))
