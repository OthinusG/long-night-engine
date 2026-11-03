class_name ProcedurePanel
extends PanelContainer

## Procedure support display and input. The panel submits an action ID; the
## runtime decides what the action means.

signal action_selected(action_id: StringName)

@onready var title_label: Label = %TitleLabel
@onready var context_label: Label = %ContextLabel
@onready var action_list: VBoxContainer = %ActionList
@onready var detail_label: Label = %DetailLabel
@onready var confirm_button: Button = %ConfirmButton

var _selected_action_id: StringName
var _runtime: ProcedureRuntime


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm)


func refresh(runtime: ProcedureRuntime) -> void:
	_runtime = runtime
	var context: ProcedureContext = runtime.current_context()
	title_label.text = context.title if context != null else ""
	context_label.text = context.description if context != null else ""
	_rebuild_actions(runtime)
	_selected_action_id = &""
	detail_label.text = ""
	confirm_button.disabled = true
	# A rebuild frees the focused button, so keep a valid control focused while
	# this panel is the active surface (spec 12.10).
	if is_visible_in_tree():
		focus_first_action()


## Called by the owner when this panel becomes (or stops being) the active
## surface, so keyboard and gamepad always have somewhere to go.
func set_interaction_enabled(enabled: bool) -> void:
	if enabled:
		focus_first_action()


func focus_first_action() -> bool:
	if not is_visible_in_tree():
		return false
	for child: Node in action_list.get_children():
		var button := child as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return true
	return false


func select_action(action_id: StringName) -> bool:
	for child: Node in action_list.get_children():
		if StringName(child.name) != action_id:
			continue
		_select(action_id, _describe(action_id))
		return true
	return false


func action_ids() -> Array[StringName]:
	var result: Array[StringName]
	for child: Node in action_list.get_children():
		result.append(StringName(child.name))
	return result


func selected_action_id() -> StringName:
	return _selected_action_id


func _rebuild_actions(runtime: ProcedureRuntime) -> void:
	for child: Node in action_list.get_children():
		action_list.remove_child(child)
		child.queue_free()
	if runtime == null:
		return
	for action: ProcedureActionDef in runtime.available_actions():
		var button := Button.new()
		button.name = String(action.id)
		button.text = action.display_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: _select(action.id, action.description))
		action_list.add_child(button)


func _describe(action_id: StringName) -> String:
	if _runtime == null:
		return ""
	var context: ProcedureContext = _runtime.current_context()
	var action: ProcedureActionDef = context.get_action(action_id) if context != null else null
	return action.description if action != null else ""


func _select(action_id: StringName, description: String) -> void:
	_selected_action_id = action_id
	detail_label.text = description
	confirm_button.disabled = false


func _on_confirm() -> void:
	if not _selected_action_id.is_empty():
		action_selected.emit(_selected_action_id)
