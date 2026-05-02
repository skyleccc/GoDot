extends Control

signal back_requested
signal level_selected(level_number: int)

@onready var back_button: Button = $BackButton
@onready var level_list: GridContainer = $LevelList

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	_setup_level_buttons()

func _setup_level_buttons() -> void:
	for child in level_list.get_children():
		if not (child is Button):
			continue

		var button := child as Button
		if not button.pressed.is_connected(_on_level_button_pressed.bind(button)):
			button.pressed.connect(_on_level_button_pressed.bind(button))

		var level_number := _parse_level_number(button.text)
		var level_exists := level_number > 0 and ResourceLoader.exists("res://levels/Level%d.tscn" % level_number)
		button.disabled = not level_exists

func _on_back_button_pressed() -> void:
	back_requested.emit()

func _on_level_button_pressed(button: Button) -> void:
	var level_number := _parse_level_number(button.text)
	if level_number <= 0:
		return
	if not ResourceLoader.exists("res://levels/Level%d.tscn" % level_number):
		return

	level_selected.emit(level_number)

func _parse_level_number(text: String) -> int:
	var trimmed := text.strip_edges()
	if not trimmed.is_valid_int():
		return -1
	return int(trimmed)
