extends CharacterBody2D

class_name WardenBoss

enum AttackType { BURST, SWEEP, MINE, SCRAMBLE, RAILGUN }

@export_group("Boss Stats")
@export var max_hp: int = 420
@export var hover_amplitude: float = 18.0
@export var hover_speed: float = 1.15
@export var phase_two_threshold: float = 0.5
@export var arena_left: float = -120.0
@export var arena_right: float = 760.0
@export var arena_top: float = -80.0
@export var arena_bottom: float = 220.0

@export_group("Reactive Armor")
@export var reactor_open_time: float = 1.0
@export var reactor_turn_open_time: float = 0.35

@export_group("Burst Bolts")
@export var burst_cooldown: float = 2.2
@export var burst_damage: int = 18
@export var burst_speed: float = 240.0
@export var burst_spread_degrees: float = 18.0

@export_group("Sweep Beam")
@export var sweep_cooldown: float = 5.5
@export var sweep_charge_time: float = 0.85
@export var sweep_beam_time: float = 0.42
@export var sweep_damage: int = 28
@export var sweep_width: float = 26.0

@export_group("Mine Layer")
@export var mine_cooldown: float = 5.8
@export var mine_count: int = 2
@export var mine_spacing: float = 36.0
@export var mine_damage: int = 24
@export var mine_speed: float = 170.0
@export var mine_arm_delay: float = 0.45

@export_group("Railgun Attack")
@export var railgun_cooldown: float = 8.0
@export var railgun_charge_time: float = 1.2
@export var railgun_beam_time: float = 0.2
@export var railgun_damage: int = 70
@export var railgun_speed: float = 1100.0

@export_group("Phase 2")
@export var scramble_cooldown: float = 9.0
@export var scramble_disable_time: float = 2.5

var projectile_scene: PackedScene = preload("res://enemies/BossProjectile.tscn")
var mine_scene: PackedScene = preload("res://hazards/WardenMine.tscn")

var current_hp: int = 0
var target: Node2D = null
var _spawn_position: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _is_dead: bool = false
var _phase_two: bool = false
var _attack_busy: bool = false
var _attack_index: int = 0
var _next_attack_delay: float = 1.2
var _facing_sign: float = 1.0
var _reactor_open_timer: float = 0.0
var _sweep_active: bool = false
var _sweep_y: float = 0.0
var _sweep_timer: float = 0.0
var _scrambled_portal: Area2D = null
var _scrambled_portal_restore_timer: float = 0.0
var _scrambled_portal_was_monitoring: bool = true

@onready var projectile_spawn: Marker2D = $ProjectileSpawn
@onready var railgun_origin: Marker2D = $RailgunOrigin
@onready var sweep_telegraph: Line2D = $SweepTelegraph
@onready var sweep_beam: Line2D = $SweepBeam
@onready var railgun_telegraph: Line2D = $RailgunTelegraph
@onready var railgun_beam: Line2D = $RailgunBeam
@onready var exhaust: AnimatedSprite2D = $Exhaust
@onready var front_armor_glow: Sprite2D = $FrontArmorGlow
@onready var rear_reactor_glow: Sprite2D = $RearReactorGlow
@onready var mine_spawn: Marker2D = get_node_or_null("MineSpawn") as Marker2D


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("warden_boss")
	current_hp = max_hp
	_spawn_position = global_position
	sweep_telegraph.visible = false
	sweep_beam.visible = false
	railgun_telegraph.visible = false
	railgun_beam.visible = false
	if exhaust:
		exhaust.play("normal")
	_sync_armor_visuals()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_ensure_target()
	if target == null:
		return

	_time += delta
	_hover()
	_update_facing()
	_update_phase_timers(delta)
	_update_scrambled_portal(delta)

	if not _phase_two and float(current_hp) / float(max_hp) <= phase_two_threshold:
		_phase_two = true
		_open_reactor_window(1.0)
		_next_attack_delay = 0.5

	if _attack_busy:
		return

	_next_attack_delay -= delta
	if _next_attack_delay > 0.0:
		return

	_start_next_attack()


func _ensure_target() -> void:
	if target != null and is_instance_valid(target):
		return
	target = get_tree().get_first_node_in_group("player") as Node2D


func _hover() -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	global_position.y = _spawn_position.y + sin(_time * hover_speed) * hover_amplitude


func _update_facing() -> void:
	var desired_sign: float = 1.0 if target.global_position.x >= global_position.x else -1.0
	if desired_sign == _facing_sign:
		return

	_facing_sign = desired_sign
	_open_reactor_window(reactor_turn_open_time)
	var current_scale: Vector2 = scale
	scale = Vector2(absf(current_scale.x) * _facing_sign, current_scale.y)


func _update_phase_timers(delta: float) -> void:
	if _reactor_open_timer > 0.0:
		_reactor_open_timer = maxf(_reactor_open_timer - delta, 0.0)

	if _sweep_active:
		_sweep_timer -= delta
		if _sweep_timer <= 0.0:
			_sweep_active = false
			sweep_beam.visible = false

	_sync_armor_visuals()


func _update_scrambled_portal(delta: float) -> void:
	if _scrambled_portal == null or not is_instance_valid(_scrambled_portal):
		return

	_scrambled_portal_restore_timer -= delta
	if _scrambled_portal_restore_timer > 0.0:
		return

	_scrambled_portal.monitoring = _scrambled_portal_was_monitoring
	if _scrambled_portal.has_node("AnimatedSprite2D"):
		var sprite: CanvasItem = _scrambled_portal.get_node("AnimatedSprite2D") as CanvasItem
		sprite.modulate = Color.WHITE
	_scrambled_portal = null


func _start_next_attack() -> void:
	_attack_busy = true
	var pattern: Array = _get_pattern()
	var attack: int = pattern[_attack_index % pattern.size()]
	_attack_index += 1

	match attack:
		AttackType.BURST:
			await _run_burst_cycle()
		AttackType.SWEEP:
			await _run_sweep_cycle()
		AttackType.MINE:
			await _run_mine_cycle()
		AttackType.SCRAMBLE:
			await _run_scramble_cycle()
		AttackType.RAILGUN:
			await _run_railgun_cycle()

	_attack_busy = false


func _get_pattern() -> Array:
	if _phase_two:
		return [AttackType.BURST, AttackType.SWEEP, AttackType.MINE, AttackType.SCRAMBLE, AttackType.RAILGUN]
	return [AttackType.BURST, AttackType.SWEEP, AttackType.MINE, AttackType.BURST]


func _run_burst_cycle() -> void:
	_open_reactor_window(0.85)
	_fire_burst_bolts()
	await get_tree().create_timer(0.3).timeout
	_next_attack_delay = burst_cooldown


func _run_sweep_cycle() -> void:
	_open_reactor_window(1.0)
	await _fire_sweep_beam()
	_next_attack_delay = sweep_cooldown


func _run_scramble_cycle() -> void:
	_open_reactor_window(0.7)
	_scramble_portal()
	await get_tree().create_timer(scramble_disable_time).timeout
	_next_attack_delay = scramble_cooldown


func _run_mine_cycle() -> void:
	_open_reactor_window(0.8)
	_drop_mines()
	await get_tree().create_timer(0.3).timeout
	_next_attack_delay = mine_cooldown


func _run_railgun_cycle() -> void:
	_open_reactor_window(1.2)
	await _fire_railgun_slug()
	_next_attack_delay = railgun_cooldown


func _fire_burst_bolts() -> void:
	var aim_direction: Vector2 = (target.global_position - projectile_spawn.global_position).normalized()
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2(_facing_sign, 0.0)

	var half_spread: float = deg_to_rad(burst_spread_degrees)
	for index in 3:
		var ratio: float = 0.0 if index == 1 else (float(index) / 2.0)
		var offset: float = lerp(-half_spread, half_spread, ratio)
		var projectile: CharacterBody2D = projectile_scene.instantiate() as CharacterBody2D
		projectile.global_position = projectile_spawn.global_position
		projectile.damage = burst_damage
		projectile.speed = burst_speed
		projectile.max_step_distance = 12.0
		get_tree().current_scene.add_child(projectile)
		projectile.set_shooter(self)
		projectile.initialize(aim_direction.rotated(offset))


func _fire_sweep_beam() -> void:
	var y: float = clampf(target.global_position.y, arena_top, arena_bottom)
	_sweep_y = y
	_show_line(sweep_telegraph, Vector2(arena_left, y), Vector2(arena_right, y), Color(1.0, 0.85, 0.2, 0.95), 7.0)

	await get_tree().create_timer(sweep_charge_time).timeout
	sweep_telegraph.visible = false
	_show_line(sweep_beam, Vector2(arena_left, y), Vector2(arena_right, y), Color(1.0, 0.2, 0.2, 1.0), sweep_width)
	sweep_beam.visible = true
	_sweep_active = true
	_sweep_timer = sweep_beam_time
	_apply_sweep_damage()


func _drop_mines() -> void:
	if mine_scene == null:
		return

	var spawn_pos: Vector2 = projectile_spawn.global_position
	if mine_spawn != null:
		spawn_pos = mine_spawn.global_position

	for mine_index in mine_count:
		var mine: CharacterBody2D = mine_scene.instantiate() as CharacterBody2D
		var horizontal_offset: float = (float(mine_index) - float(mine_count - 1) * 0.5) * mine_spacing
		mine.global_position = spawn_pos + Vector2(horizontal_offset, 0.0)
		if mine.has_method("launch_toward"):
			mine.launch_toward((target.global_position - mine.global_position).normalized())
		if mine.has_method("set"):
			mine.set("damage", mine_damage)
			mine.set("speed", mine_speed)
			mine.set("arm_delay", mine_arm_delay)
		get_tree().current_scene.add_child(mine)


func _apply_sweep_damage() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return

	var start: Vector2 = Vector2(arena_left, _sweep_y)
	var end: Vector2 = Vector2(arena_right, _sweep_y)
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, start, end)
	if target.global_position.distance_to(closest) <= sweep_width:
		target.take_damage(sweep_damage, start, false, false)


func _fire_railgun_slug() -> void:
	var origin: Vector2 = railgun_origin.global_position
	var direction: Vector2 = Vector2(_facing_sign, 0.0)
	var end_x: float = arena_right if direction.x > 0.0 else arena_left
	var end: Vector2 = Vector2(end_x, origin.y)

	_show_line(railgun_telegraph, origin, end, Color(1.0, 0.85, 0.2, 0.95), 8.0)
	await get_tree().create_timer(railgun_charge_time).timeout
	railgun_telegraph.visible = false
	_show_line(railgun_beam, origin, end, Color(1.0, 0.2, 0.2, 1.0), 22.0)

	var projectile: CharacterBody2D = projectile_scene.instantiate() as CharacterBody2D
	projectile.global_position = origin
	projectile.damage = railgun_damage
	projectile.speed = railgun_speed
	projectile.max_step_distance = 8.0
	get_tree().current_scene.add_child(projectile)
	projectile.set_shooter(self)
	projectile.initialize(direction)

	await get_tree().create_timer(railgun_beam_time).timeout
	railgun_beam.visible = false


func _scramble_portal() -> void:
	var portals: Array = get_tree().get_nodes_in_group("portals")
	if portals.is_empty():
		return

	var portal: Area2D = portals[randi() % portals.size()]
	if portal == null or not is_instance_valid(portal):
		return

	_scrambled_portal = portal
	_scrambled_portal_was_monitoring = portal.monitoring
	_scrambled_portal_restore_timer = scramble_disable_time
	portal.monitoring = false
	if portal.has_node("AnimatedSprite2D"):
		var sprite: CanvasItem = portal.get_node("AnimatedSprite2D") as CanvasItem
		sprite.modulate = Color(0.55, 0.55, 0.55, 1.0)


func _show_line(line: Line2D, start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	line.global_position = Vector2.ZERO
	line.clear_points()
	line.add_point(start)
	line.add_point(finish)
	line.default_color = color
	line.width = width
	line.visible = true


func _open_reactor_window(duration: float) -> void:
	_reactor_open_timer = maxf(_reactor_open_timer, duration)
	_sync_armor_visuals()


func _sync_armor_visuals() -> void:
	if front_armor_glow:
		front_armor_glow.modulate = Color(0.3, 0.7, 1.0, 0.2)
	if rear_reactor_glow:
		var alpha := 0.18 + clampf(_reactor_open_timer / maxf(reactor_open_time, 0.001), 0.0, 1.0) * 0.82
		rear_reactor_glow.modulate = Color(1.0, 0.25, 0.25, alpha)


func _is_rear_hit(hit_source_pos: Vector2) -> bool:
	var relative: Vector2 = hit_source_pos - global_position
	return relative.x * _facing_sign < 0.0


func _apply_hit(amount: int, hit_source_pos: Vector2, reflect: bool) -> void:
	if _is_dead:
		return

	if _reactor_open_timer > 0.0 and _is_rear_hit(hit_source_pos):
		current_hp = maxi(current_hp - amount, 0)
		if current_hp <= 0:
			_die()
		return

	if reflect:
		_reflect_attack(hit_source_pos, amount)


func _reflect_attack(hit_source_pos: Vector2, amount: int) -> void:
	var direction := (hit_source_pos - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2(_facing_sign, 0.0)

	var reflected: CharacterBody2D = projectile_scene.instantiate() as CharacterBody2D
	reflected.global_position = global_position + direction * 48.0
	reflected.damage = amount
	reflected.speed = burst_speed
	reflected.max_step_distance = 12.0
	get_tree().current_scene.add_child(reflected)
	reflected.set_shooter(self)
	reflected.initialize(direction)


func take_bullet_damage(amount: int, hit_source_pos: Vector2 = Vector2.ZERO) -> void:
	_apply_hit(amount, hit_source_pos, true)


func take_damage(amount: int, hit_source_pos: Vector2 = Vector2.ZERO, _knockback: bool = true, _apply_slow: bool = false) -> void:
	_apply_hit(amount, hit_source_pos, false)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	sweep_telegraph.visible = false
	sweep_beam.visible = false
	railgun_telegraph.visible = false
	railgun_beam.visible = false
	
	# Enable the level exit when boss dies
	var exits := get_tree().get_nodes_in_group("level_exits")
	for exit_node in exits:
		if exit_node.has_node("Area2D"):
			exit_node.get_node("Area2D").monitoring = true
			exit_node.visible = true
	
	queue_free()
