extends PortalEntity
class_name WardenProjectile

# ─────────────────────────────────────────────
#  Core properties (set by spawner before add_child)
# ─────────────────────────────────────────────
var damage: int               = 0
var speed: float              = 300.0
var max_step_distance: float  = 12.0
var direction: Vector2        = Vector2.ZERO
var shooter: Node             = null
var _grace_frame_count = 0
# ─────────────────────────────────────────────
#  Portal / redirect flags
#  Set by WardenBoss before add_child so the
#  portal system can read them without casting.
# ─────────────────────────────────────────────

## If true, the portal system is allowed to
## reroute this projectile through a portal pair.
var redirectable: bool        = false

## True only on railgun slugs. Portal system
## calls warden_ref.take_railgun_overload() when
## it reroutes this slug back into the boss rear.
var railgun_slug: bool        = false

## Damage dealt on a railgun overload hit.
## Only meaningful when railgun_slug == true.
var overload_damage: int      = 0

## Reference back to the Warden so the portal
## system can call take_railgun_overload() on it.
var warden_ref: Node          = null

# ─────────────────────────────────────────────
#  Lifetime safety — frees the projectile if
#  it never hits anything within this time.
# ─────────────────────────────────────────────
@export var lifetime: float   = 6.0
var _age: float               = 0.0

# ─────────────────────────────────────────────
#  Whether this projectile has already hit
#  something. Guards against double-hits when
#  move_and_slide() resolves multiple contacts
#  in one frame.
# ─────────────────────────────────────────────
var _hit: bool = false

var hit_scene: PackedScene = preload("res://enemies/warden_projectile_hit.tscn")


# ═════════════════════════════════════════════
#  INIT
# ═════════════════════════════════════════════

func set_shooter(owner_node: Node) -> void:
	shooter = owner_node


func initialize(dir: Vector2) -> void:
	direction = dir.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	rotation = direction.angle()


# ═════════════════════════════════════════════
#  PHYSICS
# ═════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if _hit:
		return

	if direction == Vector2.ZERO:
		queue_free()
		return

	# Lifetime guard
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	_grace_frame_count += 1
	velocity = direction * speed
	if direction.length() > 0.01:
		rotation = direction.angle()
	
	var collision := move_and_slide()

	# move_and_slide() returns true when at least one collision occurred.
	# We iterate slide collisions to find a valid target.
	if collision and _grace_frame_count > 2:
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			if col == null:
				continue
			var body := col.get_collider()
			if body == null or body == shooter:
				continue
			_on_hit(body)
			return

	_check_bounds()


# ═════════════════════════════════════════════
#  HIT RESOLUTION
# ═════════════════════════════════════════════

## Central hit handler. Called either from the
## slide-collision loop above or from an Area2D
## body_entered signal if you wire one up.
func _on_hit(body: Node) -> void:
	if _hit:
		return
	if body == shooter:
		return

	_hit = true

	# Play collision VFX/SFX
	_play_hit_effect()

	# ── Railgun overload path ──────────────────
	# Portal system sets is_overload_return = true
	# and calls this after rerouting the slug from
	# behind the boss. We forward to the warden.
	if railgun_slug and warden_ref != null and is_instance_valid(warden_ref):
		if warden_ref.has_method("take_railgun_overload"):
			warden_ref.take_railgun_overload(global_position, overload_damage)
		queue_free()
		return

	# ── Normal hit path ───────────────────────
	# Prefer take_bullet_damage (used by Warden
	# front armor so it can reflect). Fall back
	# to take_damage for everything else.
	if body.has_method("take_bullet_damage"):
		body.take_bullet_damage(damage, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(damage, global_position)

	queue_free()


func _play_hit_effect() -> void:
	var instance: Node2D = hit_scene.instantiate() as Node2D
	instance.global_position = global_position
	instance.rotation = rotation
	# ensure hit VFX is visible above geometry
	if instance.has_method("set"):
		pass
	get_tree().current_scene.add_child(instance)
	# bump AnimatedSprite2D z_index if present
	if instance.has_node("AnimatedSprite2D"):
		var aspr := instance.get_node("AnimatedSprite2D") as AnimatedSprite2D
		aspr.z_index = 300
		aspr.play("default")

	var s: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	# no collision SFX here (played by boss when firing)
	get_tree().current_scene.add_child(s)
	# keep silent; remove player after short time to avoid orphan nodes
	await get_tree().create_timer(0.1, false).timeout
	if is_instance_valid(s):
		s.queue_free()


## Called by the portal system when it redirects
## this projectile. Updates direction so the
## projectile continues from the exit portal.
func redirect(new_direction: Vector2, new_origin: Vector2) -> void:
	direction          = new_direction.normalized()
	global_position    = new_origin
	velocity           = direction * speed
	# Reset age so redirected projectiles get
	# a full lifetime from the exit portal.
	_age               = 0.0
	_hit               = false


# ═════════════════════════════════════════════
#  BOUNDS CLEANUP
# ═════════════════════════════════════════════

func _check_bounds() -> void:
	var pos := global_position
	if pos.x < -2500 or pos.x > 2500 or pos.y < -2500 or pos.y > 2500:
		queue_free()
