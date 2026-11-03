extends SceneTree

var _court_id: StringName


func _initialize() -> void:
	var loader := StoryProgramLoader.new()
	var program: StoryProgram = loader.load_file("res://story_build/story.json")
	if program == null:
		push_error(loader.error_message)
		quit(1)
		return

	var vm := StoryVM.new()
	vm.debug_logging = true
	vm.dialogue_requested.connect(_on_dialogue_requested)
	vm.court_requested.connect(_on_court_requested)
	vm.load_program(program)
	var demo_scene: StringName = &"scene_court_intro" if program.has_scene(&"scene_court_intro") else program.entry_scene
	vm.start(demo_scene)

	var resumed_dialogues: int = 0
	while vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		resumed_dialogues += 1
		if resumed_dialogues > 20:
			push_error("Demo exceeded dialogue safety limit")
			quit(1)
			return
		vm.resume_dialogue()

	if (
		vm.game_state.story.runtime_state != StoryState.RuntimeState.WAIT_COURT
		or _court_id != &"testimony_demo_01"
	):
		push_error("Demo did not stop at testimony_demo_01 court handoff")
		quit(1)
		return

	print("[Demo] PASS state=WAIT_COURT testimony=%s" % _court_id)
	quit()


func _on_dialogue_requested(
	speaker_id: StringName,
	_expression_id: StringName,
	text: String,
	source: SourceLocation,
) -> void:
	print("[Demo] %s:%d %s: %s" % [source.file, source.line, speaker_id, text.replace("\n", " / ")])


func _on_court_requested(testimony_id: StringName) -> void:
	_court_id = testimony_id
