class_name GameState
extends RefCounted

const SAVE_SCHEMA_VERSION: int = 3

var schema_version: int = SAVE_SCHEMA_VERSION
var game_version: String = "0.1.0"
var story: StoryState = StoryState.new()
var flags: Dictionary[StringName, Variant]
var evidence: Dictionary[StringName, EvidenceState]
var court: CourtState = CourtState.new()
var investigation: InvestigationState = InvestigationState.new()
var procedure: ProcedureState = ProcedureState.new()
var playtime_seconds: float = 0.0


func reset() -> void:
	story.current_chapter = &""
	story.current_scene = &""
	story.current_instruction = 0
	story.call_stack.clear()
	story.runtime_state = StoryState.RuntimeState.RUNNING
	story.current_background = &""
	flags.clear()
	evidence.clear()
	court.active_testimony = null
	court.penalty = CourtState.DEFAULT_PENALTY
	investigation.active = false
	investigation.mode = InvestigationState.Mode.INACTIVE
	investigation.current_location = &""
	investigation.current_character = &""
	investigation.visited_locations.clear()
	investigation.location_states.clear()
	procedure.active = false
	procedure.context_id = &""
	procedure.resolved = false
	procedure.resolved_action_id = &""
	procedure.visited_actions.clear()
	playtime_seconds = 0.0
