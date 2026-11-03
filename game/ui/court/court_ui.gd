class_name CourtUI
extends PanelContainer

signal previous_requested
signal next_requested
signal press_requested
signal present_requested

@onready var statement_id_label: Label = %StatementIdLabel
@onready var penalty_label: Label = %PenaltyLabel
@onready var penalty_bar: ProgressBar = %PenaltyBar
@onready var hearts_label: Label = %HeartsLabel
@onready var speaker_label: Label = %SpeakerLabel
@onready var statement_label: Label = %StatementLabel
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var press_button: Button = %PressButton
@onready var present_button: Button = %PresentButton


func _ready() -> void:
	previous_button.pressed.connect(func() -> void: previous_requested.emit())
	next_button.pressed.connect(func() -> void: next_requested.emit())
	press_button.pressed.connect(func() -> void: press_requested.emit())
	present_button.pressed.connect(func() -> void: present_requested.emit())


func refresh(runtime: CourtRuntime, speaker: String) -> void:
	var statement: StatementDef = runtime.get_current_statement()
	if statement == null:
		return
	statement_id_label.text = String(statement.id)
	speaker_label.text = speaker
	statement_label.text = statement.text
	refresh_penalty(runtime.state.penalty)


func refresh_penalty(value: int) -> void:
	penalty_bar.value = value
	var hearts: int = ceili(float(value) / float(CourtState.DEFAULT_PENALTY / 5))
	hearts = clampi(hearts, 0, 5)
	hearts_label.text = "♥ ".repeat(hearts) + "♡ ".repeat(5 - hearts)
	penalty_label.text = "生命 %d / 5" % hearts


func set_active(active: bool) -> void:
	visible = active
	set_interaction_enabled(active)
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE


func set_interaction_enabled(enabled: bool) -> void:
	previous_button.disabled = not enabled
	next_button.disabled = not enabled
	press_button.disabled = not enabled
	present_button.disabled = not enabled
	if enabled:
		next_button.grab_focus()
