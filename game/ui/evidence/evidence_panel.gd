class_name EvidencePanel
extends PanelContainer

signal present_requested(evidence_id: StringName)
signal inspect_requested(evidence_id: StringName)
signal back_requested

@onready var item_list: ItemList = %ItemList
@onready var evidence_grid: GridContainer = %EvidenceGrid
@onready var name_label: Label = %NameLabel
@onready var id_label: Label = %IdLabel
@onready var description_label: Label = %DescriptionLabel
@onready var inspect_button: Button = %InspectButton
@onready var present_button: Button = %PresentButton
@onready var back_button: Button = %BackButton

var selected_evidence_id: StringName
var _repository: EvidenceRepository
var _game_state: GameState
var _inspections: EvidenceInspectionRepository


func _ready() -> void:
	item_list.item_selected.connect(_on_item_selected)
	present_button.pressed.connect(_on_present_pressed)
	inspect_button.pressed.connect(_on_inspect_pressed)
	back_button.pressed.connect(func() -> void: back_requested.emit())


func configure(
	repository: EvidenceRepository,
	game_state: GameState,
	inspections: EvidenceInspectionRepository = null,
) -> void:
	_repository = repository
	_game_state = game_state
	_inspections = inspections


func open_panel() -> void:
	item_list.clear()
	for child: Node in evidence_grid.get_children():
		evidence_grid.remove_child(child)
		child.queue_free()
	selected_evidence_id = &""
	for definition: EvidenceDef in _repository.get_all():
		var runtime_state: EvidenceState = _game_state.evidence.get(definition.id) as EvidenceState
		if runtime_state == null or not runtime_state.owned:
			continue
		# The Court Record lists presentable evidence plus anything inspectable.
		if not definition.presentable and not _can_inspect(definition.id):
			continue
		var index: int = item_list.add_item(_list_label(definition, runtime_state))
		item_list.set_item_metadata(index, definition.id)
		_add_evidence_card(definition, runtime_state)
	set_active(true)
	if item_list.item_count > 0:
		item_list.select(0)
		_on_item_selected(0)
		item_list.grab_focus()
	else:
		_show_empty()


func close_panel() -> void:
	set_active(false)


func set_active(active: bool) -> void:
	visible = active
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	present_button.disabled = not active or selected_evidence_id.is_empty()
	inspect_button.disabled = (
		not active
		or selected_evidence_id.is_empty()
		or not _can_inspect(selected_evidence_id)
	)
	back_button.disabled = not active


func owned_evidence_ids() -> Array[StringName]:
	var result: Array[StringName]
	for index: int in item_list.item_count:
		result.append(item_list.get_item_metadata(index) as StringName)
	return result


func select_evidence(evidence_id: StringName) -> bool:
	for index: int in item_list.item_count:
		if item_list.get_item_metadata(index) as StringName == evidence_id:
			item_list.select(index)
			_on_item_selected(index)
			return true
	return false


## Evidence name as it reads at the current version.
func _list_label(definition: EvidenceDef, runtime_state: EvidenceState) -> String:
	var version: StringName = runtime_state.version if runtime_state != null else &""
	return _repository.display_name_for(definition.id, version)


func _can_inspect(evidence_id: StringName) -> bool:
	return _inspections != null and _inspections.has_inspection(evidence_id)


func _on_item_selected(index: int) -> void:
	selected_evidence_id = item_list.get_item_metadata(index) as StringName
	var definition: EvidenceDef = _repository.get_evidence(selected_evidence_id)
	var runtime_state: EvidenceState = _game_state.evidence.get(selected_evidence_id) as EvidenceState
	var version: StringName = runtime_state.version if runtime_state != null else &""
	name_label.text = _list_label(definition, runtime_state)
	id_label.text = "%s   version=%s" % [
		String(definition.id),
		String(version) if not version.is_empty() else "initial",
	]
	description_label.text = _repository.description_for(selected_evidence_id, version)
	present_button.disabled = not definition.presentable
	inspect_button.disabled = not _can_inspect(selected_evidence_id)


func _on_present_pressed() -> void:
	if not selected_evidence_id.is_empty():
		present_requested.emit(selected_evidence_id)


func _on_inspect_pressed() -> void:
	if not selected_evidence_id.is_empty():
		inspect_requested.emit(selected_evidence_id)


func _show_empty() -> void:
	name_label.text = "无可呈示证物"
	id_label.text = ""
	description_label.text = "当前没有已持有且可呈示的证物。"
	present_button.disabled = true
	inspect_button.disabled = true


func _add_evidence_card(definition: EvidenceDef, runtime_state: EvidenceState) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(150.0, 118.0)
	card.text = _list_label(definition, runtime_state)
	card.tooltip_text = definition.description_for(runtime_state.version)
	card.name = String(definition.id)
	var image_path := "res://assets/evidence/%s.png" % definition.id
	if ResourceLoader.exists(image_path):
		card.icon = load(image_path) as Texture2D
		card.expand_icon = true
	card.pressed.connect(func() -> void: select_evidence(definition.id))
	evidence_grid.add_child(card)
