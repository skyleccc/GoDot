extends PortalEntity

@export var damage: int = 24
@export var arm_delay: float = 0.65
@export var fall_velocity: float = 120.0
@export var lifetime: float = 12.0
@export var speed: float = 160.0
@export var travel_time: float = 0.9

var _armed: bool = false
var _time_alive: float = 0.0

@onready var detection_area: Area2D = $DetectionArea
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("hazards")
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered)


func initialize(_direction: Vector2 = Vector2.ZERO) -> void:
	velocity = Vector2(0.0, fall_velocity)


func launch_toward(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	velocity = direction.normalized() * speed


func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= maxf(lifetime, travel_time):
		queue_free()
		return

	if not _armed:
		arm_delay -= delta
		if arm_delay <= 0.0:
			_armed = true
			if sprite:
				sprite.modulate = Color(1.0, 0.8, 0.3, 1.0)

	velocity.y = minf(velocity.y + get_gravity().y * delta * 0.5, fall_velocity)
	custom_move_and_slide(delta)


func _on_body_entered(body: Node2D) -> void:
	if not _armed:
		return
	if body == null or not body.has_method("take_damage"):
		return

	if body.is_in_group("player"):
		body.take_damage(damage, global_position, true, false)
		queue_free()
		return

	if launched_by_portal and body.is_in_group("enemies"):
		if body.has_method("take_bullet_damage"):
			body.take_bullet_damage(damage, global_position)
		else:
			body.take_damage(damage, global_position, true, false)
		queue_free()