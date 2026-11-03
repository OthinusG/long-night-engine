class_name DialogueUI
extends PanelContainer

signal advance_requested

@onready var speaker_label: Label = %SpeakerLabel
@onready var text_label: Label = %TextLabel
@onready var continue_button: Button = %ContinueButton
@onready var next_indicator: Label = %NextIndicator


func _ready() -> void:
	continue_button.pressed.connect(func() -> void: advance_requested.emit())


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			advance_requested.emit()
			accept_event()


func show_dialogue(speaker: String, text: String) -> void:
	speaker_label.text = speaker
	text_label.text = text
	text_label.visible_ratio = 1.0
	if next_indicator != null:
		next_indicator.visible = true
	set_active(true)
	continue_button.grab_focus()


## Presentation-only reveal control; the presenter owns the text speed.
func set_reveal(fraction: float) -> void:
	text_label.visible_ratio = clampf(fraction, 0.0, 1.0)
	if next_indicator != null:
		next_indicator.visible = fraction >= 0.99


func set_active(active: bool) -> void:
	visible = active
	continue_button.disabled = not active
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
