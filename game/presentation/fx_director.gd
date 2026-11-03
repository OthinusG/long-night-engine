class_name FxDirector
extends RefCounted

## Screen effects live here only: no UI script builds its own shake, flash or
## tint. Effects never change gameplay state, and none of them block the story.

signal notice_requested(text: String)
signal notice_dismissed

const FLASH_LAYER: int = 35
const TINT_LAYER: int = 34

var _host: Control
var _flash_rect: ColorRect
var _tint_rect: ColorRect
var _flash_tween: Tween
var _notice_label: Label
var _notice_tween: Tween
var _cutin_texture: TextureRect
var _notice_waiting_for_input: bool = false
var _notice_dismiss_in_progress: bool = false


func _init(host: Control) -> void:
	_host = host
	_tint_rect = _build_layer("FxTint", TINT_LAYER)
	_flash_rect = _build_layer("FxFlash", FLASH_LAYER)
	_notice_label = Label.new()
	_notice_label.name = "PresentationNotice"
	_notice_label.z_index = 40
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_size_override("font_size", 72)
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42, 1.0))
	_notice_label.set_anchors_preset(Control.PRESET_CENTER)
	_notice_label.offset_left = -360.0
	_notice_label.offset_top = -80.0
	_notice_label.offset_right = 360.0
	_notice_label.offset_bottom = 80.0
	_notice_label.visible = false
	_host.add_child(_notice_label)
	_cutin_texture = TextureRect.new()
	_cutin_texture.name = "CourtCutin"
	_cutin_texture.z_index = 39
	_cutin_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutin_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cutin_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cutin_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cutin_texture.offset_left = 120.0
	_cutin_texture.offset_top = 180.0
	_cutin_texture.offset_right = -120.0
	_cutin_texture.offset_bottom = -180.0
	_cutin_texture.visible = false
	_host.add_child(_cutin_texture)


func is_flashing() -> bool:
	return _flash_tween != null and _flash_tween.is_valid()


func flash(color: Color = Color(1.0, 1.0, 1.0), duration: float = 0.25) -> void:
	_flash_rect.color = Color(color.r, color.g, color.b, 1.0)
	_flash_rect.visible = true
	_kill_flash()
	if not _can_tween():
		_flash_rect.visible = false
		return
	_flash_tween = _host.create_tween()
	_flash_tween.tween_property(_flash_rect, "modulate:a", 0.0, duration)
	_flash_tween.tween_callback(func() -> void: _flash_rect.visible = false)


func set_tint(color: Color, alpha: float = 0.18) -> void:
	_tint_rect.color = Color(color.r, color.g, color.b, alpha)
	_tint_rect.visible = true


func clear_tint() -> void:
	_tint_rect.visible = false


func tint_color() -> Color:
	return _tint_rect.color


## A contradiction beat: a coloured flash plus a short tint pulse. The gameplay
## result was already decided by CourtRuntime before this runs.
func contradiction(accent: Color) -> void:
	flash(accent, 0.3)
	set_tint(accent, 0.14)
	if _can_tween():
		var tween: Tween = _host.create_tween()
		tween.tween_interval(0.35)
		tween.tween_callback(clear_tint)


func notice(text: String, _duration: float = 1.5, wait_for_input: bool = false) -> void:
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_waiting_for_input = wait_for_input
	_notice_dismiss_in_progress = false
	_notice_label.text = text
	_notice_label.visible = true
	_notice_label.scale = Vector2(0.72, 0.72)
	_notice_label.modulate.a = 0.0
	var cutin_path := ""
	match text:
		"威慑":
			cutin_path = "res://assets/presentation/cutin_intimidate.png"
		"反对":
			cutin_path = "res://assets/presentation/cutin_objection.png"
	if not cutin_path.is_empty() and ResourceLoader.exists(cutin_path):
		_cutin_texture.texture = load(cutin_path) as Texture2D
		_cutin_texture.visible = true
		_cutin_texture.modulate.a = 0.0
		_notice_label.visible = false
	else:
		_cutin_texture.visible = false
	if _can_tween():
		_notice_tween = _host.create_tween()
		_notice_tween.set_parallel(true)
		_notice_tween.tween_property(_notice_label, "scale", Vector2.ONE, 0.18)
		_notice_tween.tween_property(_notice_label, "modulate:a", 1.0, 0.12)
		_notice_tween.tween_property(_cutin_texture, "modulate:a", 0.9, 0.12)
		if wait_for_input:
			_notice_tween.chain().tween_callback(func() -> void:
				_notice_tween = null
			)
		else:
			_notice_tween.chain().tween_interval(_duration)
			_notice_tween.chain().tween_property(_notice_label, "modulate:a", 0.0, 0.22)
			_notice_tween.chain().tween_property(_cutin_texture, "modulate:a", 0.0, 0.22)
			_notice_tween.chain().tween_callback(_finish_notice)
	else:
		_notice_tween = null
	# The notice target also belongs to the UI layer for accessibility/debug text.
	notice_requested.emit(text)


func has_dismissible_notice() -> bool:
	return _notice_waiting_for_input


## Starts the short exit animation for an input-dismissed notice.
func dismiss_notice() -> bool:
	if not _notice_waiting_for_input:
		return false
	if _notice_dismiss_in_progress:
		return true
	_notice_dismiss_in_progress = true
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	if not _can_tween():
		_finish_notice()
		notice_dismissed.emit()
		return true
	_notice_tween = _host.create_tween()
	_notice_tween.set_parallel(true)
	_notice_tween.tween_property(_notice_label, "modulate:a", 0.0, 0.18)
	_notice_tween.tween_property(_cutin_texture, "modulate:a", 0.0, 0.18)
	_notice_tween.chain().tween_callback(func() -> void:
		_finish_notice()
		notice_dismissed.emit()
	)
	return true


func _finish_notice() -> void:
	_notice_waiting_for_input = false
	_notice_dismiss_in_progress = false
	_notice_label.visible = false
	_cutin_texture.visible = false
	_notice_tween = null


func _build_layer(layer_name: String, layer: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = layer_name
	rect.color = Color(0.0, 0.0, 0.0, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = layer
	rect.visible = false
	_host.add_child(rect)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect


func _kill_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null


func _can_tween() -> bool:
	return _host.is_inside_tree()
