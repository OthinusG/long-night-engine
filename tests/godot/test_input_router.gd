extends SceneTree

## Step 12 input tests: action registration and bindings, idempotence, gamepad
## mapping, context switching, and context isolation.

var _failures: int = 0
var _requested: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registration()
	_test_idempotence()
	_test_gamepad_bindings()
	_test_context_action_sets()
	_test_dialogue_routing()
	_test_context_isolation()
	_test_global_actions()
	_finish()


## Every required action exists in the InputMap and can actually fire.
func _test_registration() -> void:
	InputRouter.ensure_actions()
	for action: StringName in InputRouter.required_actions():
		_expect(InputMap.has_action(action), "InputMap defines %s" % action)
		_expect(
			not InputMap.action_get_events(action).is_empty(),
			"%s has at least one binding" % action
		)


## Repeated registration (including router construction) must not duplicate
## bindings, even when another script registered some of them first.
func _test_idempotence() -> void:
	var before := _event_counts()
	InputRouter.ensure_actions()
	InputRouter.ensure_actions()
	_expect_idempotent(before, "repeated ensure_actions()")

	var router := InputRouter.new()
	_expect_idempotent(before, "router construction")
	_expect(router.get_context() == InputContext.Kind.BLOCKED, "A new router starts blocked")


func _expect_idempotent(before: Dictionary[StringName, int], label: String) -> void:
	var after := _event_counts()
	for action: StringName in before:
		_expect(
			after.get(action, -1) == before[action],
			"%s keeps %s at %d events, got %d"
			% [label, action, before[action], after.get(action, -1)]
		)


func _test_gamepad_bindings() -> void:
	_expect(_has_button(&"story_advance", JOY_BUTTON_A), "story_advance is bound to joypad A")
	_expect(_has_button(&"court_next", JOY_BUTTON_DPAD_RIGHT), "court_next is bound to d-pad right")
	_expect(_has_button(&"court_previous", JOY_BUTTON_DPAD_LEFT), "court_previous is bound to d-pad left")
	_expect(_has_axis(&"court_next", JOY_AXIS_LEFT_X, 1.0), "court_next is bound to the left stick")
	_expect(_has_axis(&"court_previous", JOY_AXIS_LEFT_X, -1.0), "court_previous is bound to the left stick")
	_expect(_has_button(&"court_press", JOY_BUTTON_X), "court_press is bound to joypad X")
	_expect(_has_button(&"court_present", JOY_BUTTON_Y), "court_present is bound to joypad Y")
	_expect(_has_button(&"court_record", JOY_BUTTON_BACK), "court_record is bound to joypad Back")
	_expect(_has_button(&"pause", JOY_BUTTON_START), "pause is bound to joypad Start")
	_expect(_has_button(&"ui_accept", JOY_BUTTON_A), "ui_accept works with a gamepad")
	_expect(_has_button(&"ui_cancel", JOY_BUTTON_B), "ui_cancel works with a gamepad")

	var router := _new_router(InputContext.Kind.DIALOGUE)
	_expect(router.handle_event(_button(JOY_BUTTON_A)), "A gamepad A press is routed")
	_expect(_requested == [&"story_advance"], "Gamepad A requested story_advance: %s" % [_requested])

	var court := _new_router(InputContext.Kind.COURT)
	_expect(court.handle_event(_axis_event(JOY_AXIS_LEFT_X, 1.0)), "The left stick routes")
	_expect(_requested == [&"court_next"], "Left stick right requested court_next: %s" % [_requested])


## Each context exposes exactly its own actions plus the two globals.
func _test_context_action_sets() -> void:
	var router := InputRouter.new()
	router.set_context(InputContext.Kind.DIALOGUE)
	_expect(router.get_context() == InputContext.Kind.DIALOGUE, "set_context stores the context")
	_expect_context(router, InputContext.Kind.DIALOGUE, [&"story_advance", &"court_record", &"auto_play", &"fast_forward"])
	_expect_context(router, InputContext.Kind.COURT, [
		&"court_next",
		&"court_previous",
		&"court_press",
		&"court_present",
		&"court_record",
	])
	_expect_context(router, InputContext.Kind.COURT_RECORD, [])
	_expect_context(router, InputContext.Kind.INVESTIGATION, [
		&"investigation_examine",
		&"investigation_talk",
		&"investigation_present",
		&"investigation_move",
		&"auto_play",
	])
	_expect_context(router, InputContext.Kind.PROCEDURE, [
		&"ui_up",
		&"ui_down",
		&"ui_accept",
	])
	_expect_context(router, InputContext.Kind.EVIDENCE_INSPECTION, [])
	_expect_context(router, InputContext.Kind.MENU, [&"ui_up", &"ui_down"])
	_expect_context(router, InputContext.Kind.BLOCKED, [])


func _test_dialogue_routing() -> void:
	var router := _new_router(InputContext.Kind.DIALOGUE)
	_expect(router.handle_event(_key(KEY_SPACE)), "Space advances dialogue")
	_expect(_requested == [&"story_advance"], "Space requested story_advance: %s" % [_requested])

	router = _new_router(InputContext.Kind.DIALOGUE)
	_expect(router.handle_event(_key(KEY_TAB)), "Tab opens the court record during dialogue")
	_expect(_requested == [&"court_record"], "Tab requested court_record: %s" % [_requested])

	router = _new_router(InputContext.Kind.DIALOGUE)
	_expect(router.handle_event(_key(KEY_A)), "A toggles auto-play during dialogue")
	_expect(_requested == [&"auto_play"], "A requested auto_play: %s" % [_requested])

	router = _new_router(InputContext.Kind.DIALOGUE)
	_expect(not router.handle_event(_key(KEY_Q)), "A court action is ignored during dialogue")
	_expect(not router.handle_event(_key(KEY_RIGHT)), "Court navigation is ignored during dialogue")
	_expect(_requested.is_empty(), "Ignored input emits nothing: %s" % [_requested])

	var echo := _key(KEY_SPACE)
	echo.echo = true
	_expect(not router.handle_event(echo), "Echo events are ignored")
	var release := _key(KEY_SPACE)
	release.pressed = false
	_expect(not router.handle_event(release), "Released events are ignored")
	_expect(not router.handle_event(InputEventMouseMotion.new()), "Mouse motion is ignored")
	# Spec 12.7: the router must never swallow mouse input; buttons keep working.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_expect(not router.handle_event(click), "Mouse clicks are left to the UI")
	_expect(_requested.is_empty(), "Echo, release, and mouse emit nothing: %s" % [_requested])


func _test_context_isolation() -> void:
	var router := _new_router(InputContext.Kind.COURT_RECORD)
	_expect(not router.handle_event(_key(KEY_SPACE)), "Dialogue advance is ignored in the court record")
	_expect(not router.handle_event(_key(KEY_TAB)), "Court actions are ignored in the court record")
	_expect(_requested.is_empty(), "The court record only accepts ui_cancel: %s" % [_requested])
	_expect(router.handle_event(_key(KEY_ESCAPE)), "Escape closes the court record")
	_expect(_requested == [&"ui_cancel"], "Escape requested ui_cancel: %s" % [_requested])
	_expect(router.handle_event(_mouse_button(MOUSE_BUTTON_RIGHT)), "Right-click closes the court record")
	_expect(_requested == [&"ui_cancel", &"ui_cancel"], "Right-click requested ui_cancel")

	router = _new_router(InputContext.Kind.COURT)
	_expect(router.handle_event(_key(KEY_RIGHT)), "Right advances statements in court")
	_expect(_requested == [&"court_next"], "Right requested court_next: %s" % [_requested])

	router = _new_router(InputContext.Kind.INVESTIGATION)
	_expect(router.handle_event(_key(KEY_1)), "1 examines in investigation")
	_expect(_requested == [&"investigation_examine"], "1 requested investigation_examine: %s" % [_requested])

	router = _new_router(InputContext.Kind.PROCEDURE)
	_expect(router.handle_event(_key(KEY_ENTER)), "Enter accepts in a procedure")
	_expect(_requested == [&"ui_accept"], "Enter requested ui_accept: %s" % [_requested])

	# Switching context changes the active set for the same event.
	router = _new_router(InputContext.Kind.COURT)
	_expect(router.handle_event(_key(KEY_RIGHT)), "Right routes in court")
	router.set_context(InputContext.Kind.BLOCKED)
	_expect(not router.handle_event(_key(KEY_RIGHT)), "Blocked ignores court navigation")
	_expect(not router.handle_event(_key(KEY_SPACE)), "Blocked ignores dialogue advance")
	_expect(router.handle_event(_key(KEY_ESCAPE)), "Blocked still routes global cancel")
	_expect(_requested == [&"court_next", &"ui_cancel"], "Blocked routes only global cancel: %s" % [_requested])


func _test_global_actions() -> void:
	var router := _new_router(InputContext.Kind.BLOCKED)
	_expect(router.handle_event(_key(KEY_ESCAPE)), "Escape is available in every context")
	_expect(_requested == [&"ui_cancel"], "Escape requested global ui_cancel")

	router = _new_router(InputContext.Kind.BLOCKED)
	_expect(router.handle_event(_mouse_button(MOUSE_BUTTON_RIGHT)), "Right-click is available in every context")
	_expect(_requested == [&"ui_cancel"], "Right-click requested global ui_cancel")

	router = _new_router(InputContext.Kind.BLOCKED)
	_expect(router.handle_event(_key(KEY_P)), "pause is available in every context")
	_expect(_requested == [&"pause"], "P requested pause: %s" % [_requested])

	router = _new_router(InputContext.Kind.BLOCKED)
	_expect(router.handle_event(_key(KEY_F12)), "debug_story_tools is available in every context")
	_expect(_requested == [&"debug_story_tools"], "F12 requested debug_story_tools: %s" % [_requested])

	router = _new_router(InputContext.Kind.DIALOGUE)
	_expect(router.handle_event(_key(KEY_F12)), "The debugger key also works during dialogue")
	_expect(_requested == [&"debug_story_tools"], "F12 requested debug_story_tools: %s" % [_requested])


func _new_router(context: InputContext.Kind) -> InputRouter:
	var router := InputRouter.new()
	router.action_requested.connect(_on_action_requested)
	router.set_context(context)
	_requested.clear()
	return router


func _on_action_requested(action: StringName) -> void:
	_requested.append(action)


func _event_counts() -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for action: StringName in InputRouter.required_actions():
		counts[action] = InputMap.action_get_events(action).size()
	return counts


func _expect_context(
	router: InputRouter,
	context: InputContext.Kind,
	own_actions: Array,
) -> void:
	var expected: Array[StringName] = InputRouter.GLOBAL_ACTIONS.duplicate()
	expected.append_array(own_actions)
	var actual := router.actions_for(context)
	_expect(
		_sorted(actual) == _sorted(expected),
		"%s exposes %s, got %s" % [InputContext.Kind.keys()[context], expected, actual]
	)


func _sorted(values: Array[StringName]) -> Array[StringName]:
	var copy := values.duplicate()
	copy.sort()
	return copy


func _has_button(action: StringName, button_index: JoyButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			var button: InputEventJoypadButton = event
			if button.button_index == button_index:
				return true
	return false


func _has_axis(action: StringName, axis: JoyAxis, axis_value: float) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			var motion: InputEventJoypadMotion = event
			if motion.axis == axis and is_equal_approx(motion.axis_value, axis_value):
				return true
	return false


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _button(button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


func _mouse_button(button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


func _axis_event(axis: JoyAxis, axis_value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	return event


func _finish() -> void:
	if _failures > 0:
		push_error("Input router tests failed: %d" % _failures)
		quit(1)
		return
	print("Input router tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
