extends Area2D

## Spike trap — cycles: Hidden → Activate → Activated → Hidden.
## Only damages players via take_spike_damage (returns them to last safe ground position).
## Has a StaticBody2D child on the Walls layer so portals can be placed on it.
##
## Can run standalone or be driven by a SpikeGroup parent (sync / stagger).

signal activate_animation_finished  ## Emitted when the Activate animation ends (used by SpikeGroup).

enum SpikeState { HIDDEN, ACTIVATING, ACTIVATED }

@export var damage: int = 10
@export var hidden_duration: float = 2.0
@export var activated_duration: float = 1.5

var _state: SpikeState = SpikeState.HIDDEN
var _timer: float = 0.0
var _grouped: bool = false  ## Set true by SpikeGroup — disables self-managed timing.

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Only detect player bodies; not detectable by player's HurtBox
	collision_layer = 8    # Hazards
	collision_mask = 1     # Player
	monitoring = true
	monitorable = false

	body_entered.connect(_on_body_entered)
	anim_player.animation_finished.connect(_on_animation_finished)

	_enter_hidden()


func _process(delta: float) -> void:
	if _grouped:
		return  # SpikeGroup handles timing
	match _state:
		SpikeState.HIDDEN:
			_timer -= delta
			if _timer <= 0.0:
				_enter_activating()
		SpikeState.ACTIVATED:
			_timer -= delta
			if _timer <= 0.0:
				_enter_hidden()


# --- Public API for SpikeGroup control ---

func group_enter_hidden() -> void:
	_enter_hidden()

func group_enter_activating() -> void:
	_enter_activating()


# --- Internal state transitions ---

func _enter_hidden() -> void:
	_state = SpikeState.HIDDEN
	_timer = hidden_duration
	collision_shape.disabled = true
	anim_player.play("Hidden")


func _enter_activating() -> void:
	_state = SpikeState.ACTIVATING
	anim_player.play("Activate")


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"Activate":
		_enter_activated()
		if _grouped:
			activate_animation_finished.emit()


func _enter_activated() -> void:
	_state = SpikeState.ACTIVATED
	_timer = activated_duration
	collision_shape.disabled = false
	anim_player.play("Activated")
	# Damage any player already overlapping
	for body in get_overlapping_bodies():
		_try_damage(body)


func _on_body_entered(body: Node2D) -> void:
	if _state == SpikeState.ACTIVATED:
		_try_damage(body)


func _try_damage(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position, false)
