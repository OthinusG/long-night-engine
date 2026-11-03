extends SceneTree

const STORY_PATH: String = "res://story_build/story.json"

var _failures: int = 0


func _initialize() -> void:
	var loader := StoryProgramLoader.new()
	var program: StoryProgram = loader.load_file(STORY_PATH)
	_expect(program != null, "Compiled StoryProgram loads: %s" % loader.error_message)
	if program != null:
		_expect(program.entry_scene == &"scene_demo_intro", "Entry scene is preserved")
		_expect(program.scenes.size() >= 10, "All demo scenes load")
		_expect(program.testimonies.size() >= 1, "Structured testimony loads")
		_expect(program.locations.size() >= 2, "Investigation locations load")
		var intro: StoryScene = program.get_scene(&"scene_demo_intro")
		_expect(intro.instructions[0].op == StoryInstruction.Op.BG, "Instruction op loads")
		_expect(intro.instructions[0].source.file == "demo/main.md", "Source file loads")
		var testimony: TestimonyDef = program.get_testimony(&"testimony_demo_01")
		_expect(testimony.statements.size() == 4, "Testimony statements load")
		_expect(testimony.statements[2].present_rules.size() == 1, "Present rules load")
		var office: LocationDef = program.get_location(&"location_office")
		_expect(office != null and office.topics.size() == 2, "Location topics load")
		_expect(office.background == &"office", "Location background loads")
		_expect(office.present_scene(&"attorney_badge") == &"scene_present_badge_office", "Present rule loads")
		_expect(office.present_scene(&"ghost_item") == &"scene_present_generic_office", "Generic present loads")
		var crime_scene: LocationDef = program.get_location(&"location_crime_scene")
		_expect(
			crime_scene.get_hotspot(&"table_report").rect == Rect2(0.35, 0.45, 0.30, 0.25),
			"Hotspot rect loads as normalized coordinates"
		)

	var malformed: StoryProgram = loader.load_json('{"schema_version": 1}')
	_expect(malformed == null, "Malformed Story IR is rejected")
	_expect(not loader.error_message.is_empty(), "Malformed Story IR reports an error")

	if _failures > 0:
		push_error("StoryProgram loader tests failed: %d" % _failures)
		quit(1)
		return
	print("StoryProgram loader tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
