## BossShip.gd (Level 5)
## Reactive armor mechanic — redirect attacks to the rear to deal damage.
## Shield gate removed. Front hits are reflected back at the player.

extends CharacterBody2D

@export_group("Boss Stats")
@export var max_hp: int = 100
@export var defeat_dialogue_id: String = ""
@export var hover_amplitude: float = 18.0
@export var hover_speed: float = 1.4
@export var strafe_speed: float = 70.0
@export var stop_distance_x: float = 240.0

@export_group("Reactive Armor")
@export var reactor_open_time: float = 1.0
@export var reactor_turn_open_time: float = 0.35

@export_group("Projectile Attack")
@export var projectile_cooldown: float = 1.0
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
@export var railgun_beam_time: float = 1.0

var projectile_scene: PackedScene = preload("res://enemies/BossProjectile.tscn")
var aoe_scene: PackedScene = preload("res://enemies/BossAOEIndicator.tscn")
var projectile_sound: AudioStream = preload("res://enemies/sounds/08_Weapon_Shot_SciFi.wav.wav")
var railgun_sound: AudioStream = preload("res://enemies/sounds/Laser Beam 2.wav")

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
var _railgun_hit_player: bool = false
var _reactor_open_timer: float = 0.0

@onready var projectile_spawn: Marker2D = $ProjectileSpawn
@onready var railgun_origin: Marker2D = $RailgunOrigin
@onready var aoe_container: Node2D = $AOEContainer
@onready var telegraph_line: Line2D = $RailgunTelegraph
@onready var beam_line: AnimatedSprite2D = $RailgunBeam
@onready var exhaust: AnimatedSprite2D = $Exhaust
@onready var death_explosion: AnimatedSprite2D = $DeathExplosion
## Optional glow nodes — assign in editor if your scene has them
@onready var front_armor_glow: Sprite2D = get_node_or_null("FrontArmorGlow") as Sprite2D
@onready var rear_reactor_glow: Sprite2D = get_node_or_null("RearReactorGlow") as Sprite2D


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss") 
	current_hp = max_hp
	_spawn_position = global_position
	_projectile_timer = projectile_cooldown
	_aoe_timer = aoe_cooldown
	_railgun_timer = railgun_cooldown
	telegraph_line.visible = false
	beam_line.visible = false

	_ensure_target()
	if target != null and is_instance_valid(target):
		var dir: float = sign(target.global_position.x - global_position.x)
		if dir != 0.0:
			_facing_sign = dir
			var s := scale
			scale = Vector2(absf(s.x) * _facing_sign, s.y)

	_sync_armor_visuals()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_ensure_target()
	if target == null:
		return

	_time += delta
	_apply_hover_and_strafe(delta)
	_update_phase_timers(delta)

	if _is_railgun_charging:
		return

	_projectile_timer -= delta
	_aoe_timer -= delta
	_railgun_timer -= delta

	if _projectile_timer <= 0.0:
		_shoot_projectile()
		_projectile_timer = projectile_cooldown

	if _aoe_timer <= 0.0:
		if not _are_shields_active():
			_cast_aoe_pattern()
		_aoe_timer = aoe_cooldown

	if _railgun_timer <= 0.0:
		_railgun_timer = railgun_cooldown
		_fire_railgun()


func _ensure_target() -> void:
	if target != null and is_instance_valid(target):
		return
	target = get_tree().get_first_node_in_group("player") as Node2D


func _update_phase_timers(delta: float) -> void:
	if _reactor_open_timer > 0.0:
		_reactor_open_timer = maxf(_reactor_open_timer - delta, 0.0)
	_sync_armor_visuals()


func _apply_hover_and_strafe(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	global_position.y = _spawn_position.y + sin(_time * hover_speed) * hover_amplitude

	if target != null and is_instance_valid(target):
		var dir: float = sign(target.global_position.x - global_position.x)
		if dir != 0.0:
			_set_facing_sign(dir)

	_update_exhaust(0.0)


func _set_facing_sign(new_sign: float) -> void:
	if new_sign == 0.0 or new_sign == _facing_sign:
		return
	_facing_sign = new_sign
	var s := scale
	scale = Vector2(absf(s.x) * _facing_sign, s.y)
	# Brief window when turning — rear is briefly exposed
	_open_reactor_window(reactor_turn_open_time)


func _update_exhaust(movement_x: float) -> void:
	if exhaust == null:
		return
	var anim := "turbo" if absf(movement_x) > 1.0 else "normal"
	if exhaust.animation != anim:
		exhaust.play(anim)


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


## Damage accepted from any direction.
func _apply_hit(amount: int, _hit_source_pos: Vector2, _reflect: bool) -> void:
	if _is_dead:
		return
	current_hp = maxi(current_hp - amount, 0)
	print("[BossShip] Hit! damage:", amount, " hp:", current_hp)
	if current_hp <= 0:
		_die()


func _reflect_attack(hit_source_pos: Vector2, amount: int) -> void:
	var direction := (hit_source_pos - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2(_facing_sign, 0.0)
	var reflected := projectile_scene.instantiate() as CharacterBody2D
	reflected.global_position = global_position + direction * 48.0
	reflected.damage = amount
	if reflected.has_method("set"):
		reflected.set("speed", 300.0)
	get_tree().current_scene.add_child(reflected)
	reflected.set_shooter(self)
	reflected.initialize(direction)


func take_bullet_damage(amount: int, hit_source_pos: Vector2 = Vector2.ZERO) -> void:
	_open_reactor_window(0.5)
	_apply_hit(amount, hit_source_pos, true)


func take_damage(amount: int, hit_source_pos: Vector2 = Vector2.ZERO, _knockback: bool = true, _apply_slow: bool = false) -> void:
	_apply_hit(amount, hit_source_pos, false)


func _shoot_projectile() -> void:
	var projectile := projectile_scene.instantiate()
	projectile.global_position = projectile_spawn.global_position
	var aim: Vector2 = (target.global_position - projectile.global_position).normalized()
	projectile.damage = projectile_damage
	if projectile.has_method("set"):
		projectile.set("redirectable", true)
	get_tree().current_scene.add_child(projectile)
	projectile.set_shooter(self)
	projectile.initialize(aim)
	_play_sound(projectile_sound, projectile_spawn.global_position)
	_open_reactor_window(0.6)


func _play_sound(sound: AudioStream, pos: Vector2) -> void:
	var audio_player := AudioStreamPlayer2D.new()
	audio_player.stream = sound
	audio_player.global_position = pos
	audio_player.bus = &"SFX"
	get_tree().current_scene.add_child(audio_player)
	audio_player.play()
	await audio_player.finished
	audio_player.queue_free()


func _are_shields_active() -> bool:
	var shields := get_tree().get_nodes_in_group("shield_projectors")
	for s in shields:
		if is_instance_valid(s) and s.has_method("is_alive") and s.is_alive():
			return true
	return false


func _cast_aoe_pattern() -> void:
	if target == null or not is_instance_valid(target):
		return
	var aoe := aoe_scene.instantiate()
	aoe.global_position = target.global_position
	aoe.radius = aoe_radius
	aoe.telegraph_time = aoe_telegraph_time
	aoe.damage = aoe_damage
	aoe.z_index = 200
	get_tree().current_scene.add_child(aoe)
	_open_reactor_window(aoe_telegraph_time)


func _fire_railgun() -> void:
	if _is_railgun_charging or target == null:
		return
	_is_railgun_charging = true

	var origin := railgun_origin.global_position
	var dir := (target.global_position - origin).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var end := origin + dir * railgun_length

	_show_line(telegraph_line, origin, end, Color(1.0, 0.65, 0.0, 0.95), railgun_width * 0.4)
	_open_reactor_window(railgun_charge_time)

	var sound_start_time: float = railgun_charge_time - 0.7
	await get_tree().create_timer(sound_start_time, false).timeout
	
	# Start the railgun sound during the last 0.7 seconds of telegraph
	var rail_audio := AudioStreamPlayer2D.new()
	rail_audio.stream = railgun_sound
	rail_audio.global_position = railgun_origin.global_position
	rail_audio.bus = &"SFX"
	get_tree().current_scene.add_child(rail_audio)
	rail_audio.play()
	
	# Wait for remaining telegraph time
	await get_tree().create_timer(0.7, false).timeout
	telegraph_line.visible = false

	_show_beam_animation(origin, dir)
	_railgun_hit_player = false

	var elapsed: float = 0.0
	while elapsed < railgun_beam_time:
		elapsed += 0.016
		if not _railgun_hit_player:
			_apply_railgun_damage(origin, end)
		await get_tree().create_timer(0.016, false).timeout

	beam_line.visible = false

	var tween := create_tween()
	tween.tween_property(rail_audio, "volume_db", -80.0, 0.3)
	await tween.finished
	rail_audio.stop()
	rail_audio.queue_free()

	_is_railgun_charging = false


func _show_line(line: Line2D, start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	line.global_position = Vector2.ZERO
	line.clear_points()
	line.add_point(start)
	line.add_point(finish)
	line.default_color = color
	line.width = width
	line.visible = true


func _show_beam_animation(origin: Vector2, direction: Vector2) -> void:
	beam_line.global_position = origin
	beam_line.rotation = direction.angle()
	beam_line.visible = true
	beam_line.frame = 0
	beam_line.self_modulate = Color.GREEN
	beam_line.scale.y = 1.0
	var base_width: float = 64.0
	var scale_factor: float = railgun_length / base_width
	beam_line.scale.x = scale_factor
	beam_line.global_position = origin + direction * (base_width * scale_factor / 2.0)
	beam_line.play()


func _apply_railgun_damage(start: Vector2, finish: Vector2) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage") or _railgun_hit_player:
		return
	var closest := Geometry2D.get_closest_point_to_segment(target.global_position, start, finish)
	if target.global_position.distance_to(closest) <= railgun_width:
		target.take_damage(railgun_damage, start, false, false)
		_railgun_hit_player = true


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	telegraph_line.visible = false
	beam_line.visible = false
	_shutdown_level_threats()

	var exits := get_tree().get_nodes_in_group("level_exits")
	for exit_node in exits:
		if exit_node.has_node("Area2D"):
			exit_node.get_node("Area2D").monitoring = true
			exit_node.visible = true

	await _play_death_explosion()
	_start_defeat_dialogue()
	queue_free()


func _play_death_explosion() -> void:
	death_explosion.play()
	var explosion_sound := AudioStreamPlayer2D.new()
	explosion_sound.stream = preload("res://asssets/sounds/FREE FPS SFX Pack/Rocket_Explosion-004.wav")
	explosion_sound.global_position = death_explosion.global_position
	explosion_sound.bus = &"SFX"
	get_tree().current_scene.add_child(explosion_sound)
	explosion_sound.play()
	await death_explosion.animation_finished
	explosion_sound.queue_free()


func _shutdown_level_threats() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is Node) or enemy == self:
			continue
		if enemy.has_method("take_bullet_damage"):
			enemy.call("take_bullet_damage", 9999, global_position)
		elif enemy.has_method("take_damage"):
			enemy.call("take_damage", 9999, global_position, true, false)
		else:
			enemy.queue_free()
	for turret in get_tree().get_nodes_in_group("turrets"):
		if turret.has_method("deactivate"):
			turret.call("deactivate")
		elif turret is Node:
			turret.process_mode = Node.PROCESS_MODE_DISABLED
	for laser in get_tree().get_nodes_in_group("lasers"):
		if laser.has_method("deactivate"):
			laser.call("deactivate")
		elif laser is Node:
			laser.process_mode = Node.PROCESS_MODE_DISABLED
	for spike_group in get_tree().get_nodes_in_group("spike_groups"):
		if spike_group.has_method("deactivate"):
			spike_group.call("deactivate")
		elif spike_group is Node:
			spike_group.process_mode = Node.PROCESS_MODE_DISABLED
	for spike in get_tree().get_nodes_in_group("spikes"):
		if spike.has_method("deactivate"):
			spike.call("deactivate")
		elif spike is Node:
			spike.process_mode = Node.PROCESS_MODE_DISABLED
	for bullet in get_tree().get_nodes_in_group("turret_bullets"):
		if bullet is Node:
			bullet.queue_free()


func _start_defeat_dialogue() -> void:
	if defeat_dialogue_id.is_empty():
		return
	var dialogue_hud := get_tree().get_first_node_in_group("dialogue_hud")
	if dialogue_hud == null:
		return
	if dialogue_hud.has_method("is_dialogue_active") and dialogue_hud.call("is_dialogue_active"):
		return
	if dialogue_hud.has_method("start_dialogue"):
		dialogue_hud.call("start_dialogue", defeat_dialogue_id)
