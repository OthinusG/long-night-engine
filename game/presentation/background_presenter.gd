class_name BackgroundPresenter
extends RefCounted

## Shows the current background by stable ID. The resource is resolved through
## AssetRegistry; when the art does not exist yet the fill colour stands in, so
## gameplay is unaffected while Chapter 1 art is in production.

const DIALOGUE_FILL: Color = Color("18253a")
const COURT_FILL: Color = Color("3a2025")
const MISSING_FILL: Color = Color("241d2b")

var current_background_id: StringName = &""

var _fill: ColorRect
var _label: Label
var _texture_rect: TextureRect
var _placeholder_rect: TextureRect
var _assets: AssetRegistry
var _court_active: bool = false
var _tween: Tween


func _init(fill: ColorRect, label: Label, assets: AssetRegistry) -> void:
	_fill = fill
	_label = label
	_assets = assets
	_placeholder_rect = _build_texture("BackgroundPlaceholder", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_texture_rect = _build_texture("BackgroundTexture", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_refresh()


func show_background(background_id: StringName, fade_seconds: float = 0.0) -> void:
	current_background_id = background_id
	var path: String = _assets.resolve(AssetRegistry.Kind.BACKGROUND, background_id)
	if path.is_empty():
		_texture_rect.texture = null
		_texture_rect.visible = false
		_placeholder_rect.texture = _assets.placeholder_texture()
		_placeholder_rect.visible = _placeholder_rect.texture != null
	else:
		_texture_rect.texture = load(path) as Texture2D
		_texture_rect.visible = _texture_rect.texture != null
		_placeholder_rect.visible = false
	_fill.color = _base_fill()
	_refresh_label()
	if fade_seconds > 0.0 and _can_tween():
		_texture_rect.modulate.a = 0.0
		_kill_tween()
		_tween = _texture_rect.create_tween()
		_tween.tween_property(_texture_rect, "modulate:a", 1.0, fade_seconds)


func clear() -> void:
	current_background_id = &""
	_texture_rect.texture = null
	_texture_rect.visible = false
	_placeholder_rect.visible = false
	_fill.color = _base_fill()
	_refresh_label()


## Court presentation is a state of the same background, not a second layer.
func set_court_active(active: bool) -> void:
	_court_active = active
	_fill.color = _base_fill()
	_refresh_label()


func is_court_active() -> bool:
	return _court_active


func is_showing(background_id: StringName) -> bool:
	return current_background_id == background_id


func has_texture() -> bool:
	return _texture_rect.visible and _texture_rect.texture != null


func label_text() -> String:
	return _label.text


func _base_fill() -> Color:
	if _court_active:
		return COURT_FILL
	if current_background_id.is_empty():
		return DIALOGUE_FILL
	if not has_texture():
		return MISSING_FILL
	return DIALOGUE_FILL


func _refresh_label() -> void:
	var suffix: String = (
		String(current_background_id) if not current_background_id.is_empty() else "NONE"
	)
	_label.text = (
		"COURT / CROSS-EXAMINATION  %s" % suffix
		if _court_active
		else "BACKGROUND  %s" % suffix
	)


func _refresh() -> void:
	_fill.color = _base_fill()
	_refresh_label()


func _build_texture(node_name: String, stretch: TextureRect.StretchMode) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = stretch
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	_fill.add_child(rect)
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rect.grow_vertical = Control.GROW_DIRECTION_BOTH
	return rect


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _can_tween() -> bool:
	return _texture_rect.is_inside_tree()
