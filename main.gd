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
@onready var level_manager: Node = $LevelManager

const START_LEVEL_NUMBER := 1

func _ready() -> void:
	_connect_menu_signals()
	_show_main_menu()

func _process(_delta: float) -> void:
	check_for_debug_input()

func _connect_menu_signals() -> void:
	if main_menu_hud.has_signal("play_game_requested"):
		main_menu_hud.play_game_requested.connect(_on_play_game_requested)
	if main_menu_hud.has_signal("level_select_requested"):
		main_menu_hud.level_select_requested.connect(_on_level_select_requested)
	if main_menu_hud.has_signal("quit_requested"):
		main_menu_hud.quit_requested.connect(_on_quit_requested)

	if level_selection_hud.has_signal("back_requested"):
		level_selection_hud.back_requested.connect(_on_level_selection_back_requested)
	if level_selection_hud.has_signal("level_selected"):
		level_selection_hud.level_selected.connect(_on_level_selected)

func _show_main_menu() -> void:
	_set_gameplay_visible(false)
	main_menu_ui.visible = true
	level_selection_ui.visible = false

func _show_level_selection() -> void:
	main_menu_ui.visible = false
	level_selection_ui.visible = true

func _start_game_at_level(level_number: int) -> void:
	if level_manager and level_manager.has_method("load_level"):
		level_manager.load_level(level_number)

	_set_gameplay_visible(true)
	main_menu_ui.visible = false
	level_selection_ui.visible = false

func _set_gameplay_visible(should_be_visible: bool) -> void:
	_set_subtree_active(playing_area, should_be_visible)
	_set_node_active(multiplayer_ui, should_be_visible)

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

func _on_play_game_requested() -> void:
	_start_game_at_level(START_LEVEL_NUMBER)

func _on_level_select_requested() -> void:
	_show_level_selection()

func _on_quit_requested() -> void:
	get_tree().quit()

func _on_level_selection_back_requested() -> void:
	_show_main_menu()

func _on_level_selected(level_number: int) -> void:
	_start_game_at_level(level_number)
