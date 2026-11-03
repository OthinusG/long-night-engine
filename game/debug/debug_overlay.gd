class_name DebugOverlay
extends PanelContainer

## Development-only overlay for StoryDebugger: shows canonical state and submits
## debug operations. Display and input only; every rule lives in StoryDebugger.

const OK_COLOR: Color = Color(0.6, 0.9, 0.6)
const FAIL_COLOR: Color = Color(1.0, 0.55, 0.45)

var _debugger: StoryDebugger
var _dump: TextEdit
var _status: Label
var _preset_select: OptionButton
var _scene_input: LineEdit
var _testimony_input: LineEdit
var _statement_input: LineEdit
var _flag_input: LineEdit
var _flag_value: LineEdit
var _evidence_input: LineEdit
var _version_input: LineEdit
var _location_input: LineEdit
var _topic_input: LineEdit
var _hotspot_input: LineEdit
var _context_input: LineEdit
var _inspect_evidence_input: LineEdit
var _inspect_hotspot_input: LineEdit


func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		return
	_build()


func configure(debugger: StoryDebugger) -> void:
	_debugger = debugger
	if not _debugger.state_changed.is_connected(refresh):
		_debugger.state_changed.connect(refresh)
	if _preset_select == null:
		push_warning("[DebugOverlay] Story debugger is disabled in this build.")
		return
	_preset_select.clear()
	for preset_id: StringName in _debugger.preset_ids():
		_preset_select.add_item(String(preset_id))
	if _preset_select.item_count == 0:
		_preset_select.add_item("(no presets)")
	refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	if _debugger == null or _dump == null:
		return
	_dump.text = _debugger.describe_state()


func dump_text() -> String:
	return _dump.text if _dump != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


func _build() -> void:
	# The overlay covers live gameplay, so its own background must be opaque.
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.055, 0.065, 0.085, 0.99)
	background.border_color = Color(0.35, 0.4, 0.48)
	background.set_border_width_all(2)
	add_theme_stylebox_override("panel", background)

	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	header.add_child(_label("STORY DEBUGGER", 24, true))
	_button(header, "刷新", refresh)
	_button(header, "关闭 (F12)", toggle)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	layout.add_child(body)

	_dump = TextEdit.new()
	_dump.editable = false
	_dump.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_dump.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dump.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_dump)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(470.0, 0.0)
	controls.add_theme_constant_override("separation", 8)
	body.add_child(controls)

	controls.add_child(_label("JUMP", 18, true))
	var scene_row := _row(controls)
	_scene_input = _input_field(scene_row, "scene_id")
	_button(scene_row, "跳转场景", _jump_to_scene)
	var testimony_row := _row(controls)
	_testimony_input = _input_field(testimony_row, "testimony_id")
	_button(testimony_row, "跳转证词", _jump_to_testimony)
	var statement_row := _row(controls)
	_statement_input = _input_field(statement_row, "statement_id")
	_button(statement_row, "跳转证言", _jump_to_statement)
	var preset_row := _row(controls)
	_preset_select = OptionButton.new()
	_preset_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_child(_preset_select)
	_button(preset_row, "应用预设", _apply_preset)

	controls.add_child(_label("FLAGS", 18, true))
	var flag_row := _row(controls)
	_flag_input = _input_field(flag_row, "flag_id")
	_flag_value = _input_field(flag_row, "value")
	_button(flag_row, "设置", _set_flag)
	_button(flag_row, "清除", _clear_flag)

	controls.add_child(_label("EVIDENCE", 18, true))
	var evidence_row := _row(controls)
	_evidence_input = _input_field(evidence_row, "evidence_id")
	_version_input = _input_field(evidence_row, "version")
	_button(evidence_row, "获得", _add_evidence)
	_button(evidence_row, "移除", _remove_evidence)
	_button(evidence_row, "改版本", _set_evidence_version)

	controls.add_child(_label("FLOW", 18, true))
	var flow_row := _row(controls)
	_button(flow_row, "快进", _fast_forward)
	_button(flow_row, "暂停", _pause)
	_button(flow_row, "继续", _resume)

	controls.add_child(_label("INVESTIGATION", 18, true))
	var location_row := _row(controls)
	_location_input = _input_field(location_row, "location_id")
	_button(location_row, "跳转地点", _jump_to_location)
	_button(location_row, "结束调查", _end_investigation)
	var topic_row := _row(controls)
	_topic_input = _input_field(topic_row, "topic_id")
	_button(topic_row, "解锁话题", _unlock_topic)
	var hotspot_row := _row(controls)
	_hotspot_input = _input_field(hotspot_row, "hotspot_id")
	_button(hotspot_row, "标记已查", _mark_hotspot)
	_button(hotspot_row, "取消标记", _unmark_hotspot)

	controls.add_child(_label("PROCEDURE / INSPECTION", 18, true))
	var procedure_row := _row(controls)
	_context_input = _input_field(procedure_row, "context_id")
	_button(procedure_row, "跳转程序", _jump_to_procedure)
	var inspect_row := _row(controls)
	_inspect_evidence_input = _input_field(inspect_row, "evidence_id")
	_inspect_hotspot_input = _input_field(inspect_row, "hotspot_id")
	_button(inspect_row, "标记检视", _mark_inspected)
	_button(inspect_row, "取消检视", _unmark_inspected)

	_status = _label("Ready.", 16, false)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0.0, 64.0)
	controls.add_child(_status)


func _jump_to_scene() -> void:
	_report(_debugger.jump_to_scene(StringName(_scene_input.text.strip_edges())))


func _jump_to_testimony() -> void:
	_report(_debugger.jump_to_testimony(StringName(_testimony_input.text.strip_edges())))


func _jump_to_statement() -> void:
	_report(_debugger.jump_to_statement(
		StringName(_testimony_input.text.strip_edges()),
		StringName(_statement_input.text.strip_edges()),
	))


func _apply_preset() -> void:
	if _preset_select.item_count == 0 or _preset_select.get_item_text(0).begins_with("("):
		_status.text = "FAIL  No debug presets loaded."
		_status.add_theme_color_override("font_color", FAIL_COLOR)
		return
	_report(_debugger.apply_preset(StringName(
		_preset_select.get_item_text(_preset_select.selected)
	)))


func _set_flag() -> void:
	_report(_debugger.set_flag(
		StringName(_flag_input.text.strip_edges()),
		_parse_flag_value(_flag_value.text.strip_edges()),
	))


func _clear_flag() -> void:
	_report(_debugger.clear_flag(StringName(_flag_input.text.strip_edges())))


func _add_evidence() -> void:
	_report(_debugger.add_evidence(StringName(_evidence_input.text.strip_edges())))


func _remove_evidence() -> void:
	_report(_debugger.remove_evidence(StringName(_evidence_input.text.strip_edges())))


func _set_evidence_version() -> void:
	_report(_debugger.set_evidence_version(
		StringName(_evidence_input.text.strip_edges()),
		StringName(_version_input.text.strip_edges()),
	))


func _fast_forward() -> void:
	_report(_debugger.fast_forward())


func _jump_to_location() -> void:
	_report(_debugger.jump_to_location(StringName(_location_input.text.strip_edges())))


func _end_investigation() -> void:
	_report(_debugger.end_investigation())


func _unlock_topic() -> void:
	_report(_debugger.unlock_topic(StringName(_topic_input.text.strip_edges())))


func _mark_hotspot() -> void:
	_report(_debugger.set_hotspot_examined(
		StringName(_hotspot_input.text.strip_edges()),
		true,
	))


func _unmark_hotspot() -> void:
	_report(_debugger.set_hotspot_examined(
		StringName(_hotspot_input.text.strip_edges()),
		false,
	))


func _jump_to_procedure() -> void:
	_report(_debugger.jump_to_procedure(StringName(_context_input.text.strip_edges())))


func _mark_inspected() -> void:
	_report(_debugger.set_hotspot_inspected(
		StringName(_inspect_evidence_input.text.strip_edges()),
		StringName(_inspect_hotspot_input.text.strip_edges()),
		true,
	))


func _unmark_inspected() -> void:
	_report(_debugger.set_hotspot_inspected(
		StringName(_inspect_evidence_input.text.strip_edges()),
		StringName(_inspect_hotspot_input.text.strip_edges()),
		false,
	))


func _pause() -> void:
	_report(_debugger.pause())


func _resume() -> void:
	_report(_debugger.resume())


## Debug flag values stay primitive so they can be saved as JSON.
func _parse_flag_value(text: String) -> Variant:
	if text == "true":
		return true
	if text == "false":
		return false
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	return text


func _report(success: bool) -> void:
	_status.text = "%s  %s" % ["OK" if success else "FAIL", _debugger.last_message]
	_status.add_theme_color_override("font_color", OK_COLOR if success else FAIL_COLOR)
	refresh()


func _label(text: String, size: int, expands: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	if expands:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _row(parent: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


func _input_field(parent: HBoxContainer, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(120.0, 0.0)
	parent.add_child(field)
	return field


func _button(parent: HBoxContainer, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)
	return button
