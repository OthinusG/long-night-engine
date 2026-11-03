class_name TransitionDirector
extends RefCounted

## Owns the black veil used for major transitions. It never sequences the story:
## the story asks for a fade, and the veil reports when the screen is covered.

signal veil_covered
signal veil_cleared

const VEIL_LAYER: int = 38

var _veil: ColorRect
var _tween: Tween
var _locked: bool = false


func _init(host: Control) -> void:
	_veil = ColorRect.new()
	_veil.name = "TransitionVeil"
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.z_index = VEIL_LAYER
	_veil.visible = false
	host.add_child(_veil)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)


## True while a transition runs; input should be ignored by the caller.
func is_locked() -> bool:
	return _locked


func is_covered() -> bool:
	return _veil.visible and _veil.color.a >= 0.99


func fade_to_black(duration: float = 0.4) -> void:
	_locked = true
	_veil.visible = true
	_animate(1.0, duration, func() -> void: veil_covered.emit())


func fade_from_black(duration: float = 0.4) -> void:
	if not _veil.visible:
		_locked = false
		veil_cleared.emit()
		return
	_locked = true
	_animate(0.0, duration, func() -> void:
		_veil.visible = false
		_locked = false
		veil_cleared.emit())


func snap_to_black() -> void:
	_kill()
	_veil.color = Color(0.0, 0.0, 0.0, 1.0)
	_veil.visible = true
	_locked = true


func snap_to_clear() -> void:
	_kill()
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_veil.visible = false
	_locked = false


func _animate(target_alpha: float, duration: float, finished: Callable) -> void:
	var start_alpha: float = _veil.color.a
	_kill()
	if duration <= 0.0 or not _veil.is_inside_tree():
		_veil.color.a = target_alpha
		finished.call()
		return
	_tween = _veil.create_tween()
	_tween.tween_property(_veil, "color:a", target_alpha, duration)
	_tween.tween_callback(finished)


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
