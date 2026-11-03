class_name InvestigationPresenter
extends RefCounted

## Presentation for investigation locations. The runtime stays authoritative:
## this class only mirrors the active location onto the background and stage.

var _stage: CharacterStage
var _background: BackgroundPresenter
var _content: ContentRegistry
var _runtime: InvestigationRuntime


func _init(
	content: ContentRegistry,
	stage: CharacterStage,
	background: BackgroundPresenter,
) -> void:
	_content = content
	_stage = stage
	_background = background


func connect_runtime(runtime: InvestigationRuntime) -> void:
	_runtime = runtime
	runtime.investigation_started.connect(_on_investigation_started)
	runtime.location_changed.connect(_on_location_changed)
	runtime.branch_resumed.connect(_on_branch_resumed)


func refresh() -> void:
	if _runtime == null:
		return
	_show_location(_runtime.current_location())


func _on_investigation_started(_location_id: StringName) -> void:
	_background.set_court_active(false)
	_show_location(_runtime.current_location())


func _on_location_changed(_location_id: StringName) -> void:
	_show_location(_runtime.current_location())


## A branch may have changed the background with @bg; the location owns it again.
func _on_branch_resumed(_context: InvestigationBranchContext) -> void:
	_show_location(_runtime.current_location())


func _show_location(location: LocationDef) -> void:
	if location == null:
		return
	_background.show_background(location.background)
	# A gameplay subsystem owns the whole portrait stage while active. Always
	# discard portraits authored by the preceding story scene before rebuilding.
	_stage.clear_stage()
	var character_id: StringName = _runtime.state.current_character
	if _runtime.state.mode != InvestigationState.Mode.LOCATION_ACTIVE and not character_id.is_empty():
		_stage.show_character(character_id, CharacterStage.Slot.CENTER)
