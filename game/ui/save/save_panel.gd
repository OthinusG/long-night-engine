class_name SavePanel
extends PanelContainer

## Minimal debug save/load panel. It submits slot numbers only; SaveManager
## decides whether the current state may be saved.

signal save_requested(slot: int)
signal load_requested(slot: int)

const SLOT_COUNT: int = SaveManager.SLOT_COUNT

var _save_buttons: Array[Button]


func _ready() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	add_child(content)

	var title := Label.new()
	title.text = "SAVE / LOAD"
	content.add_child(title)

	for slot: int in range(1, SLOT_COUNT + 1):
		var row := HBoxContainer.new()
		var slot_label := Label.new()
		slot_label.text = "SLOT %d" % slot
		slot_label.custom_minimum_size = Vector2(80.0, 0.0)
		row.add_child(slot_label)

		var save_button := Button.new()
		save_button.text = "保存"
		save_button.pressed.connect(func() -> void: save_requested.emit(slot))
		row.add_child(save_button)
		_save_buttons.append(save_button)

		var load_button := Button.new()
		load_button.text = "读取"
		load_button.pressed.connect(func() -> void: load_requested.emit(slot))
		row.add_child(load_button)

		content.add_child(row)


func set_save_enabled(enabled: bool) -> void:
	for button: Button in _save_buttons:
		button.disabled = not enabled
