class_name PresentationCoordinator
extends RefCounted

## Single boundary between gameplay events and how they look. It routes domain
## events to dedicated presenters and never decides a gameplay result.

signal dialogue_presented
signal court_presented
signal investigation_presented
signal procedure_presented
signal inspection_presented
signal feedback_changed(text: String)
signal presentation_changed

var background: BackgroundPresenter
var stage: CharacterStage
var dialogue: DialoguePresenter
var court: CourtPresenter
var investigation: InvestigationPresenter
var camera: CameraDirector
var fx: FxDirector
var transition: TransitionDirector
var audio: AudioManager

var _content: ContentRegistry
var _assets: AssetRegistry
var _dialogue_ui: DialogueUI


func _init(
	host: Control,
	background_view: ColorRect,
	background_label: Label,
	stage_root: Control,
	camera_node: Camera2D,
	content: ContentRegistry,
	assets: AssetRegistry,
) -> void:
	_content = content
	_assets = assets
	background = BackgroundPresenter.new(background_view, background_label, assets)
	stage = CharacterStage.new(stage_root, content, assets)
	camera = CameraDirector.new(camera_node)
	fx = FxDirector.new(host)
	transition = TransitionDirector.new(host)
	audio = AudioManager.new(host, assets)
	fx.notice_requested.connect(func(text: String) -> void: feedback_changed.emit(text))


func bind_ui(dialogue_ui: DialogueUI, court_ui: CourtUI) -> void:
	_dialogue_ui = dialogue_ui
	dialogue = DialoguePresenter.new(dialogue_ui, stage, _content)
	court = CourtPresenter.new(court_ui, _content, stage, background, camera, fx)
	court.feedback_changed.connect(_on_feedback)


func connect_runtimes(
	story_vm: StoryVM,
	court_runtime: CourtRuntime,
	investigation_runtime: InvestigationRuntime,
) -> void:
	story_vm.scene_changed.connect(_on_scene_changed)
	story_vm.dialogue_requested.connect(_on_dialogue_requested)
	story_vm.background_requested.connect(_on_background_requested)
	story_vm.bgm_requested.connect(_on_bgm_requested)
	story_vm.sfx_requested.connect(_on_sfx_requested)
	story_vm.character_requested.connect(_on_character_requested)
	story_vm.character_hidden.connect(_on_character_hidden)
	court.connect_runtime(court_runtime)
	court.refresh()
	investigation = InvestigationPresenter.new(_content, stage, background)
	investigation.connect_runtime(investigation_runtime)


func _on_scene_changed(_scene_id: StringName) -> void:
	stage.clear_stage()
	presentation_changed.emit()


## Rebuilds stable presentation from canonical state after a load or a debug jump.
func refresh_from_state(game_state: GameState) -> void:
	if game_state == null:
		return
	stage.clear_stage()
	background.show_background(game_state.story.current_background)
	background.set_court_active(game_state.story.runtime_state == StoryState.RuntimeState.WAIT_COURT)
	match game_state.story.runtime_state:
		StoryState.RuntimeState.WAIT_COURT:
			court.refresh()
			court_presented.emit()
		StoryState.RuntimeState.WAIT_INVESTIGATION:
			investigation.refresh()
			investigation_presented.emit()
		StoryState.RuntimeState.WAIT_PROCEDURE:
			procedure_presented.emit()
		_:
			pass
	presentation_changed.emit()


func apply_text_speed(characters_per_second: float) -> void:
	if dialogue != null:
		dialogue.set_text_speed(characters_per_second)


func tick(delta: float) -> void:
	if dialogue != null:
		dialogue.advance_reveal(delta)
	stage.tick(delta)


func is_transition_locked() -> bool:
	return transition.is_locked()


func missing_asset_count() -> int:
	return _assets.missing_asset_count()


func _on_dialogue_requested(
	speaker_id: StringName,
	expression_id: StringName,
	text: String,
	_source: SourceLocation,
) -> void:
	dialogue.show_line(speaker_id, expression_id, text)
	dialogue_presented.emit()
	presentation_changed.emit()


func _on_background_requested(background_id: StringName) -> void:
	background.show_background(background_id)
	presentation_changed.emit()


func _on_bgm_requested(bgm_id: StringName) -> void:
	audio.play_bgm(bgm_id)


func _on_sfx_requested(sfx_id: StringName) -> void:
	audio.play_sfx(sfx_id)


func _on_feedback(text: String) -> void:
	feedback_changed.emit(text)
	presentation_changed.emit()


func _on_character_requested(
	character_id: StringName,
	slot: StringName,
	expression_id: StringName,
) -> void:
	stage.show_character(character_id, CharacterStage.slot_from_name(slot))
	if not expression_id.is_empty():
		stage.set_expression(character_id, expression_id)
	presentation_changed.emit()


func _on_character_hidden(character_id: StringName) -> void:
	if character_id == &"all":
		stage.clear_stage()
	else:
		stage.hide_character(character_id)
	presentation_changed.emit()
