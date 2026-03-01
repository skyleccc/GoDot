extends Node2D

## Groups child Spike nodes and controls their timing centrally.
##
## Usage:
##   1. Add this script to a Node2D.
##   2. Instance multiple Spike scenes as children (order = activation order).
##   3. Set hidden_duration, activated_duration, and stagger_delay on this node.
##      - stagger_delay = 0  → all spikes activate / deactivate at the same time.
##      - stagger_delay > 0  → spikes activate one-by-one in child order with
##        the given delay between each.  They all hide simultaneously.
##
## The per-spike durations on each child are ignored while grouped.

enum GroupState { HIDDEN, ACTIVATING, ACTIVATED }

@export var hidden_duration: float = 2.0
@export var activated_duration: float = 1.5
## Seconds between each spike's activation in wave mode.  0 = all sync.
@export var stagger_delay: float = 0.0

var _state: GroupState = GroupState.HIDDEN
var _timer: float = 0.0
var _spikes: Array[Area2D] = []
var _activations_pending: int = 0
var _stagger_tween: Tween = null


func _ready() -> void:
	for child in get_children():
		if child is Area2D and child.has_method("group_enter_hidden"):
			child._grouped = true
			_spikes.append(child)
			child.activate_animation_finished.connect(_on_spike_activate_finished)

	if _spikes.is_empty():
		push_warning("SpikeGroup '%s' found no Spike children — are they direct children?" % name)
		return

	print("SpikeGroup '%s': %d spikes, stagger_delay=%.2f" % [name, _spikes.size(), stagger_delay])
	_enter_hidden()


func _process(delta: float) -> void:
	if _spikes.is_empty():
		return

	match _state:
		GroupState.HIDDEN:
			_timer -= delta
			if _timer <= 0.0:
				_start_activating()
		GroupState.ACTIVATED:
			_timer -= delta
			if _timer <= 0.0:
				_enter_hidden()


# ---------------------------------------------------------------------------

func _enter_hidden() -> void:
	_state = GroupState.HIDDEN
	_timer = hidden_duration
	# Cancel any in-flight stagger tween
	if _stagger_tween and _stagger_tween.is_valid():
		_stagger_tween.kill()
	for spike in _spikes:
		spike.group_enter_hidden()


func _start_activating() -> void:
	_state = GroupState.ACTIVATING
	_activations_pending = _spikes.size()

	if stagger_delay <= 0.0 or _spikes.size() <= 1:
		# Sync — activate all at once
		for spike in _spikes:
			spike.group_enter_activating()
	else:
		# Wave — first spike immediately, rest via Tween
		_spikes[0].group_enter_activating()
		_stagger_tween = create_tween()
		for i in range(1, _spikes.size()):
			_stagger_tween.tween_interval(stagger_delay)
			_stagger_tween.tween_callback(_spikes[i].group_enter_activating)


func _on_spike_activate_finished() -> void:
	_activations_pending -= 1
	if _activations_pending <= 0:
		_state = GroupState.ACTIVATED
		_timer = activated_duration
