extends Control

signal retry_requested
signal menu_requested

@onready var retry_button: Button = $MenuPanel/VBoxContainer/RetryButton
@onready var menu_button: Button = $MenuPanel/VBoxContainer/MenuButton

func _enter_tree() -> void:
	hide()

func _ready() -> void:
	hide()
	add_to_group("game_over_hud")
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	retry_button.pressed.connect(_on_retry_button_pressed)
	menu_button.pressed.connect(_on_menu_button_pressed)

func _on_retry_button_pressed() -> void:
	retry_requested.emit()
	await get_tree().process_frame
	if visible:
		_fallback_retry()

func _on_menu_button_pressed() -> void:
	menu_requested.emit()
	await get_tree().process_frame
	if visible:
		_fallback_return_to_menu()

func show_game_over() -> void:
	visible = true
	get_tree().paused = true
	retry_button.grab_focus()

func hide_game_over() -> void:
	visible = false
	get_tree().paused = false

func _fallback_retry() -> void:
	hide_game_over()
	var level_manager = get_tree().get_first_node_in_group("level_manager")
	if level_manager != null and level_manager.has_method("get_current_level_number") and level_manager.has_method("load_level"):
		var current_level = level_manager.get_current_level_number()
		level_manager.load_level(current_level)

func _fallback_return_to_menu() -> void:
	hide_game_over()
	get_tree().change_scene_to_file("res://Main.tscn")
