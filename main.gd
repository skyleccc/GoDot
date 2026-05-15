extends Node2D

@onready var debug_hud: CanvasLayer = $NonPlayingUiComponents/DebugHUD
@onready var playing_area: Node = $PlayingArea
@onready var character: Node2D = $PlayingArea/Character
@onready var playing_ui: CanvasLayer = $PlayingArea/PlayingUI
@onready var multiplayer_ui: CanvasLayer = $NonPlayingUiComponents/MultiplayerUI
@onready var main_menu_ui: CanvasLayer = $NonPlayingUiComponents/MainMenuUI
@onready var level_selection_ui: CanvasLayer = $NonPlayingUiComponents/LevelSelectionUI
@onready var main_menu_hud: Control = $NonPlayingUiComponents/MainMenuUI/MainMenuHUD
@onready var level_selection_hud: Control = $NonPlayingUiComponents/LevelSelectionUI/LevelSelectionHUD
@onready var pause_menu_ui: CanvasLayer = $NonPlayingUiComponents/PauseMenuUI
@onready var pause_menu_hud: Control = $NonPlayingUiComponents/PauseMenuUI/PauseMenuHUD
@onready var settings_ui: CanvasLayer = $NonPlayingUiComponents/SettingsUI
@onready var settings_hud: Control = $NonPlayingUiComponents/SettingsUI/SettingsHUD
@onready var background_music_manager: AudioStreamPlayer = $BackgroundMusicManager
@onready var level_manager: Node = $LevelManager

const START_LEVEL_NUMBER := 1
var _settings_from_pause: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_menu_signals()
	_configure_pause_menu()
	_configure_settings_menu()
	_disable_multiplayer()
	_show_main_menu()

func _process(_delta: float) -> void:
	check_for_debug_input()

func _unhandled_input(event: InputEvent) -> void:
	if _is_dialogue_active():
		get_viewport().set_input_as_handled()
		return
	if pause_menu_ui and pause_menu_ui.visible:
		if event.is_action_pressed("Pause") or event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("Pause"):
		return
	if settings_ui and settings_ui.visible:
		return
	if get_tree().paused:
		_resume_gameplay()
		get_viewport().set_input_as_handled()
		return
	if _is_gameplay_active():
		_pause_gameplay()
		get_viewport().set_input_as_handled()

func _is_dialogue_active() -> bool:
	var dialogue_hud := get_tree().get_first_node_in_group("dialogue_hud")
	if dialogue_hud == null:
		return false
	if dialogue_hud.has_method("is_dialogue_active"):
		return dialogue_hud.call("is_dialogue_active")
	return false

func _connect_menu_signals() -> void:
	if main_menu_hud.has_signal("play_game_requested"):
		main_menu_hud.play_game_requested.connect(_on_play_game_requested)
	if main_menu_hud.has_signal("level_select_requested"):
		main_menu_hud.level_select_requested.connect(_on_level_select_requested)
	if main_menu_hud.has_signal("settings_requested"):
		main_menu_hud.settings_requested.connect(_on_settings_requested)
	if main_menu_hud.has_signal("quit_requested"):
		main_menu_hud.quit_requested.connect(_on_quit_requested)

	if level_selection_hud.has_signal("back_requested"):
		level_selection_hud.back_requested.connect(_on_level_selection_back_requested)
	if level_selection_hud.has_signal("level_selected"):
		level_selection_hud.level_selected.connect(_on_level_selected)

	if pause_menu_hud.has_signal("resume_requested"):
		pause_menu_hud.resume_requested.connect(_on_pause_menu_resume_requested)
	if pause_menu_hud.has_signal("settings_requested"):
		pause_menu_hud.settings_requested.connect(_on_pause_menu_settings_requested)
	if pause_menu_hud.has_signal("exit_requested"):
		pause_menu_hud.exit_requested.connect(_on_pause_menu_exit_requested)

	if settings_hud and settings_hud.has_signal("back_requested"):
		settings_hud.back_requested.connect(_on_settings_back_requested)

func _configure_pause_menu() -> void:
	if pause_menu_ui:
		pause_menu_ui.visible = false
		pause_menu_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if pause_menu_hud:
		pause_menu_hud.process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func _configure_settings_menu() -> void:
	if settings_ui:
		settings_ui.visible = false
		settings_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if settings_hud:
		settings_hud.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		if background_music_manager and settings_hud.has_method("set_music_manager"):
			settings_hud.call("set_music_manager", background_music_manager)

func _show_main_menu() -> void:
	_resume_gameplay()
	_set_gameplay_visible(false)
	main_menu_ui.visible = true
	level_selection_ui.visible = false
	if settings_ui:
		settings_ui.visible = false

func _show_level_selection() -> void:
	_resume_gameplay()
	main_menu_ui.visible = false
	level_selection_ui.visible = true
	if settings_ui:
		settings_ui.visible = false

func _start_game_at_level(level_number: int) -> void:
	_resume_gameplay()
	if level_manager and level_manager.has_method("load_level"):
		level_manager.load_level(level_number)

	_set_gameplay_visible(true)
	main_menu_ui.visible = false
	level_selection_ui.visible = false

func _set_gameplay_visible(should_be_visible: bool) -> void:
	_set_subtree_active(playing_area, should_be_visible)
	if not should_be_visible:
		if pause_menu_ui:
			pause_menu_ui.visible = false
		if settings_ui:
			settings_ui.visible = false

func _disable_multiplayer() -> void:
	if multiplayer_ui == null:
		return
	_set_subtree_active(multiplayer_ui, false)
	multiplayer_ui.visible = false

func _get_current_level_node() -> Node:
	if level_manager and is_instance_valid(level_manager):
		var current_level: Variant = level_manager.get("current_level")
		if current_level is Node and is_instance_valid(current_level):
			return current_level as Node

	return get_node_or_null("PlayingArea/LevelLayout")

func _set_node_active(node: Node, should_be_active: bool) -> void:
	if node == null:
		return

	node.process_mode = Node.PROCESS_MODE_INHERIT if should_be_active else Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		(node as CanvasItem).visible = should_be_active
	elif node is CanvasLayer:
		(node as CanvasLayer).visible = should_be_active

func _set_subtree_active(root: Node, should_be_active: bool) -> void:
	if root == null:
		return

	_set_node_active(root, should_be_active)
	for child in root.get_children():
		if child is Node:
			_set_subtree_active(child as Node, should_be_active)

func check_for_debug_input() -> void:
	if Input.is_action_just_pressed("ShowDebugHUD"):
		debug_hud.visible = not debug_hud.visible
		if debug_hud.visible:
			print("DebugHUD is enabled.")
		else:
			print("DebugHUD is disabled.")

func _pause_gameplay() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	if pause_menu_ui:
		pause_menu_ui.visible = true

func _resume_gameplay() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	if pause_menu_ui:
		pause_menu_ui.visible = false

func _is_gameplay_active() -> bool:
	return playing_area.process_mode != Node.PROCESS_MODE_DISABLED

func _on_play_game_requested() -> void:
	_start_game_at_level(START_LEVEL_NUMBER)

func _on_level_select_requested() -> void:
	_show_level_selection()

func _on_settings_requested() -> void:
	_show_settings(false)

func _on_quit_requested() -> void:
	get_tree().quit()

func _on_level_selection_back_requested() -> void:
	_show_main_menu()

func _on_level_selected(level_number: int) -> void:
	_start_game_at_level(level_number)

func _on_pause_menu_resume_requested() -> void:
	_resume_gameplay()

func _on_pause_menu_settings_requested() -> void:
	_show_settings(true)

func _on_pause_menu_exit_requested() -> void:
	_resume_gameplay()
	_show_main_menu()

func _show_settings(from_pause: bool) -> void:
	_settings_from_pause = from_pause
	var settings_process_mode := Node.PROCESS_MODE_WHEN_PAUSED if from_pause else Node.PROCESS_MODE_INHERIT
	if settings_ui:
		settings_ui.process_mode = settings_process_mode
	if settings_hud:
		settings_hud.process_mode = settings_process_mode
	if not from_pause:
		_resume_gameplay()
		main_menu_ui.visible = false
		level_selection_ui.visible = false
	else:
		if pause_menu_ui:
			pause_menu_ui.visible = false
	if settings_ui:
		settings_ui.visible = true

func _on_settings_back_requested() -> void:
	if settings_ui:
		settings_ui.visible = false
	if _settings_from_pause:
		if pause_menu_ui:
			pause_menu_ui.visible = true
	else:
		main_menu_ui.visible = true
