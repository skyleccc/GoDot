extends PortalEntity

## Portal-style 2D platformer character controller.
## Designed around the core Portal mechanic: momentum is preserved through portals.
## Air control is intentionally weak so portal flings carry the player properly.
## Includes coyote time and jump buffering for responsive platforming feel.

@export var SPEED: float = 150.0
@export var SPRINT_MULTIPLIER: float = 1.5
@export var JUMP_VELOCITY: float = -400.0
@export var MAX_SPEED: float = 1500.0

@export_group("Acceleration")
@export var GROUND_ACCELERATION: float = 20.0
@export var AIR_ACCELERATION: float = 5.0
@export var FLING_AIR_ACCELERATION: float = 1.0

@export_group("Friction")
@export var GROUND_FRICTION: float = 1000.0  # higher = stops faster on ground
@export var AIR_FRICTION: float = 2.0
@export var FLING_AIR_FRICTION: float = 0.15

@export_group("Jump Feel")
@export var COYOTE_TIME: float = 0.12
@export var JUMP_BUFFER_TIME: float = 0.1

@export_group("Health")
@export var max_hp: int = 100
@export var default_hazard_damage: int = 10
@export var invincibility_grace: float = 0.3
@export var knockback_force: Vector2 = Vector2(60.0, -75.0)

@onready var sprite: Sprite2D = $Player
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var _state_machine: AnimationNodeStateMachinePlayback = null

var start_position: Vector2
var current_hp: int
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_grounded: bool = false
var _is_invincible: bool = false
var _invincibility_timer: float = 0.0
var _is_knocked_back: bool = false
var _knockback_timer: float = 0.0
var _is_dying: bool = false
var _die_timer: float = 0.0
var _respawn_delay_timer: float = 0.0
var _awaiting_respawn: bool = false
var _is_landing: bool = false
var _landing_timer: float = 0.0
var _was_airborne: bool = false

func _ready() -> void:
	current_hp = max_hp
	animation_tree.active = true
	_state_machine = animation_tree.get("parameters/playback")
	start_position = position
	print("Player spawned — HP: ", current_hp, " / ", max_hp)

func _physics_process(delta: float) -> void:
	# --- Invincibility countdown ---
	if _is_invincible:
		_invincibility_timer -= delta
		# Blink the sprite to indicate invincibility
		sprite.modulate.a = 0.3 if fmod(_invincibility_timer, 0.16) < 0.08 else 1.0
		if _invincibility_timer <= 0.0:
			_is_invincible = false
			sprite.modulate.a = 1.0

	# --- Waiting for respawn after die animation ---
	if _awaiting_respawn:
		_respawn_delay_timer -= delta
		if _respawn_delay_timer <= 0.0:
			_finish_die()
		return

	# --- Die animation in progress: only apply gravity + slide, no input ---
	if _is_dying:
		_die_timer -= delta
		if not is_grounded:
			velocity += get_gravity() * delta
		custom_move_and_slide(delta)
		if _die_timer <= 0.0:
			# Die animation done — freeze and wait for respawn delay
			_is_dying = false
			_awaiting_respawn = true
			_respawn_delay_timer = 0.6
			velocity = Vector2.ZERO
		return

	# --- Knockback animation in progress: apply gravity but no player input ---
	if _is_knocked_back:
		_knockback_timer -= delta
		if not is_grounded:
			velocity += get_gravity() * delta
		custom_move_and_slide(delta)
		if _knockback_timer <= 0.0:
			_is_knocked_back = false
			if _state_machine:
				_state_machine.travel("Move")
		return

	# --- Land animation in progress: hold position, no input ---
	if _is_landing:
		_landing_timer -= delta
		if not is_grounded:
			velocity += get_gravity() * delta
		else:
			velocity.x = 0.0
		custom_move_and_slide(delta)
		if _landing_timer <= 0.0:
			_is_landing = false
			if _state_machine:
				_state_machine.travel("Move")
		_was_grounded = is_grounded
		_was_airborne = not is_grounded
		return

	# --- Coyote time tracking ---
	if is_grounded:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer -= delta

	# --- Jump buffer tracking ---
	if Input.is_action_just_pressed("Up"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		_jump_buffer_timer -= delta

	# --- Gravity ---
	if not is_grounded:
		velocity += get_gravity() * delta

	# --- Jump (with coyote time + buffer) ---
	var can_jump := _coyote_timer > 0.0 or is_grounded
	if can_jump and _jump_buffer_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		# Cancel portal launch state when player intentionally jumps
		# so they get full air control back
		launched_by_portal = false

	# --- Horizontal movement ---
	var direction := Input.get_axis("Left", "Right")
	var is_sprinting := Input.is_action_pressed("Sprint") and is_grounded
	var target_speed := direction * SPEED * (SPRINT_MULTIPLIER if is_sprinting else 1.0)

	if is_grounded:
		if direction != 0:
			velocity.x = lerp(velocity.x, target_speed, minf(GROUND_ACCELERATION * delta, 1.0))
		# On ground: apply strong friction to stop quickly
		# But don't apply friction if we just landed from a portal fling
		# and the player is still holding a direction
		if direction == 0:
			velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
	else:
		# In air: use different acceleration depending on portal state
		var air_accel := FLING_AIR_ACCELERATION if launched_by_portal else AIR_ACCELERATION
		var air_fric := FLING_AIR_FRICTION if launched_by_portal else AIR_FRICTION

		if direction != 0:
			# Gentle air steering — weaker during portal flings
			velocity.x = lerp(velocity.x, target_speed, minf(air_accel * delta, 1.0))
		else:
			# Air deceleration — very slow during portal flings
			velocity.x = move_toward(velocity.x, 0.0, air_fric * delta)

	# --- Speed cap (prevents infinite acceleration from repeated portals) ---
	velocity = velocity.limit_length(MAX_SPEED)

	# --- Sprite flipping (based on velocity, not input) ---
	if velocity.x > 0.1:
		sprite.flip_h = false
	elif velocity.x < -0.1:
		sprite.flip_h = true

	# --- Animation ---
	if _state_machine:
		if not is_grounded:
			# Airborne: pick animation based on vertical velocity
			if velocity.y < -50.0:
				_travel_if_not("JumpRise")
			elif velocity.y < 50.0:
				_travel_if_not("JumpMid")
			else:
				_travel_if_not("JumpFall")
		elif _was_airborne:
			# Just landed this frame — play Land and lock input
			_is_landing = true
			_landing_timer = 0.2  # Land animation length
			_state_machine.travel("Land")
		else:
			# On ground — use Move blend space (idle/walk/sprint)
			var current := _state_machine.get_current_node()
			if current != "Land" and current != "Move":
				_state_machine.travel("Move")

	if direction != 0:
		animation_tree.set("parameters/Move/blend_position", 1.0 if is_sprinting else 0.5)
	else:
		animation_tree.set("parameters/Move/blend_position", 0.0)

	# --- Move ---
	custom_move_and_slide(delta)

	# --- Track grounded state change ---
	_was_grounded = is_grounded
	_was_airborne = not is_grounded

## Called when a hazard Area2D overlaps the character's HurtBox.
func _on_hurt_box_area_entered(area: Area2D) -> void:
	if _is_invincible or _is_dying:
		return
	# Use the hazard's damage value if it has one, otherwise fall back to default
	var damage: int = default_hazard_damage
	if area.get("damage") != null:
		damage = area.get("damage")
	take_damage(damage, area.global_position)

## Apply damage to the character, play hit animation, and start invincibility.
func take_damage(amount: int, hit_source_pos: Vector2 = global_position, knockback: bool = true) -> void:
	if _is_invincible or _is_dying:
		return
	current_hp -= amount
	print("Player hit! -", amount, " HP  →  HP: ", current_hp, " / ", max_hp)
	if current_hp <= 0:
		_start_die()
	elif knockback:
		_start_knockback(hit_source_pos)
	else:
		_start_invincibility(invincibility_grace)

## Begin the knockback animation and apply knockback velocity.
func _start_knockback(hit_source_pos: Vector2) -> void:
	_is_knocked_back = true
	_knockback_timer = 0.9  # Knockback animation length
	# Knockback direction: push away from the damage source
	var kb_dir: float = sign(global_position.x - hit_source_pos.x)
	if kb_dir == 0:
		kb_dir = -1.0 if sprite.flip_h else 1.0
	velocity = Vector2(kb_dir * knockback_force.x, knockback_force.y)
	# Start invincibility for the animation duration + grace period
	_start_invincibility(0.9 + invincibility_grace)  # 0.9s = Knockback anim length
	# Travel to Knockback state in the AnimationTree
	if _state_machine:
		_state_machine.travel("Knockback")

## Begin the die animation — player is locked in place.
func _start_die() -> void:
	_is_dying = true
	_die_timer = 0.63  # Die animation length
	velocity = Vector2(0.0, knockback_force.y * 0.5)  # Small upward pop
	_start_invincibility(999.0)  # Invincible throughout death
	if _state_machine:
		_state_machine.travel("Die")

## Called after die animation + respawn delay — reset to spawn.
func _finish_die() -> void:
	print("Player died! Respawning...")
	_awaiting_respawn = false
	current_hp = max_hp
	position = start_position
	velocity = Vector2.ZERO
	launched_by_portal = false
	# Brief invincibility after respawn
	_start_invincibility(1.0)
	# Return to Move state
	if _state_machine:
		_state_machine.travel("Move")
	print("HP restored: ", current_hp, " / ", max_hp)

## Activate invincibility for the given duration.
func _start_invincibility(duration: float) -> void:
	_is_invincible = true
	_invincibility_timer = duration

## Travel to a state only if not already in it (avoids restarting the same animation).
func _travel_if_not(state_name: String) -> void:
	if _state_machine and _state_machine.get_current_node() != state_name:
		_state_machine.travel(state_name)
