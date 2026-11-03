class_name CameraDirector
extends RefCounted

## Minimal reusable camera operations. It knows nothing about gameplay; callers
## decide when a shake or a zoom is appropriate.

const SHAKE_STEPS: int = 6

var _camera: Camera2D
var _tween: Tween
var _shaking: bool = false


func _init(camera: Camera2D) -> void:
	_camera = camera


func is_shaking() -> bool:
	return _shaking


func shake(intensity: float, duration: float = 0.3) -> void:
	if _camera == null or intensity <= 0.0:
		return
	_restart()
	_shaking = true
	# A fixed alternating pattern keeps the effect deterministic and testable.
	var step: float = maxf(duration, 0.05) / float(SHAKE_STEPS)
	_tween = _camera.create_tween()
	for index: int in range(SHAKE_STEPS):
		var falloff: float = 1.0 - float(index) / float(SHAKE_STEPS)
		var direction: float = -1.0 if index % 2 == 0 else 1.0
		var offset := Vector2(direction * intensity * falloff, intensity * 0.4 * falloff)
		_tween.tween_property(_camera, "offset", offset, step)
	_tween.tween_property(_camera, "offset", Vector2.ZERO, step)
	_tween.tween_callback(func() -> void: _shaking = false)


func impulse(offset: Vector2, duration: float = 0.2) -> void:
	if _camera == null:
		return
	_restart()
	_tween = _camera.create_tween()
	_tween.tween_property(_camera, "offset", offset, duration * 0.5)
	_tween.tween_property(_camera, "offset", Vector2.ZERO, duration * 0.5)


func zoom_to(scale: float, duration: float = 0.3) -> void:
	if _camera == null:
		return
	_restart()
	var target := Vector2(scale, scale)
	if duration <= 0.0:
		_camera.zoom = target
		return
	_tween = _camera.create_tween()
	_tween.tween_property(_camera, "zoom", target, duration)


func reset() -> void:
	_restart()
	_shaking = false
	if _camera != null:
		_camera.offset = Vector2.ZERO
		_camera.zoom = Vector2.ONE


func _restart() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
