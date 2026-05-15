extends PortalEntity

@export var damage: int = 24
@export var arm_delay: float = 0.65
@export var fall_velocity: float = 120.0
@export var lifetime: float = 12.0
@export var speed: float = 160.0
@export var travel_time: float = 0.9
@export var min_detonate_time: float = 5.0
@export var max_detonate_time: float = 7.0

var _armed: bool = false
var _time_alive: float = 0.0
var _detonate_timer: float = 0.0
var _has_detonated: bool = false
var _launch_velocity: Vector2 = Vector2.ZERO

@onready var detection_area: Area2D = $DetectionArea
@onready var sprite: AnimatedSprite2D = $Sprite2D

var explosion_frames: Array = [
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-1.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-2.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-3.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-4.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-5.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-6.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-7.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-b/Sprites/explosion-1-b-8.png")
]


func _ready() -> void:
	add_to_group("hazards")
	if sprite != null:
		sprite.play("default")
	if detection_area != null:
		detection_area.body_entered.connect(_on_body_entered)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	_detonate_timer = rng.randf_range(min_detonate_time, max_detonate_time)


func initialize(_direction: Vector2 = Vector2.ZERO) -> void:
	_launch_velocity = Vector2(0.0, fall_velocity)
	velocity = _launch_velocity


func launch_toward(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	_launch_velocity = direction.normalized() * speed
	velocity = _launch_velocity


func _physics_process(delta: float) -> void:
	if _has_detonated:
		return

	_time_alive += delta
	if _time_alive >= _detonate_timer:
		_detonate()
		return

	if _time_alive >= maxf(lifetime, travel_time):
		_detonate()
		return

	if not _armed:
		arm_delay -= delta
		if arm_delay <= 0.0:
			_armed = true
			if sprite != null:
				sprite.modulate = Color(1.0, 0.8, 0.3, 1.0)

	# apply the stored launch velocity, then add gravity so that
	# launches with vertical components remain intact
	velocity = _launch_velocity
	velocity += get_gravity() * delta * 0.5
	# clamp downward speed to fall_velocity to avoid excessive fast fall
	velocity.y = minf(velocity.y, fall_velocity)
	move_and_slide()


func _on_body_entered(body: Node2D) -> void:
	if _has_detonated or body == null:
		return

	if body.is_in_group("player"):
		if _armed and body.has_method("take_damage"):
			body.take_damage(damage, global_position, true, false)
		_detonate()
		return

	if not _armed:
		return

	if launched_by_portal and body.is_in_group("enemies"):
		if body.has_method("take_bullet_damage"):
			body.take_bullet_damage(damage, global_position)
		elif body.has_method("take_damage"):
			body.take_damage(damage, global_position, true, false)
		_detonate()


func _detonate() -> void:
	if _has_detonated:
		return
	_has_detonated = true
	velocity = Vector2.ZERO
	# hide the mine's visible sprite immediately so it doesn't linger
	if sprite != null:
		sprite.visible = false
		sprite.stop()
	# disable detection and any collision shapes to prevent further interactions
	if detection_area != null:
		detection_area.monitoring = false
	for child in get_children():
		if child is CollisionShape2D:
			child.disabled = true

	var sprite_frames: SpriteFrames = SpriteFrames.new()
	sprite_frames.add_animation("explosion")
	for texture in explosion_frames:
		sprite_frames.add_frame("explosion", texture, 1.0)
	sprite_frames.set_animation_loop("explosion", false)

	var explosion: AnimatedSprite2D = AnimatedSprite2D.new()
	explosion.sprite_frames = sprite_frames
	explosion.animation = "explosion"
	explosion.centered = true
	explosion.offset = Vector2.ZERO
	explosion.scale = Vector2(1.6, 1.6)
	explosion.global_position = global_position + Vector2(0.0, -18.0)
	explosion.z_index = 100
	get_tree().current_scene.add_child(explosion)
	explosion.play()

	var explosion_sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	explosion_sound.stream = preload("res://asssets/sounds/FREE FPS SFX Pack/Rocket_Explosion-001.wav")
	explosion_sound.global_position = global_position
	explosion_sound.bus = &"Master"
	get_tree().current_scene.add_child(explosion_sound)
	explosion_sound.play()

	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(explosion):
		explosion.queue_free()
	if is_instance_valid(explosion_sound):
		explosion_sound.queue_free()
	queue_free()
