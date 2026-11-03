class_name EvidenceInspectionRuntime
extends RefCounted

## Evidence inspection rules. Progress lives on the evidence object itself
## (EvidenceState); definitions are authored data.
##
## Hotspot branches run through StoryVM as a nested CALL, so an inspection can be
## opened from court or investigation without disturbing the outer branch.

signal inspection_opened(evidence_id: StringName)
signal hotspot_inspected(evidence_id: StringName, hotspot_id: StringName)
signal inspection_completed(evidence_id: StringName)
signal inspection_closed(evidence_id: StringName)
signal story_branch_requested(target_scene: StringName)
signal branch_resumed(hotspot_id: StringName)
signal action_rejected(message: String)

var game_state: GameState
var last_error: String = ""
var debug_logging: bool = false

## Which evidence object is open. UI selection, intentionally not saved.
var active_evidence: StringName

var _definitions: EvidenceInspectionRepository
var _pending_hotspot: EvidenceHotspotDef


func _init(
	runtime_game_state: GameState = null,
	inspection_definitions: EvidenceInspectionRepository = null,
) -> void:
	game_state = runtime_game_state if runtime_game_state != null else GameState.new()
	_definitions = inspection_definitions


func open(evidence_id: StringName) -> bool:
	var definition: EvidenceInspectionDef = current_definition_for(evidence_id)
	if definition == null:
		return _reject("Evidence cannot be inspected: %s" % evidence_id)
	var state: EvidenceState = _evidence_state(evidence_id)
	if state == null or not state.owned:
		return _reject("Evidence is not owned: %s" % evidence_id)
	active_evidence = evidence_id
	_pending_hotspot = null
	_log("OPEN %s" % evidence_id)
	inspection_opened.emit(evidence_id)
	return true


func close() -> bool:
	if active_evidence.is_empty():
		return _reject("No inspection is open.")
	var evidence_id: StringName = active_evidence
	active_evidence = &""
	_pending_hotspot = null
	_log("CLOSE %s" % evidence_id)
	inspection_closed.emit(evidence_id)
	return true


func is_open() -> bool:
	return not active_evidence.is_empty()


func current_definition() -> EvidenceInspectionDef:
	return current_definition_for(active_evidence)


## Authored inspection data, read-only for callers (debugger).
func repository() -> EvidenceInspectionRepository:
	return _definitions


func current_definition_for(evidence_id: StringName) -> EvidenceInspectionDef:
	if _definitions == null or evidence_id.is_empty():
		return null
	return _definitions.get_inspection(evidence_id)


func can_inspect(evidence_id: StringName) -> bool:
	var state: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	return (
		current_definition_for(evidence_id) != null
		and state != null
		and state.owned
	)


## Hotspots whose unlock requirement is satisfied and that are not yet inspected.
func available_hotspots() -> Array[EvidenceHotspotDef]:
	var result: Array[EvidenceHotspotDef]
	var definition: EvidenceInspectionDef = current_definition()
	if definition == null:
		return result
	for hotspot: EvidenceHotspotDef in definition.hotspots:
		if is_hotspot_available(hotspot) and not is_hotspot_inspected(hotspot.id):
			result.append(hotspot)
	return result


func is_hotspot_available(hotspot: EvidenceHotspotDef) -> bool:
	if hotspot == null:
		return false
	if hotspot.unlocked_by.is_empty():
		return true
	return is_hotspot_inspected(hotspot.unlocked_by)


func is_hotspot_inspected(hotspot_id: StringName) -> bool:
	var state: EvidenceState = game_state.evidence.get(active_evidence) as EvidenceState
	return state != null and state.has_inspected(hotspot_id)


func is_complete(evidence_id: StringName = &"") -> bool:
	var target: StringName = evidence_id if not evidence_id.is_empty() else active_evidence
	var state: EvidenceState = game_state.evidence.get(target) as EvidenceState
	return state != null and state.inspection_complete


func inspected_hotspots(evidence_id: StringName) -> Array[StringName]:
	var state: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	return state.inspected_hotspots if state != null else []


## Resolves a hotspot into a story branch. Returns the scene, or "" when rejected.
func inspect(hotspot_id: StringName) -> StringName:
	if active_evidence.is_empty():
		_reject("No inspection is open.")
		return &""
	if _pending_hotspot != null:
		_reject("A hotspot branch is already running.")
		return &""
	var definition: EvidenceInspectionDef = current_definition()
	var hotspot: EvidenceHotspotDef = (
		definition.get_hotspot(hotspot_id) if definition != null else null
	)
	if hotspot == null or hotspot.scene.is_empty():
		_reject("Unknown inspection hotspot: %s" % hotspot_id)
		return &""
	if not is_hotspot_available(hotspot):
		_reject("Inspection hotspot is locked: %s" % hotspot_id)
		return &""
	_pending_hotspot = hotspot
	_log("HOTSPOT %s -> %s" % [hotspot.id, hotspot.scene])
	story_branch_requested.emit(hotspot.scene)
	return hotspot.scene


func resume_after_story_branch() -> bool:
	if _pending_hotspot == null:
		return _reject("No inspection story branch is pending.")
	var hotspot: EvidenceHotspotDef = _pending_hotspot
	_pending_hotspot = null
	var evidence_id: StringName = active_evidence
	var state: EvidenceState = _evidence_state(evidence_id)
	if state == null:
		return _fail("Inspection evidence disappeared: %s" % evidence_id)
	state.mark_inspected(hotspot.id)
	_log("INSPECTED %s %s" % [evidence_id, hotspot.id])
	hotspot_inspected.emit(evidence_id, hotspot.id)
	branch_resumed.emit(hotspot.id)
	refresh_completion(evidence_id)
	if state.inspection_complete:
		_log("COMPLETE %s" % evidence_id)
		inspection_completed.emit(evidence_id)
	return true


## Recomputes the completion flag from the inspected hotspots.
func refresh_completion(evidence_id: StringName) -> void:
	var state: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if state == null:
		return
	state.inspection_complete = _all_hotspots_inspected(evidence_id)


func reset_progress(evidence_id: StringName) -> bool:
	var state: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if state == null:
		return _reject("Unknown evidence: %s" % evidence_id)
	state.inspected_hotspots.clear()
	state.inspection_complete = false
	return true


func _all_hotspots_inspected(evidence_id: StringName) -> bool:
	var definition: EvidenceInspectionDef = current_definition_for(evidence_id)
	var state: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if definition == null or state == null or definition.hotspots.is_empty():
		return false
	for hotspot: EvidenceHotspotDef in definition.hotspots:
		if not state.has_inspected(hotspot.id):
			return false
	return true


func _evidence_state(evidence_id: StringName) -> EvidenceState:
	return game_state.evidence.get(evidence_id) as EvidenceState


func _reject(message: String) -> bool:
	last_error = message
	action_rejected.emit(message)
	if debug_logging:
		push_warning("[Inspection] %s" % message)
	return false


func _fail(message: String) -> bool:
	last_error = message
	action_rejected.emit(message)
	if debug_logging:
		push_error("[Inspection] %s" % message)
	return false


func _log(message: String) -> void:
	if debug_logging:
		print("[Inspection] %s" % message)
