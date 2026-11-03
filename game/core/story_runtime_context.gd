class_name StoryRuntimeContext
extends RefCounted

signal dialogue_requested(
	speaker_id: StringName,
	expression_id: StringName,
	text: String,
	source: SourceLocation,
)
signal background_requested(background_id: StringName)
signal bgm_requested(bgm_id: StringName)
signal sfx_requested(sfx_id: StringName)
signal court_requested(testimony_id: StringName)
signal investigation_requested(location_id: StringName)
signal talk_unlock_requested(topic_id: StringName)
signal procedure_requested(context_id: StringName)
signal character_requested(
	character_id: StringName,
	slot: StringName,
	expression_id: StringName,
)
signal character_hidden(character_id: StringName)

var game_state: GameState


func _init(runtime_game_state: GameState) -> void:
	game_state = runtime_game_state


func request_dialogue(instruction: StoryInstruction) -> void:
	dialogue_requested.emit(
		instruction.speaker_id,
		instruction.expression_id,
		instruction.text,
		instruction.source,
	)


func request_background(background_id: StringName) -> void:
	background_requested.emit(background_id)


func request_bgm(bgm_id: StringName) -> void:
	bgm_requested.emit(bgm_id)


func request_sfx(sfx_id: StringName) -> void:
	sfx_requested.emit(sfx_id)


func request_court(testimony_id: StringName) -> void:
	court_requested.emit(testimony_id)


func request_investigation(location_id: StringName) -> void:
	investigation_requested.emit(location_id)


func request_talk_unlock(topic_id: StringName) -> void:
	talk_unlock_requested.emit(topic_id)


func request_procedure(context_id: StringName) -> void:
	procedure_requested.emit(context_id)


func request_character(
	character_id: StringName,
	slot: StringName,
	expression_id: StringName,
) -> void:
	character_requested.emit(character_id, slot, expression_id)


func request_hide(character_id: StringName) -> void:
	character_hidden.emit(character_id)
