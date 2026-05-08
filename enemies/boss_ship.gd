extends CharacterBody2D

@export_group("Boss Stats")
@export var max_hp: int = 300
@export var hover_amplitude: float = 18.0
@export var hover_speed: float = 1.4
@export var strafe_speed: float = 70.0
@export var stop_distance_x: float = 240.0

@export_group("Projectile Attack")
@export var projectile_cooldown: float = 2
@export var projectile_damage: int = 20

@export_group("AoE Attack")
@export var aoe_cooldown: float = 5.0
@export var aoe_radius: float = 65.0
@export var aoe_damage: int = 28
@export var aoe_side_offset: float = 130.0
@export var aoe_telegraph_time: float = 1.0

@export_group("Railgun Attack")
@export var railgun_cooldown: float = 8.0
@export var railgun_charge_time: float = 1.4
@export var railgun_damage: int = 70
@export var railgun_length: float = 2200.0
@export var railgun_width: float = 22.0
@export var railgun_beam_time: float = 0.25

var projectile_scene: PackedScene = preload("res://enemies/BossProjectile.tscn")
var aoe_scene: PackedScene = preload("res://enemies/BossAOEIndicator.tscn")

var current_hp: int = 0
var target: Node2D = null
var _spawn_position: Vector2
var _time: float = 0.0
var _projectile_timer: float = 0.0
var _aoe_timer: float = 0.0
var _railgun_timer: float = 0.0
var _is_railgun_charging: bool = false
var _is_dead: bool = false
var _facing_sign: float = 1.0

@onready var projectile_spawn: Marker2D = $ProjectileSpawn
@onready var railgun_origin: Marker2D = $RailgunOrigin
@onready var aoe_container: Node2D = $AOEContainer
@onready var telegraph_line: Line2D = $RailgunTelegraph
@onready var beam_line: Line2D = $RailgunBeam
@onready var exhaust: AnimatedSprite2D = $Exhaust

func _ready() -> void:
	add_to_group("enemies")
	current_hp = max_hp
	_spawn_position = global_position
	_projectile_timer = projectile_cooldown
	_aoe_timer = aoe_cooldown
	_railgun_timer = railgun_cooldown
	telegraph_line.visible = false
	beam_line.visible = false

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_ensure_target()
	if target == null:
		return

	_time += delta
	_apply_hover_and_strafe(delta)

	if _is_railgun_charging:
		return

	_projectile_timer -= delta
	_aoe_timer -= delta
	_railgun_timer -= delta

	if _projectile_timer <= 0.0:
		_shoot_projectile()
		_projectile_timer = projectile_cooldown

	if _aoe_timer <= 0.0:
		_cast_aoe_pattern()
		_aoe_timer = aoe_cooldown

	if _railgun_timer <= 0.0:
		_railgun_timer = railgun_cooldown
		_fire_railgun()

func _ensure_target() -> void:
	if target != null and is_instance_valid(target):
		return
	target = get_tree().get_first_node_in_group("player") as Node2D

func _apply_hover_and_strafe(delta: float) -> void:
	# Vertical-only movement: no horizontal strafe
	velocity = Vector2(0.0, 0.0)
	move_and_slide()
	global_position.y = _spawn_position.y + sin(_time * hover_speed) * hover_amplitude
	_update_exhaust(0.0)

func _set_facing_sign(new_sign: float) -> void:
	if new_sign == 0.0 or new_sign == _facing_sign:
		return

	_facing_sign = new_sign
	var current_scale := scale
	scale = Vector2(absf(current_scale.x) * _facing_sign, current_scale.y)

func _update_exhaust(movement_x: float) -> void:
	if exhaust == null:
		return

	var animation_name := "normal"
	if absf(movement_x) > 1.0:
		animation_name = "turbo"

	if exhaust.animation != animation_name:
		exhaust.play(animation_name)

func _shoot_projectile() -> void:
	var projectile := projectile_scene.instantiate()
	projectile.global_position = projectile_spawn.global_position

	var aim_direction: Vector2 = (target.global_position - projectile.global_position).normalized()
	projectile.damage = projectile_damage
	get_tree().current_scene.add_child(projectile)
	projectile.set_shooter(self)
	projectile.initialize(aim_direction)

func _cast_aoe_pattern() -> void:
	if target == null or not is_instance_valid(target):
		return

	var center := target.global_position
	var offsets := [Vector2.ZERO, Vector2.LEFT * aoe_side_offset, Vector2.RIGHT * aoe_side_offset]

	for offset in offsets:
		var aoe := aoe_scene.instantiate()
		# Spawn the AoE directly at the player's current position; it
		# will stay in place after being spawned (no following).
		aoe.global_position = target.global_position + offset
		aoe.radius = aoe_radius
		aoe.telegraph_time = aoe_telegraph_time
		aoe.damage = aoe_damage
		# Add AoE to the current scene root so it remains fixed in world
		# space after spawning (not parented to the boss which moves).
		aoe.z_index = 200
		get_tree().current_scene.add_child(aoe)

func _fire_railgun() -> void:
	if _is_railgun_charging or target == null:
		return

	_is_railgun_charging = true

	var origin := railgun_origin.global_position
	var dir := (target.global_position - origin).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var end := origin + dir * railgun_length

	_show_line(telegraph_line, origin, end, Color(1.0, 0.85, 0.2, 0.95), railgun_width * 0.4)
	await get_tree().create_timer(railgun_charge_time).timeout
	telegraph_line.visible = false

	_show_line(beam_line, origin, end, Color(1.0, 0.2, 0.2, 1.0), railgun_width)
	_apply_railgun_damage(origin, end)
	await get_tree().create_timer(railgun_beam_time).timeout
	beam_line.visible = false

	_is_railgun_charging = false

func _show_line(line: Line2D, start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	line.global_position = Vector2.ZERO
	line.clear_points()
	line.add_point(start)
	line.add_point(finish)
	line.default_color = color
	line.width = width
	line.visible = true

func _apply_railgun_damage(start: Vector2, finish: Vector2) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return

	var closest := Geometry2D.get_closest_point_to_segment(target.global_position, start, finish)
	var distance := target.global_position.distance_to(closest)
	if distance <= railgun_width:
		target.take_damage(railgun_damage, start, false, false)

func take_bullet_damage(amount: int, _hit_source_pos: Vector2 = global_position) -> void:
	if _is_dead:
		return
	
	# Check if any crystals are still active
	if _are_shields_active():
		print("Boss is protected! Destroy all crystals first!")
		return
	
	current_hp -= amount
	print("Boss hit! -", amount, " HP  ->  ", current_hp, " / ", max_hp)
	if current_hp <= 0:
		current_hp = 0
		_die()

func _are_shields_active() -> bool:
	"""Check if any active crystals remain."""
	var crystals := get_tree().get_nodes_in_group("shield_projectors")
	for crystal in crystals:
		if crystal.is_alive():
			return true
	return false

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	telegraph_line.visible = false
	beam_line.visible = false
	queue_free()
