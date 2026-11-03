class_name StoryProgramLoader
extends RefCounted

var error_message: String = ""


func load_file(path: String) -> StoryProgram:
	error_message = ""
	if not FileAccess.file_exists(path):
		_fail("Story IR file does not exist: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Cannot open Story IR file: %s" % path)
		return null
	return load_json(file.get_as_text())


func load_json(text: String) -> StoryProgram:
	error_message = ""
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		_fail("Malformed Story IR JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		_fail("Story IR root must be an object.")
		return null

	var root: Dictionary = json.data
	var schema_version: int = _required_int(root, "schema_version", "Story IR")
	if _has_error():
		return null
	if schema_version != StoryProgram.SCHEMA_VERSION:
		_fail("Unsupported Story IR schema_version: %d" % schema_version)
		return null

	var entry_scene := StringName(_required_string(root, "entry_scene", "Story IR"))
	var scenes_data: Dictionary = _required_dictionary(root, "scenes", "Story IR")
	var testimonies_data: Dictionary = _required_dictionary(root, "testimonies", "Story IR")
	if _has_error():
		return null

	var program := StoryProgram.new(entry_scene)
	for scene_key: Variant in scenes_data:
		if not scene_key is String:
			_fail("Story scene keys must be strings.")
			return null
		var scene: StoryScene = _parse_scene(String(scene_key), scenes_data[scene_key])
		if scene == null:
			return null
		program.add_scene(scene)

	for testimony_key: Variant in testimonies_data:
		if not testimony_key is String:
			_fail("Testimony keys must be strings.")
			return null
		var testimony: TestimonyDef = _parse_testimony(
			String(testimony_key),
			testimonies_data[testimony_key],
		)
		if testimony == null:
			return null
		program.add_testimony(testimony)

	# Locations are an additive IR section: story builds from before Step 09 do
	# not carry it, and an investigation command fails loudly when one is missing.
	var locations_value: Variant = root.get("locations", {})
	if not locations_value is Dictionary:
		_fail("Story IR 'locations' must be an object.")
		return null
	var locations_data: Dictionary = locations_value
	for location_key: Variant in locations_data:
		if not location_key is String:
			_fail("Location keys must be strings.")
			return null
		var location: LocationDef = _parse_location(
			String(location_key),
			locations_data[location_key],
		)
		if location == null:
			return null
		program.add_location(location)

	if program.get_scene(entry_scene) == null:
		_fail("Entry scene does not exist: %s" % entry_scene)
		return null
	if not _validate_references(program):
		return null
	return program


func _parse_scene(scene_key: String, value: Variant) -> StoryScene:
	if not value is Dictionary:
		_fail("Scene '%s' must be an object." % scene_key)
		return null
	var data: Dictionary = value
	var scene_id: String = _required_string(data, "id", "Scene '%s'" % scene_key)
	var source: SourceLocation = _parse_source(data.get("source"), "Scene '%s'" % scene_key)
	var instructions_data: Array = _required_array(data, "instructions", "Scene '%s'" % scene_key)
	if _has_error():
		return null
	if scene_id != scene_key:
		_fail("Scene key '%s' does not match id '%s'." % [scene_key, scene_id])
		return null

	var scene := StoryScene.new(StringName(scene_id), source)
	for index: int in instructions_data.size():
		var instruction: StoryInstruction = _parse_instruction(
			instructions_data[index],
			"Scene '%s' instruction %d" % [scene_id, index],
		)
		if instruction == null:
			return null
		scene.instructions.append(instruction)
	return scene


func _parse_instruction(value: Variant, context: String) -> StoryInstruction:
	if not value is Dictionary:
		_fail("%s must be an object." % context)
		return null
	var data: Dictionary = value
	var op_name: String = _required_string(data, "op", context)
	var source: SourceLocation = _parse_source(data.get("source"), context)
	if _has_error():
		return null

	var op: StoryInstruction.Op
	match op_name:
		"say":
			op = StoryInstruction.Op.SAY
		"goto":
			op = StoryInstruction.Op.GOTO
		"call":
			op = StoryInstruction.Op.CALL
		"return":
			op = StoryInstruction.Op.RETURN
		"flag":
			op = StoryInstruction.Op.FLAG
		"condition":
			op = StoryInstruction.Op.CONDITION
		"bg":
			op = StoryInstruction.Op.BG
		"bgm":
			op = StoryInstruction.Op.BGM
		"sfx":
			op = StoryInstruction.Op.SFX
		"start_testimony":
			op = StoryInstruction.Op.START_TESTIMONY
		"evidence_add":
			op = StoryInstruction.Op.EVIDENCE_ADD
		"evidence_update":
			op = StoryInstruction.Op.EVIDENCE_UPDATE
		"evidence_remove":
			op = StoryInstruction.Op.EVIDENCE_REMOVE
		"investigation":
			op = StoryInstruction.Op.INVESTIGATION
		"investigation_end":
			op = StoryInstruction.Op.INVESTIGATION_END
		"talk_unlock":
			op = StoryInstruction.Op.TALK_UNLOCK
		"procedure":
			op = StoryInstruction.Op.PROCEDURE
		"procedure_end":
			op = StoryInstruction.Op.PROCEDURE_END
		"stage":
			op = StoryInstruction.Op.STAGE
		_:
			_fail("%s has unknown op '%s'." % [context, op_name])
			return null

	var instruction := StoryInstruction.new(op, source)
	match op:
		StoryInstruction.Op.SAY:
			instruction.speaker_id = StringName(_required_string(data, "speaker", context))
			instruction.expression_id = StringName(_required_string(data, "expression", context))
			instruction.text = _required_string(data, "text", context)
		StoryInstruction.Op.GOTO, StoryInstruction.Op.CALL:
			instruction.target_scene = StringName(_required_string(data, "target", context))
		StoryInstruction.Op.FLAG:
			instruction.flag_id = StringName(_required_string(data, "flag", context))
			instruction.value = _required_bool(data, "value", context)
		StoryInstruction.Op.CONDITION:
			instruction.flag_id = StringName(_required_string(data, "flag", context))
			instruction.equals_value = _required_bool(data, "equals", context)
			instruction.target_scene = StringName(_required_string(data, "target", context))
		StoryInstruction.Op.BG:
			instruction.background_id = StringName(_required_string(data, "background", context))
		StoryInstruction.Op.BGM:
			instruction.bgm_id = StringName(_required_string(data, "bgm", context))
		StoryInstruction.Op.SFX:
			instruction.sfx_id = StringName(_required_string(data, "sfx", context))
		StoryInstruction.Op.START_TESTIMONY:
			instruction.testimony_id = StringName(_required_string(data, "testimony", context))
		StoryInstruction.Op.EVIDENCE_ADD, StoryInstruction.Op.EVIDENCE_REMOVE:
			instruction.evidence_id = StringName(_required_string(data, "evidence", context))
		StoryInstruction.Op.EVIDENCE_UPDATE:
			instruction.evidence_id = StringName(_required_string(data, "evidence", context))
			instruction.evidence_version = StringName(_required_string(data, "version", context))
		StoryInstruction.Op.INVESTIGATION:
			instruction.location_id = StringName(_required_string(data, "location", context))
		StoryInstruction.Op.TALK_UNLOCK:
			instruction.topic_id = StringName(_required_string(data, "topic", context))
		StoryInstruction.Op.PROCEDURE:
			instruction.context_id = StringName(_required_string(data, "context", context))
		StoryInstruction.Op.STAGE:
			instruction.character_id = StringName(_required_string(data, "character", context))
			instruction.stage_slot = StringName(_optional_string(data, "slot", "center"))
			instruction.expression_id = StringName(_optional_string(data, "expression", ""))
			instruction.visible = _required_bool(data, "visible", context)
		StoryInstruction.Op.RETURN, StoryInstruction.Op.INVESTIGATION_END, StoryInstruction.Op.PROCEDURE_END:
			pass
	if _has_error():
		return null
	return instruction


func _parse_testimony(testimony_key: String, value: Variant) -> TestimonyDef:
	if not value is Dictionary:
		_fail("Testimony '%s' must be an object." % testimony_key)
		return null
	var data: Dictionary = value
	var testimony_id: String = _required_string(data, "id", "Testimony '%s'" % testimony_key)
	var wrong_target := StringName(_required_string(data, "wrong_target", "Testimony '%s'" % testimony_key))
	var wrong_penalty: int = _required_int(data, "wrong_penalty", "Testimony '%s'" % testimony_key)
	var source: SourceLocation = _parse_source(data.get("source"), "Testimony '%s'" % testimony_key)
	var statements_data: Array = _required_array(data, "statements", "Testimony '%s'" % testimony_key)
	if _has_error():
		return null
	if testimony_id != testimony_key:
		_fail("Testimony key '%s' does not match id '%s'." % [testimony_key, testimony_id])
		return null
	if not wrong_penalty in range(0, 101):
		_fail("Testimony '%s' has invalid wrong_penalty." % testimony_id)
		return null

	var testimony := TestimonyDef.new(
		StringName(testimony_id),
		wrong_target,
		wrong_penalty,
		source,
	)
	for index: int in statements_data.size():
		var statement: StatementDef = _parse_statement(
			statements_data[index],
			"Testimony '%s' statement %d" % [testimony_id, index],
		)
		if statement == null:
			return null
		testimony.add_statement(statement)
	if testimony.statements.is_empty():
		_fail("Testimony '%s' must contain at least one statement." % testimony_id)
		return null
	return testimony


func _parse_statement(value: Variant, context: String) -> StatementDef:
	if not value is Dictionary:
		_fail("%s must be an object." % context)
		return null
	var data: Dictionary = value
	var statement := StatementDef.new(
		StringName(_required_string(data, "id", context)),
		StringName(_required_string(data, "speaker", context)),
		_required_string(data, "text", context),
		StringName(_required_string(data, "press_target", context, true)),
		StringName(_required_string(data, "expression", context)),
		_parse_source(data.get("source"), context),
	)
	var rules_data: Array = _required_array(data, "present_rules", context)
	if _has_error():
		return null
	for index: int in rules_data.size():
		var rule: PresentRule = _parse_present_rule(
			rules_data[index],
			"%s present rule %d" % [context, index],
		)
		if rule == null:
			return null
		statement.add_present_rule(rule)
	return statement


func _parse_present_rule(value: Variant, context: String) -> PresentRule:
	if not value is Dictionary:
		_fail("%s must be an object." % context)
		return null
	var data: Dictionary = value
	var result_name: String = _required_string(data, "result", context)
	var result_type: PresentResultType.Value
	match result_name:
		"correct":
			result_type = PresentResultType.Value.CORRECT
		"wrong":
			result_type = PresentResultType.Value.WRONG
		"special":
			result_type = PresentResultType.Value.SPECIAL
		_:
			_fail("%s has unknown result '%s'." % [context, result_name])
			return null
	var rule := PresentRule.new(
		StringName(_required_string(data, "evidence", context)),
		StringName(_required_string(data, "target", context)),
		result_type,
		_parse_source(data.get("source"), context),
	)
	# Version gates were added after the first IR; an absent key means "any version".
	if data.get("required_version") is String:
		rule.required_version = StringName(data["required_version"])
	return null if _has_error() else rule


func _parse_location(location_key: String, value: Variant) -> LocationDef:
	if not value is Dictionary:
		_fail("Location '%s' must be an object." % location_key)
		return null
	var data: Dictionary = value
	var context := "Location '%s'" % location_key
	var location_id: String = _required_string(data, "id", context)
	var source: SourceLocation = _parse_source(data.get("source"), context)
	var display_name: String = _required_string(data, "name", context, true)
	var background := StringName(_required_string(data, "background", context))
	var generic_present := StringName(_required_string(data, "generic_present", context, true))
	var characters_data: Array = _required_array(data, "characters", context)
	var moves_data: Array = _required_array(data, "moves", context)
	var reactions_data: Dictionary = _required_dictionary(data, "present_reactions", context)
	var hotspots_data: Array = _required_array(data, "hotspots", context)
	var topics_data: Array = _required_array(data, "topics", context)
	if _has_error():
		return null
	if location_id != location_key:
		_fail("Location key '%s' does not match id '%s'." % [location_key, location_id])
		return null

	var location := LocationDef.new(StringName(location_id), source)
	location.display_name = display_name
	location.background = background
	location.generic_present = generic_present
	for character: Variant in characters_data:
		if not character is String:
			_fail("%s characters must be strings." % context)
			return null
		location.characters.append(StringName(character))
	for destination: Variant in moves_data:
		if not destination is String:
			_fail("%s moves must be strings." % context)
			return null
		location.moves.append(StringName(destination))
	for evidence_key: Variant in reactions_data:
		if not evidence_key is String or not reactions_data[evidence_key] is String:
			_fail("%s present_reactions must map evidence IDs to scenes." % context)
			return null
		location.present_reactions[StringName(evidence_key)] = StringName(
			reactions_data[evidence_key]
		)
	for index: int in hotspots_data.size():
		var hotspot: HotspotDef = _parse_hotspot(
			hotspots_data[index],
			"%s hotspot %d" % [context, index],
		)
		if hotspot == null:
			return null
		location.hotspots.append(hotspot)
	for index: int in topics_data.size():
		var topic: TalkTopicDef = _parse_topic(topics_data[index], "%s topic %d" % [context, index])
		if topic == null:
			return null
		location.topics.append(topic)
	return location


func _parse_hotspot(value: Variant, context: String) -> HotspotDef:
	if not value is Dictionary:
		_fail("%s must be an object." % context)
		return null
	var data: Dictionary = value
	var hotspot_id: String = _required_string(data, "id", context)
	var scene := StringName(_required_string(data, "scene", context))
	var source: SourceLocation = _parse_source(data.get("source"), context)
	var rect_data: Array = _required_array(data, "rect", context)
	if _has_error():
		return null
	if rect_data.size() != 4:
		_fail("%s rect requires four numbers." % context)
		return null
	var values: Array[float] = []
	for entry: Variant in rect_data:
		if not (entry is float or entry is int):
			_fail("%s rect values must be numbers." % context)
			return null
		values.append(float(entry))
	return HotspotDef.new(
		StringName(hotspot_id),
		Rect2(values[0], values[1], values[2], values[3]),
		scene,
		source,
	)


func _parse_topic(value: Variant, context: String) -> TalkTopicDef:
	if not value is Dictionary:
		_fail("%s must be an object." % context)
		return null
	var data: Dictionary = value
	var topic_id: String = _required_string(data, "id", context)
	var title: String = _required_string(data, "title", context)
	var scene := StringName(_required_string(data, "scene", context))
	var locked: bool = _required_bool(data, "locked", context)
	var source: SourceLocation = _parse_source(data.get("source"), context)
	if _has_error():
		return null
	return TalkTopicDef.new(StringName(topic_id), title, scene, locked, source)


func _find_topic(program: StoryProgram, topic_id: StringName) -> TalkTopicDef:
	for location: LocationDef in program.locations.values():
		var topic: TalkTopicDef = location.get_topic(topic_id)
		if topic != null:
			return topic
	return null


func _parse_source(value: Variant, context: String) -> SourceLocation:
	if not value is Dictionary:
		_fail("%s requires source.file and source.line." % context)
		return null
	var data: Dictionary = value
	var file: String = _required_string(data, "file", "%s source" % context)
	var line: int = _required_int(data, "line", "%s source" % context)
	if _has_error():
		return null
	if line < 1:
		_fail("%s source.line must be positive." % context)
		return null
	return SourceLocation.new(file, line)


func _validate_references(program: StoryProgram) -> bool:
	for scene: StoryScene in program.scenes.values():
		for instruction: StoryInstruction in scene.instructions:
			if instruction.op in [StoryInstruction.Op.GOTO, StoryInstruction.Op.CALL, StoryInstruction.Op.CONDITION]:
				if program.get_scene(instruction.target_scene) == null:
					_fail("%s references missing scene '%s'." % [_source_label(instruction.source), instruction.target_scene])
					return false
			elif instruction.op == StoryInstruction.Op.START_TESTIMONY:
				if program.get_testimony(instruction.testimony_id) == null:
					_fail("%s references missing testimony '%s'." % [_source_label(instruction.source), instruction.testimony_id])
					return false
			elif instruction.op == StoryInstruction.Op.INVESTIGATION:
				if program.get_location(instruction.location_id) == null:
					_fail("%s references missing location '%s'." % [_source_label(instruction.source), instruction.location_id])
					return false
			elif instruction.op == StoryInstruction.Op.TALK_UNLOCK:
				if _find_topic(program, instruction.topic_id) == null:
					_fail("%s references missing talk topic '%s'." % [_source_label(instruction.source), instruction.topic_id])
					return false
	for location: LocationDef in program.locations.values():
		for hotspot: HotspotDef in location.hotspots:
			if program.get_scene(hotspot.scene) == null:
				_fail("Hotspot '%s' references missing scene '%s'." % [hotspot.id, hotspot.scene])
				return false
		for topic: TalkTopicDef in location.topics:
			if program.get_scene(topic.scene) == null:
				_fail("Topic '%s' references missing scene '%s'." % [topic.id, topic.scene])
				return false
		for evidence_id: StringName in location.present_reactions:
			if program.get_scene(location.present_reactions[evidence_id]) == null:
				_fail("Present reaction for '%s' references missing scene '%s'." % [
					evidence_id,
					location.present_reactions[evidence_id],
				])
				return false
		if (
			not location.generic_present.is_empty()
			and program.get_scene(location.generic_present) == null
		):
			_fail("Generic present reaction references missing scene '%s'." % location.generic_present)
			return false
		for destination: StringName in location.moves:
			if program.get_location(destination) == null:
				_fail("Location '%s' moves to missing location '%s'." % [location.id, destination])
				return false
	for testimony: TestimonyDef in program.testimonies.values():
		if program.get_scene(testimony.wrong_target_scene) == null:
			_fail("Testimony '%s' references missing wrong scene '%s'." % [testimony.id, testimony.wrong_target_scene])
			return false
		for statement: StatementDef in testimony.statements:
			if not statement.press_target_scene.is_empty() and program.get_scene(statement.press_target_scene) == null:
				_fail("Statement '%s' references missing press scene '%s'." % [statement.id, statement.press_target_scene])
				return false
			for rule: PresentRule in statement.present_rules:
				if program.get_scene(rule.target_scene) == null:
					_fail("Present rule references missing scene '%s'." % rule.target_scene)
					return false
	return true


func _required_dictionary(data: Dictionary, key: String, context: String) -> Dictionary:
	if not data.has(key) or not data[key] is Dictionary:
		_fail("%s requires object field '%s'." % [context, key])
		return {}
	return data[key]


func _required_array(data: Dictionary, key: String, context: String) -> Array:
	if not data.has(key) or not data[key] is Array:
		_fail("%s requires array field '%s'." % [context, key])
		return []
	return data[key]


func _required_string(
	data: Dictionary,
	key: String,
	context: String,
	allow_empty: bool = false,
) -> String:
	if not data.has(key) or not data[key] is String:
		_fail("%s requires string field '%s'." % [context, key])
		return ""
	var value: String = data[key]
	if not allow_empty and value.is_empty():
		_fail("%s field '%s' must not be empty." % [context, key])
	return value


func _required_int(data: Dictionary, key: String, context: String) -> int:
	if not data.has(key) or not data[key] is float:
		_fail("%s requires integer field '%s'." % [context, key])
		return 0
	var number: float = data[key]
	if number != floorf(number):
		_fail("%s field '%s' must be an integer." % [context, key])
		return 0
	return int(number)


func _optional_string(data: Dictionary, key: String, fallback: String) -> String:
	if not data.has(key) or not data[key] is String:
		return fallback
	return data[key]


func _required_bool(data: Dictionary, key: String, context: String) -> bool:
	if not data.has(key) or not data[key] is bool:
		_fail("%s requires boolean field '%s'." % [context, key])
		return false
	return data[key]


func _source_label(source: SourceLocation) -> String:
	return "%s:%d" % [source.file, source.line]


func _fail(message: String) -> void:
	if error_message.is_empty():
		error_message = message


func _has_error() -> bool:
	return not error_message.is_empty()
