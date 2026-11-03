class_name SaveManager
extends RefCounted

## Owns save file IO and runtime restore.
##
## Only canonical GameState is written. Loading validates the payload first, then
## replaces domain state and reconnects the runtimes; rebuilding presentation
## from that state is the caller's job.

const SAVE_DIRECTORY: String = "user://saves"
const SLOT_COUNT: int = 3

var error_message: String = ""
var directory: String = SAVE_DIRECTORY
var migrator: SaveMigrator
var game_state: GameState
var story_vm: StoryVM
var court_runtime: CourtRuntime
var investigation_runtime: InvestigationRuntime
var procedure_runtime: ProcedureRuntime
var program: StoryProgram
var evidence_repository: EvidenceRepository


func _init(
	runtime_game_state: GameState,
	runtime_story_vm: StoryVM,
	runtime_court: CourtRuntime,
	runtime_investigation: InvestigationRuntime,
	runtime_procedure: ProcedureRuntime,
	runtime_program: StoryProgram,
	runtime_evidence: EvidenceRepository,
	save_directory: String = SAVE_DIRECTORY,
) -> void:
	game_state = runtime_game_state
	story_vm = runtime_story_vm
	court_runtime = runtime_court
	investigation_runtime = runtime_investigation
	procedure_runtime = runtime_procedure
	program = runtime_program
	evidence_repository = runtime_evidence
	directory = save_directory
	migrator = SaveMigrator.new()


static func slot_path(save_directory: String, slot: int) -> String:
	return "%s/save_%03d.json" % [save_directory, slot]


## Save is allowed only in stable states: a visible dialogue line outside any
## gameplay branch, or testimony/investigation/procedure browsing that is not
## inside a Press/Present/Examine/Talk/action branch.
func can_save() -> bool:
	if game_state == null or court_runtime == null or investigation_runtime == null:
		return false
	if procedure_runtime == null or story_vm == null:
		return false
	# One check covers every branch kind, including nested procedure and
	# inspection branches whose continuation is transient.
	if story_vm.is_in_story_branch():
		return false
	if game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		return true
	if game_state.story.runtime_state == StoryState.RuntimeState.WAIT_INVESTIGATION:
		return game_state.investigation.active
	if game_state.story.runtime_state == StoryState.RuntimeState.WAIT_PROCEDURE:
		return game_state.procedure.active
	return (
		game_state.story.runtime_state == StoryState.RuntimeState.WAIT_COURT
		and court_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_ACTIVE
	)


func has_slot(slot: int) -> bool:
	return _is_valid_slot(slot) and FileAccess.file_exists(slot_path(directory, slot))


func get_slot_info(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var path: String = slot_path(directory, slot)
	var parsed: Variant = _read_json(path)
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed as Dictionary
	var modified_time: int = FileAccess.get_modified_time(path)
	var story_data: Dictionary = data.get("story", {})
	return {
		"slot": slot,
		"chapter": story_data.get("chapter", "default"),
		"scene": story_data.get("current_scene", ""),
		"playtime": data.get("playtime_seconds", 0.0),
		"modified_time": modified_time,
	}


func save_slot(slot: int) -> bool:
	error_message = ""
	if not _is_valid_slot(slot):
		return _fail("Save slot out of range: %d" % slot)
	if not can_save():
		return _fail("Save is only allowed during dialogue or stable testimony browsing.")

	var target_path: String = slot_path(directory, slot)
	# ponytail: FileAccess has no fsync, so "validating the write" means parsing
	# the temp file again before it replaces the previous slot.
	var temp_path: String = "%s.tmp" % target_path
	if not _write_text(temp_path, JSON.stringify(SaveSerializer.to_dict(game_state), "\t")):
		return false
	if _read_json(temp_path) == null:
		return false

	var directory_access := DirAccess.open(directory)
	if directory_access == null:
		return _fail("Cannot open save directory: %s" % directory)
	if directory_access.file_exists(target_path.get_file()):
		directory_access.remove(target_path.get_file())
	var rename_error: Error = directory_access.rename(
		temp_path.get_file(),
		target_path.get_file(),
	)
	if rename_error != OK:
		return _fail("Cannot replace save slot %d (error %d)." % [slot, rename_error])
	return true


func load_slot(slot: int) -> bool:
	error_message = ""
	if not _is_valid_slot(slot):
		return _fail("Save slot out of range: %d" % slot)
	var path: String = slot_path(directory, slot)
	var parsed: Variant = _read_json(path)
	if parsed == null:
		return false
	if not parsed is Dictionary:
		return _fail("Save file root must be an object: %s" % path)
	var data: Dictionary = migrator.migrate(parsed)
	if data.is_empty():
		return _fail("Save file '%s' rejected: %s" % [path, migrator.error_message])
	_recover_unambiguous_court_save(data)
	var validator := SaveValidator.new()
	if not validator.validate(
		data,
		program,
		evidence_repository,
		procedure_runtime.repository() if procedure_runtime != null else null,
	):
		return _fail("Invalid save '%s': %s" % [path, validator.error_message])

	# The payload is valid, so replacing state cannot leave a half-loaded session.
	court_runtime.clear_runtime()
	investigation_runtime.clear_runtime()
	if procedure_runtime != null:
		procedure_runtime.clear_runtime()
	SaveSerializer.apply_dict(game_state, data)
	if not _restore_runtimes(data["story"]["runtime_state"]):
		return false
	return true


## Older builds could persist WAIT_COURT before the court hand-off completed.
## Recover only the unambiguous case: the blocking instruction is START_TESTIMONY.
## A save with no such instruction remains rejected instead of inventing state.
func _recover_unambiguous_court_save(data: Dictionary) -> void:
	var story: Dictionary = data.get("story", {})
	var court: Dictionary = data.get("court", {})
	if story.get("runtime_state", "") != "WAIT_COURT" or court.get("active", false):
		return
	var scene: StoryScene = program.get_scene(StringName(story.get("scene", "")))
	var index: int = int(story.get("instruction_index", 0))
	if scene == null or index <= 0 or index > scene.instructions.size():
		return
	var instruction: StoryInstruction = scene.instructions[index - 1]
	if instruction == null or instruction.op != StoryInstruction.Op.START_TESTIMONY:
		return
	var definition: TestimonyDef = program.get_testimony(instruction.testimony_id)
	if definition == null or definition.statements.is_empty():
		return
	court["active"] = true
	court["testimony_id"] = String(definition.id)
	court["current_statement_id"] = String(definition.statements[0].id)
	court["visited_statements"] = [String(definition.statements[0].id)]
	court["pressed_statements"] = []
	data["court"] = court


func _restore_runtimes(state_name: String) -> bool:
	var target: StoryState.RuntimeState = StoryState.RuntimeState[state_name]
	if target == StoryState.RuntimeState.WAIT_COURT:
		if game_state.court.active_testimony == null:
			return _fail("Save waits for court without an active testimony.")
		var definition: TestimonyDef = program.get_testimony(
			game_state.court.active_testimony.testimony_id
		)
		if not court_runtime.restore_active_testimony(definition):
			return _fail("Cannot restore the active testimony: %s" % court_runtime.last_error)
		if not story_vm.restore_position(target, false):
			return _fail("Cannot restore the story position: %s" % story_vm.last_error)
		return true
	if target == StoryState.RuntimeState.WAIT_INVESTIGATION:
		if not game_state.investigation.active:
			return _fail("Save waits for an investigation that is not active.")
		if not investigation_runtime.restore_active_investigation():
			return _fail("Cannot restore the investigation: %s" % investigation_runtime.last_error)
		if not story_vm.restore_position(target, false):
			return _fail("Cannot restore the story position: %s" % story_vm.last_error)
		return true
	if target == StoryState.RuntimeState.WAIT_PROCEDURE:
		if procedure_runtime == null or not game_state.procedure.active:
			return _fail("Save waits for a procedure that is not active.")
		if not procedure_runtime.restore_active_procedure():
			return _fail("Cannot restore the procedure: %s" % procedure_runtime.last_error)
		if not story_vm.restore_position(target, false):
			return _fail("Cannot restore the story position: %s" % story_vm.last_error)
		return true
	# WAIT_DIALOGUE replays the instruction that blocked the VM so the visible
	# line is reconstructed instead of being skipped or repeated.
	if not story_vm.restore_position(target, true):
		return _fail("Cannot restore the story position: %s" % story_vm.last_error)
	return true


func _write_text(path: String, text: String) -> bool:
	if not _ensure_directory():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("Cannot write save file '%s'." % path)
	file.store_string(text)
	file.close()
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		error_message = "Save file does not exist: %s" % path
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "Cannot open save file '%s'." % path
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		error_message = "Malformed save JSON in '%s' at line %d: %s" % [
			path,
			json.get_error_line(),
			json.get_error_message(),
		]
		file.close()
		return null
	file.close()
	return json.data


func _ensure_directory() -> bool:
	if DirAccess.dir_exists_absolute(directory):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return _fail("Cannot create save directory '%s' (error %d)." % [directory, error])
	return true


func _is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func _fail(message: String) -> bool:
	error_message = message
	return false
