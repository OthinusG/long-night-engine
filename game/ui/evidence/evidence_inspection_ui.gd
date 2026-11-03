class_name EvidenceInspectionUI
extends PanelContainer

## Evidence inspection display and input. Hotspots are submitted by ID; the
## runtime resolves what inspecting them means.

signal hotspot_selected(hotspot_id: StringName)
signal back_requested

@onready var stage: Control = %Stage
@onready var image_label: Label = %ImageLabel
@onready var name_label: Label = %NameLabel
@onready var version_label: Label = %VersionLabel
@onready var description_label: Label = %DescriptionLabel
@onready var back_button: Button = %BackButton

var _runtime: EvidenceInspectionRuntime
var _repository: EvidenceRepository


func _ready() -> void:
	back_button.pressed.connect(func() -> void: back_requested.emit())


func refresh(runtime: EvidenceInspectionRuntime, repository: EvidenceRepository) -> void:
	_runtime = runtime
	_repository = repository
	var definition: EvidenceInspectionDef = runtime.current_definition()
	var evidence_id: StringName = runtime.active_evidence
	var state: EvidenceState = runtime.game_state.evidence.get(evidence_id) as EvidenceState
	var version: StringName = state.version if state != null else &""
	name_label.text = repository.display_name_for(evidence_id, version)
	version_label.text = "版本 %s" % (String(version) if not version.is_empty() else "initial")
	description_label.text = repository.description_for(evidence_id, version)
	image_label.text = (
		"EVIDENCE IMAGE  %s" % definition.image if definition != null else "NO INSPECTION DATA"
	)
	_rebuild_hotspots(runtime, definition)


func hotspot_ids() -> Array[StringName]:
	var result: Array[StringName]
	for child: Node in stage.get_children():
		result.append(StringName(child.name))
	return result


## Called by the owner when the inspection becomes the active surface. Hotspots
## are the panel's focusable content and Back is the fallback, so keyboard and
## gamepad can always act (spec 12.10).
func set_interaction_enabled(enabled: bool) -> void:
	if not enabled or not is_visible_in_tree():
		return
	for child: Node in stage.get_children():
		var button := child as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return
	back_button.grab_focus()


func _rebuild_hotspots(
	runtime: EvidenceInspectionRuntime,
	definition: EvidenceInspectionDef,
) -> void:
	for child: Node in stage.get_children():
		# Detach before freeing: the rebuild can run from inside a hotspot's own
		# pressed signal, where Godot keeps the node locked.
		stage.remove_child(child)
		child.queue_free()
	if definition == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.85, 0.55, 0.16)
	style.border_color = Color(0.95, 0.85, 0.55, 0.85)
	style.set_border_width_all(2)
	var done_style := StyleBoxFlat.new()
	done_style.bg_color = Color(0.45, 0.85, 0.55, 0.14)
	done_style.border_color = Color(0.45, 0.85, 0.55, 0.7)
	done_style.set_border_width_all(2)
	for hotspot: EvidenceHotspotDef in definition.hotspots:
		if not runtime.is_hotspot_available(hotspot):
			continue
		var inspected: bool = runtime.is_hotspot_inspected(hotspot.id)
		var button := Button.new()
		button.name = String(hotspot.id)
		button.text = "%s ✓" % hotspot.id if inspected else String(hotspot.id)
		button.add_theme_stylebox_override("normal", done_style if inspected else style)
		if not inspected:
			button.pressed.connect(func() -> void: hotspot_selected.emit(hotspot.id))
		else:
			button.disabled = true
		stage.add_child(button)
		button.set_anchor(SIDE_LEFT, hotspot.rect.position.x)
		button.set_anchor(SIDE_TOP, hotspot.rect.position.y)
		button.set_anchor(SIDE_RIGHT, hotspot.rect.end.x)
		button.set_anchor(SIDE_BOTTOM, hotspot.rect.end.y)
		# set_anchor() keeps the current rect, so the offsets must be cleared for
		# the button to fill its normalized rect.
		button.offset_left = 0.0
		button.offset_top = 0.0
		button.offset_right = 0.0
		button.offset_bottom = 0.0
