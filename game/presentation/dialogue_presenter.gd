class_name DialoguePresenter
extends RefCounted

## Turns a dialogue request into what the player sees: the display name, the
## staged speaker and the dialogue panel. It never decides what happens next and
## never branches the story.

var _dialogue_ui: DialogueUI
var _stage: CharacterStage
var _content: ContentRegistry
var _text_speed: float = 0.0
var _revealing: bool = false
var _revealed: float = 0.0
var _length: int = 0


func _init(dialogue_ui: DialogueUI, stage: CharacterStage, content: ContentRegistry) -> void:
	_dialogue_ui = dialogue_ui
	_stage = stage
	_content = content


## Characters per second; 0 keeps the text instant.
func set_text_speed(characters_per_second: float) -> void:
	_text_speed = maxf(characters_per_second, 0.0)


func text_speed() -> float:
	return _text_speed


func is_revealing() -> bool:
	return _revealing


func advance_reveal(delta: float) -> void:
	if not _revealing:
		return
	_revealed += _text_speed * delta
	if _revealed >= float(_length):
		complete_reveal()
		return
	_dialogue_ui.set_reveal(_revealed / float(maxi(_length, 1)))


func complete_reveal() -> void:
	_revealing = false
	_revealed = float(_length)
	_dialogue_ui.set_reveal(1.0)


func show_line(speaker_id: StringName, expression_id: StringName, text: String) -> void:
	if not speaker_id.is_empty():
		_stage_character(speaker_id, expression_id)
	var display_name: String = (
		_content.get_display_name(speaker_id) if not speaker_id.is_empty() else ""
	)
	_dialogue_ui.show_dialogue(display_name, text)
	_length = text.length()
	_revealed = 0.0
	_revealing = _text_speed > 0.0 and _length > 0
	_dialogue_ui.set_reveal(0.0 if _revealing else 1.0)


func _stage_character(speaker_id: StringName, expression_id: StringName) -> void:
	if not _stage.has_character(speaker_id):
		_stage.show_character(speaker_id, CharacterStage.Slot.CENTER)
	if not expression_id.is_empty():
		_stage.set_expression(speaker_id, expression_id)
