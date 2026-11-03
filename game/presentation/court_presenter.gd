class_name CourtPresenter
extends RefCounted

## Reacts to CourtRuntime domain events. Every outcome is already decided by the
## runtime before these handlers run; this class only chooses how it looks.

signal feedback_changed(text: String)

const CORRECT_ACCENT: Color = Color(1.0, 0.97, 0.85)
const WRONG_ACCENT: Color = Color(0.85, 0.2, 0.2)

var _court_ui: CourtUI
var _content: ContentRegistry
var _stage: CharacterStage
var _background: BackgroundPresenter
var _camera: CameraDirector
var _fx: FxDirector
var _runtime: CourtRuntime


func _init(
	court_ui: CourtUI,
	content: ContentRegistry,
	stage: CharacterStage,
	background: BackgroundPresenter,
	camera: CameraDirector,
	fx: FxDirector,
) -> void:
	_court_ui = court_ui
	_content = content
	_stage = stage
	_background = background
	_camera = camera
	_fx = fx


func connect_runtime(runtime: CourtRuntime) -> void:
	_runtime = runtime
	runtime.testimony_started.connect(_on_testimony_started)
	runtime.statement_changed.connect(_on_statement_changed)
	runtime.statement_pressed.connect(_on_statement_pressed)
	runtime.present_wrong.connect(_on_present_wrong)
	runtime.present_correct.connect(_on_present_correct)
	runtime.penalty_changed.connect(_on_penalty_changed)
	runtime.testimony_completed.connect(_on_testimony_completed)


## Rebuilds the courtroom surface from runtime state, e.g. after a save load.
func refresh() -> void:
	if _runtime == null:
		return
	var statement: StatementDef = _runtime.get_current_statement()
	if statement == null:
		return
	_stage_statement_speaker(statement)
	_court_ui.refresh(
		_runtime,
		_content.get_display_name(statement.speaker_id),
	)


func _on_testimony_started(_testimony_id: StringName) -> void:
	_background.set_court_active(true)
	# Court presentation starts from a clean stage; story-scene portraits must
	# never leak into testimony preview or interrogation.
	_stage.clear_stage()
	_fx.set_tint(WRONG_ACCENT, 0.10)
	_camera.impulse(Vector2(0.0, -6.0), 0.25)
	_fx.notice("开始证言", 1.6)
	feedback_changed.emit("TESTIMONY")


func _on_statement_changed(_statement_id: StringName) -> void:
	var statement: StatementDef = _runtime.get_current_statement()
	if statement != null:
		_stage_statement_speaker(statement)
	refresh()


func _on_statement_pressed(_statement_id: StringName, _target_scene: StringName) -> void:
	_camera.impulse(Vector2(4.0, 0.0), 0.18)
	_fx.notice("威慑", 1.5, true)


func _on_present_wrong(_statement_id: StringName, _evidence_id: StringName) -> void:
	_camera.shake(10.0, 0.35)
	_fx.contradiction(WRONG_ACCENT)
	feedback_changed.emit("WRONG")


func _on_present_correct(_statement_id: StringName, _evidence_id: StringName) -> void:
	_camera.shake(6.0, 0.25)
	_fx.flash(CORRECT_ACCENT, 0.35)
	_fx.notice("反对", 1.5, true)
	feedback_changed.emit("CORRECT")


func _on_penalty_changed(_previous: int, current: int) -> void:
	_court_ui.refresh_penalty(current)


func _on_testimony_completed(_testimony_id: StringName) -> void:
	_background.set_court_active(false)
	_fx.clear_tint()


func _stage_statement_speaker(statement: StatementDef) -> void:
	if statement.speaker_id.is_empty():
		return
	if not _stage.has_character(statement.speaker_id):
		_stage.show_character(statement.speaker_id, CharacterStage.Slot.CENTER)
	if not statement.expression_id.is_empty():
		_stage.set_expression(statement.speaker_id, statement.expression_id)
