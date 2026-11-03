class_name GalleryUI
extends PanelContainer

## Gallery dialog providing CG gallery and BGM listening player with material locks.

signal closed

const GALLERY_PATH: String = "res://data/gallery.json"

var cg_list: Array[Dictionary] = []
var bgm_list: Array[Dictionary] = []

var _manager: GalleryManager
var _tab_cg_btn: Button
var _tab_bgm_btn: Button
var _cg_scroll: ScrollContainer
var _bgm_scroll: ScrollContainer
var _cg_grid: GridContainer
var _bgm_rows_container: VBoxContainer
var _fullscreen_preview: Control
var _preview_texture: TextureRect
var _preview_title: Label
var _audio_player: AudioStreamPlayer
var _now_playing_title: Label
var _now_playing_id: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(1300, 780)
	anchors_preset = Control.PRESET_CENTER
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	style.border_color = Color(0.42, 0.50, 0.65, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 36.0
	style.content_margin_top = 28.0
	style.content_margin_right = 36.0
	style.content_margin_bottom = 28.0
	add_theme_stylebox_override("panel", style)

	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = &"BGM"
	add_child(_audio_player)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 18)
	add_child(root_vbox)

	# Header bar: Title + Tabs + Back
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)

	var title_lbl := Label.new()
	title_lbl.text = "鉴 赏 画 廊"
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.96, 0.84, 0.55, 1.0))
	header.add_child(title_lbl)

	_tab_cg_btn = Button.new()
	_tab_cg_btn.text = "【 画 卷 鉴 赏 】"
	_tab_cg_btn.custom_minimum_size = Vector2(180, 42)
	_tab_cg_btn.pressed.connect(func() -> void: _switch_tab(true))
	header.add_child(_tab_cg_btn)

	_tab_bgm_btn = Button.new()
	_tab_bgm_btn.text = "【 音 律 清 听 】"
	_tab_bgm_btn.custom_minimum_size = Vector2(180, 42)
	_tab_bgm_btn.pressed.connect(func() -> void: _switch_tab(false))
	header.add_child(_tab_bgm_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var back_btn := Button.new()
	back_btn.text = "返 回"
	back_btn.custom_minimum_size = Vector2(120, 42)
	back_btn.pressed.connect(func() -> void: _on_close())
	header.add_child(back_btn)

	root_vbox.add_child(header)

	var hsep := HSeparator.new()
	root_vbox.add_child(hsep)

	# Container for the two views
	var view_container := PanelContainer.new()
	view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner_style := StyleBoxEmpty.new()
	view_container.add_theme_stylebox_override("panel", inner_style)
	root_vbox.add_child(view_container)

	# 1. CG View
	_cg_scroll = ScrollContainer.new()
	_cg_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_container.add_child(_cg_scroll)

	_cg_grid = GridContainer.new()
	_cg_grid.columns = 5
	_cg_grid.add_theme_constant_override("h_separation", 24)
	_cg_grid.add_theme_constant_override("v_separation", 24)
	_cg_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cg_scroll.add_child(_cg_grid)

	# 2. BGM View
	_bgm_scroll = ScrollContainer.new()
	_bgm_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bgm_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bgm_scroll.visible = false
	view_container.add_child(_bgm_scroll)

	var bgm_root := VBoxContainer.new()
	bgm_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_root.add_theme_constant_override("separation", 12)
	_bgm_scroll.add_child(bgm_root)

	var now_playing_box := HBoxContainer.new()
	now_playing_box.add_theme_constant_override("separation", 16)
	var np_tag := Label.new()
	np_tag.text = "当前播放："
	np_tag.add_theme_color_override("font_color", Color(0.96, 0.84, 0.55, 1.0))
	now_playing_box.add_child(np_tag)
	_now_playing_title = Label.new()
	_now_playing_title.text = "未在播放"
	_now_playing_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	now_playing_box.add_child(_now_playing_title)

	var stop_btn := Button.new()
	stop_btn.text = "■ 停止播放"
	stop_btn.pressed.connect(_stop_bgm)
	now_playing_box.add_child(stop_btn)

	bgm_root.add_child(now_playing_box)

	var bgm_sep := HSeparator.new()
	bgm_root.add_child(bgm_sep)

	_bgm_rows_container = VBoxContainer.new()
	_bgm_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bgm_rows_container.add_theme_constant_override("separation", 12)
	bgm_root.add_child(_bgm_rows_container)

	# Fullscreen preview overlay
	_fullscreen_preview = Control.new()
	_fullscreen_preview.visible = false
	_fullscreen_preview.top_level = true
	_fullscreen_preview.z_index = 100
	_fullscreen_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fullscreen_preview.offset_left = 0.0
	_fullscreen_preview.offset_top = 0.0
	_fullscreen_preview.offset_right = 0.0
	_fullscreen_preview.offset_bottom = 0.0
	_fullscreen_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_fullscreen_preview.gui_input.connect(_on_preview_gui_input)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.96)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_overlay.offset_left = 0.0
	bg_overlay.offset_top = 0.0
	bg_overlay.offset_right = 0.0
	bg_overlay.offset_bottom = 0.0
	bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen_preview.add_child(bg_overlay)

	_preview_texture = TextureRect.new()
	_preview_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_texture.offset_left = 40.0
	_preview_texture.offset_top = 40.0
	_preview_texture.offset_right = -40.0
	_preview_texture.offset_bottom = -70.0
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen_preview.add_child(_preview_texture)

	_preview_title = Label.new()
	_preview_title.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_preview_title.offset_top = -60.0
	_preview_title.offset_bottom = -20.0
	_preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_title.add_theme_font_size_override("font_size", 22)
	_preview_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_fullscreen_preview.add_child(_preview_title)

	add_child(_fullscreen_preview)

	_rebuild_views()


func configure(manager: GalleryManager) -> void:
	_manager = manager
	if _manager != null and not _manager.unlock_changed.is_connected(_rebuild_views):
		_manager.unlock_changed.connect(_rebuild_views)
	if is_node_ready():
		_rebuild_views()


func open_gallery() -> void:
	visible = true
	_rebuild_views()
	_switch_tab(true)


func close_gallery() -> void:
	_stop_bgm()
	if _fullscreen_preview != null:
		_fullscreen_preview.visible = false
	visible = false


func _on_close() -> void:
	close_gallery()
	closed.emit()


func _switch_tab(show_cg: bool) -> void:
	_cg_scroll.visible = show_cg
	_bgm_scroll.visible = not show_cg
	_tab_cg_btn.disabled = show_cg
	_tab_bgm_btn.disabled = not show_cg


func _rebuild_views() -> void:
	if _cg_grid == null or _bgm_rows_container == null:
		return

	_load_gallery_data_if_needed()

	# Rebuild CGs
	for child in _cg_grid.get_children():
		_cg_grid.remove_child(child)
		child.queue_free()

	var unlocked_cgs: int = 0
	for item: Dictionary in cg_list:
		var is_unlocked: bool = _manager != null and _manager.is_cg_unlocked(item["id"])
		if is_unlocked:
			unlocked_cgs += 1
		var card := _build_cg_card(item, is_unlocked)
		_cg_grid.add_child(card)

	_tab_cg_btn.text = "【 画 卷 鉴 赏 (%d/%d) 】" % [unlocked_cgs, cg_list.size()]

	# Rebuild BGMs
	for child in _bgm_rows_container.get_children():
		_bgm_rows_container.remove_child(child)
		child.queue_free()

	var unlocked_bgms: int = 0
	for item: Dictionary in bgm_list:
		var is_unlocked: bool = _manager != null and _manager.is_bgm_unlocked(item["id"])
		if is_unlocked:
			unlocked_bgms += 1
		var row := _build_bgm_row(item, is_unlocked)
		_bgm_rows_container.add_child(row)

	_tab_bgm_btn.text = "【 音 律 清 听 (%d/%d) 】" % [unlocked_bgm_count_val(unlocked_bgms), bgm_list.size()]


func _load_gallery_data_if_needed() -> void:
	if not cg_list.is_empty() or not bgm_list.is_empty():
		return
	if not FileAccess.file_exists(GALLERY_PATH):
		return
	var file := FileAccess.open(GALLERY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var dict := parsed as Dictionary
	if dict.has("cgs") and typeof(dict["cgs"]) == TYPE_ARRAY:
		for item in dict["cgs"]:
			if typeof(item) == TYPE_DICTIONARY:
				cg_list.append(item as Dictionary)
	if dict.has("bgms") and typeof(dict["bgms"]) == TYPE_ARRAY:
		for item in dict["bgms"]:
			if typeof(item) == TYPE_DICTIONARY:
				bgm_list.append(item as Dictionary)


func unlocked_bgm_count_val(count: int) -> int:
	return count


func _build_cg_card(item: Dictionary, is_unlocked: bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(216, 160)
	vbox.add_theme_constant_override("separation", 6)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(216, 122)
	btn.clip_contents = true

	var file_path: String = item["file"]
	if is_unlocked and ResourceLoader.exists(file_path):
		var tex: Texture2D = load(file_path) as Texture2D
		btn.icon = tex
		btn.expand_icon = true
		btn.tooltip_text = "点击全屏鉴赏"
		btn.pressed.connect(func() -> void: _open_cg_preview(item))
	else:
		btn.text = "🔒  锁 定"
		btn.disabled = true
		btn.tooltip_text = "在游戏剧情中触发此场景后解锁"

	vbox.add_child(btn)

	var label := Label.new()
	label.text = item["name"] if is_unlocked else "？？？？"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	if is_unlocked:
		label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.9))
	else:
		label.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55, 0.6))
	vbox.add_child(label)

	return vbox


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if is_preview_open():
				close_preview()
			else:
				_on_close()
			accept_event()


func is_preview_open() -> bool:
	return _fullscreen_preview != null and _fullscreen_preview.visible


func close_preview() -> void:
	if _fullscreen_preview != null:
		_fullscreen_preview.visible = false


func _open_cg_preview(item: Dictionary) -> void:
	var file_path: String = item["file"]
	if ResourceLoader.exists(file_path):
		_preview_texture.texture = load(file_path) as Texture2D
		_preview_title.text = "【 %s 】  (点击左键或右键退出)" % item["name"]
		_fullscreen_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fullscreen_preview.offset_left = 0.0
		_fullscreen_preview.offset_top = 0.0
		_fullscreen_preview.offset_right = 0.0
		_fullscreen_preview.offset_bottom = 0.0
		_fullscreen_preview.visible = true


func _on_preview_gui_input(event: InputEvent) -> void:
	if not is_preview_open():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			close_preview()
			accept_event()


func _build_bgm_row(item: Dictionary, is_unlocked: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.10, 0.13, 0.19, 0.8) if is_unlocked else Color(0.07, 0.08, 0.11, 0.5)
	row_style.set_corner_radius_all(6)
	row_style.content_margin_left = 18.0
	row_style.content_margin_top = 12.0
	row_style.content_margin_right = 18.0
	row_style.content_margin_bottom = 12.0
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	row.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = item["name"] if is_unlocked else "？？？？？？"
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_unlocked:
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.93, 0.98, 1.0))
	else:
		name_lbl.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55, 0.6))
	hbox.add_child(name_lbl)

	var id_lbl := Label.new()
	id_lbl.text = "[ %s ]" % item["id"] if is_unlocked else "[ 🔒 锁定 ]"
	id_lbl.add_theme_font_size_override("font_size", 13)
	if is_unlocked:
		id_lbl.add_theme_color_override("font_color", Color(0.6, 0.68, 0.8, 0.6))
	else:
		id_lbl.add_theme_color_override("font_color", Color(0.35, 0.38, 0.45, 0.5))
	hbox.add_child(id_lbl)

	var play_btn := Button.new()
	if is_unlocked:
		play_btn.text = "▶ 试 听"
		play_btn.custom_minimum_size = Vector2(100, 38)
		play_btn.pressed.connect(func() -> void: _play_bgm(item))
	else:
		play_btn.text = "🔒 未解锁"
		play_btn.disabled = true
		play_btn.custom_minimum_size = Vector2(100, 38)
	hbox.add_child(play_btn)

	return row


func _play_bgm(item: Dictionary) -> void:
	var file_path: String = item["file"]
	if ResourceLoader.exists(file_path):
		var stream: AudioStream = load(file_path) as AudioStream
		_audio_player.stream = stream
		_audio_player.play()
		_now_playing_id = item["id"]
		_now_playing_title.text = "%s  (%s)" % [item["name"], item["id"]]


func _stop_bgm() -> void:
	if _audio_player != null:
		_audio_player.stop()
	_now_playing_id = ""
	if _now_playing_title != null:
		_now_playing_title.text = "未在播放"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _fullscreen_preview != null and _fullscreen_preview.visible:
			_fullscreen_preview.visible = false
			get_viewport().set_input_as_handled()
			return
		_on_close()
		get_viewport().set_input_as_handled()
