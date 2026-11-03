class_name PauseMenu
extends PanelContainer

## In-game pause menu shown on ESC. Provides Resume, Save, Load, Settings, Title, Quit.

signal resume_requested
signal save_requested
signal load_requested
signal settings_requested
signal title_requested
signal quit_requested

var _resume_button: Button
var _save_button: Button
var _load_button: Button
var _settings_button: Button
var _title_button: Button
var _quit_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(420, 520)
	anchors_preset = Control.PRESET_CENTER
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	style.border_color = Color(0.42, 0.50, 0.65, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 40.0
	style.content_margin_top = 36.0
	style.content_margin_right = 40.0
	style.content_margin_bottom = 36.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	var title := Label.new()
	title.text = "长 夜  ·  暂 停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.55, 1.0))
	vbox.add_child(title)

	var hsep := HSeparator.new()
	vbox.add_child(hsep)

	_resume_button = _create_menu_button("继 续 游 戏", func() -> void: resume_requested.emit())
	vbox.add_child(_resume_button)

	_save_button = _create_menu_button("保 存 游 戏", func() -> void: save_requested.emit())
	vbox.add_child(_save_button)

	_load_button = _create_menu_button("读 取 游 戏", func() -> void: load_requested.emit())
	vbox.add_child(_load_button)

	_settings_button = _create_menu_button("系 统 设 置", func() -> void: settings_requested.emit())
	vbox.add_child(_settings_button)

	_title_button = _create_menu_button("返 回 标 题", func() -> void: title_requested.emit())
	vbox.add_child(_title_button)

	_quit_button = _create_menu_button("退 出 游 戏", func() -> void: quit_requested.emit())
	vbox.add_child(_quit_button)


func _create_menu_button(label_text: String, on_click: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(300, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(on_click)
	return btn


func open_menu() -> void:
	visible = true
	if _resume_button != null:
		_resume_button.grab_focus()


func close_menu() -> void:
	visible = false


func set_save_enabled(can_save: bool) -> void:
	if _save_button != null:
		_save_button.disabled = not can_save
