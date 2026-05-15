extends Control

# References to the 3 heart nodes
@onready var heart_1: Control = $Heart
@onready var heart_2: Control = $Heart2
@onready var heart_3: Control = $Heart3

var _current_lives: int = 3
var _player: Node = null
var _level_manager: Node = null
var _game_over_menu: Node = null
var _just_died: bool = false
var _has_seen_alive_hp: bool = false
var _game_over_token: int = 0

func _ready() -> void:
	add_to_group("lives_hud")
	print("=== LIVES_HUD: _ready() called ===")
	_current_lives = 3
	_update_hearts_display()
	_bind_player()
	_bind_level_manager()
	_bind_game_over_hud()
	call_deferred("_bind_game_over_hud")
	if _game_over_menu != null and _game_over_menu.has_method("hide_game_over"):
		_game_over_menu.hide_game_over()
	print("=== LIVES_HUD: _ready() finished ===")

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind_player()
	if _level_manager == null or not is_instance_valid(_level_manager):
		_bind_level_manager()
	if _game_over_menu == null or not is_instance_valid(_game_over_menu):
		_bind_game_over_hud()
	

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		print("=== LIVES_HUD: Player not found in 'player' group ===")
		return

	print("=== LIVES_HUD: Found player, connecting hp_changed signal ===")
	var hp_changed_callable := Callable(self, "_on_player_hp_changed")
	if _player.has_signal("hp_changed"):
		if not _player.is_connected("hp_changed", hp_changed_callable):
			_player.connect("hp_changed", hp_changed_callable)
			print("=== LIVES_HUD: Successfully connected hp_changed signal ===")
		else:
			print("=== LIVES_HUD: hp_changed signal already connected ===")
	else:
		print("=== LIVES_HUD: Player does not have hp_changed signal ===")

	if _player.get("current_hp") != null and int(_player.get("current_hp")) > 0:
		_has_seen_alive_hp = true

func _bind_level_manager() -> void:
	_level_manager = get_tree().get_first_node_in_group("level_manager")
	if _level_manager == null:
		return

	var level_loaded_callable := Callable(self, "_on_level_loaded")
	if _level_manager.has_signal("level_loaded") and not _level_manager.is_connected("level_loaded", level_loaded_callable):
		_level_manager.connect("level_loaded", level_loaded_callable)

func _bind_game_over_hud() -> void:
	_game_over_menu = get_tree().get_first_node_in_group("game_over_hud")
	if _game_over_menu == null:
		print("=== LIVES_HUD: Game Over HUD not found in 'game_over_hud' group ===")
		return

	print("=== LIVES_HUD: Found Game Over HUD, connecting signals ===")
	var retry_callable := Callable(self, "_on_retry_pressed")
	var menu_callable := Callable(self, "_on_quit_pressed")

	if _game_over_menu.has_signal("retry_requested") and not _game_over_menu.is_connected("retry_requested", retry_callable):
		_game_over_menu.connect("retry_requested", retry_callable)
	if _game_over_menu.has_signal("menu_requested") and not _game_over_menu.is_connected("menu_requested", menu_callable):
		_game_over_menu.connect("menu_requested", menu_callable)

	if _game_over_menu.has_method("hide_game_over"):
		_game_over_menu.hide_game_over()

func _on_player_hp_changed(current_hp: int, _max_hp: int) -> void:
	if current_hp > 0:
		_has_seen_alive_hp = true
		_just_died = false
		return

	if not _has_seen_alive_hp:
		# Ignore invalid startup/deferred signals until we have seen a healthy HP state.
		return

	if current_hp <= 0 and not _just_died:
		_just_died = true
		print("Player died! Current lives: ", _current_lives)
		_lose_life()
		print("Lives after death: ", _current_lives)

func _on_level_loaded(_level_number: int) -> void:
	_current_lives = 3
	_just_died = false
	_has_seen_alive_hp = false
	_game_over_token += 1
	_update_hearts_display()
	if _game_over_menu != null and _game_over_menu.has_method("hide_game_over"):
		_game_over_menu.hide_game_over()

func _lose_life() -> void:
	if _current_lives > 0:
		_current_lives -= 1
		print("Lost a life! Lives remaining: ", _current_lives)
		_update_hearts_display()

		if _current_lives <= 0:
			print("No more lives! Scheduling game over...")
			_game_over_token += 1
			_schedule_game_over(_game_over_token)

func _schedule_game_over(token: int) -> void:
	await get_tree().create_timer(0.7).timeout
	if token != _game_over_token:
		return
	if _game_over_menu != null and _game_over_menu.has_method("show_game_over"):
		_game_over_menu.show_game_over()

func should_respawn() -> bool:
	var can_respawn := _current_lives > 0
	print("should_respawn() called. Can respawn: ", can_respawn, " Lives remaining: ", _current_lives)
	return can_respawn

func _update_hearts_display() -> void:
	var hearts: Array = [heart_1, heart_2, heart_3]
	print("Updating hearts display. Current lives: ", _current_lives)
	print("Hearts array: ", hearts)

	for i in range(hearts.size()):
		var heart = hearts[i]
		if heart == null:
			print("Heart ", i, " is null!")
			continue

		var fill = heart.get_node_or_null("Fill")
		if fill != null:
			fill.visible = (i < _current_lives)
			print("Heart ", i, " fill visible: ", fill.visible)
		else:
			print("Heart ", i, " has no Fill node!")
			var child_names: Array[String] = []
			for child in heart.get_children():
				child_names.append(child.name)
			print("Heart ", i, " children: ", child_names)

func _on_retry_pressed() -> void:
	if _level_manager != null and _level_manager.has_method("get_current_level_number"):
		var current_level = _level_manager.get_current_level_number()
		_level_manager.load_level(current_level)

func _on_quit_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")
