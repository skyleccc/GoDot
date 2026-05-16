## WardenBoss.gd (Level 10)
## Now requires shields to be destroyed first (like Level 5 boss used to),
## AND THEN requires rear hits to deal damage (reactive armor from original Warden).
## Two-layer challenge: destroy shields → redirect attacks to the rear.

extends CharacterBody2D

enum AttackType { BURST, SWEEP, MINE, SCRAMBLE, RAILGUN }

@export_group("Boss Stats")
@export var max_hp: int = 10
@export var defeat_dialogue_id: String = ""
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
@export var debug_force_railgun: bool = false

@export_group("Audio Resources")
@export var death_sound_res: AudioStream = null
@export var shot_sound_res: AudioStream = null
@export var railgun_sound_res: AudioStream = null

@export_group("Phase 2")
@export var scramble_cooldown: float = 9.0
@export var scramble_disable_time: float = 2.5

var projectile_scene: PackedScene = preload("res://enemies/WardenProjectile.tscn")
var mine_scene: PackedScene = preload("res://hazards/WardenMine.tscn")
var death_explosion_frames: Array = [
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-1.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-2.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-3.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-4.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-5.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-6.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-7.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-8.png")
]

var current_hp: int = 0
var target: Node2D = null
var _spawn_position: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _is_dead: bool = false
var _phase_two: bool = false
var _attack_busy: bool = false
var _attack_index: int = 0
var _next_attack_delay: float = 3.0
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
@onready var sweep_beam: AnimatedSprite2D = $SweepBeam
@onready var railgun_telegraph: Line2D = $RailgunTelegraph
@onready var railgun_beam: AnimatedSprite2D = $RailgunBeam
@onready var exhaust: AnimatedSprite2D = $Exhaust
@onready var front_armor_glow: Sprite2D = $FrontArmorGlow
@onready var rear_reactor_glow: Sprite2D = $RearReactorGlow
@onready var mine_spawn: Marker2D = get_node_or_null("MineSpawn") as Marker2D


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("warden_boss")
	add_to_group("boss") 
	current_hp = max_hp

	if death_sound_res == null:
		for p in ["res://asssets/sounds/FREE FPS SFX Pack/Rocket_Explosion-001.wav", "res://enemies/sounds/Rocket_Explosion-001.wav"]:
			if ResourceLoader.exists(p):
				death_sound_res = ResourceLoader.load(p) as AudioStream
				break

	if shot_sound_res == null:
		for p in ["res://enemies/sounds/07_Weapon_Shot_SciFi.wav.wav", "res://enemies/sounds/08_Weapon_Shot_SciFi.wav.wav"]:
			if ResourceLoader.exists(p):
				shot_sound_res = ResourceLoader.load(p) as AudioStream
				break

	if railgun_sound_res == null:
		for p in ["res://enemies/sounds/Laser Beam 2.wav", "res://enemies/sounds/03_Energy_Hit.wav.wav"]:
			if ResourceLoader.exists(p):
				railgun_sound_res = ResourceLoader.load(p) as AudioStream
				break

	_spawn_position = global_position
	sweep_telegraph.visible = false
	sweep_beam.visible = false
	railgun_telegraph.visible = false
	railgun_beam.visible = false
	if exhaust:
		exhaust.play("normal")
	_detach_railgun_fx_nodes()
	_sync_armor_visuals()

	if debug_force_railgun:
		_delayed_debug_fire()


func _delayed_debug_fire() -> void:
	await get_tree().create_timer(0.9, false).timeout
	await debug_fire_railgun()


func debug_fire_railgun() -> void:
	if _attack_busy:
		return
	_attack_busy = true
	_open_reactor_window(1.2)
	await _run_railgun_cycle()
	_attack_busy = false


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


func _play_sound(a: AudioStream, pos: Vector2, duration: float = 1.0, volume_db: float = 0.0) -> void:
	if a == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = a
	p.global_position = pos
	p.bus = &"SFX"
	p.volume_db = volume_db
	get_tree().current_scene.add_child(p)
	p.play()
	await get_tree().create_timer(duration, false).timeout
	if is_instance_valid(p):
		p.queue_free()


func _hover() -> void:
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
		(_scrambled_portal.get_node("AnimatedSprite2D") as CanvasItem).modulate = Color.WHITE
	_scrambled_portal = null


func _start_next_attack() -> void:
	_attack_busy = true
	var pattern: Array = _get_pattern()
	var attack: int = pattern[_attack_index % pattern.size()]
	_attack_index += 1

	match attack:
		AttackType.BURST:   await _run_burst_cycle()
		AttackType.SWEEP:   await _run_sweep_cycle()
		AttackType.MINE:    await _run_mine_cycle()
		AttackType.SCRAMBLE: await _run_scramble_cycle()
		AttackType.RAILGUN: await _run_railgun_cycle()

	_attack_busy = false


func _get_pattern() -> Array:
	if _phase_two:
		return [AttackType.BURST, AttackType.SWEEP, AttackType.MINE, AttackType.SCRAMBLE, AttackType.RAILGUN]
	return [AttackType.BURST, AttackType.RAILGUN, AttackType.SWEEP, AttackType.MINE]


func _run_burst_cycle() -> void:
	_open_reactor_window(0.85)
	_fire_burst_bolts()
	await get_tree().create_timer(0.3, false).timeout
	_next_attack_delay = burst_cooldown


func _run_sweep_cycle() -> void:
	_open_reactor_window(1.0)
	await _fire_sweep_beam()
	_next_attack_delay = sweep_cooldown


func _run_scramble_cycle() -> void:
	_open_reactor_window(0.7)
	_scramble_portal()
	await get_tree().create_timer(scramble_disable_time, false).timeout
	_next_attack_delay = scramble_cooldown


func _run_mine_cycle() -> void:
	_open_reactor_window(0.8)
	_drop_mines()
	await get_tree().create_timer(0.3, false).timeout
	_next_attack_delay = mine_cooldown


func _run_railgun_cycle() -> void:
	_open_reactor_window(1.2)
	await _fire_railgun_slug()
	_next_attack_delay = railgun_cooldown


# ── Shield Gate ────────────────────────────────────────────────────────────────

func _are_shields_active() -> bool:
	for crystal in get_tree().get_nodes_in_group("shield_projectors"):
		if is_instance_valid(crystal) and crystal.has_method("is_alive") and crystal.is_alive():
			return true
	return false


# ── Damage & Reactive Armor ────────────────────────────────────────────────────

func _is_rear_hit(hit_source_pos: Vector2) -> bool:
	return (hit_source_pos - global_position).x * _facing_sign < 0.0


func _apply_hit(amount: int, hit_source_pos: Vector2, reflect: bool) -> void:
	if _is_dead:
		return

	# LAYER 1: Shields must be destroyed first
	if _are_shields_active():
		print("[WardenBoss] Shields active — hit blocked!")
		if reflect:
			_reflect_attack(hit_source_pos, amount)
		return

	# LAYER 2: Must hit the rear weak spot
	if _is_rear_hit(hit_source_pos):
		current_hp = maxi(current_hp - amount, 0)
		print("[WardenBoss] Rear hit! damage:", amount, " hp:", current_hp)
		if current_hp <= 0:
			_die()
		return

	if reflect:
		_reflect_attack(hit_source_pos, amount)


func _reflect_attack(hit_source_pos: Vector2, amount: int) -> void:
	var direction := (hit_source_pos - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2(_facing_sign, 0.0)
	var reflected := projectile_scene.instantiate() as CharacterBody2D
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


# ── Attacks ────────────────────────────────────────────────────────────────────

func _fire_burst_bolts() -> void:
	var aim: Vector2 = (target.global_position - projectile_spawn.global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2(_facing_sign, 0.0)
	var half_spread: float = deg_to_rad(burst_spread_degrees)
	for index in range(3):
		var ratio: float = float(index) / 2.0
		var offset: float = lerp(-half_spread, half_spread, ratio)
		var dir: Vector2 = aim.rotated(offset)
		var projectile := projectile_scene.instantiate() as CharacterBody2D
		projectile.global_position = projectile_spawn.global_position + dir * 60.0
		projectile.damage = burst_damage
		projectile.speed = burst_speed
		projectile.max_step_distance = 12.0
		if projectile.has_method("set"):
			projectile.set("redirectable", true)
		projectile.set_shooter(self)
		projectile.initialize(dir)
		get_tree().current_scene.add_child(projectile)
		if shot_sound_res != null:
			_play_sound(shot_sound_res, projectile.global_position, 0.9)


func _fire_sweep_beam() -> void:
	var y: float = clampf(target.global_position.y, arena_top, arena_bottom)
	_sweep_y = y
	_show_line(sweep_telegraph, Vector2(arena_left, y), Vector2(arena_right, y), Color(1.0, 0.85, 0.2, 0.95), 7.0)
	await get_tree().create_timer(sweep_charge_time, false).timeout
	sweep_telegraph.visible = false

	var sweep_audio: AudioStreamPlayer = null
	if railgun_sound_res != null:
		sweep_audio = AudioStreamPlayer.new()
		sweep_audio.stream = railgun_sound_res
		sweep_audio.bus = &"SFX"
		sweep_audio.volume_db = 4.0
		get_tree().root.add_child(sweep_audio)
		sweep_audio.play()

	_animate_sweep_beam(y)
	_sweep_active = true
	_sweep_timer = sweep_beam_time

	var elapsed: float = 0.0
	while elapsed < sweep_beam_time:
		_apply_sweep_damage()
		await get_tree().create_timer(0.05, false).timeout
		elapsed += 0.05

	if sweep_audio != null and is_instance_valid(sweep_audio):
		var tween := create_tween()
		tween.tween_property(sweep_audio, "volume_db", -80.0, 0.3)
		await tween.finished
		sweep_audio.stop()
		sweep_audio.queue_free()


func _drop_mines() -> void:
	if mine_scene == null:
		return
	var spawn_pos: Vector2 = projectile_spawn.global_position
	if mine_spawn != null:
		spawn_pos = mine_spawn.global_position
	for mine_index in range(mine_count):
		var mine := mine_scene.instantiate() as CharacterBody2D
		var h_offset: float = (float(mine_index) - float(mine_count - 1) * 0.5) * mine_spacing
		mine.global_position = spawn_pos + Vector2(h_offset, 0.0)
		if mine.has_method("launch_toward"):
			mine.launch_toward((target.global_position - mine.global_position).normalized())
		if mine.has_method("set"):
			mine.set("damage", mine_damage)
			mine.set("speed", mine_speed)
			mine.set("arm_delay", mine_arm_delay)
			mine.set("redirectable", true)
			mine.set("warden_ref", self)
		get_tree().current_scene.add_child(mine)


func _apply_sweep_damage() -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	var start := Vector2(arena_left, _sweep_y)
	var end := Vector2(arena_right, _sweep_y)
	var closest := Geometry2D.get_closest_point_to_segment(target.global_position, start, end)
	if target.global_position.distance_to(closest) <= sweep_width:
		target.take_damage(sweep_damage, start, false, false)


func _fire_railgun_slug() -> void:
	var origin: Vector2 = railgun_origin.global_position
	var direction: Vector2 = (target.global_position - origin).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2(_facing_sign, 0.0)
	var end: Vector2 = origin + direction * 1500.0

	_show_line(railgun_telegraph, origin, end, Color(1.0, 0.85, 0.2, 0.95), 8.0)
	await get_tree().create_timer(railgun_charge_time, false).timeout
	railgun_telegraph.visible = false

	var rail_audio := AudioStreamPlayer.new()
	rail_audio.stream = railgun_sound_res
	rail_audio.bus = &"SFX"
	rail_audio.volume_db = 4.0
	get_tree().root.add_child(rail_audio)
	rail_audio.play()

	_animate_railgun_beam(origin, end)
	_apply_railgun_damage(origin, end)
	await get_tree().create_timer(railgun_beam_time, false).timeout
	railgun_beam.visible = false

	if is_instance_valid(rail_audio):
		var tween := create_tween()
		tween.tween_property(rail_audio, "volume_db", -80.0, 0.3)
		await tween.finished
		rail_audio.stop()
		rail_audio.queue_free()

	var projectile := projectile_scene.instantiate() as CharacterBody2D
	projectile.global_position = origin + direction * 60.0
	projectile.damage = railgun_damage
	projectile.speed = railgun_speed
	projectile.max_step_distance = 8.0
	if projectile.has_method("set"):
		projectile.set("redirectable", true)
		projectile.set("railgun_slug", true)
		projectile.set("warden_ref", self)
		projectile.set("overload_damage", railgun_damage)
	projectile.set_shooter(self)
	projectile.initialize(direction)
	get_tree().current_scene.add_child(projectile)



func _scramble_portal() -> void:
	var portals: Array = get_tree().get_nodes_in_group("portals")
	if portals.is_empty():
		return
	var best_portal: Area2D = null
	var best_dist: float = INF
	for p in portals:
		if p == null or not is_instance_valid(p):
			continue
		var d: float = (p as Node2D).global_position.distance_to(target.global_position)
		if d < best_dist:
			best_dist = d
			best_portal = p
	if best_portal == null:
		return
	_scrambled_portal = best_portal
	_scrambled_portal_was_monitoring = best_portal.monitoring
	_scrambled_portal_restore_timer = scramble_disable_time
	best_portal.monitoring = false
	if best_portal.has_node("AnimatedSprite2D"):
		(best_portal.get_node("AnimatedSprite2D") as CanvasItem).modulate = Color(0.55, 0.55, 0.55, 1.0)


func _show_line(line: Line2D, start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	line.global_position = Vector2.ZERO
	line.clear_points()
	line.add_point(start)
	line.add_point(finish)
	line.default_color = color
	line.width = width
	line.visible = true


func _apply_railgun_damage(start: Vector2, finish: Vector2) -> bool:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return false
	var closest := Geometry2D.get_closest_point_to_segment(target.global_position, start, finish)
	if target.global_position.distance_to(closest) <= 22.0:
		target.take_damage(railgun_damage, start, false, false)
		return true
	return false


func _open_reactor_window(duration: float) -> void:
	_reactor_open_timer = maxf(_reactor_open_timer, duration)
	_sync_armor_visuals()


func _sync_armor_visuals() -> void:
	if front_armor_glow:
		front_armor_glow.modulate = Color(0.3, 0.7, 1.0, 0.2)
	if rear_reactor_glow:
		var alpha := 0.18 + clampf(_reactor_open_timer / maxf(reactor_open_time, 0.001), 0.0, 1.0) * 0.82
		rear_reactor_glow.modulate = Color(1.0, 0.25, 0.25, alpha)


# ── Death ──────────────────────────────────────────────────────────────────────

func _detach_railgun_fx_nodes() -> void:
	var root := get_tree().root
	if root == null:
		return
	if is_instance_valid(railgun_telegraph) and railgun_telegraph.get_parent() != root:
		railgun_telegraph.reparent(root)
		railgun_telegraph.top_level = true
		railgun_telegraph.process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(railgun_beam) and railgun_beam.get_parent() != root:
		railgun_beam.reparent(root)
		railgun_beam.top_level = true
		railgun_beam.process_mode = Node.PROCESS_MODE_ALWAYS
		railgun_beam.z_index = 500
		railgun_beam.show_behind_parent = false


func _animate_railgun_beam(origin: Vector2, end: Vector2) -> void:
	var direction: Vector2 = (end - origin).normalized()
	var length: float = origin.distance_to(end)
	var base_texture: Texture2D = railgun_beam.sprite_frames.get_frame_texture("pulse", 0)
	var base_width: float = maxf(base_texture.get_size().x, 1.0)
	railgun_beam.global_position = origin + direction * (length * 0.5)
	railgun_beam.rotation = direction.angle()
	railgun_beam.scale = Vector2(length / base_width, 1.0)
	railgun_beam.modulate = Color(0.74, 0.38, 1.0, 1.0)
	railgun_beam.z_index = 500
	railgun_beam.process_mode = Node.PROCESS_MODE_ALWAYS
	railgun_beam.visible = true
	railgun_beam.frame = 0
	railgun_beam.play("pulse")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for _p in range(4):
		tween.tween_property(railgun_beam, "modulate", Color(0.92, 0.55, 1.0, 1.0), 0.04)
		tween.tween_property(railgun_beam, "modulate", Color(0.74, 0.38, 1.0, 1.0), 0.04)


func _animate_sweep_beam(y: float) -> void:
	var length: float = arena_right - arena_left
	var base_texture: Texture2D = sweep_beam.sprite_frames.get_frame_texture("pulse", 0)
	var base_width: float = maxf(base_texture.get_size().x, 1.0)
	sweep_beam.global_position = Vector2(arena_left + length * 0.5, y)
	sweep_beam.rotation = 0.0
	sweep_beam.scale = Vector2(length / base_width, 1.0)
	sweep_beam.modulate = Color(1.0, 0.2, 0.2, 1.0)
	sweep_beam.z_index = 100
	sweep_beam.process_mode = Node.PROCESS_MODE_ALWAYS
	sweep_beam.visible = true
	sweep_beam.frame = 0
	sweep_beam.play("pulse")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for _p in range(4):
		tween.tween_property(sweep_beam, "modulate", Color(1.0, 0.4, 0.4, 1.0), 0.04)
		tween.tween_property(sweep_beam, "modulate", Color(1.0, 0.2, 0.2, 1.0), 0.04)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	sweep_telegraph.visible = false
	sweep_beam.visible = false
	railgun_telegraph.visible = false
	railgun_beam.visible = false

	var death_node: AnimatedSprite2D = get_node_or_null("DeathExplosion") as AnimatedSprite2D
	if death_node != null:
		if has_node("Ship"):
			(get_node("Ship") as CanvasItem).visible = false
		death_node.visible = true
		death_node.z_index = 200
		death_node.play("explosion")
		var s := AudioStreamPlayer2D.new()
		s.stream = death_sound_res
		s.global_position = global_position
		s.bus = &"SFX"
		get_tree().current_scene.add_child(s)
		s.play()
	else:
		var sf := SpriteFrames.new()
		sf.add_animation("explosion")
		for texture in death_explosion_frames:
			sf.add_frame("explosion", texture, 1.0)
		sf.set_animation_loop("explosion", false)
		var explosion := AnimatedSprite2D.new()
		explosion.sprite_frames = sf
		explosion.animation = "explosion"
		explosion.centered = true
		explosion.scale = Vector2(2.2, 2.2)
		explosion.global_position = global_position + Vector2(0.0, -10.0)
		explosion.z_index = 200
		get_tree().current_scene.add_child(explosion)
		explosion.play()
		var s2 := AudioStreamPlayer2D.new()
		s2.stream = death_sound_res
		s2.global_position = global_position
		s2.bus = &"SFX"
		get_tree().current_scene.add_child(s2)
		s2.play()

	var exits := get_tree().get_nodes_in_group("level_exits")
	for exit_node in exits:
		if exit_node.has_node("Area2D"):
			exit_node.get_node("Area2D").monitoring = true
			exit_node.visible = true

	await get_tree().create_timer(1.25).timeout
	_start_defeat_dialogue()
  
	queue_free()


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
