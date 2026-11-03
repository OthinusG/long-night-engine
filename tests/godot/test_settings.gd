extends SceneTree

## Step 12 settings tests: defaults, save/load roundtrip, invalid-file fallback,
## AudioServer projection, display modes, and the settings panel.
##
## Scratch files live in /tmp: user:// is outside the sandbox.

const TEST_DIR: String = "/tmp/long_night_settings_tests"
const TEST_PATH: String = TEST_DIR + "/settings.json"
const SETTINGS_SCENE: String = "res://game/ui/settings/settings_ui.tscn"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clear_test_directory()
	_test_defaults()
	_test_invalid_file_fallback()
	_test_roundtrip()
	_test_audio_buses()
	_test_display_modes()
	await _test_settings_ui()
	_finish()


func _test_defaults() -> void:
	var settings := GameSettings.new()
	_expect(is_equal_approx(settings.master_volume, 0.8), "Master defaults to 0.8")
	_expect(is_equal_approx(settings.bgm_volume, 0.8), "BGM defaults to 0.8")
	_expect(is_equal_approx(settings.sfx_volume, 0.8), "SFX defaults to 0.8")
	_expect(is_equal_approx(settings.voice_volume, 0.8), "Voice defaults to 0.8")
	_expect(settings.text_speed == GameSettings.DEFAULT_TEXT_SPEED, "Text speed defaults to the fastest readable level")
	_expect(is_equal_approx(settings.auto_speed, GameSettings.DEFAULT_AUTO_SPEED), "Auto speed defaults to a discrete level")
	_expect(settings.display_mode == DisplaySettings.Mode.WINDOWED, "Windowed is the default mode")
	_expect(
		settings.window_width == 1920 and settings.window_height == 1080,
		"The default window is 1920x1080: %dx%d" % [settings.window_width, settings.window_height]
	)
	_expect(
		settings.duplicate_settings().to_dictionary() == settings.to_dictionary(),
		"duplicate_settings copies every value"
	)
	_expect(
		GameSettings.from_dictionary({}).to_dictionary() == settings.to_dictionary(),
		"An empty dictionary yields defaults"
	)

	# Settings are a normal state: no file means defaults plus a reason.
	var manager := SettingsManager.new(TEST_PATH)
	_expect(not manager.load_settings(), "A missing settings file reports false")
	_expect(not manager.last_error.is_empty(), "A missing file is explained: %s" % manager.last_error)
	_expect(is_equal_approx(manager.settings.master_volume, 0.8), "A missing file yields defaults")


func _test_invalid_file_fallback() -> void:
	_write_text("{\"master_volume\": ")
	var manager := SettingsManager.new(TEST_PATH)
	_expect(
		is_equal_approx(manager.settings.master_volume, GameSettings.DEFAULT_VOLUME),
		"Malformed JSON yields defaults"
	)

	_write_text("[1, 2, 3]")
	manager = SettingsManager.new(TEST_PATH)
	_expect(
		is_equal_approx(manager.settings.bgm_volume, GameSettings.DEFAULT_VOLUME),
		"JSON that is not an object yields defaults"
	)

	_write_text("")
	manager = SettingsManager.new(TEST_PATH)
	_expect(manager.settings.text_speed == GameSettings.DEFAULT_TEXT_SPEED, "An empty file yields defaults")

	_write_text(JSON.stringify({
		"master_volume": "loud",
		"bgm_volume": 5.0,
		"sfx_volume": -1.0,
		"voice_volume": true,
		"text_speed": 999.0,
		"display_mode": "hologram",
		"window_width": 10,
		"window_height": "tall",
	}))
	manager = SettingsManager.new(TEST_PATH)
	_expect(
		is_equal_approx(manager.settings.master_volume, GameSettings.DEFAULT_VOLUME),
		"A wrongly typed volume falls back to the default"
	)
	_expect(is_equal_approx(manager.settings.bgm_volume, 1.0), "A too-large volume is clamped")
	_expect(is_equal_approx(manager.settings.sfx_volume, 0.0), "A negative volume is clamped")
	_expect(
		is_equal_approx(manager.settings.voice_volume, GameSettings.DEFAULT_VOLUME),
		"A boolean is not accepted as a volume"
	)
	_expect(
		manager.settings.text_speed == GameSettings.DEFAULT_TEXT_SPEED,
		"Text speed falls back to a discrete maximum level"
	)
	_expect(
		manager.settings.display_mode == DisplaySettings.Mode.WINDOWED,
		"An unknown display mode falls back to windowed"
	)
	_expect(
		manager.settings.window_width == DisplaySettings.MIN_WIDTH,
		"A tiny window width is clamped: %d" % manager.settings.window_width
	)
	_expect(
		manager.settings.window_height == GameSettings.DEFAULT_WINDOW_HEIGHT,
		"A wrongly typed window height falls back to the default"
	)


func _test_roundtrip() -> void:
	var manager := SettingsManager.new(TEST_PATH)
	var settings := manager.settings
	settings.master_volume = 0.35
	settings.bgm_volume = 0.0
	settings.sfx_volume = 1.0
	settings.voice_volume = 0.6
	settings.text_speed = GameSettings.TEXT_SPEED_LEVELS[2]
	settings.auto_speed = GameSettings.AUTO_SPEED_LEVELS[2]
	settings.display_mode = DisplaySettings.Mode.BORDERLESS
	settings.window_width = 1600
	settings.window_height = 900
	_expect(manager.save(), "Saving settings succeeds: %s" % manager.last_error)
	_expect(FileAccess.file_exists(TEST_PATH), "The settings file exists")
	_expect(manager.last_error.is_empty(), "A successful save clears the error")

	var text := SettingsSerializer.to_json(settings)
	_expect(text.contains("\"format_version\": 1"), "JSON writes the format version")
	_expect(text.begins_with("{\n  \""), "JSON is pretty printed: %s" % text.substr(0, 20))
	_expect(text.ends_with("\n"), "JSON ends with a newline")
	_expect(SettingsSerializer.to_json(settings) == text, "Serialization is deterministic")
	_expect(
		SettingsSerializer.from_json(text).to_dictionary() == settings.to_dictionary(),
		"from_json roundtrips every value"
	)

	var reloaded := SettingsManager.new(TEST_PATH)
	_expect(reloaded.load_settings(), "The stored settings file loads")
	_expect(
		reloaded.settings.to_dictionary() == settings.to_dictionary(),
		"Save/load roundtrips every value: %s" % [reloaded.settings.to_dictionary()]
	)


func _test_audio_buses() -> void:
	var manager := SettingsManager.new(TEST_PATH)
	for bus_name: StringName in SettingsManager.AUDIO_BUSES:
		_expect(AudioServer.get_bus_index(bus_name) >= 0, "The %s bus exists" % bus_name)
	for bus_name: StringName in [&"BGM", &"SFX", &"Voice"]:
		var index := AudioServer.get_bus_index(bus_name)
		_expect(AudioServer.get_bus_send(index) == &"Master", "%s is routed to Master" % bus_name)

	manager.set_volume(&"BGM", 0.25)
	var bgm_index := AudioServer.get_bus_index(&"BGM")
	_expect(is_equal_approx(manager.settings.bgm_volume, 0.25), "set_volume updates the settings")
	_expect(is_equal_approx(manager.get_volume(&"BGM"), 0.25), "get_volume reports the stored value")
	_expect(
		is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bgm_index)), 0.25),
		"The BGM volume reaches the AudioServer: %f"
		% db_to_linear(AudioServer.get_bus_volume_db(bgm_index))
	)

	# A slider at 0 must not push -inf into the mixer.
	manager.set_volume(&"SFX", 0.0)
	var sfx_index := AudioServer.get_bus_index(&"SFX")
	_expect(
		is_equal_approx(AudioServer.get_bus_volume_db(sfx_index), AudioBusConfig.SILENT_DB),
		"A zero volume uses the silent floor: %f" % AudioServer.get_bus_volume_db(sfx_index)
	)

	var changes: Array[GameSettings] = []
	manager.settings_changed.connect(func(changed: GameSettings) -> void: changes.append(changed))
	manager.set_volume(&"Master", 0.5)
	_expect(changes.size() == 1, "set_volume notifies listeners once, got %d" % changes.size())
	manager.set_text_speed(GameSettings.TEXT_SPEED_LEVELS[2])
	_expect(changes.size() == 2, "set_text_speed notifies listeners")
	_expect(manager.settings.text_speed == GameSettings.TEXT_SPEED_LEVELS[2], "set_text_speed stores the value")
	_expect(manager.get_volume(&"Master") == 0.5, "The master volume was stored")

	manager.reset_to_defaults()
	_expect(changes.size() == 3, "reset_to_defaults notifies listeners")
	_expect(
		is_equal_approx(manager.settings.master_volume, GameSettings.DEFAULT_VOLUME),
		"reset_to_defaults restores defaults"
	)
	_expect(
		is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), GameSettings.DEFAULT_VOLUME),
		"reset_to_defaults also reaches the AudioServer"
	)


func _test_display_modes() -> void:
	var modes: Array[DisplaySettings.Mode] = [
		DisplaySettings.Mode.WINDOWED,
		DisplaySettings.Mode.BORDERLESS,
		DisplaySettings.Mode.FULLSCREEN,
	]
	for mode: DisplaySettings.Mode in modes:
		var mode_name := DisplaySettings.mode_to_string(mode)
		_expect(
			DisplaySettings.mode_from_string(mode_name) == mode,
			"Display mode %s roundtrips" % mode_name
		)
	_expect(
		DisplaySettings.mode_from_string("FULLSCREEN") == DisplaySettings.Mode.FULLSCREEN,
		"Mode parsing ignores case"
	)
	_expect(
		DisplaySettings.mode_from_string("bogus") == DisplaySettings.Mode.WINDOWED,
		"An unknown mode name falls back to windowed"
	)

	# Applying a mode is a no-op under --headless and must not touch the data.
	var manager := SettingsManager.new(TEST_PATH)
	manager.settings.display_mode = DisplaySettings.Mode.FULLSCREEN
	manager.settings.window_width = 1600
	manager.settings.window_height = 900
	var before := manager.settings.to_dictionary()
	manager.apply_display()
	DisplaySettings.apply(DisplaySettings.Mode.BORDERLESS, 0, -10)
	DisplaySettings.apply(DisplaySettings.Mode.WINDOWED, 1280, 720)
	_expect(
		manager.settings.to_dictionary() == before,
		"Applying a display mode does not corrupt settings"
	)
	_expect(
		manager.settings.display_mode == DisplaySettings.Mode.FULLSCREEN,
		"The requested mode survives apply"
	)
	_expect(manager.save(), "Display settings save: %s" % manager.last_error)
	_expect(
		SettingsManager.new(TEST_PATH).settings.display_mode == DisplaySettings.Mode.FULLSCREEN,
		"The display mode persists"
	)


func _test_settings_ui() -> void:
	var packed: PackedScene = load(SETTINGS_SCENE)
	_expect(packed != null, "The settings scene loads")
	if packed == null:
		return
	var panel := packed.instantiate() as SettingsUI
	_expect(panel != null, "The settings scene is a SettingsUI")
	if panel == null:
		return
	root.add_child(panel)
	await process_frame

	var master_slider := panel.find_child("MasterSlider", true, false) as HSlider
	var bgm_slider := panel.find_child("BGMSlider", true, false) as HSlider
	var text_speed_slider := panel.find_child("TextSpeedSlider", true, false) as HSlider
	var auto_speed_slider := panel.find_child("AutoSpeedSlider", true, false) as HSlider
	var display_button := panel.find_child("DisplayModeButton", true, false) as OptionButton
	var apply_button := panel.find_child("ApplyButton", true, false) as Button
	var back_button := panel.find_child("BackButton", true, false) as Button
	_expect(master_slider != null, "The master volume slider exists")
	_expect(bgm_slider != null, "The BGM volume slider exists")
	_expect(text_speed_slider != null, "The text-speed slider exists")
	_expect(auto_speed_slider != null, "The auto-play speed slider exists")
	_expect(display_button != null and display_button.item_count == 3, "The display mode has three options")
	_expect(apply_button != null, "The Apply button exists")
	_expect(back_button != null, "The Back button exists")
	if (
		master_slider == null
		or bgm_slider == null
		or text_speed_slider == null
		or auto_speed_slider == null
		or display_button == null
		or apply_button == null
		or back_button == null
	):
		panel.free()
		return

	var manager := SettingsManager.new(TEST_PATH)
	var closed_count: Array[int] = [0]
	panel.closed.connect(func() -> void: closed_count[0] += 1)
	panel.configure(manager)
	_expect(not panel.is_open(), "The panel starts hidden")

	# Deterministic values: the file on disk was written by an earlier test.
	manager.reset_to_defaults()
	# Spec 12.10: a panel records the focus it took over and gives it back.
	var probe := Button.new()
	probe.name = "FocusProbe"
	root.add_child(probe)
	probe.grab_focus()
	_expect(root.gui_get_focus_owner() == probe, "The focus probe holds focus before the panel opens")
	panel.open_panel()
	await process_frame
	_expect(panel.is_open(), "open_panel shows the panel")
	_expect(
		is_equal_approx(master_slider.value, GameSettings.DEFAULT_VOLUME * 100.0),
		"The slider reflects the stored master volume: %f" % master_slider.value
	)
	_expect(is_equal_approx(text_speed_slider.value, 2.0), "The text-speed slider reflects the default readable level")
	_expect(is_equal_approx(auto_speed_slider.value, 2.0), "The auto-play slider reflects the default discrete level")
	_expect(
		panel.get_viewport().gui_get_focus_owner() != null,
		"Opening the panel grabs focus"
	)

	# Volume and text speed apply immediately.
	bgm_slider.value = 40.0
	_expect(
		is_equal_approx(manager.settings.bgm_volume, 0.4),
		"Moving a volume slider applies immediately: %f" % manager.settings.bgm_volume
	)
	_expect(
		is_equal_approx(
			db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"BGM"))),
			0.4
		),
		"The slider reaches the AudioServer"
	)
	text_speed_slider.value = 2.0
	_expect(
		manager.settings.text_speed == GameSettings.TEXT_SPEED_LEVELS[2],
		"Moving the text-speed slider applies immediately: %f" % manager.settings.text_speed
	)
	auto_speed_slider.value = 2.0
	_expect(
		manager.settings.auto_speed == GameSettings.AUTO_SPEED_LEVELS[2],
		"Moving the auto-play slider applies immediately: %f" % manager.settings.auto_speed
	)

	# Display mode waits for Apply.
	display_button.select(2)
	_expect(
		manager.settings.display_mode == DisplaySettings.Mode.WINDOWED,
		"The display mode changes only on Apply"
	)
	apply_button.pressed.emit()
	_expect(
		manager.settings.display_mode == DisplaySettings.Mode.FULLSCREEN,
		"Apply stores the chosen display mode"
	)

	var res_button := panel.find_child("ResolutionButton", true, false) as OptionButton
	_expect(res_button != null, "ResolutionButton exists in SettingsUI")
	if res_button != null:
		res_button.select(0)
		apply_button.pressed.emit()
		_expect(
			manager.settings.window_width == 1280 and manager.settings.window_height == 720,
			"Apply stores chosen resolution: %dx%d" % [manager.settings.window_width, manager.settings.window_height]
		)



	back_button.pressed.emit()
	await process_frame
	_expect(not panel.is_open(), "Back closes the panel")
	_expect(closed_count[0] == 1, "Back emits closed once, got %d" % closed_count[0])
	_expect(
		root.gui_get_focus_owner() == probe,
		"Closing the panel restores the previous focus"
	)
	_expect(FileAccess.file_exists(TEST_PATH), "Closing the panel persists the settings")

	var reloaded := SettingsManager.new(TEST_PATH)
	_expect(is_equal_approx(reloaded.settings.bgm_volume, 0.4), "The applied volume was saved")
	_expect(reloaded.settings.text_speed == GameSettings.TEXT_SPEED_LEVELS[2], "The applied text speed was saved")
	_expect(reloaded.settings.auto_speed == GameSettings.AUTO_SPEED_LEVELS[2], "The applied auto-play speed was saved")
	_expect(
		reloaded.settings.display_mode == DisplaySettings.Mode.FULLSCREEN,
		"The applied display mode was saved"
	)

	panel.open_panel()
	await process_frame
	_expect(panel.is_open(), "The panel can be reopened")
	panel.close_panel()
	await process_frame
	_expect(not panel.is_open(), "close_panel hides the panel without emitting closed")
	_expect(closed_count[0] == 1, "close_panel does not emit closed twice, got %d" % closed_count[0])
	probe.free()
	panel.free()


func _write_text(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clear_test_directory() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	var directory := DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)


func _finish() -> void:
	if _failures > 0:
		push_error("Settings tests failed: %d" % _failures)
		quit(1)
		return
	print("Settings tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
