extends Node2D

## Saw hazard — moves back and forth between its start position and EndPoint.
## Stationary if EndPoint ≈ start position (just spins forever).
## Activate animation loops continuously. Pauses movement at each endpoint.
##
## Damages and knocks back the player on contact (Area2D on Hazards layer).
## Not on Walls/PortalSurfaces layers, so portals cannot be placed on it.

@export var damage: int = 15
@export var move_speed: float = 80.0          ## pixels per second
@export var pause_at_ends: float = 0.3        ## brief pause at each endpoint
@export var stationary_threshold: float = 4.0 ## distance below which saw stays still

var _start_pos: Vector2
var _end_pos: Vector2
var _is_moving: bool = false
var _tween: Tween = null
var _going_to_end: bool = true

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $Area2D
@onready var end_point: Marker2D = $EndPoint


func _ready() -> void:
	# --- Collision setup: Hazards layer, detect only Player ---
	area.collision_layer = 8   # Hazards
	area.collision_mask = 1    # Player
	area.monitoring = true
	area.monitorable = false
	area.body_entered.connect(_on_body_entered)

	# --- Animation ---
	anim_sprite.play(&"Activate")

	# --- Movement ---
	_start_pos = global_position
	_end_pos = end_point.global_position

	if _start_pos.distance_to(_end_pos) > stationary_threshold:
		_is_moving = true
		_travel_to_next()


# ── Movement ─────────────────────────────────────────────────────────────────

func _travel_to_next() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	var target := _end_pos if _going_to_end else _start_pos
	var distance := global_position.distance_to(target)
	var duration := distance / move_speed

	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "global_position", target, duration)
	_tween.tween_interval(pause_at_ends)
	_tween.tween_callback(_on_reached_end)

	_going_to_end = not _going_to_end


func _on_reached_end() -> void:
	_travel_to_next()


## Damage + knockback any player that touches the saw.
func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position)
