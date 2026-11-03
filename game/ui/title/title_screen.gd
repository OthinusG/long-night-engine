class_name TitleScreen
extends Control

## Classic Galgame-style Title Screen featuring Start, Continue, Gallery, Settings, and Quit.

signal start_game_requested
signal continue_game_requested
signal gallery_requested
signal settings_requested
signal quit_requested

@onready var background_rect: TextureRect = %BackgroundRect
@onready var continue_button: Button = %ContinueButton
@onready var start_button: Button = %StartButton
@onready var gallery_button: Button = %GalleryButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	start_button.pressed.connect(func() -> void: start_game_requested.emit())
	continue_button.pressed.connect(func() -> void: continue_game_requested.emit())
	gallery_button.pressed.connect(func() -> void: gallery_requested.emit())
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())

	var bg_path := "res://assets/backgrounds/bg_yamen_gate_predawn.png"
	if ResourceLoader.exists(bg_path):
		background_rect.texture = load(bg_path) as Texture2D


func open_title(has_saves: bool = false) -> void:
	visible = true
	continue_button.disabled = not has_saves
	start_button.grab_focus()


func close_title() -> void:
	visible = false
