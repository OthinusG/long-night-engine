class_name InputRouter
extends RefCounted

## Routes raw input events to gameplay actions according to an explicit context.
##
## Gameplay code listens to `action_requested` instead of testing raw keys, so
## no script outside this file needs to know about Space, Q, or a joypad button.
## The router never inspects UI state: the caller sets the context.

signal action_requested(action: StringName)

## Available in every context (cancel, debugger, and pause are global).
const GLOBAL_ACTIONS: Array[StringName] = [&"ui_cancel", &"pause", &"debug_story_tools"]

var _context: InputContext.Kind = InputContext.Kind.BLOCKED


func _init() -> void:
	ensure_actions()


## Adds the InputMap actions and their bindings. Idempotent: existing actions
## keep their bindings, only missing bindings are added. Safe under --headless.
static func ensure_actions() -> void:
	for action: StringName in required_actions():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var bindings := _default_bindings()
	for action: StringName in bindings:
		for event: InputEvent in bindings[action]:
			_add_event_once(action, event)


## The complete action list in stable order. `ui_accept`, `ui_cancel`, `ui_up`
## and `ui_down` are Godot built-ins that are reused, not redefined.
static func required_actions() -> Array[StringName]:
	var actions: Array[StringName] = [
		&"story_advance",
		&"ui_accept",
		&"ui_cancel",
		&"ui_up",
		&"ui_down",
		&"court_next",
		&"court_previous",
		&"court_press",
		&"court_present",
		&"court_record",
		&"investigation_examine",
		&"investigation_talk",
		&"investigation_present",
		&"investigation_move",
		&"pause",
		&"debug_story_tools",
		&"auto_play",
		&"fast_forward",
	]
	return actions


func set_context(context: InputContext.Kind) -> void:
	_context = context


func get_context() -> InputContext.Kind:
	return _context


## The action set for a context: the global actions plus that context's own
## actions. Nothing else may leak across contexts.
func actions_for(context: InputContext.Kind) -> Array[StringName]:
	var actions: Array[StringName] = GLOBAL_ACTIONS.duplicate()
	match context:
		InputContext.Kind.DIALOGUE:
			actions.append_array([&"story_advance", &"court_record", &"auto_play", &"fast_forward"])
		InputContext.Kind.COURT:
			actions.append_array([
				&"court_next",
				&"court_previous",
				&"court_press",
				&"court_present",
				&"court_record",
			])
		InputContext.Kind.COURT_RECORD:
			pass
		InputContext.Kind.INVESTIGATION:
			actions.append_array([
				&"investigation_examine",
				&"investigation_talk",
				&"investigation_present",
				&"investigation_move",
				&"auto_play",
			])
		InputContext.Kind.PROCEDURE:
			actions.append_array([&"ui_up", &"ui_down", &"ui_accept"])
		InputContext.Kind.EVIDENCE_INSPECTION:
			pass
		InputContext.Kind.MENU:
			actions.append_array([&"ui_up", &"ui_down"])
		InputContext.Kind.BLOCKED:
			pass
	return actions


## Returns true when the event was consumed by an action of the active context.
## Echoes and releases are ignored, and the first matching action wins.
func handle_event(event: InputEvent) -> bool:
	if event == null or event.is_echo() or not event.is_pressed():
		return false
	for action: StringName in actions_for(_context):
		if event.is_action_pressed(action):
			action_requested.emit(action)
			return true
	return false


static func _default_bindings() -> Dictionary[StringName, Array]:
	var bindings: Dictionary[StringName, Array] = {}
	bindings[&"story_advance"] = [_key(KEY_SPACE), _key(KEY_ENTER), _button(JOY_BUTTON_A)]
	bindings[&"ui_accept"] = [_key(KEY_SPACE), _key(KEY_ENTER), _button(JOY_BUTTON_A)]
	bindings[&"ui_cancel"] = [
		_key(KEY_ESCAPE),
		_button(JOY_BUTTON_B),
		_mouse_button(MOUSE_BUTTON_RIGHT),
	]
	bindings[&"ui_up"] = [_key(KEY_UP), _button(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)]
	bindings[&"ui_down"] = [_key(KEY_DOWN), _button(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)]
	bindings[&"court_next"] = [
		_key(KEY_RIGHT),
		_key(KEY_D),
		_button(JOY_BUTTON_DPAD_RIGHT),
		_axis(JOY_AXIS_LEFT_X, 1.0),
	]
	bindings[&"court_previous"] = [
		_key(KEY_LEFT),
		_key(KEY_A),
		_button(JOY_BUTTON_DPAD_LEFT),
		_axis(JOY_AXIS_LEFT_X, -1.0),
	]
	bindings[&"court_press"] = [_key(KEY_Q), _button(JOY_BUTTON_X)]
	bindings[&"court_present"] = [_key(KEY_E), _button(JOY_BUTTON_Y)]
	bindings[&"court_record"] = [_key(KEY_TAB), _button(JOY_BUTTON_BACK)]
	bindings[&"investigation_examine"] = [_key(KEY_Q), _key(KEY_1)]
	bindings[&"investigation_talk"] = [_key(KEY_T), _key(KEY_2)]
	bindings[&"investigation_present"] = [_key(KEY_E), _key(KEY_3)]
	bindings[&"investigation_move"] = [_key(KEY_M), _key(KEY_4)]
	bindings[&"pause"] = [_key(KEY_P), _button(JOY_BUTTON_START)]
	bindings[&"debug_story_tools"] = [_key(KEY_F12)]
	bindings[&"auto_play"] = [_key(KEY_A)]
	bindings[&"fast_forward"] = [_key(KEY_CTRL)]
	return bindings


static func _add_event_once(action: StringName, event: InputEvent) -> void:
	for existing: InputEvent in InputMap.action_get_events(action):
		if _same_binding(existing, event):
			return
	InputMap.action_add_event(action, event)


static func _same_binding(first: InputEvent, second: InputEvent) -> bool:
	if first is InputEventKey and second is InputEventKey:
		var first_key: InputEventKey = first
		var second_key: InputEventKey = second
		return (
			first_key.keycode == second_key.keycode
			and first_key.physical_keycode == second_key.physical_keycode
		)
	if first is InputEventMouseButton and second is InputEventMouseButton:
		var first_mouse: InputEventMouseButton = first
		var second_mouse: InputEventMouseButton = second
		return first_mouse.button_index == second_mouse.button_index
	if first is InputEventJoypadButton and second is InputEventJoypadButton:
		var first_button: InputEventJoypadButton = first
		var second_button: InputEventJoypadButton = second
		return first_button.button_index == second_button.button_index
	if first is InputEventJoypadMotion and second is InputEventJoypadMotion:
		var first_motion: InputEventJoypadMotion = first
		var second_motion: InputEventJoypadMotion = second
		return (
			first_motion.axis == second_motion.axis
			and signf(first_motion.axis_value) == signf(second_motion.axis_value)
		)
	return false


static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	return event


static func _mouse_button(button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	return event


static func _button(button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	return event


static func _axis(axis: JoyAxis, axis_value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	return event
