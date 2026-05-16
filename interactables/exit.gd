extends Node2D

signal level_completed

@onready var area: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

@export var proximity_delay_seconds: float = 1.5
@export var completion_dialogue_id: String = ""
@export var start_disabled: bool = false  ## If true, exit starts disabled (for boss levels)

var _is_completed: bool = false
var _is_processing: bool = false
var _player_in_range: bool = false


func _ready() -> void:
	add_to_group("level_exits")
	
	# Disable exit if it should start disabled (boss levels)
	if start_disabled:
		area.monitoring = false
		visible = false
	
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	
	if animation_player.has_animation("Idle"):
		animation_player.play("Idle")


func _on_body_entered(body: Node) -> void:
	if _is_completed or _is_processing:
		return
	if not _is_player(body):
		return
	
	_player_in_range = true
	_begin_completion_sequence(body)


func _on_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	_player_in_range = false


func _begin_completion_sequence(triggering_player: Node) -> void:
	_is_processing = true
	
	if proximity_delay_seconds > 0.0:
		await get_tree().create_timer(proximity_delay_seconds).timeout
	
	if _is_completed or not _player_in_range:
		_is_processing = false
		if animation_player.has_animation("Idle"):
			animation_player.play("Idle")
		return
	
	_is_completed = true
	
	if animation_player.has_animation("Activate"):
		animation_player.play("Activate")
		var activate_length: float = animation_player.current_animation_length
		if activate_length > 0.0:
			var hide_delay: float = minf(0.2, activate_length)
			if hide_delay > 0.0:
				await get_tree().create_timer(hide_delay).timeout
			if is_instance_valid(triggering_player) and triggering_player is CanvasItem:
				(triggering_player as CanvasItem).visible = false
			var remaining_time: float = activate_length - hide_delay
			if remaining_time > 0.0:
				await get_tree().create_timer(remaining_time).timeout
	
	await _play_completion_dialogue()
	level_completed.emit()


func _is_player(body: Node) -> bool:
	return body.is_in_group("player") or body.has_method("set_spawn_point")


func _play_completion_dialogue() -> void:
	if completion_dialogue_id.is_empty():
		return
	
	var dialogue_hud := get_tree().get_first_node_in_group("dialogue_hud")
	if dialogue_hud == null:
		return
	if dialogue_hud.has_method("is_dialogue_active") and dialogue_hud.call("is_dialogue_active"):
		return
	if not dialogue_hud.has_method("start_dialogue"):
		return
	
	var started: bool = dialogue_hud.call("start_dialogue", completion_dialogue_id)
	if not started:
		return
	
	while true:
		var finished_id: String = await dialogue_hud.dialogue_finished
		if finished_id == completion_dialogue_id:
			break
