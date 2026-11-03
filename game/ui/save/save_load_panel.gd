class_name SaveLoadPanel
extends PanelContainer

## Modal save/load dialog supporting 3 slots with metadata previews and safe state validation.

signal save_slot_selected(slot: int)
signal load_slot_selected(slot: int)
signal closed

enum Mode {
	SAVE,
	LOAD,
}

var current_mode: Mode = Mode.SAVE
var save_manager: SaveManager

var _title_label: Label
var _status_hint_label: Label
var _slot_containers: Array[PanelContainer] = []
var _action_buttons: Array[Button] = []
var _back_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(860, 620)
	anchors_preset = Control.PRESET_CENTER
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	style.border_color = Color(0.42, 0.50, 0.65, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 32.0
	style.content_margin_top = 28.0
	style.content_margin_right = 32.0
	style.content_margin_bottom = 28.0
	add_theme_stylebox_override("panel", style)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 20)
	add_child(root_vbox)

	# Header
	var header_hbox := HBoxContainer.new()
	_title_label = Label.new()
	_title_label.text = "存 档"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.84, 0.55, 1.0))
	header_hbox.add_child(_title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	_status_hint_label = Label.new()
	_status_hint_label.add_theme_font_size_override("font_size", 16)
	_status_hint_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 0.9))
	header_hbox.add_child(_status_hint_label)

	root_vbox.add_child(header_hbox)

	# Slot list
	var slots_vbox := VBoxContainer.new()
	slots_vbox.add_theme_constant_override("separation", 14)
	slots_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(slots_vbox)

	for slot_idx: int in range(1, SaveManager.SLOT_COUNT + 1):
		var slot_card := _build_slot_card(slot_idx)
		slots_vbox.add_child(slot_card)
		_slot_containers.append(slot_card)

	# Footer
	var footer_hbox := HBoxContainer.new()
	footer_hbox.alignment = BoxContainer.ALIGNMENT_END

	_back_button = Button.new()
	_back_button.text = "返 回"
	_back_button.custom_minimum_size = Vector2(140, 44)
	_back_button.add_theme_font_size_override("font_size", 18)
	_back_button.pressed.connect(func() -> void: closed.emit())
	footer_hbox.add_child(_back_button)

	root_vbox.add_child(footer_hbox)


func open_panel(mode: Mode, manager: SaveManager) -> void:
	current_mode = mode
	save_manager = manager
	visible = true
	_refresh_display()
	if _back_button != null:
		_back_button.grab_focus()


func close_panel() -> void:
	visible = false


func _build_slot_card(slot: int) -> PanelContainer:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.11, 0.15, 0.22, 0.85)
	card_style.border_color = Color(0.28, 0.35, 0.48, 0.7)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(6)
	card_style.content_margin_left = 20.0
	card_style.content_margin_top = 16.0
	card_style.content_margin_right = 20.0
	card_style.content_margin_bottom = 16.0
	card.add_theme_stylebox_override("panel", card_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	card.add_child(hbox)

	var slot_tag := Label.new()
	slot_tag.text = "卷宗 %02d" % slot
	slot_tag.add_theme_font_size_override("font_size", 22)
	slot_tag.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65, 1.0))
	slot_tag.custom_minimum_size = Vector2(110, 0)
	hbox.add_child(slot_tag)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)

	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.text = "【 空 白 存 档 】"
	info_vbox.add_child(desc_label)

	var meta_label := Label.new()
	meta_label.name = "MetaLabel"
	meta_label.add_theme_font_size_override("font_size", 14)
	meta_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 0.8))
	meta_label.text = "--"
	info_vbox.add_child(meta_label)

	var action_btn := Button.new()
	action_btn.name = "ActionBtn"
	action_btn.custom_minimum_size = Vector2(120, 44)
	action_btn.add_theme_font_size_override("font_size", 18)
	action_btn.pressed.connect(func() -> void: _on_action_pressed(slot))
	hbox.add_child(action_btn)
	_action_buttons.append(action_btn)

	return card


func _refresh_display() -> void:
	if save_manager == null:
		return

	var is_save := current_mode == Mode.SAVE
	_title_label.text = "保 存 进 度" if is_save else "读 取 进 度"

	var can_save_now := save_manager.can_save()
	if is_save and not can_save_now:
		_status_hint_label.text = "当前剧情分支或质询中无法存档"
	else:
		_status_hint_label.text = ""

	for slot_idx: int in range(1, SaveManager.SLOT_COUNT + 1):
		var card := _slot_containers[slot_idx - 1]
		var desc_label: Label = card.find_child("DescLabel", true, false) as Label
		var meta_label: Label = card.find_child("MetaLabel", true, false) as Label
		var action_btn: Button = card.find_child("ActionBtn", true, false) as Button

		var info: Dictionary = save_manager.get_slot_info(slot_idx)
		var has_data := not info.is_empty()

		if has_data:
			var scene_id: String = String(info.get("scene", "scene"))
			var chapter_id: String = String(info.get("chapter", "ch01"))
			desc_label.text = "%s  [%s]" % [_chapter_display_name(chapter_id), scene_id]
			desc_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))

			var playtime: float = float(info.get("playtime", 0.0))
			var mtime: int = int(info.get("modified_time", 0))
			var time_str := Time.get_datetime_string_from_unix_time(mtime, true) if mtime > 0 else ""
			meta_label.text = "游玩时长: %02d:%02d:%02d   保存时间: %s" % [
				int(playtime) / 3600,
				(int(playtime) % 3600) / 60,
				int(playtime) % 60,
				time_str,
			]
		else:
			desc_label.text = "【 空 白 存 档 】"
			desc_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72, 0.6))
			meta_label.text = "无数据"

		if is_save:
			action_btn.text = "覆 盖" if has_data else "保 存"
			action_btn.disabled = not can_save_now
		else:
			action_btn.text = "读 取"
			action_btn.disabled = not has_data


func _chapter_display_name(chapter_id: String) -> String:
	if chapter_id.is_empty():
		return "Prologue"
	return chapter_id.capitalize()


func _on_action_pressed(slot: int) -> void:
	if current_mode == Mode.SAVE:
		save_slot_selected.emit(slot)
	else:
		load_slot_selected.emit(slot)
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
