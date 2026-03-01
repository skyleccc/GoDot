extends Node2D

## Laser hazard that deals continuous damage to the player while they overlap.

@export var damage: int = 20
@export var damage_interval: float = 0.5  ## seconds between each damage tick

var _damage_timer: float = 0.0
var _targets_in_area: Array[Node2D] = []

@onready var area: Area2D = $Area2D


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _targets_in_area.is_empty():
		return
	_damage_timer -= delta
	if _damage_timer <= 0.0:
		_damage_timer = damage_interval
		for target in _targets_in_area:
			if target.has_method("take_damage"):
				target.take_damage(damage, global_position)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		_targets_in_area.append(body)
		# Deal damage immediately on contact
		body.take_damage(damage, global_position)
		_damage_timer = damage_interval


func _on_body_exited(body: Node2D) -> void:
	_targets_in_area.erase(body)
