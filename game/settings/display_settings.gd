class_name DisplaySettings
extends RefCounted

## Window mode/size application. Kept separate from GameSettings so window
## handling can be tested (and skipped) without touching stored settings.

enum Mode { WINDOWED, BORDERLESS, FULLSCREEN }

const MIN_WIDTH: int = 640
const MAX_WIDTH: int = 7680
const MIN_HEIGHT: int = 360
const MAX_HEIGHT: int = 4320


## Unknown or missing names fall back to windowed.
static func mode_from_string(value: String) -> Mode:
	match value.strip_edges().to_lower():
		"borderless":
			return Mode.BORDERLESS
		"fullscreen":
			return Mode.FULLSCREEN
		_:
			return Mode.WINDOWED


static func mode_to_string(mode: Mode) -> String:
	match mode:
		Mode.BORDERLESS:
			return "borderless"
		Mode.FULLSCREEN:
			return "fullscreen"
		_:
			return "windowed"


## Applies a mode to the native main window. Under --headless this is a
## deliberate no-op, so headless tests can call it freely.
static func apply(mode: Mode, width: int, height: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if (
		tree == null
		or tree.root == null
		or not tree.root.is_visible()
		or tree.root.size.x <= 0.0
		or tree.root.size.y <= 0.0
	):
		return

	var window_id := DisplayServer.MAIN_WINDOW_ID
	var screen_id := DisplayServer.window_get_current_screen(window_id)
	var screen_usable := DisplayServer.screen_get_usable_rect(screen_id)

	match mode:
		Mode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window_id)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true, window_id)
			tree.root.borderless = true
			var size := Vector2i(
				clampi(width, MIN_WIDTH, MAX_WIDTH),
				clampi(height, MIN_HEIGHT, MAX_HEIGHT),
			)
			DisplayServer.window_set_size(size, window_id)
			tree.root.size = size
			var pos_x := screen_usable.position.x + (screen_usable.size.x - size.x) / 2
			var pos_y := screen_usable.position.y + (screen_usable.size.y - size.y) / 2
			DisplayServer.window_set_position(Vector2i(pos_x, pos_y), window_id)
		Mode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false, window_id)
			tree.root.borderless = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN, window_id)
		_:
			# WINDOWED: Switch mode to WINDOWED first, then ensure borderless is explicitly FALSE.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window_id)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false, window_id)
			tree.root.borderless = false

			# Title bar and window border decoration allowance:
			# On standard desktop, reserve space for OS window decorations and taskbar.
			var max_w := maxi(MIN_WIDTH, screen_usable.size.x - 32)
			var max_h := maxi(MIN_HEIGHT, screen_usable.size.y - 64)
			var target_w := clampi(width, MIN_WIDTH, max_w)
			var target_h := clampi(height, MIN_HEIGHT, max_h)
			# Maintain standard 16:9 aspect ratio so viewport doesn't distort or clip
			if float(target_w) / float(target_h) > 16.0 / 9.0:
				target_w = int(target_h * 16.0 / 9.0)
			else:
				target_h = int(target_w * 9.0 / 16.0)

			var target_size := Vector2i(target_w, target_h)
			DisplayServer.window_set_size(target_size, window_id)
			tree.root.size = target_size

			# Center the window within usable rect so title bar is guaranteed on-screen
			var pos_x := screen_usable.position.x + (screen_usable.size.x - target_size.x) / 2
			var pos_y := screen_usable.position.y + (screen_usable.size.y - target_size.y) / 2
			pos_y = maxi(pos_y, screen_usable.position.y)
			DisplayServer.window_set_position(Vector2i(pos_x, pos_y), window_id)
