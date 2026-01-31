extends CharacterBody2D

@export var speed: int = 500
var direction = Vector2(0,0)
var screenSize

func _ready() -> void:
	screenSize = get_viewport().get_visible_rect()
	position = (screenSize.size)/2
	direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	
func _process(delta):
	velocity = direction * speed
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		direction = direction.bounce(collision.get_normal())
