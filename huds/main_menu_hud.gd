extends Control

signal play_game_requested
signal level_select_requested
signal quit_requested

@onready var play_game_button: Button = $VBoxContainer/PlayGameButton
@onready var level_select_button: Button = $VBoxContainer/LevelSelectButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

func _ready() -> void:
	play_game_button.pressed.connect(_on_play_game_button_pressed)
	level_select_button.pressed.connect(_on_level_select_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

func _on_play_game_button_pressed() -> void:
	play_game_requested.emit()

func _on_level_select_button_pressed() -> void:
	level_select_requested.emit()

func _on_quit_button_pressed() -> void:
	quit_requested.emit()
