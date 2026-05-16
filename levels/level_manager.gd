extends Node

signal level_loaded(level_number: int)

@export var first_level_number: int = 1
@export var current_level_path: NodePath = NodePath("../PlayingArea/LevelLayout")
@export var player_path: NodePath = NodePath("../PlayingArea/Character")
@export var persistent_sibling_names: Array[StringName] = [
	&"Character",
	&"PlayingUI"
]

const DYNAMIC_GROUPS: Array[StringName] = [
	&"portals",
	&"turret_bullets",
	&"striker_bullets",
	&"hazards",
	&"enemies",
	&"shield_projectors",
	&"warden_boss",
	&"boss_aoe"
]

var current_level: Node2D = null
var player: Node = null
var current_level_number: int = 1
var _level_mount_parent: Node = null
var _level_mount_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("level_manager")
	current_level = get_node_or_null(current_level_path) as Node2D
	player = get_node_or_null(player_path)

	if current_level == null:
		push_error("LevelManager could not find initial level at path: %s" % [current_level_path])
		return

	_level_mount_parent = current_level.get_parent()
	_level_mount_position = current_level.position

	_detect_current_level_number()
	_register_level_interactables()
	_place_player_on_first_spawn()
	level_loaded.emit(current_level_number)

func finish_current_level() -> void:
	var next_level_number := current_level_number + 1
	var next_level_path := "res://levels/Level%d.tscn" % next_level_number

	if ResourceLoader.exists(next_level_path):
		_load_level(next_level_number)
		return

	print("No next level found after Level%d. Restarting from Level%d." % [current_level_number, first_level_number])
	_load_level(first_level_number)

func load_level(level_number: int) -> void:
	if level_number < first_level_number:
		push_warning("Requested level %d is below first level %d." % [level_number, first_level_number])
		return

	var level_path := "res://levels/Level%d.tscn" % level_number
	if not ResourceLoader.exists(level_path):
		push_warning("Requested level does not exist: %s" % level_path)
		return

	_load_level(level_number)

func _load_level(level_number: int) -> void:
	_cleanup_before_level_load()

	if current_level and is_instance_valid(current_level):
		current_level.queue_free()
		# Wait two frames: queue_free() deletes at the END of a frame, but
		# process_frame fires at the START. Two awaits ensure old nodes are
		# fully freed and removed from groups before the new level is added.
		await get_tree().process_frame
		await get_tree().process_frame

	var level_path := "res://levels/Level%d.tscn" % level_number
	var level_resource := ResourceLoader.load(level_path)
	if level_resource == null or not (level_resource is PackedScene):
		push_error("Failed to load level scene: %s" % level_path)
		return

	var level_instance := (level_resource as PackedScene).instantiate() as Node2D
	if level_instance == null:
		push_error("Failed to instantiate level scene: %s" % level_path)
		return

	level_instance.position = _level_mount_position
	_level_mount_parent.add_child(level_instance)

	current_level = level_instance
	current_level_number = level_number
	_register_level_interactables()
	_place_player_on_first_spawn()
	_reset_player_health()
	_set_player_visible(true)
	level_loaded.emit(current_level_number)
	print("Loaded %s" % level_path)

func _cleanup_before_level_load() -> void:
	var dialogue_hud := get_tree().get_first_node_in_group("dialogue_hud")
	if dialogue_hud and dialogue_hud.has_method("reset_for_level_load"):
		dialogue_hud.call("reset_for_level_load")

	if player and player.has_node("PortalGun"):
		var portal_gun := player.get_node("PortalGun")
		if portal_gun and portal_gun.has_method("_clear_portals"):
			portal_gun._clear_portals()

	# Free all nodes in dynamic combat groups (enemies, projectiles, hazards, etc.)
	for group_name in DYNAMIC_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node and is_instance_valid(node):
				# Stop processing to prevent coroutines from resuming on freed nodes
				node.set_process(false)
				node.set_physics_process(false)
				node.queue_free()

	# Clean up orphaned nodes on the scene root that were reparented there
	# (WardenBoss reparents railgun_telegraph / railgun_beam to root,
	#  and adds AudioStreamPlayer for sweep/railgun sounds)
	var root := get_tree().root
	if root != null:
		for child in root.get_children():
			if not is_instance_valid(child):
				continue
			# Only clean up nodes that have no owner (dynamically reparented)
			# and are not the current scene itself
			if child == get_tree().current_scene:
				continue
			if child.owner != null:
				continue
			if child is Line2D or child is AnimatedSprite2D:
				child.queue_free()
			elif child is AudioStreamPlayer:
				child.stop()
				child.queue_free()

	# Clean up orphaned nodes on current_scene that were spawned by bosses/projectiles
	# (explosions, hit effects, AoE indicators, audio players, etc.)
	var scene := get_tree().current_scene
	if scene != null and _level_mount_parent != null:
		for child in scene.get_children():
			if not is_instance_valid(child):
				continue
			# Skip persistent structural nodes
			if child == _level_mount_parent:
				continue
			if child.name == _level_mount_parent.name:
				continue
			# Skip other known persistent scene children (NonPlayingUiComponents, etc.)
			if child.name == &"NonPlayingUiComponents" or child.name == &"BackgroundMusicManager" or child.name == &"LevelManager":
				continue
			# Skip if it's a known persistent sibling under _level_mount_parent
			if persistent_sibling_names.has(child.name):
				continue
			# If the child is part of the original Main scene, skip it
			if child.owner == scene:
				continue
			# Everything else is a dynamically-added node — free it
			if child is Node:
				child.set_process(false)
				child.set_physics_process(false)
				child.queue_free()

	if _level_mount_parent == null:
		return

	for child in _level_mount_parent.get_children():
		if not (child is Node):
			continue
		if child == current_level:
			continue
		if persistent_sibling_names.has(child.name):
			continue
		child.queue_free()

func _detect_current_level_number() -> void:
	var scene_file: String = current_level.scene_file_path if current_level else ""
	if scene_file.is_empty():
		current_level_number = first_level_number
		return

	var file_name := scene_file.get_file().get_basename()
	if file_name.begins_with("Level"):
		var level_number_text := file_name.trim_prefix("Level")
		if level_number_text.is_valid_int():
			current_level_number = int(level_number_text)

func _register_level_interactables() -> void:
	if current_level == null:
		return

	for exit_node in get_tree().get_nodes_in_group("level_exits"):
		if not (exit_node is Node):
			continue
		if not current_level.is_ancestor_of(exit_node):
			continue
		if not exit_node.has_signal("level_completed"):
			continue
		if not exit_node.level_completed.is_connected(_on_level_completed):
			exit_node.level_completed.connect(_on_level_completed)

func _place_player_on_first_spawn() -> void:
	if current_level == null:
		return
	if player == null:
		return
	if not player.has_method("set_spawn_point"):
		return

	var first_spawn := _find_first_spawn_in_level()
	if first_spawn == null:
		return

	player.set_spawn_point(first_spawn.global_position, true)

	if first_spawn.has_method("activate"):
		first_spawn.activate(true)

func _find_first_spawn_in_level() -> Node2D:
	for node in get_tree().get_nodes_in_group("spawn_points"):
		if node is Node2D and current_level.is_ancestor_of(node):
			return node
	return null

func _on_level_completed() -> void:
	finish_current_level()

func get_current_level_number() -> int:
	return current_level_number

func _reset_player_health() -> void:
	if player and player.has_method("reset_health"):
		player.reset_health()

func _set_player_visible(is_visible: bool) -> void:
	if player and player is CanvasItem:
		(player as CanvasItem).visible = is_visible
