extends PortalEntity

@export var speed: float = 260.0
@export var lifetime: float = 6.0
@export var damage: int = 20
@export var max_step_distance: float = 12.0

var direction: Vector2 = Vector2.RIGHT
var _time_alive: float = 0.0
var _shooter: CollisionObject2D = null

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("hazards")
	animated_sprite.play("default")

func initialize(start_direction: Vector2) -> void:
	direction = start_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	velocity = direction * speed
	rotation = velocity.angle()

func set_shooter(shooter_body: CollisionObject2D) -> void:
	_shooter = shooter_body
	if _shooter != null:
		add_collision_exception_with(_shooter)

func notify_portal_launch() -> void:
	super.notify_portal_launch()
	if _shooter != null:
		remove_collision_exception_with(_shooter)
		_shooter = null

func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()
		return

	if velocity.length() > 0.01:
		rotation = velocity.angle()

	var remaining_distance := velocity.length() * delta
	if remaining_distance <= 0.001:
		return

	var step_count := maxi(1, int(ceil(remaining_distance / max_step_distance)))
	var step_motion := velocity * (delta / float(step_count))

	for _i in step_count:
		var collision := move_and_collide(step_motion)
		if collision == null:
			continue

		if _is_portal_collision(collision):
			# Nudge just into the portal surface so portal overlap detection is reliable.
			global_position = collision.get_position() + collision.get_normal() * -6.0
			return

		var collider := collision.get_collider()
		if collider == null:
			queue_free()
			return

		# Boss projectile always hurts non-enemy targets (player).
		if collider.has_method("take_damage") and not collider.is_in_group("enemies"):
			collider.take_damage(damage, global_position, true, false)
			queue_free()
			return

		# Projectile can hurt enemies only when redirected through a portal.
		if launched_by_portal and collider.has_method("take_bullet_damage") and collider.is_in_group("enemies"):
			collider.take_bullet_damage(damage, global_position)
			queue_free()
			return

		queue_free()
		return

func _is_portal_collision(collision: KinematicCollision2D) -> bool:
	# Base check from PortalEntity.
	if _find_portal_at_collision(collision):
		return true

	# Fallback probe around the hit point to catch narrow/high-speed impacts.
	var space_state := get_world_2d().direct_space_state
	var hit_pos: Vector2 = collision.get_position()
	var normal: Vector2 = collision.get_normal()
	var sample_points := [
		hit_pos,
		hit_pos + normal * -8.0,
		hit_pos + normal * -16.0,
		hit_pos + normal * 4.0,
	]

	for point in sample_points:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = point
		query.collide_with_areas = true
		query.collide_with_bodies = false

		for result in space_state.intersect_point(query):
			if result.collider is Area2D and result.collider.is_in_group("portals"):
				return true

	return false
