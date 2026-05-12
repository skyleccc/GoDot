extends StaticBody2D

@export_group("Crystal Stats")
@export var max_hp: int = 50
@export var damage_taken_per_hit: int = 15

var current_hp: int = 0
var _is_alive: bool = true

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

signal crystal_destroyed

# Explosion animation frames
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
	add_to_group("shield_projectors")
	current_hp = max_hp
	
	# Setup projectile detection
	_update_visual()

func _physics_process(_delta: float) -> void:
	pass  # StaticBody2D doesn't move

	

func take_damage(amount: int, hit_source_pos: Vector2 = Vector2(), _knockback: bool = true, _apply_slow: bool = false) -> void:
	if not _is_alive:
		return
	if hit_source_pos == Vector2():
		hit_source_pos = global_position

	current_hp -= amount
	_update_visual()
	print("Crystal hit! HP: ", current_hp, " / ", max_hp)

	if current_hp <= 0:
		_destroy()

func _destroy() -> void:
	_is_alive = false
	crystal_destroyed.emit()
	
	# Hide the crystal visuals
	if has_node("Decor3"):
		$Decor3.visible = false
	if has_node("Decor4"):
		$Decor4.visible = false
	
	# Create explosion animation
	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("explosion")
	for texture in explosion_frames:
		sprite_frames.add_frame("explosion", texture, 1.0)
	# Set animation to not loop
	sprite_frames.set_animation_loop("explosion", false)
	
	var explosion := AnimatedSprite2D.new()
	explosion.sprite_frames = sprite_frames
	explosion.animation = "explosion"
	explosion.centered = true
	explosion.offset = Vector2.ZERO
	explosion.scale = Vector2(1.6, 1.6)
	# Lift the larger explosion slightly so it does not clip into the floor.
	explosion.global_position = collision_shape.global_position + Vector2(0.0, -18.0)
	explosion.z_index = 100
	get_tree().current_scene.add_child(explosion)
	explosion.play()
	
	print("Crystal destroyed at ", collision_shape.global_position)
	
	# Wait for explosion animation to finish before removing
	await explosion.animation_finished
	explosion.queue_free()
	queue_free()

func _update_visual() -> void:
	"""Update crystal color based on health."""
	if not _is_alive:
		return
	
	var health_ratio := float(current_hp) / float(max_hp)
	
	# Fade from green to yellow to red as health decreases
	var color: Color
	if health_ratio > 0.66:
		color = Color(0.2, 1.0, 0.2, 1.0)  # Green
	elif health_ratio > 0.33:
		color = Color(1.0, 0.85, 0.2, 1.0)  # Yellow
	else:
		color = Color(1.0, 0.2, 0.2, 1.0)  # Red
	
	if has_node("Decor3"):
		$Decor3.modulate = color
	if has_node("Decor4"):
		$Decor4.modulate = color

func is_alive() -> bool:
	return _is_alive
