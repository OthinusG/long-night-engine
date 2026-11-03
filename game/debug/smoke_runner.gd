class_name SmokeRunner
extends RefCounted

## Boot check used by scripts/smoke_test.sh against a development or exported
## build. It drives the shipped story through its opening lines and reports what
## came up, so a broken export fails loudly instead of opening an empty window.

const MAX_STEPS: int = 40
const SMOKE_SLOT: int = 1

var failures: Array[String] = []

var _main: Main


func _init(main: Main) -> void:
	_main = main


func run() -> void:
	await _main.get_tree().process_frame
	_check(_main.story_vm != null and _main.story_vm.program != null, "story program loaded")
	_check(_main.content_registry != null, "content registry loaded")
	_check(
		_main.content_manifest.format_version == ContentManifest.FORMAT_VERSION,
		"content manifest format matches",
	)
	_check(_main.ui_state == Main.UIState.DIALOGUE, "story starts in dialogue")

	var steps: int = 0
	while _main.ui_state == Main.UIState.DIALOGUE and steps < MAX_STEPS:
		_main.dialogue_ui.continue_button.pressed.emit()
		await _main.get_tree().process_frame
		steps += 1
	_check(steps > 0, "dialogue advances")
	_check(_main.ui_state != Main.UIState.ERROR, "no fatal runtime state")
	await _check_release_debugger()
	_check_persistence_paths()

	for failure: String in failures:
		push_error("[Smoke] %s" % failure)
	print(
		"[Smoke] %s steps=%d ui=%s debug_build=%s user_dir=%s"
		% [
			"PASS" if failures.is_empty() else "FAIL",
			steps,
			Main.UIState.keys()[_main.ui_state],
			OS.is_debug_build(),
			OS.get_user_data_dir().get_file(),
		]
	)
	_main.get_tree().quit(failures.size())


## Specs 14.8/14.31: the shipped build must be able to write its own user data.
## A scratch directory is used so a real player's slots and settings are never
## touched; the write itself is what proves the path is usable.
func _check_persistence_paths() -> void:
	var directory := "user://smoke_test"
	DirAccess.make_dir_recursive_absolute(directory)
	_main.save_manager.directory = directory
	_check(_main.save_manager.can_save(), "a stable state is saveable")
	if _main.request_save(SMOKE_SLOT):
		_check(_main.request_load(SMOKE_SLOT), "the smoke save loads back")
	else:
		_check(false, "save failed: %s" % _main.save_manager.error_message)

	var settings_manager: SettingsManager = _main.settings_manager
	var default_path: String = settings_manager.path
	settings_manager.path = directory.path_join("settings.json")
	_check(settings_manager.save(), "settings are writable: %s" % settings_manager.last_error)
	settings_manager.path = default_path


## Spec 14.11: a release build must not expose the Story Debugger, even though
## the overlay node still ships. The debug key goes through the input router, so
## pressing it exercises the same path as F12.
func _check_release_debugger() -> void:
	if OS.is_debug_build():
		return
	_check(not _main.debug_overlay.visible, "Story Debugger starts hidden in a release build")
	_main.input_router.action_requested.emit(&"debug_story_tools")
	await _main.get_tree().process_frame
	_check(
		not _main.debug_overlay.visible,
		"Story Debugger cannot be opened in a release build"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
