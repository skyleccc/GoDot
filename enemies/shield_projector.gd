extends StaticBody2D

@export_group("Crystal Stats")
@export var max_hp: int = 50
@export var damage_taken_per_hit: int = 15

var current_hp: int = 0
var _is_alive: bool = true

signal crystal_destroyed

func _ready() -> void:
	add_to_group("shield_projectors")
	current_hp = max_hp
	
	# Setup projectile detection
	_update_visual()

func _physics_process(_delta: float) -> void:
	pass  # StaticBody2D doesn't move

	

func take_damage(amount: int, hit_source_pos: Vector2 = Vector2(), knockback: bool = true, apply_slow: bool = false) -> void:
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
	
	# Visual feedback - fade out and remove
	if has_node("Decor3"):
		$Decor3.modulate = Color.GRAY
	if has_node("Decor4"):
		$Decor4.modulate = Color.GRAY
	
	print("Crystal destroyed at ", global_position)
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
