extends AudioStreamPlayer

@export var tracks: Array[AudioStream] = []
@export var autoplay_on_ready: bool = true
@export var loop_playlist: bool = true
@export var shuffle_enabled: bool = true
@export var music_bus_name: String = "Music"

var _current_track_index: int = -1
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_music_bus_exists()
	bus = music_bus_name
	_rng.randomize()
	finished.connect(_on_track_finished)

	if tracks.is_empty() and stream:
		tracks = [stream]

	if autoplay_on_ready and not tracks.is_empty():
		if _current_track_index < 0:
			_current_track_index = _pick_start_index()
		_play_current()

func _ensure_music_bus_exists() -> void:
	var index := AudioServer.get_bus_index(music_bus_name)
	if index != -1:
		return
	var new_index := AudioServer.get_bus_count()
	AudioServer.add_bus(new_index)
	AudioServer.set_bus_name(new_index, music_bus_name)
	if AudioServer.get_bus_index("Master") != -1:
		AudioServer.set_bus_send(new_index, "Master")

func set_playlist(new_tracks: Array[AudioStream], start_immediately: bool = true) -> void:
	tracks = new_tracks.duplicate()
	_current_track_index = _pick_start_index()
	if start_immediately and not tracks.is_empty():
		_play_current()

func set_shuffle(enabled: bool) -> void:
	shuffle_enabled = enabled

func play_next() -> void:
	if tracks.is_empty():
		return
	_current_track_index = _pick_next_index()
	if _current_track_index < 0:
		stop()
		return
	_play_current()

func play_previous() -> void:
	if tracks.is_empty():
		return

	if shuffle_enabled:
		_current_track_index = _rng.randi_range(0, tracks.size() - 1)
	else:
		_current_track_index -= 1
		if _current_track_index < 0:
			_current_track_index = tracks.size() - 1 if loop_playlist else 0

	_play_current()

func play_track(index: int) -> void:
	if index < 0 or index >= tracks.size():
		return
	_current_track_index = index
	_play_current()

func get_current_track_index() -> int:
	return _current_track_index

func _on_track_finished() -> void:
	play_next()

func _play_current() -> void:
	if _current_track_index < 0 or _current_track_index >= tracks.size():
		return

	stream = tracks[_current_track_index]
	if stream:
		play()

func _pick_start_index() -> int:
	if tracks.is_empty():
		return -1
	if shuffle_enabled:
		return _rng.randi_range(0, tracks.size() - 1)
	return 0

func _pick_next_index() -> int:
	if tracks.is_empty():
		return -1

	if shuffle_enabled:
		if tracks.size() == 1:
			return 0
		var candidate_index := _current_track_index
		while candidate_index == _current_track_index:
			candidate_index = _rng.randi_range(0, tracks.size() - 1)
		return candidate_index

	var next_index := _current_track_index + 1
	if next_index >= tracks.size():
		if loop_playlist:
			return 0
		return -1
	return next_index
