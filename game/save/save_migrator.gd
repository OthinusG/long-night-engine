class_name SaveMigrator
extends RefCounted

## Applies sequential schema migrations to a raw save payload before validation.
##
## Version 2 filled the previously reserved, always-empty "investigation" object
## with real investigation state. Later schema changes register one step per
## version instead of branching inside SaveManager or the validator.

var error_message: String = ""
var _steps: Dictionary[int, Callable]


func _init() -> void:
	register_step(1, func(data: Dictionary) -> Dictionary:
		data["investigation"] = {
			"active": false,
			"mode": InvestigationState.Mode.keys()[InvestigationState.Mode.INACTIVE],
			"location": "",
			"character": "",
			"visited_locations": [],
			"locations": {},
		}
		return data
	)
	register_step(2, func(data: Dictionary) -> Dictionary:
		data["procedure"] = {
			"active": false,
			"context_id": "",
			"resolved": false,
			"resolved_action_id": "",
			"visited_actions": [],
		}
		var evidence: Variant = data.get("evidence", {})
		if evidence is Dictionary:
			for evidence_key: Variant in evidence:
				if not evidence[evidence_key] is Dictionary:
					continue
				var entry: Dictionary = evidence[evidence_key]
				entry["inspected_hotspots"] = entry.get("inspected_hotspots", [])
				entry["inspection_complete"] = entry.get("inspection_complete", false)
		return data
	)


func register_step(from_version: int, step: Callable) -> void:
	assert(from_version >= 0, "Migration source version must not be negative")
	assert(step.is_valid(), "Migration step must be callable")
	_steps[from_version] = step


func migrate(data: Dictionary) -> Dictionary:
	error_message = ""
	var version_value: Variant = data.get("schema_version")
	if not (version_value is int or version_value is float):
		return _fail({}, "Save requires a numeric schema_version.")
	var version: int = int(version_value)
	if version < 0:
		return _fail({}, "Save schema_version must not be negative.")
	if version > GameState.SAVE_SCHEMA_VERSION:
		return _fail(
			{},
			"Save schema_version %d is newer than this build (%d)."
			% [version, GameState.SAVE_SCHEMA_VERSION]
		)

	while version < GameState.SAVE_SCHEMA_VERSION:
		if not _steps.has(version):
			return _fail({}, "No migration registered from schema_version %d." % version)
		var step: Callable = _steps[version]
		var migrated: Variant = step.call(data)
		if not migrated is Dictionary:
			return _fail({}, "Migration from schema_version %d failed." % version)
		data = migrated
		version += 1
		data["schema_version"] = version
	return data


func _fail(result: Dictionary, message: String) -> Dictionary:
	error_message = message
	return result
