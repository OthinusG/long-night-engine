extends SceneTree

const MAIN_SCENE: String = "res://game/main.tscn"


func _initialize() -> void:
	if not ResourceLoader.exists(MAIN_SCENE, "PackedScene"):
		push_error("Bootstrap test failed: main scene is missing or invalid")
		quit(1)
		return

	print("Bootstrap test passed")
	quit()
