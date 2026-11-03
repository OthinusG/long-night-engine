class_name CharacterStage
extends RefCounted

## Transient visual state for the speaking cast. It is deliberately not part of
## the save payload: after a load the stage is rebuilt from the story/runtime
## state through the presenters.

enum Slot { LEFT, CENTER, RIGHT }

const SLOT_WIDTH_RATIO: float = 0.35
const STAGE_TOP_OFFSET: float = -920.0
const STAGE_BOTTOM_OFFSET: float = 0.0


class SlotView:
	var character_id: StringName = &""
	var expression_id: StringName = &""
	var slot: int = Slot.CENTER
	var panel: Panel
	var texture: TextureRect
	var label: Label


var _root: Control
var _content: ContentRegistry
var _assets: AssetRegistry
var _views: Dictionary[StringName, SlotView] = {}
var _idle_time: float = 0.0


func _init(root: Control, content: ContentRegistry, assets: AssetRegistry) -> void:
	_root = root
	_content = content
	_assets = assets


static func slot_center_ratio(slot: Slot) -> float:
	match slot:
		Slot.LEFT:
			return 0.22
		Slot.RIGHT:
			return 0.78
		_:
			return 0.5


static func slot_from_name(slot_name: StringName) -> Slot:
	match slot_name:
		&"left":
			return Slot.LEFT
		&"right":
			return Slot.RIGHT
		_:
			return Slot.CENTER


## Returns false when the character is unknown to the content registry.
func show_character(character_id: StringName, slot: Slot = Slot.CENTER) -> bool:
	if not _content.has_character(character_id):
		push_warning("[Stage] Unknown character: %s" % character_id)
		return false
	var view: SlotView = _views.get(character_id)
	if view == null:
		view = _create_view(character_id)
		_views[character_id] = view
	view.slot = slot
	view.expression_id = _resolve_expression(character_id, view.expression_id)
	_apply(view)
	return true


func hide_character(character_id: StringName) -> bool:
	var view: SlotView = _views.get(character_id)
	if view == null:
		return false
	_root.remove_child(view.panel)
	view.panel.queue_free()
	_views.erase(character_id)
	return true


func set_expression(character_id: StringName, expression_id: StringName) -> bool:
	var view: SlotView = _views.get(character_id)
	if view == null:
		return false
	view.expression_id = _resolve_expression(character_id, expression_id)
	_apply(view)
	if view.panel.is_inside_tree():
		view.texture.modulate.a = 0.0
		var tween := view.panel.create_tween()
		tween.tween_property(view.texture, "modulate:a", 1.0, 0.16)
	return true


func tick(delta: float) -> void:
	_idle_time += delta
	for view: SlotView in _views.values():
		var breathe := sin(_idle_time * 2.2 + float(view.slot)) * 0.012 + 1.0
		view.texture.scale = Vector2(breathe, breathe)


func move_character(character_id: StringName, slot: Slot) -> bool:
	var view: SlotView = _views.get(character_id)
	if view == null:
		return false
	view.slot = slot
	_apply(view)
	return true


func clear_stage() -> void:
	for character_id: StringName in _views.keys():
		hide_character(character_id)


func has_character(character_id: StringName) -> bool:
	return _views.has(character_id)


func visible_characters() -> Array[StringName]:
	var ids: Array[StringName] = []
	for character_id: StringName in _views:
		ids.append(character_id)
	ids.sort_custom(
		func(left: StringName, right: StringName) -> bool:
			return _views[left].slot < _views[right].slot
	)
	return ids


func current_slot(character_id: StringName) -> Slot:
	var view: SlotView = _views.get(character_id)
	return view.slot if view != null else Slot.CENTER


func current_expression(character_id: StringName) -> StringName:
	var view: SlotView = _views.get(character_id)
	return view.expression_id if view != null else &""


func stage_size() -> int:
	return _views.size()


func _create_view(character_id: StringName) -> SlotView:
	var view := SlotView.new()
	view.character_id = character_id

	view.panel = Panel.new()
	view.panel.name = "Slot_%s" % character_id
	view.panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(view.panel)

	view.texture = TextureRect.new()
	view.texture.name = "Portrait"
	view.texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.panel.add_child(view.texture)
	view.texture.set_anchors_preset(Control.PRESET_FULL_RECT)

	view.label = Label.new()
	view.label.name = "Caption"
	view.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	view.panel.add_child(view.label)
	view.label.set_anchors_preset(Control.PRESET_FULL_RECT)
	return view


func _apply(view: SlotView) -> void:
	var center: float = slot_center_ratio(view.slot)
	view.panel.anchor_left = center - SLOT_WIDTH_RATIO * 0.5
	view.panel.anchor_right = center + SLOT_WIDTH_RATIO * 0.5
	view.panel.anchor_top = 1.0
	view.panel.anchor_bottom = 1.0
	# set_anchor-style assignment keeps the previous offsets, so they are set
	# explicitly here instead of being inherited from the default rect.
	view.panel.offset_left = 0.0
	view.panel.offset_right = 0.0
	view.panel.offset_top = STAGE_TOP_OFFSET
	view.panel.offset_bottom = STAGE_BOTTOM_OFFSET
	var portrait: String = _assets.resolve_portrait(view.character_id, view.expression_id)
	view.texture.texture = load(portrait) as Texture2D if not portrait.is_empty() else null
	view.texture.visible = view.texture.texture != null
	var display_name: String = _content.get_display_name(view.character_id)
	view.label.text = (
		"%s\n[%s]" % [display_name, view.expression_id]
		if view.expression_id != &""
		else display_name
	)
	view.label.visible = not view.texture.visible


func _resolve_expression(character_id: StringName, expression_id: StringName) -> StringName:
	if not expression_id.is_empty() and _content.has_expression(character_id, expression_id):
		return expression_id
	var fallback: StringName = _content.default_expression(character_id)
	if expression_id != &"" and expression_id != fallback:
		push_warning(
			"[Stage] Unknown expression %s for %s; using %s"
			% [expression_id, character_id, fallback]
		)
	return fallback
