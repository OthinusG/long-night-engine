extends SceneTree

## Engine test for save & load system across dialogue, investigation, and court testimony.

const TEST_SAVE_DIR: String = "/tmp/engine_save_tests"
const MAIN_SCENE: String = "res://game/main.tscn"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_clear_test_directory()
	await _test_save_load_lifecycle()
	_clear_test_directory()
	_finish()


func _clear_test_directory() -> void:
	if DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		var dir := DirAccess.open(TEST_SAVE_DIR)
		if dir != null:
			dir.list_dir_begin()
			var file := dir.get_next()
			while file != "":
				if not dir.current_is_dir():
					dir.remove(file)
				file = dir.get_next()
			dir.list_dir_end()


func _test_save_load_lifecycle() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE)
	var main: Main = main_scene.instantiate() as Main
	root.add_child(main)
	await process_frame
	await process_frame
	main.save_manager.directory = TEST_SAVE_DIR

	main.start_new_game()
	await process_frame
	await process_frame

	# 1. Dialogue Save / Load
	_expect(main.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE, "Starts in dialogue")
	_expect(main.save_manager.can_save(), "Can save in dialogue")
	_expect(main.request_save(1), "Save slot 1 in dialogue succeeds")
	_expect(main.request_load(1), "Load slot 1 succeeds")
	_expect(main.ui_state == Main.UIState.DIALOGUE, "Restored state is DIALOGUE")

	# 2. Advance to Investigation
	while main.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		main.story_vm.resume_dialogue()
		await process_frame

	_expect(main.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_INVESTIGATION, "Reaches investigation")
	_expect(main.save_manager.can_save(), "Can save in investigation")
	_expect(main.request_save(2), "Save slot 2 in investigation succeeds")
	_expect(main.request_load(2), "Load slot 2 in investigation succeeds")
	_expect(main.ui_state == Main.UIState.INVESTIGATION, "Restored state is INVESTIGATION")

	# 3. Investigation move & examine
	_expect(main.investigation_runtime.move(&"location_crime_scene"), "Move to crime scene succeeds")
	await process_frame
	var examine_scene := main.investigation_runtime.examine(&"table_report")
	_expect(not examine_scene.is_empty(), "Examine table report returns branch scene")
	await process_frame

	# 4. Advance into Court
	while main.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		main.story_vm.resume_dialogue()
		await process_frame

	_expect(main.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_COURT, "Reaches court testimony")
	while main.court_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		main.court_runtime.advance_preview()
		await process_frame

	_expect(main.court_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_ACTIVE, "Testimony is active")
	_expect(main.save_manager.can_save(), "Can save in court testimony")
	_expect(main.request_save(3), "Save slot 3 in court testimony succeeds")

	# Move to next statement then reload slot 3
	main.court_runtime.next_statement()
	_expect(main.court_runtime.get_current_statement().id == &"demo_s02", "Advanced to statement demo_s02")
	_expect(main.request_load(3), "Load slot 3 in court succeeds")
	_expect(main.court_runtime.get_current_statement().id == &"demo_s01", "Restored statement is demo_s01")
	_expect(main.ui_state == Main.UIState.COURT, "Restored state is COURT")

	main.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: ", message)
	else:
		_failures += 1
		printerr("  FAIL: ", message)


func _finish() -> void:
	if _failures > 0:
		printerr("Test failures: %d" % _failures)
		quit(1)
	else:
		print("All save/load tests passed successfully!")
		quit(0)
