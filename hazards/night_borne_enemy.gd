extends CharacterBody2D


enum State { IDLE, ROAM, CHASE, ATTACK, HURT, DEATH }

# ── Stats ──────────────────────────────────────────────────────────────────────
@export_group("Stats")
@export var max_hp: int = 50
@export var move_speed: float = 60.0
@export var chase_speed: float = 120.0
@export var attack_damage: int = 20

# ── Timers ─────────────────────────────────────────────────────────────────────
@export_group("Timers")
@export var attack_cooldown: float = 1.5
@export var deaggro_time: float = 2.0
@export var roam_idle_min: float = 1.0
@export var roam_idle_max: float = 3.0
@export var roam_walk_min: float = 1.0
@export var roam_walk_max: float = 3.0

# ── Attack Window ──────────────────────────────────────────────────────────────
@export_group("Attack Window")
@export var damage_window_start: float = 0.58  ## seconds into Slash animation
@export var damage_window_end: float = 0.67    ## seconds into Slash animation
@export var attack_range: float = 45.0         ## X distance to begin attacking

# ── Line of Sight ──────────────────────────────────────────────────────────────
@export_group("Line of Sight")
@export var los_range: float = 200.0  ## How far the LOS raycasts extend

# ── Edge Detection ─────────────────────────────────────────────────────────────
@export_group("Edge Detection")
@export var edge_ray_horizontal: float = 20.0
@export var edge_ray_vertical: float = 30.0

# ── Wall / Obstacle Detection ──────────────────────────────────────────────────
@export_group("Wall Detection")
@export var wall_ray_length: float = 15.0  ## How far ahead to check for walls/hazards

# Animation durations (must match AnimationPlayer)
const SLASH_DURATION: float = 0.867
const HURT_DURATION: float = 0.5
const DEATH_DURATION: float = 2.0

# ── Internal State ─────────────────────────────────────────────────────────────
var current_hp: int
var state: State = State.IDLE
var target: Node2D = null
var facing: float = 1.0  # 1 = right, -1 = left

var _roam_timer: float = 0.0
var _idle_timer: float = 0.0
var _roam_direction: float = 0.0

var _attack_cooldown_timer: float = 0.0
var _attack_elapsed: float = 0.0
var _has_dealt_damage: bool = false

var _deaggro_timer: float = 0.0
var _player_in_deaggro: bool = false  # true while player is inside DeaggroArea
var _has_los: bool = false            # true when LOS raycast hits the player

var _hurt_timer: float = 0.0
var _death_timer: float = 0.0

var _edge_ray_left: RayCast2D
var _edge_ray_right: RayCast2D
var _los_ray_left: RayCast2D
var _los_ray_right: RayCast2D
var _wall_ray_left: RayCast2D
var _wall_ray_right: RayCast2D

# ── Node References ────────────────────────────────────────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var deaggro_area: Area2D = $DeaggroArea
@onready var hit_box: Area2D = $HitBox
@onready var hurt_box: Area2D = $HurtBox


# ═══════════════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")

	# Signals
	deaggro_area.body_entered.connect(_on_deaggro_body_entered)
	deaggro_area.body_exited.connect(_on_deaggro_body_exited)
	hit_box.body_entered.connect(_on_hitbox_body_entered)

	# Prevent player's HurtBox from also detecting our HitBox (avoids double damage)
	hit_box.monitorable = false
	_set_hitbox_active(false)

	# Edge detection raycasts (keep enemy on the platform)
	_setup_edge_detection()
	# Line-of-sight raycasts (player detection)
	_setup_los_raycasts()
	# Wall / obstacle raycasts (prevent walking into things)
	_setup_wall_detection()

	_enter_state(State.IDLE)
	print("NightBorne spawned — HP: ", current_hp, " / ", max_hp)


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Attack cooldown tick
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

	# Update line-of-sight check every physics frame
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

	if state != State.DEATH:
		move_and_slide()


# ═══════════════════════════════════════════════════════════════════════════════
#  State Processors
# ═══════════════════════════════════════════════════════════════════════════════

func _process_idle(delta: float) -> void:
	velocity.x = 0.0
	_idle_timer -= delta

	if _has_los and _valid_target():
		_enter_state(State.CHASE)
		return

	if _idle_timer <= 0.0:
		_enter_state(State.ROAM)


func _process_roam(delta: float) -> void:
	_roam_timer -= delta

	# Aggro check — LOS required
	if _has_los and _valid_target():
		_enter_state(State.CHASE)
		return

	# Turn around at platform edges or walls
	if _is_at_edge(_roam_direction) or _is_wall_ahead(_roam_direction):
		_roam_direction = -_roam_direction
		_update_facing(_roam_direction)

	velocity.x = _roam_direction * move_speed

	if _roam_timer <= 0.0:
		_enter_state(State.IDLE)


func _process_chase(delta: float) -> void:
	if not _valid_target():
		_enter_state(State.IDLE)
		return

	# Deaggro: player left the DeaggroArea OR lost LOS
	if not _player_in_deaggro or not _has_los:
		_deaggro_timer -= delta
		if _deaggro_timer <= 0.0:
			target = null
			_enter_state(State.IDLE)
			return
	else:
		# Reset deaggro while player is in area AND in sight
		_deaggro_timer = deaggro_time

	var dir_to_target := signf(target.global_position.x - global_position.x)
	var dist := absf(target.global_position.x - global_position.x)

	_update_facing(dir_to_target)

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


func _process_attack(delta: float) -> void:
	velocity.x = 0.0
	_attack_elapsed += delta

	# Damage window — check for hits
	var in_window := _attack_elapsed >= damage_window_start and _attack_elapsed <= damage_window_end
	if in_window and not _has_dealt_damage:
		_set_hitbox_active(true)
		_deal_attack_damage()
	elif _attack_elapsed > damage_window_end:
		_set_hitbox_active(false)

	# Slash animation complete
	if _attack_elapsed >= SLASH_DURATION:
		_finish_attack()


func _process_hurt(delta: float) -> void:
	velocity.x = 0.0
	_hurt_timer -= delta
	if _hurt_timer <= 0.0:
		if _has_los and _valid_target():
			_enter_state(State.CHASE)
		else:
			_enter_state(State.IDLE)


func _process_death(delta: float) -> void:
	velocity.x = 0.0
	_death_timer -= delta
	if _death_timer <= 0.0:
		queue_free()


# ═══════════════════════════════════════════════════════════════════════════════
#  State Transitions
# ═══════════════════════════════════════════════════════════════════════════════

func _enter_state(new_state: State) -> void:
	state = new_state
	match new_state:
		State.IDLE:
			_idle_timer = randf_range(roam_idle_min, roam_idle_max)
			anim_player.play("Idle")
		State.ROAM:
			_roam_direction = [-1.0, 1.0].pick_random()
			_roam_timer = randf_range(roam_walk_min, roam_walk_max)
			_update_facing(_roam_direction)
			anim_player.play("Run")
		State.CHASE:
			_deaggro_timer = deaggro_time
			anim_player.play("Run")
		State.ATTACK:
			velocity.x = 0.0
			_attack_elapsed = 0.0
			_has_dealt_damage = false
			_set_hitbox_active(true)  # Enable early so physics registers overlaps
			anim_player.play("Slash")
		State.HURT:
			_hurt_timer = HURT_DURATION
			_set_hitbox_active(false)
			anim_player.play("Hurt")
		State.DEATH:
			_death_timer = DEATH_DURATION
			_set_hitbox_active(false)
			collision_layer = 0
			collision_mask = 0
			anim_player.play("Death")


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
	print("NightBorne hit! -", amount, " HP  →  ", current_hp, " / ", max_hp)
	if current_hp <= 0:
		current_hp = 0
		_enter_state(State.DEATH)
	else:
		_enter_state(State.HURT)


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Dealing
# ═══════════════════════════════════════════════════════════════════════════════

func _deal_attack_damage() -> void:
	for body in hit_box.get_overlapping_bodies():
		if body == self or body.is_in_group("enemies"):
			continue
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, global_position)
			_has_dealt_damage = true
			return  # One hit per swing


## Backup signal — catches bodies entering the hitbox mid-swing during the window.
func _on_hitbox_body_entered(body: Node2D) -> void:
	if state != State.ATTACK or _has_dealt_damage:
		return
	if _attack_elapsed < damage_window_start or _attack_elapsed > damage_window_end:
		return
	if body == self or body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, global_position)
		_has_dealt_damage = true


# ═══════════════════════════════════════════════════════════════════════════════
#  Detection — Line of Sight + Deaggro Area
# ═══════════════════════════════════════════════════════════════════════════════

## DeaggroArea signals — tracks whether the player is within the leash zone.
func _on_deaggro_body_entered(body: Node2D) -> void:
	if body == self or body.is_in_group("enemies") or body.is_in_group("turret_bullets"):
		return
	if body.has_method("take_damage"):
		_player_in_deaggro = true
		# Remember the player reference for LOS checks
		if target == null:
			target = body


func _on_deaggro_body_exited(body: Node2D) -> void:
	if body == target:
		_player_in_deaggro = false
		_deaggro_timer = deaggro_time


## Cast LOS rays left and right every physics frame.
## Aggro triggers when a ray hits a body with take_damage (the player).
func _update_los() -> void:
	if state == State.DEATH:
		_has_los = false
		return

	_has_los = false

	# Check both rays — either side can spot the player
	for ray in [_los_ray_left, _los_ray_right]:
		if ray.is_colliding():
			var collider = ray.get_collider()
			if collider and collider.has_method("take_damage"):
				_has_los = true
				if target == null or target != collider:
					target = collider
				return  # Found player, no need to check other ray


# ═══════════════════════════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════════════════════════

func _valid_target() -> bool:
	return target != null and is_instance_valid(target)


func _update_facing(dir: float) -> void:
	if dir == 0.0:
		return
	facing = dir
	sprite.flip_h = facing < 0.0
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
	# Left-facing LOS ray
	_los_ray_left = RayCast2D.new()
	_los_ray_left.target_position = Vector2(-los_range, 0.0)
	_los_ray_left.collision_mask = 3  # Player (1) + Walls (2) — walls block LOS
	_los_ray_left.enabled = true
	add_child(_los_ray_left)

	# Right-facing LOS ray
	_los_ray_right = RayCast2D.new()
	_los_ray_right.target_position = Vector2(los_range, 0.0)
	_los_ray_right.collision_mask = 3  # Player (1) + Walls (2) — walls block LOS
	_los_ray_right.enabled = true
	add_child(_los_ray_right)


func _setup_wall_detection() -> void:
	# Left-facing wall ray — detects Walls (2) + Hazards (8) = mask 10
	_wall_ray_left = RayCast2D.new()
	_wall_ray_left.target_position = Vector2(-wall_ray_length, 0.0)
	_wall_ray_left.collision_mask = 10  # Walls (2) + Hazards (8)
	_wall_ray_left.enabled = true
	add_child(_wall_ray_left)

	# Right-facing wall ray
	_wall_ray_right = RayCast2D.new()
	_wall_ray_right.target_position = Vector2(wall_ray_length, 0.0)
	_wall_ray_right.collision_mask = 10  # Walls (2) + Hazards (8)
	_wall_ray_right.enabled = true
	add_child(_wall_ray_right)
