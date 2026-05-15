extends Area2D

@export var radius: float = 60.0
@export var telegraph_time: float = 1.0
@export var warning_after_telegraph: float = 0.75

@export var damage: int = 25

var detonation_explosion_frames: Array[Texture2D] = [
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f1.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f2.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f3.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f4.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f5.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f6.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f7.png"),
	preload("res://asssets/Explosions/explosion pack 1/Explosions pack/explosion-1-f/Sprites/explosion-f8.png")
]

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var fill: Polygon2D = $Fill
@onready var outline: Line2D = $Outline

var _follow_node: Node2D = null
var _offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = false
	monitorable = true

	var circle_shape := collision_shape.shape as CircleShape2D
	if circle_shape:
		circle_shape.radius = radius

	_build_circle_visuals()
	_detonate_after_delay()

	set_process(true)

func set_follow_node(node: Node2D, offset: Vector2 = Vector2.ZERO) -> void:
	_follow_node = node
	_offset = offset
	if _follow_node != null:
		global_position = _follow_node.global_position + _offset

func _process(_delta: float) -> void:
	if _follow_node != null and collision_layer == 0:
		if is_instance_valid(_follow_node):
			global_position = _follow_node.global_position + _offset
		else:
			_follow_node = null

func _build_circle_visuals() -> void:
	var points := PackedVector2Array()
	var segments := 48
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	fill.polygon = points
	fill.color = Color(1.0, 0.75, 0.15, 0.35)

	outline.points = points
	outline.width = 3.0
	outline.closed = true
	outline.default_color = Color(1.0, 0.9, 0.35, 0.9)

func _detonate_after_delay() -> void:
	await get_tree().create_timer(telegraph_time).timeout
	fill.visible = false
	outline.visible = false
	# Enable monitoring just long enough to capture overlapping bodies,
	# spawn the explosion, apply a single instant of damage, then disable monitoring
	collision_layer = 8
	monitoring = true
	await get_tree().process_frame
	_spawn_detonation_explosion(global_position)

	for body in get_overlapping_bodies():
		if body != null and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage, global_position, true, false)

	# Prevent any lingering damage after the instant
	monitoring = false
	collision_layer = 0

	queue_free()

func _spawn_detonation_explosion(spawn_position: Vector2) -> void:
	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("explosion")
	for texture in detonation_explosion_frames:
		sprite_frames.add_frame("explosion", texture, 1.0)
	sprite_frames.set_animation_loop("explosion", false)

	var explosion := AnimatedSprite2D.new()
	explosion.sprite_frames = sprite_frames
	explosion.animation = "explosion"
	explosion.centered = true
	explosion.scale = Vector2(2.0, 2.0)
	explosion.global_position = spawn_position
	explosion.z_index = 100
	get_tree().current_scene.add_child(explosion)
	explosion.animation_finished.connect(explosion.queue_free)
	explosion.play()
	
	# Play explosion sound
	var explosion_sound := AudioStreamPlayer2D.new()
	explosion_sound.stream = preload("res://asssets/sounds/FREE FPS SFX Pack/Rocket_Explosion-002.wav")
	explosion_sound.global_position = spawn_position
	explosion_sound.bus = &"Master"
	get_tree().current_scene.add_child(explosion_sound)
	explosion_sound.play()
	await explosion_sound.finished
	explosion_sound.queue_free()
