class_name InvestigationUI
extends Control

## Investigation display and input only. Every action is submitted to
## InvestigationRuntime, which decides what it means.

signal examine_requested(hotspot_id: StringName)
signal talk_requested(topic_id: StringName)
signal move_requested(location_id: StringName)
signal present_requested
signal mode_requested(mode: InvestigationState.Mode)

@onready var location_label: Label = %LocationLabel
@onready var character_label: Label = %CharacterLabel
@onready var stage: Control = %Stage
@onready var mode_panel: PanelContainer = %ModePanel
@onready var mode_row: HBoxContainer = %ModeRow
@onready var examine_button: Button = %ExamineButton
@onready var talk_button: Button = %TalkButton
@onready var present_button: Button = %PresentButton
@onready var move_button: Button = %MoveButton


func _ready() -> void:
	examine_button.pressed.connect(
		func() -> void: mode_requested.emit(InvestigationState.Mode.LOCATION_ACTIVE)
	)
	talk_button.pressed.connect(
		func() -> void: mode_requested.emit(InvestigationState.Mode.TALK_MODE)
	)
	move_button.pressed.connect(
		func() -> void: mode_requested.emit(InvestigationState.Mode.MOVE_MODE)
	)
	present_button.pressed.connect(func() -> void: present_requested.emit())


func refresh(runtime: InvestigationRuntime, location: LocationDef, character: String) -> void:
	var active: bool = runtime != null and runtime.state.active
	location_label.text = location.display_name if location != null else ""
	character_label.text = character
	_rebuild_hotspots(runtime, location)
	_rebuild_mode_row(runtime, location)
	_set_interaction_enabled(active and runtime.state.mode != InvestigationState.Mode.WAIT_STORY_BRANCH)
	talk_button.disabled = not (active and runtime.can_talk())
	present_button.disabled = not (active and runtime.can_present())
	if not active:
		return
	_apply_mode(runtime.state.mode)


func set_interaction_enabled(enabled: bool) -> void:
	_set_interaction_enabled(enabled)
	if enabled and is_visible_in_tree():
		examine_button.grab_focus()


func hotspot_ids() -> Array[StringName]:
	var result: Array[StringName]
	for child: Node in stage.get_children():
		result.append(StringName(child.name))
	return result


func topic_ids() -> Array[StringName]:
	return _row_button_ids()


func move_ids() -> Array[StringName]:
	return _row_button_ids()


func _apply_mode(mode: InvestigationState.Mode) -> void:
	stage.visible = mode == InvestigationState.Mode.LOCATION_ACTIVE
	mode_panel.visible = mode in [
		InvestigationState.Mode.TALK_MODE,
		InvestigationState.Mode.MOVE_MODE,
	]


func _set_interaction_enabled(enabled: bool) -> void:
	examine_button.disabled = not enabled
	move_button.disabled = not enabled


func _rebuild_hotspots(runtime: InvestigationRuntime, location: LocationDef) -> void:
	for child: Node in stage.get_children():
		# Detach before freeing: the rebuild can run from inside a hotspot's own
		# pressed signal, where Godot keeps the node locked.
		stage.remove_child(child)
		child.queue_free()
	if runtime == null or location == null:
		return
	# Authored hotspots are normalized, so the overlay survives any viewport size.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.85, 0.55, 0.16)
	style.border_color = Color(0.95, 0.85, 0.55, 0.85)
	style.set_border_width_all(2)
	for hotspot: HotspotDef in location.hotspots:
		var button := Button.new()
		var hotspot_id: StringName = hotspot.id
		button.name = String(hotspot.id)
		button.text = (
			"%s ✓" % hotspot.id if runtime.is_hotspot_examined(hotspot.id) else String(hotspot.id)
		)
		button.add_theme_stylebox_override("normal", style)
		button.pressed.connect(func() -> void: examine_requested.emit(hotspot_id))
		stage.add_child(button)
		button.set_anchor(SIDE_LEFT, hotspot.rect.position.x)
		button.set_anchor(SIDE_TOP, hotspot.rect.position.y)
		button.set_anchor(SIDE_RIGHT, hotspot.rect.end.x)
		button.set_anchor(SIDE_BOTTOM, hotspot.rect.end.y)
		# set_anchor() keeps the current rect, so the offsets must be cleared for
		# the button to fill its normalized rect.
		button.offset_left = 0.0
		button.offset_top = 0.0
		button.offset_right = 0.0
		button.offset_bottom = 0.0


func _rebuild_mode_row(runtime: InvestigationRuntime, location: LocationDef) -> void:
	for child: Node in mode_row.get_children():
		mode_row.remove_child(child)
		child.queue_free()
	if runtime == null or location == null:
		return
	match runtime.state.mode:
		InvestigationState.Mode.TALK_MODE:
			for topic: TalkTopicDef in runtime.available_topics():
				var text: String = topic.title
				if runtime.is_topic_completed(topic.id):
					text = "%s ✓" % text
				_add_row_button(topic.id, text, func() -> void: talk_requested.emit(topic.id))
		InvestigationState.Mode.MOVE_MODE:
			for destination: StringName in runtime.available_moves():
				_add_row_button(
					destination,
					String(destination),
					func() -> void: move_requested.emit(destination),
				)
		_:
			pass
	if mode_row.get_child_count() == 0:
		var hint := Label.new()
		hint.text = "(没有可用选项)"
		mode_row.add_child(hint)


func _add_row_button(id: StringName, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.name = String(id)
	button.text = text
	button.pressed.connect(handler)
	mode_row.add_child(button)


func _row_button_ids() -> Array[StringName]:
	var result: Array[StringName]
	for child: Node in mode_row.get_children():
		if child is Button:
			result.append(StringName(child.name))
	return result
