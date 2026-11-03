class_name StoryDebugger
extends RefCounted

## Development-only story tools: inspect canonical state and enter any story
## location without replaying the game.
##
## Every mutation goes through the runtime that owns it (StoryVM, CourtRuntime) or
## writes typed domain state directly. Nothing here is player-facing, and no
## gameplay code may depend on this class.

signal state_changed

const PRESET_PATH: String = "res://data/debug_presets.json"
const FAST_FORWARD_LINE_LIMIT: int = 1000

var last_message: String = ""
var error_message: String = ""

var game_state: GameState
## Assigned by the host once the presentation layer exists; the dump then also
## reports what is currently on screen and which track is playing (spec 11.24).
## It stays null in headless tests, where there is no visual layer.
var presentation: PresentationCoordinator
var story_vm: StoryVM
var court_runtime: CourtRuntime
var investigation_runtime: InvestigationRuntime
var procedure_runtime: ProcedureRuntime
var inspection_runtime: EvidenceInspectionRuntime
var program: StoryProgram
var evidence_repository: EvidenceRepository

var _presets: Dictionary[StringName, Dictionary]


func _init(
	runtime_game_state: GameState,
	runtime_story_vm: StoryVM,
	runtime_court: CourtRuntime,
	runtime_investigation: InvestigationRuntime,
	runtime_procedure: ProcedureRuntime,
	runtime_inspection: EvidenceInspectionRuntime,
	runtime_program: StoryProgram,
	runtime_evidence: EvidenceRepository,
) -> void:
	game_state = runtime_game_state
	story_vm = runtime_story_vm
	court_runtime = runtime_court
	investigation_runtime = runtime_investigation
	procedure_runtime = runtime_procedure
	inspection_runtime = runtime_inspection
	program = runtime_program
	evidence_repository = runtime_evidence


# --- presets -----------------------------------------------------------------

## Loads optional debug presets. A broken preset file must never break gameplay,
## so the failure is reported instead of fatal.
func load_presets(path: String = PRESET_PATH) -> bool:
	error_message = ""
	_presets.clear()
	if not FileAccess.file_exists(path):
		return _fail("Debug preset file does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open debug preset file: %s" % path)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return _fail("Malformed debug presets at line %d: %s" % [
			json.get_error_line(),
			json.get_error_message(),
		])
	file.close()
	if not json.data is Dictionary:
		return _fail("Debug preset root must be an object.")
	var entries: Variant = (json.data as Dictionary).get("presets")
	if not entries is Array:
		return _fail("Debug presets require a 'presets' array.")
	for value: Variant in entries:
		if not value is Dictionary:
			return _fail("Each debug preset must be an object.")
		var preset: Dictionary = value
		if not preset.get("id") is String or String(preset["id"]).is_empty():
			return _fail("Each debug preset requires a string id.")
		_presets[StringName(preset["id"])] = preset
	error_message = ""
	return true


func preset_ids() -> Array[StringName]:
	var ids: Array[StringName]
	ids.assign(_presets.keys())
	ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return ids


## Establishes the state a preset declares, then jumps to its target.
func apply_preset(preset_id: StringName) -> bool:
	var preset: Dictionary = _presets.get(preset_id, {})
	if preset.is_empty():
		return _fail("Unknown debug preset: %s" % preset_id)
	var flags: Variant = preset.get("flags", {})
	if flags is Dictionary:
		for flag_key: Variant in flags:
			game_state.flags[StringName(flag_key)] = flags[flag_key]
	var evidence: Variant = preset.get("evidence", [])
	if evidence is Array:
		for evidence_id: Variant in evidence:
			add_evidence(StringName(evidence_id))
	var versions: Variant = preset.get("evidence_versions", {})
	if versions is Dictionary:
		for evidence_key: Variant in versions:
			set_evidence_version(StringName(evidence_key), StringName(versions[evidence_key]))

	var statement: Variant = preset.get("statement")
	var testimony: Variant = preset.get("testimony")
	var scene: Variant = preset.get("scene")
	if statement is String and testimony is String:
		return jump_to_statement(StringName(testimony), StringName(statement))
	if testimony is String:
		return jump_to_testimony(StringName(testimony))
	if scene is String:
		return jump_to_scene(StringName(scene))
	return _fail("Debug preset '%s' has no jump target." % preset_id)


# --- teleport ----------------------------------------------------------------

## Debug teleport: drops incompatible transient state, then runs the target scene
## from its first instruction until the story blocks.
func jump_to_scene(scene_id: StringName) -> bool:
	if program == null or program.get_scene(scene_id) == null:
		return _fail("Unknown scene: %s" % scene_id)
	_clear_court_session()
	if investigation_runtime.state.active:
		investigation_runtime.end_investigation()
	if procedure_runtime != null and procedure_runtime.state.active:
		procedure_runtime.end_procedure()
	if inspection_runtime != null and inspection_runtime.is_open():
		inspection_runtime.close()
	story_vm.start(scene_id)
	if game_state.story.runtime_state == StoryState.RuntimeState.ERROR:
		return _fail("Jump to scene '%s' failed: %s" % [scene_id, story_vm.last_error])
	return _ok("Scene %s -> %s" % [scene_id, story_state_name()])


func jump_to_testimony(testimony_id: StringName) -> bool:
	var definition: TestimonyDef = program.get_testimony(testimony_id)
	if definition == null:
		return _fail("Unknown testimony: %s" % testimony_id)
	if definition.statements.is_empty():
		return _fail("Testimony '%s' has no statements." % testimony_id)
	return _start_testimony(definition, definition.statements[0].id)


func jump_to_statement(testimony_id: StringName, statement_id: StringName) -> bool:
	var definition: TestimonyDef = program.get_testimony(testimony_id)
	if definition == null:
		return _fail("Unknown testimony: %s" % testimony_id)
	if not definition.statements.is_empty():
		var known: bool = false
		for statement: StatementDef in definition.statements:
			if statement.id == statement_id:
				known = true
				break
		if not known:
			return _fail("Testimony '%s' has no statement '%s'." % [testimony_id, statement_id])
	return _start_testimony(definition, statement_id)


func _start_testimony(definition: TestimonyDef, statement_id: StringName) -> bool:
	# The main story must wait somewhere valid: after the testimony it resumes
	# from the current position, exactly like a story-driven testimony.
	if game_state.story.current_scene.is_empty():
		return _fail("Jump into a scene before jumping into a testimony.")
	_clear_court_session()
	if not story_vm.restore_position(StoryState.RuntimeState.WAIT_COURT, false):
		return _fail("Cannot park the story for debugging: %s" % story_vm.last_error)
	if not court_runtime.start_testimony(definition):
		return _fail("Cannot start testimony '%s': %s" % [definition.id, court_runtime.last_error])
	_finish_testimony_preview()
	if statement_id != definition.statements[0].id:
		if not court_runtime.debug_select_statement(statement_id):
			return _fail("Cannot select statement '%s': %s" % [statement_id, court_runtime.last_error])
	return _ok("Testimony %s statement %s" % [
		definition.id,
		game_state.court.active_testimony.current_statement_id,
	])


# --- investigation -----------------------------------------------------------

## Teleports into an investigation location: drops incompatible runtime state,
## parks the main story, then starts the investigation.
func jump_to_location(location_id: StringName) -> bool:
	if program.get_location(location_id) == null:
		return _fail("Unknown location: %s" % location_id)
	if game_state.story.current_scene.is_empty():
		return _fail("Jump into a scene before jumping into a location.")
	_clear_court_session()
	if investigation_runtime.state.active:
		investigation_runtime.end_investigation()
	if not story_vm.restore_position(StoryState.RuntimeState.WAIT_INVESTIGATION, false):
		return _fail("Cannot park the story for debugging: %s" % story_vm.last_error)
	if not investigation_runtime.start_investigation(location_id):
		return _fail("Cannot start the investigation: %s" % investigation_runtime.last_error)
	return _ok("Investigation at %s" % location_id)


## Ends the investigation and lets the main story continue.
func end_investigation() -> bool:
	if not investigation_runtime.state.active:
		return _fail("No investigation is active.")
	if not investigation_runtime.end_investigation():
		return _fail("Cannot end the investigation: %s" % investigation_runtime.last_error)
	if game_state.story.runtime_state == StoryState.RuntimeState.WAIT_INVESTIGATION:
		story_vm.resume_from_investigation()
	return _ok("Investigation ended -> %s" % story_state_name())


func unlock_topic(topic_id: StringName) -> bool:
	if not investigation_runtime.unlock_topic(topic_id):
		return _fail("Cannot unlock topic '%s': %s" % [topic_id, investigation_runtime.last_error])
	return _ok("Unlocked topic %s" % topic_id)


func set_hotspot_examined(hotspot_id: StringName, examined: bool) -> bool:
	var location: LocationDef = investigation_runtime.current_location()
	if location == null:
		return _fail("No investigation location is active.")
	if location.get_hotspot(hotspot_id) == null:
		return _fail("Unknown hotspot: %s" % hotspot_id)
	var location_state: LocationState = game_state.investigation.ensure_location_state(location.id)
	if examined:
		location_state.mark_examined(hotspot_id)
	else:
		location_state.examined_hotspots.erase(hotspot_id)
	return _ok("%s hotspot %s" % ["Examined" if examined else "Cleared", hotspot_id])


# --- procedure and inspection -------------------------------------------------

## Teleports into a procedure context: drops incompatible runtime state, parks the
## main story, then activates the context.
func jump_to_procedure(context_id: StringName) -> bool:
	var context: ProcedureContext = (
		procedure_runtime.repository().get_context(context_id)
		if procedure_runtime != null and procedure_runtime.repository() != null
		else null
	)
	if context == null:
		return _fail("Unknown procedure context: %s" % context_id)
	if game_state.story.current_scene.is_empty():
		return _fail("Jump into a scene before jumping into a procedure.")
	_clear_court_session()
	if investigation_runtime.state.active:
		investigation_runtime.end_investigation()
	if procedure_runtime.state.active:
		procedure_runtime.end_procedure()
	if not story_vm.restore_position(StoryState.RuntimeState.WAIT_PROCEDURE, false):
		return _fail("Cannot park the story for debugging: %s" % story_vm.last_error)
	if not procedure_runtime.start_context(context_id):
		return _fail("Cannot start the procedure: %s" % procedure_runtime.last_error)
	return _ok("Procedure %s" % context_id)


func set_hotspot_inspected(
	evidence_id: StringName,
	hotspot_id: StringName,
	inspected: bool,
) -> bool:
	if inspection_runtime == null:
		return _fail("Evidence inspection is not available.")
	var definition: EvidenceInspectionDef = inspection_runtime.current_definition_for(evidence_id)
	if definition == null or definition.get_hotspot(hotspot_id) == null:
		return _fail("Unknown inspection hotspot: %s" % hotspot_id)
	var state: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if state == null:
		state = EvidenceState.new(evidence_id)
		game_state.evidence[evidence_id] = state
	if inspected:
		state.mark_inspected(hotspot_id)
	else:
		state.inspected_hotspots.erase(hotspot_id)
	inspection_runtime.refresh_completion(evidence_id)
	return _ok("%s hotspot %s" % ["Inspected" if inspected else "Cleared", hotspot_id])


# --- flow control ------------------------------------------------------------
## Auto-advances dialogue until the story blocks on gameplay, finishes, or fails.
func fast_forward() -> bool:
	if game_state.story.runtime_state != StoryState.RuntimeState.WAIT_DIALOGUE:
		return _fail("Fast forward requires a waiting dialogue line (now: %s)." % story_state_name())
	var lines: int = 0
	while game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		story_vm.resume_dialogue()
		lines += 1
		if lines > FAST_FORWARD_LINE_LIMIT:
			return _fail("Fast forward stopped after %d lines." % FAST_FORWARD_LINE_LIMIT)
	if game_state.story.runtime_state == StoryState.RuntimeState.ERROR:
		return _fail("Fast forward hit a story error: %s" % story_vm.last_error)
	_finish_testimony_preview()
	return _ok("Fast forwarded %d lines to %s" % [lines, story_state_name()])


func _finish_testimony_preview() -> void:
	while court_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		court_runtime.advance_preview()


func pause() -> bool:
	if game_state.story.runtime_state != StoryState.RuntimeState.RUNNING:
		return _fail("Pause requires a running story (now: %s)." % story_state_name())
	story_vm.pause()
	return _ok("Paused")


func resume() -> bool:
	if game_state.story.runtime_state != StoryState.RuntimeState.PAUSED:
		return _fail("Resume requires a paused story (now: %s)." % story_state_name())
	story_vm.resume()
	if game_state.story.runtime_state == StoryState.RuntimeState.ERROR:
		return _fail("Resume failed: %s" % story_vm.last_error)
	return _ok("Resumed -> %s" % story_state_name())


# --- domain edits ------------------------------------------------------------

func set_flag(flag_id: StringName, value: Variant) -> bool:
	if flag_id.is_empty():
		return _fail("Flag name is required.")
	game_state.flags[flag_id] = value
	return _ok("Flag %s = %s" % [flag_id, value])


func clear_flag(flag_id: StringName) -> bool:
	if not game_state.flags.has(flag_id):
		return _fail("Unknown flag: %s" % flag_id)
	game_state.flags.erase(flag_id)
	return _ok("Cleared flag %s" % flag_id)


func add_evidence(evidence_id: StringName) -> bool:
	if evidence_repository.get_evidence(evidence_id) == null:
		return _fail("Unknown evidence ID: %s" % evidence_id)
	var evidence := _evidence_state(evidence_id)
	evidence.owned = true
	evidence.discovered = true
	return _ok("Added evidence %s" % evidence_id)


func remove_evidence(evidence_id: StringName) -> bool:
	var evidence: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if evidence == null or not evidence.owned:
		return _fail("Evidence is not owned: %s" % evidence_id)
	evidence.owned = false
	return _ok("Removed evidence %s" % evidence_id)


func set_evidence_version(evidence_id: StringName, version: StringName) -> bool:
	if evidence_repository.get_evidence(evidence_id) == null:
		return _fail("Unknown evidence ID: %s" % evidence_id)
	_evidence_state(evidence_id).version = version
	return _ok("Evidence %s version = %s" % [evidence_id, version])


# --- inspection --------------------------------------------------------------

func story_state_name() -> String:
	return StoryState.RuntimeState.keys()[game_state.story.runtime_state]


func court_state_name() -> String:
	if court_runtime == null:
		return "NOT_LOADED"
	return CourtRuntime.RuntimeState.keys()[court_runtime.runtime_state]


## Story source mapping of the instruction that will execute next.
func current_source() -> String:
	if program == null:
		return "(no program)"
	var scene: StoryScene = program.get_scene(game_state.story.current_scene)
	if scene == null:
		return "(no scene)"
	var index: int = game_state.story.current_instruction
	var file: String = scene.source.file if scene.source != null else String(scene.id)
	if index < 0 or index >= scene.instructions.size():
		return "story_src/%s (end of scene)" % file
	var instruction: StoryInstruction = scene.instructions[index]
	if instruction == null or instruction.source == null:
		return "story_src/%s:%d" % [file, index]
	return "story_src/%s:%d" % [instruction.source.file, instruction.source.line]


## Subsystem, error, scene, source and instruction of the current failure.
func error_report() -> String:
	var report: Array[String] = []
	if game_state.story.runtime_state == StoryState.RuntimeState.ERROR:
		report.append("  subsystem   StoryVM")
		report.append("  error       %s" % story_vm.last_error)
	if court_runtime.runtime_state == CourtRuntime.RuntimeState.ERROR:
		report.append("  subsystem   CourtRuntime")
		report.append("  error       %s" % court_runtime.last_error)
	if report.is_empty():
		return ""
	report.append("  scene       %s" % game_state.story.current_scene)
	report.append("  source      %s" % current_source())
	report.append("  instruction %d" % game_state.story.current_instruction)
	return "\n".join(PackedStringArray(report))


func describe_state() -> String:
	var lines: Array[String] = []
	lines.append("CHAPTER      %s" % _or_none(game_state.story.current_chapter))
	lines.append("SCENE        %s" % _or_none(game_state.story.current_scene))
	lines.append("SOURCE       %s" % current_source())
	lines.append("INSTRUCTION  %d" % game_state.story.current_instruction)
	lines.append("STORY        %s" % story_state_name())
	lines.append("BACKGROUND   %s" % _or_none(game_state.story.current_background))

	lines.append("")
	lines.append("CALL STACK (%d)" % game_state.story.call_stack.size())
	for index: int in game_state.story.call_stack.size():
		var frame: StoryStackFrame = game_state.story.call_stack[index]
		lines.append("  [%d] %s:%d" % [index, frame.scene_id, frame.instruction_index])

	lines.append("")
	lines.append("FLAGS (%d)" % game_state.flags.size())
	for flag_id: StringName in _sorted_names(game_state.flags.keys()):
		lines.append("  %s = %s" % [flag_id, game_state.flags[flag_id]])

	lines.append("")
	lines.append("EVIDENCE")
	for definition: EvidenceDef in evidence_repository.get_all():
		var evidence: EvidenceState = game_state.evidence.get(definition.id) as EvidenceState
		lines.append("  %s owned=%s discovered=%s version=%s presentable=%s" % [
			String(definition.id).rpad(22),
			"yes" if evidence != null and evidence.owned else "no",
			"yes" if evidence != null and evidence.discovered else "no",
			_or_none(evidence.version if evidence != null else &""),
			"yes" if definition.presentable else "no",
		])

	lines.append("")
	lines.append("COURT")
	lines.append("  runtime     %s" % court_state_name())
	lines.append("  penalty     %d" % game_state.court.penalty)
	var session: TestimonySession = game_state.court.active_testimony
	if session == null:
		lines.append("  testimony   (none)")
	else:
		lines.append("  testimony   %s" % session.testimony_id)
		lines.append("  statement   %s" % session.current_statement_id)
		lines.append("  visited     %s" % _join_names(session.visited_statements))
		lines.append("  pressed     %s" % _join_names(session.pressed_statements))
	var branch: CourtBranchContext = court_runtime.pending_branch()
	if branch != null:
		lines.append("  branch      %s statement=%s target=%s" % [
			CourtBranchContext.Type.keys()[branch.type],
			branch.statement_id,
			branch.target_scene,
		])

	lines.append("")
	lines.append("INVESTIGATION")
	lines.append("  active      %s" % ("yes" if investigation_runtime.state.active else "no"))
	lines.append("  mode        %s" % InvestigationState.Mode.keys()[investigation_runtime.state.mode])
	lines.append("  location    %s" % _or_none(investigation_runtime.state.current_location))
	lines.append("  character   %s" % _or_none(investigation_runtime.state.current_character))
	lines.append("  visited     %s" % _join_names(investigation_runtime.state.visited_locations))
	var current_location: LocationDef = investigation_runtime.current_location()
	if current_location != null:
		for hotspot: HotspotDef in current_location.hotspots:
			lines.append("  hotspot     %s %s" % [
				String(hotspot.id).rpad(22),
				"examined" if investigation_runtime.is_hotspot_examined(hotspot.id) else "-",
			])
		for topic: TalkTopicDef in current_location.topics:
			var topic_flags: Array[String] = []
			if not investigation_runtime.is_topic_available(topic.id):
				topic_flags.append("locked")
			if investigation_runtime.is_topic_completed(topic.id):
				topic_flags.append("done")
			lines.append("  topic       %s %s" % [
				String(topic.id).rpad(22),
				", ".join(PackedStringArray(topic_flags)) if not topic_flags.is_empty() else "open",
			])

	lines.append("")
	lines.append("PROCEDURE")
	lines.append("  active      %s" % ("yes" if procedure_runtime.state.active else "no"))
	lines.append("  context     %s" % _or_none(procedure_runtime.state.context_id))
	lines.append("  resolved    %s%s" % [
		"yes" if procedure_runtime.state.resolved else "no",
		" (%s)" % procedure_runtime.state.resolved_action_id
		if not procedure_runtime.state.resolved_action_id.is_empty()
		else "",
	])
	lines.append("  visited     %s" % _join_names(procedure_runtime.state.visited_actions))
	var context: ProcedureContext = procedure_runtime.current_context()
	if context != null:
		for action: ProcedureActionDef in context.actions:
			var action_flags: Array[String] = [ProcedureResult.Type.keys()[action.result_type]]
			if not procedure_runtime.is_action_available(action):
				action_flags.append("requirements unmet")
			if procedure_runtime.state.visited_actions.has(action.id):
				action_flags.append("visited")
			lines.append("  action      %s %s" % [
				String(action.id).rpad(30),
				", ".join(PackedStringArray(action_flags)),
			])

	lines.append("")
	lines.append("EVIDENCE INSPECTION")
	for definition: EvidenceInspectionDef in _inspection_definitions():
		var evidence: EvidenceState = game_state.evidence.get(definition.evidence_id) as EvidenceState
		var version: StringName = evidence.version if evidence != null else &""
		lines.append("  %s version=%s complete=%s inspected=%d/%d" % [
			String(definition.evidence_id).rpad(22),
			_or_none(version),
			"yes" if evidence != null and evidence.inspection_complete else "no",
			evidence.inspected_hotspots.size() if evidence != null else 0,
			definition.hotspots.size(),
		])
		for hotspot: EvidenceHotspotDef in definition.hotspots:
			lines.append("    hotspot   %s %s" % [
				String(hotspot.id).rpad(22),
				"inspected" if evidence != null and evidence.has_inspected(hotspot.id) else "-",
			])

	if presentation != null:
		lines.append("")
		lines.append("PRESENTATION (transient)")
		lines.append("  background  %s" % _or_none(presentation.background.current_background_id))
		lines.append("  stage       %s" % _stage_summary())
		lines.append("  bgm         %s" % _or_none(presentation.audio.current_bgm()))

	var errors: String = error_report()
	if not errors.is_empty():
		lines.append("")
		lines.append("RUNTIME ERROR")
		lines.append(errors)
	return "\n".join(PackedStringArray(lines))


# --- internals ---------------------------------------------------------------

## Every authored inspection definition, for the state dump.
func _inspection_definitions() -> Array[EvidenceInspectionDef]:
	var result: Array[EvidenceInspectionDef]
	if inspection_runtime == null or inspection_runtime.repository() == null:
		return result
	for definition: EvidenceDef in evidence_repository.get_all():
		var inspection: EvidenceInspectionDef = (
			inspection_runtime.current_definition_for(definition.id)
		)
		if inspection != null:
			result.append(inspection)
	return result

## Drops any court session so teleporting cannot leave an old testimony attached.
func _clear_court_session() -> void:
	court_runtime.abort_testimony()


func _evidence_state(evidence_id: StringName) -> EvidenceState:
	var evidence: EvidenceState = game_state.evidence.get(evidence_id) as EvidenceState
	if evidence == null:
		evidence = EvidenceState.new(evidence_id)
		game_state.evidence[evidence_id] = evidence
	return evidence


func _sorted_names(values: Array) -> Array[StringName]:
	var names: Array[StringName]
	names.assign(values)
	names.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return names


func _join_names(values: Array[StringName]) -> String:
	if values.is_empty():
		return "(none)"
	var names: Array[String] = []
	for value: StringName in values:
		names.append(String(value))
	return ", ".join(PackedStringArray(names))


func _or_none(value: Variant) -> String:
	var text: String = String(value)
	return text if not text.is_empty() else "(none)"


## Cast currently on stage, as `character@slot/expression`.
func _stage_summary() -> String:
	var entries: Array[String] = []
	for character_id: StringName in presentation.stage.visible_characters():
		entries.append("%s@%s/%s" % [
			character_id,
			CharacterStage.Slot.keys()[presentation.stage.current_slot(character_id)].to_lower(),
			_or_none(presentation.stage.current_expression(character_id)),
		])
	return ", ".join(PackedStringArray(entries)) if not entries.is_empty() else "(empty)"


func _ok(message: String) -> bool:
	error_message = ""
	last_message = message
	state_changed.emit()
	return true


func _fail(message: String) -> bool:
	error_message = message
	last_message = message
	return false
