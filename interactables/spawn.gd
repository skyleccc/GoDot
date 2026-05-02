extends Node2D

signal spawn_reached(spawn_global_position: Vector2)

@onready var area: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _is_activated: bool = false
var _is_transitioning: bool = false

func _ready() -> void:
	add_to_group("spawn_points")
	area.body_entered.connect(_on_body_entered)
	_play_idle_animation()

func _on_body_entered(body: Node) -> void:
	if not _is_player(body):
		return

	if body.has_method("set_spawn_point"):
		body.set_spawn_point(global_position)

	activate()
	spawn_reached.emit(global_position)

func activate(force: bool = false) -> void:
	if _is_activated and not force:
		return
	if _is_transitioning:
		return

	_is_activated = true
	_is_transitioning = true
	if animation_player.has_animation("Activate"):
		animation_player.play("Activate")
		var activate_length: float = animation_player.current_animation_length
		if activate_length > 0.0:
			await get_tree().create_timer(activate_length).timeout

	_play_idle_animation()
	_is_transitioning = false

func _play_idle_animation() -> void:
	if animation_player.has_animation("Activated"):
		animation_player.play("Activated")

func _is_player(body: Node) -> bool:
	return body.is_in_group("player") or body.has_method("set_spawn_point")
