class_name SettingsUI
extends PanelContainer

## Settings panel providing audio, text speed, auto-play speed, display mode,
## and resolution sliders/options.
##
## Apply semantics: volume sliders and text speed apply immediately; display mode and
## resolution are applied by the Apply button. Closing the panel writes the settings file.

signal closed

const VOLUME_MAX: float = 100.0
const DISPLAY_MODES: Array[DisplaySettings.Mode] = [
	DisplaySettings.Mode.WINDOWED,
	DisplaySettings.Mode.BORDERLESS,
	DisplaySettings.Mode.FULLSCREEN,
]

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var _manager: SettingsManager
var _volume_sliders: Dictionary[StringName, HSlider] = {}
var _text_speed_slider: HSlider
var _auto_speed_slider: HSlider
var _display_mode_button: OptionButton
var _resolution_button: OptionButton
var _previous_focus: Control
## Set while open_panel() rewrites the controls, so refresh does not echo back
## into SettingsManager.
var _refreshing: bool = false


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title := Label.new()
	title.text = "设置"
	content.add_child(title)

	for bus_name: StringName in SettingsManager.AUDIO_BUSES:
		var slider := _add_slider_row(
			content,
			_bus_title(bus_name),
			VOLUME_MAX,
			GameSettings.DEFAULT_VOLUME * VOLUME_MAX,
			_volume_text,
			func(value: float) -> void: _on_volume_changed(bus_name, value / VOLUME_MAX),
		)
		slider.name = "%sSlider" % bus_name
		_volume_sliders[bus_name] = slider

	# Four discrete text-speed levels.
	_text_speed_slider = _add_slider_row(
		content,
		"文字速度",
		3.0,
		GameSettings.TEXT_SPEED_LEVELS.find(GameSettings.DEFAULT_TEXT_SPEED),
		_text_speed_text,
		func(value: float) -> void: _on_text_speed_changed(value),
	)
	_text_speed_slider.name = "TextSpeedSlider"

	# Four discrete auto-play speed levels.
	_auto_speed_slider = _add_slider_row(
		content,
		"自动播放速度",
		3.0,
		GameSettings.AUTO_SPEED_LEVELS.find(GameSettings.nearest_level(GameSettings.DEFAULT_AUTO_SPEED, GameSettings.AUTO_SPEED_LEVELS)),
		_auto_speed_text,
		func(value: float) -> void: _on_auto_speed_changed(value),
	)
	_auto_speed_slider.name = "AutoSpeedSlider"


	# Display mode
	var display_row := HBoxContainer.new()
	display_row.add_theme_constant_override("separation", 10)
	var display_label := Label.new()
	display_label.text = "显示模式"
	display_label.custom_minimum_size = Vector2(140.0, 0.0)
	display_row.add_child(display_label)
	_display_mode_button = OptionButton.new()
	_display_mode_button.name = "DisplayModeButton"
	_display_mode_button.custom_minimum_size = Vector2(240.0, 0.0)
	for mode: DisplaySettings.Mode in DISPLAY_MODES:
		_display_mode_button.add_item(_mode_title(mode))
	display_row.add_child(_display_mode_button)
	content.add_child(display_row)

	# Resolution options
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 10)
	var res_label := Label.new()
	res_label.text = "分辨率"
	res_label.custom_minimum_size = Vector2(140.0, 0.0)
	res_row.add_child(res_label)
	_resolution_button = OptionButton.new()
	_resolution_button.name = "ResolutionButton"
	_resolution_button.custom_minimum_size = Vector2(240.0, 0.0)
	for res: Vector2i in RESOLUTIONS:
		var res_desc := "%d × %d" % [res.x, res.y]
		if res.x == 1920 and res.y == 1080:
			res_desc += " (1080p 标准)"
		elif res.x == 1280 and res.y == 720:
			res_desc += " (720p)"
		elif res.x == 2560 and res.y == 1440:
			res_desc += " (2K)"
		elif res.x == 3840 and res.y == 2160:
			res_desc += " (4K)"
		_resolution_button.add_item(res_desc)
	res_row.add_child(_resolution_button)
	content.add_child(res_row)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	content.add_child(buttons)

	var apply_button := Button.new()
	apply_button.name = "ApplyButton"
	apply_button.text = "应用显示设置"
	apply_button.pressed.connect(_on_apply_pressed)
	buttons.add_child(apply_button)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "返回"
	back_button.pressed.connect(_on_back_pressed)
	buttons.add_child(back_button)

	if _manager != null:
		_refresh()


func configure(manager: SettingsManager) -> void:
	_manager = manager
	_refresh()


func open_panel() -> void:
	if is_inside_tree():
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and not is_ancestor_of(focused):
			_previous_focus = focused
	visible = true
	_refresh()
	_volume_sliders[&"Master"].grab_focus()


## Hides the panel and persists the settings. Does not emit `closed`, so a
## caller handling that signal may call this safely.
func close_panel() -> void:
	visible = false
	if _manager != null:
		_manager.save()
	if (
		_previous_focus != null
		and is_instance_valid(_previous_focus)
		and _previous_focus.is_visible_in_tree()
	):
		_previous_focus.grab_focus()
	_previous_focus = null


func is_open() -> bool:
	return visible


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_back_pressed()
			accept_event()


func _refresh() -> void:
	if _manager == null or not is_node_ready():
		return
	var current := _manager.settings
	_refreshing = true
	_volume_sliders[&"Master"].value = current.master_volume * VOLUME_MAX
	_volume_sliders[&"BGM"].value = current.bgm_volume * VOLUME_MAX
	_volume_sliders[&"SFX"].value = current.sfx_volume * VOLUME_MAX
	_volume_sliders[&"Voice"].value = current.voice_volume * VOLUME_MAX
	_text_speed_slider.value = GameSettings.TEXT_SPEED_LEVELS.find(GameSettings.nearest_level(current.text_speed, GameSettings.TEXT_SPEED_LEVELS))
	_auto_speed_slider.value = GameSettings.AUTO_SPEED_LEVELS.find(GameSettings.nearest_level(current.auto_speed, GameSettings.AUTO_SPEED_LEVELS))
	_display_mode_button.select(DISPLAY_MODES.find(current.display_mode))

	var res_idx := -1
	for i: int in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i].x == current.window_width and RESOLUTIONS[i].y == current.window_height:
			res_idx = i
			break
	if res_idx < 0:
		res_idx = 2 # default 1920x1080
	_resolution_button.select(res_idx)

	_refreshing = false


func _text_speed_text(value: float) -> String:
	var speed := GameSettings.TEXT_SPEED_LEVELS[clampi(int(value), 0, 3)]
	if speed <= 0.0:
		return "瞬时"
	return "%d 字/秒" % int(speed)


func _auto_speed_text(value: float) -> String:
	var delay := GameSettings.AUTO_SPEED_LEVELS[clampi(int(value), 0, 3)]
	if delay <= 0.0:
		return "即时"
	return "%.1f 秒" % delay


func _on_volume_changed(bus_name: StringName, linear: float) -> void:
	if _refreshing or _manager == null:
		return
	_manager.set_volume(bus_name, linear)


func _on_text_speed_changed(value: float) -> void:
	if _refreshing or _manager == null:
		return
	_manager.set_text_speed(GameSettings.TEXT_SPEED_LEVELS[clampi(int(value), 0, 3)])


func _on_auto_speed_changed(value: float) -> void:
	if _refreshing or _manager == null:
		return
	_manager.set_auto_speed(GameSettings.AUTO_SPEED_LEVELS[clampi(int(value), 0, 3)])



## Display changes are the expensive ones, so they wait for an explicit Apply.
func _on_apply_pressed() -> void:
	if _manager == null:
		return
	var selected_res: Vector2i = RESOLUTIONS[_resolution_button.selected]
	_manager.settings.window_width = selected_res.x
	_manager.settings.window_height = selected_res.y
	_manager.settings.display_mode = DISPLAY_MODES[_display_mode_button.selected]
	_manager.apply_display()
	_manager.save()


func _on_back_pressed() -> void:
	close_panel()
	closed.emit()


## Builds a "title [slider] value" row and keeps the value label in sync.
func _add_slider_row(
	parent: VBoxContainer,
	title: String,
	maximum: float,
	initial: float,
	format: Callable,
	on_changed: Callable,
) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var title_label := Label.new()
	title_label.text = title
	title_label.custom_minimum_size = Vector2(140.0, 0.0)
	row.add_child(title_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = maximum
	slider.step = 1.0
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(320.0, 0.0)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = format.call(initial)
	value_label.custom_minimum_size = Vector2(110.0, 0.0)
	row.add_child(value_label)

	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = format.call(value)
		on_changed.call(value)
	)
	parent.add_child(row)
	return slider


func _volume_text(value: float) -> String:
	return "%d%%" % int(value)


func _bus_title(bus_name: StringName) -> String:

	match bus_name:
		&"Master":
			return "总音量"
		&"BGM":
			return "背景音乐"
		&"SFX":
			return "音效"
		_:
			return "语音"


func _mode_title(mode: DisplaySettings.Mode) -> String:
	match mode:
		DisplaySettings.Mode.BORDERLESS:
			return "无边框窗口"
		DisplaySettings.Mode.FULLSCREEN:
			return "全屏"
		_:
			return "窗口"
