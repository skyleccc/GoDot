extends CharacterBody2D

## Striker Enemy — patrol / chase melee+ranged AI with dash.
## Uses line-of-sight raycasts (both sides) for player detection.
## DeaggroArea (Area2D) is created at runtime for leash detection.
## Strike animation: frames 2-4, 6-7 = melee hitbox; frame 13 = bullet spawn.
## Only turret bullets hurt it.

enum State { IDLE, ROAM, CHASE, ATTACK, HURT, DEATH, DASH }

# ── Stats ──────────────────────────────────────────────────────────────────────
@export_group("Stats")
@export var max_hp: int = 50
@export var move_speed: float = 60.0
@export var chase_speed: float = 120.0

# ── Timers ─────────────────────────────────────────────────────────────────────
@export_group("Timers")
@export var attack_cooldown: float = 1.5
@export var deaggro_time: float = 2.0
@export var roam_idle_min: float = 1.0
@export var roam_idle_max: float = 3.0
@export var roam_walk_min: float = 1.0
@export var roam_walk_max: float = 3.0

# ── Attack ─────────────────────────────────────────────────────────────────────
@export_group("Attack")
@export var attack_damage: int = 20
@export var attack_range: float = 45.0  ## X distance to begin attacking
@export var bullet_speed: float = 200.0
@export var bullet_lifetime: float = 2.0
@export var bullet_damage: int = 10

# ── Dash ───────────────────────────────────────────────────────────────────────
@export_group("Dash")
@export var dash_speed: float = 300.0
@export var dash_cooldown: float = 4.0
@export var dash_range_min: float = 80.0   ## Min dist for dash to trigger
@export var dash_range_max: float = 180.0  ## Max dist for dash to trigger

# ── Line of Sight ──────────────────────────────────────────────────────────────
@export_group("Line of Sight")
@export var los_range: float = 200.0

# ── Edge Detection ─────────────────────────────────────────────────────────────
@export_group("Edge Detection")
@export var edge_ray_horizontal: float = 20.0
@export var edge_ray_vertical: float = 30.0

# ── Wall / Obstacle Detection ──────────────────────────────────────────────────
@export_group("Wall Detection")
@export var wall_ray_length: float = 15.0

# ── Strike frame constants (0-indexed) ─────────────────────────────────────────
const MELEE_FRAMES: Array[int] = [2, 3, 4, 6, 7]
const BULLET_FRAME: int = 13

# Preloads
var bullet_scene: PackedScene = preload("res://hazards/StrikerBullet.tscn")

# ── Internal State ─────────────────────────────────────────────────────────────
var current_hp: int
var state: State = State.IDLE
var target: Node2D = null
var facing: float = 1.0  # 1 = right, -1 = left

var _roam_timer: float = 0.0
var _idle_timer: float = 0.0
var _roam_direction: float = 0.0

var _attack_cooldown_timer: float = 0.0
var _has_dealt_damage: bool = false
var _has_spawned_bullet: bool = false

var _deaggro_timer: float = 0.0
var _player_in_deaggro: bool = false
var _has_los: bool = false

var _dash_cooldown_timer: float = 0.0
var _dash_direction: float = 1.0

var _edge_ray_left: RayCast2D
var _edge_ray_right: RayCast2D
var _los_ray_left: RayCast2D
var _los_ray_right: RayCast2D
var _wall_ray_left: RayCast2D
var _wall_ray_right: RayCast2D

# ── Node References ────────────────────────────────────────────────────────────
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_box: Area2D = $HitBox
@onready var hurt_box: Area2D = $HurtBox
@onready var bullet_spawn: Marker2D = $BulletSpawn
@onready var deaggro_area: Area2D = $DeaggroArea


# ═══════════════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")

	# Disable looping on one-shot animations
	var sf := animated_sprite.sprite_frames
	for anim_name in ["Death", "Struck", "Strike", "Dash"]:
		if sf.has_animation(anim_name):
			sf.set_animation_loop(anim_name, false)

	# Signals
	animated_sprite.frame_changed.connect(_on_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	hit_box.body_entered.connect(_on_hitbox_body_entered)

	# Prevent double damage from player's HurtBox overlap
	hit_box.monitorable = false
	_set_hitbox_active(false)

	# DeaggroArea signals
	deaggro_area.body_entered.connect(_on_deaggro_body_entered)
	deaggro_area.body_exited.connect(_on_deaggro_body_exited)
	# Edge detection raycasts
	_setup_edge_detection()
	# Line-of-sight raycasts
	_setup_los_raycasts()
	# Wall / obstacle raycasts
	_setup_wall_detection()

	_enter_state(State.IDLE)
	print("Striker spawned — HP: ", current_hp, " / ", max_hp)


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Cooldown ticks
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta

	# Update line-of-sight
	_update_los()

	# State machine
	match state:
		State.IDLE:
			_process_idle(delta)
		State.ROAM:
			_process_roam(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
		State.HURT:
			_process_hurt(delta)
		State.DEATH:
			_process_death(delta)
		State.DASH:
			_process_dash(delta)

	if state != State.DEATH:
		move_and_slide()


# ═══════════════════════════════════════════════════════════════════════════════
#  State Processors
# ═══════════════════════════════════════════════════════════════════════════════

func _process_idle(_delta: float) -> void:
	velocity.x = 0.0
	_idle_timer -= _delta

	if _has_los and _valid_target():
		_enter_state(State.CHASE)
		return

	if _idle_timer <= 0.0:
		_enter_state(State.ROAM)


func _process_roam(_delta: float) -> void:
	_roam_timer -= _delta

	if _has_los and _valid_target():
		_enter_state(State.CHASE)
		return

	if _is_at_edge(_roam_direction) or _is_wall_ahead(_roam_direction):
		_roam_direction = -_roam_direction
		_update_facing(_roam_direction)

	velocity.x = _roam_direction * move_speed

	if _roam_timer <= 0.0:
		_enter_state(State.IDLE)


func _process_chase(_delta: float) -> void:
	if not _valid_target():
		_enter_state(State.IDLE)
		return

	# Deaggro: player left the DeaggroArea OR lost LOS
	if not _player_in_deaggro or not _has_los:
		_deaggro_timer -= _delta
		if _deaggro_timer <= 0.0:
			target = null
			_enter_state(State.IDLE)
			return
	else:
		_deaggro_timer = deaggro_time

	var dir_to_target := signf(target.global_position.x - global_position.x)
	var dist := absf(target.global_position.x - global_position.x)

	_update_facing(dir_to_target)

	# Try dash if in range and off cooldown
	if _dash_cooldown_timer <= 0.0 and dist >= dash_range_min and dist <= dash_range_max:
		_enter_state(State.DASH)
		return

	# Don't walk off edges or into walls while chasing
	if _is_at_edge(dir_to_target) or _is_wall_ahead(dir_to_target):
		velocity.x = 0.0
	elif dist > attack_range:
		velocity.x = dir_to_target * chase_speed
	else:
		velocity.x = 0.0

	# Attack if close enough and off cooldown
	if dist <= attack_range and _attack_cooldown_timer <= 0.0:
		_enter_state(State.ATTACK)


func _process_attack(_delta: float) -> void:
	velocity.x = 0.0
	# Frame-based logic handled by _on_frame_changed and _on_animation_finished


func _process_hurt(_delta: float) -> void:
	velocity.x = 0.0
	# Handled by _on_animation_finished


func _process_death(_delta: float) -> void:
	velocity.x = 0.0
	# Handled by _on_animation_finished


func _process_dash(_delta: float) -> void:
	# Don't dash off edges or into walls
	if _is_at_edge(_dash_direction) or _is_wall_ahead(_dash_direction):
		velocity.x = 0.0
	else:
		velocity.x = _dash_direction * dash_speed

	# Check if close enough to attack mid-dash
	if _valid_target():
		var dist := absf(target.global_position.x - global_position.x)
		if dist <= attack_range and _attack_cooldown_timer <= 0.0:
			_enter_state(State.ATTACK)
			return
	# Dash ends when animation finishes (handled by _on_animation_finished)


# ═══════════════════════════════════════════════════════════════════════════════
#  Animation Callbacks
# ═══════════════════════════════════════════════════════════════════════════════

const RETARGET_FRAMES: Array[int] = [2, 6, 12]  # Frames where the striker can change facing direction to track target during attack

func _on_frame_changed() -> void:
	if state != State.ATTACK:
		return

	var frame := animated_sprite.frame

	# Allow direction change on key frames
	if frame in RETARGET_FRAMES and _valid_target():
		var dir_to_target := signf(target.global_position.x - global_position.x)
		_update_facing(dir_to_target)

	# Melee window: frames 2-4, 6-7
	if frame in MELEE_FRAMES:
		if not _has_dealt_damage:
			_set_hitbox_active(true)
			_deal_attack_damage()
	else:
		_set_hitbox_active(false)

	# Ranged: frame 13 spawns bullet
	if frame == BULLET_FRAME and not _has_spawned_bullet:
		_has_spawned_bullet = true
		_spawn_bullet()


func _on_animation_finished() -> void:
	match state:
		State.ATTACK:
			_finish_attack()
		State.HURT:
			if _has_los and _valid_target():
				_enter_state(State.CHASE)
			else:
				_enter_state(State.IDLE)
		State.DEATH:
			queue_free()
		State.DASH:
			_dash_cooldown_timer = dash_cooldown
			if _has_los and _valid_target():
				_enter_state(State.CHASE)
			else:
				_enter_state(State.IDLE)


# ═══════════════════════════════════════════════════════════════════════════════
#  State Transitions
# ═══════════════════════════════════════════════════════════════════════════════

func _enter_state(new_state: State) -> void:
	state = new_state
	match new_state:
		State.IDLE:
			_idle_timer = randf_range(roam_idle_min, roam_idle_max)
			animated_sprite.play("Idle")
		State.ROAM:
			_roam_direction = [-1.0, 1.0].pick_random()
			_roam_timer = randf_range(roam_walk_min, roam_walk_max)
			_update_facing(_roam_direction)
			animated_sprite.play("Run")
		State.CHASE:
			_deaggro_timer = deaggro_time
			animated_sprite.play("Run")
		State.ATTACK:
			velocity.x = 0.0
			_has_dealt_damage = false
			_has_spawned_bullet = false
			_set_hitbox_active(false)
			animated_sprite.play("Strike")
		State.HURT:
			_set_hitbox_active(false)
			animated_sprite.play("Struck")
		State.DEATH:
			_set_hitbox_active(false)
			collision_layer = 0
			collision_mask = 0
			animated_sprite.play("Death")
		State.DASH:
			if _valid_target():
				_dash_direction = signf(target.global_position.x - global_position.x)
			else:
				_dash_direction = facing
			_update_facing(_dash_direction)
			animated_sprite.play("Dash")


func _finish_attack() -> void:
	_set_hitbox_active(false)
	_attack_cooldown_timer = attack_cooldown
	if _has_los and _valid_target():
		_enter_state(State.CHASE)
	else:
		_enter_state(State.IDLE)


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Receiving
# ═══════════════════════════════════════════════════════════════════════════════

## Called by turret bullets — the ONLY source that can hurt this enemy.
func take_bullet_damage(amount: int, _hit_source_pos: Vector2 = global_position) -> void:
	if state == State.DEATH:
		return
	current_hp -= amount
	print("Striker hit! -", amount, " HP  →  ", current_hp, " / ", max_hp)
	if current_hp <= 0:
		current_hp = 0
		_enter_state(State.DEATH)
	else:
		_enter_state(State.HURT)


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Dealing (Melee)
# ═══════════════════════════════════════════════════════════════════════════════

func _deal_attack_damage() -> void:
	for body in hit_box.get_overlapping_bodies():
		if body == self or body.is_in_group("enemies"):
			continue
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, global_position)
			_has_dealt_damage = true
			return  # One hit per swing


## Backup signal — catches bodies entering the hitbox mid-swing during melee frames.
func _on_hitbox_body_entered(body: Node2D) -> void:
	if state != State.ATTACK or _has_dealt_damage:
		return
	var frame := animated_sprite.frame
	if frame not in MELEE_FRAMES:
		return
	if body == self or body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, global_position)
		_has_dealt_damage = true


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Dealing (Ranged)
# ═══════════════════════════════════════════════════════════════════════════════

func _spawn_bullet() -> void:
	var bullet = bullet_scene.instantiate()
	# Mirror spawn position based on facing direction
	var spawn_offset := Vector2(bullet_spawn.position.x * facing, bullet_spawn.position.y)
	bullet.global_position = global_position + spawn_offset
	bullet.direction = facing
	bullet.speed = bullet_speed
	bullet.lifetime = bullet_lifetime
	bullet.damage = bullet_damage
	get_tree().current_scene.add_child(bullet)
	bullet.initialize()
	# Prevent bullet from colliding with the striker that spawned it
	bullet.add_collision_exception_with(self)


# ═══════════════════════════════════════════════════════════════════════════════
#  Detection — Line of Sight + Deaggro Area
# ═══════════════════════════════════════════════════════════════════════════════

func _on_deaggro_body_entered(body: Node2D) -> void:
	if body == self or body.is_in_group("enemies") or body.is_in_group("turret_bullets") or body.is_in_group("striker_bullets"):
		return
	if body.has_method("take_damage"):
		_player_in_deaggro = true
		if target == null:
			target = body


func _on_deaggro_body_exited(body: Node2D) -> void:
	if body == target:
		_player_in_deaggro = false
		_deaggro_timer = deaggro_time


func _update_los() -> void:
	if state == State.DEATH:
		_has_los = false
		return

	_has_los = false

	for ray in [_los_ray_left, _los_ray_right]:
		if ray.is_colliding():
			var collider = ray.get_collider()
			if collider and collider.has_method("take_damage"):
				_has_los = true
				if target == null or target != collider:
					target = collider
				return


# ═══════════════════════════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════════════════════════

func _valid_target() -> bool:
	return target != null and is_instance_valid(target)


func _update_facing(dir: float) -> void:
	if dir == 0.0:
		return
	facing = dir
	animated_sprite.flip_h = facing < 0.0
	# Mirror HitBox collision shapes to match facing direction
	hit_box.scale.x = absf(hit_box.scale.x) * signf(facing)


func _set_hitbox_active(active: bool) -> void:
	hit_box.monitoring = active
	for child in hit_box.get_children():
		if child is CollisionShape2D:
			child.disabled = not active


func _is_at_edge(direction: float) -> bool:
	if not is_on_floor():
		return false
	if direction < 0.0:
		return _edge_ray_left != null and not _edge_ray_left.is_colliding()
	elif direction > 0.0:
		return _edge_ray_right != null and not _edge_ray_right.is_colliding()
	return false


func _is_wall_ahead(direction: float) -> bool:
	if direction < 0.0:
		return _wall_ray_left != null and _wall_ray_left.is_colliding()
	elif direction > 0.0:
		return _wall_ray_right != null and _wall_ray_right.is_colliding()
	return false


func _setup_edge_detection() -> void:
	_edge_ray_left = RayCast2D.new()
	_edge_ray_left.target_position = Vector2(-edge_ray_horizontal, edge_ray_vertical)
	_edge_ray_left.collision_mask = 2  # Walls layer
	_edge_ray_left.enabled = true
	add_child(_edge_ray_left)

	_edge_ray_right = RayCast2D.new()
	_edge_ray_right.target_position = Vector2(edge_ray_horizontal, edge_ray_vertical)
	_edge_ray_right.collision_mask = 2  # Walls layer
	_edge_ray_right.enabled = true
	add_child(_edge_ray_right)


func _setup_los_raycasts() -> void:
	_los_ray_left = RayCast2D.new()
	_los_ray_left.target_position = Vector2(-los_range, 0.0)
	_los_ray_left.collision_mask = 3  # Player (1) + Walls (2)
	_los_ray_left.enabled = true
	add_child(_los_ray_left)

	_los_ray_right = RayCast2D.new()
	_los_ray_right.target_position = Vector2(los_range, 0.0)
	_los_ray_right.collision_mask = 3  # Player (1) + Walls (2)
	_los_ray_right.enabled = true
	add_child(_los_ray_right)


func _setup_wall_detection() -> void:
	_wall_ray_left = RayCast2D.new()
	_wall_ray_left.target_position = Vector2(-wall_ray_length, 0.0)
	_wall_ray_left.collision_mask = 10  # Walls (2) + Hazards (8)
	_wall_ray_left.enabled = true
	add_child(_wall_ray_left)

	_wall_ray_right = RayCast2D.new()
	_wall_ray_right.target_position = Vector2(wall_ray_length, 0.0)
	_wall_ray_right.collision_mask = 10  # Walls (2) + Hazards (8)
	_wall_ray_right.enabled = true
	add_child(_wall_ray_right)
