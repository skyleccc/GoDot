extends Control

signal back_requested

const SETTINGS_PATH: String = "user://settings.cfg"

@export var master_bus_name: String = "Master"
@export var effects_bus_name: String = "SFX"
@export var dialogue_bus_name: String = "Dialogue"
@export var music_bus_name: String = "Music"
@export var available_resolutions: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]
@export var window_modes: Array[String] = ["Windowed", "Fullscreen", "Borderless"]

@onready var window_mode_option: OptionButton = $SettingsPanel/VBoxContainer/TabContainer/DisplayTab/DisplayVBox/WindowModeRow/WindowModeOption
@onready var resolution_option: OptionButton = $SettingsPanel/VBoxContainer/TabContainer/DisplayTab/DisplayVBox/ResolutionRow/ResolutionOption
@onready var apply_display_button: Button = $SettingsPanel/VBoxContainer/TabContainer/DisplayTab/DisplayVBox/ApplyDisplayButton
@onready var master_slider: HSlider = $SettingsPanel/VBoxContainer/TabContainer/AudioTab/AudioVBox/MasterRow/MasterSlider
@onready var effects_slider: HSlider = $SettingsPanel/VBoxContainer/TabContainer/AudioTab/AudioVBox/EffectsRow/EffectsSlider
@onready var music_slider: HSlider = $SettingsPanel/VBoxContainer/TabContainer/AudioTab/AudioVBox/MusicRow/MusicSlider
@onready var dialogue_slider: HSlider = $SettingsPanel/VBoxContainer/TabContainer/AudioTab/AudioVBox/DialogueRow/DialogueSlider
@onready var playlist_container: VBoxContainer = $SettingsPanel/VBoxContainer/TabContainer/PlaylistTab/ScrollContainer/PlaylistContainer
@onready var apply_button: Button = $SettingsPanel/VBoxContainer/ApplyButton
@onready var back_button: Button = $SettingsPanel/VBoxContainer/BackButton

var _music_manager: AudioStreamPlayer = null
var _all_tracks: Array[AudioStream] = []
var _resolution_values: Array[Vector2i] = []
var _track_checkboxes: Array[CheckBox] = []
var _track_indices: Array[int] = []
var _pending_playlist_paths: Array[String] = []
var _suppress_save: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_populate_window_modes()
	_populate_resolutions()
	_suppress_save = true
	_load_settings()
	_sync_display_ui()
	_sync_audio_ui()
	_suppress_save = false
	apply_button.pressed.connect(_on_apply_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	apply_display_button.pressed.connect(_on_apply_display_button_pressed)
	window_mode_option.item_selected.connect(_on_window_mode_selected)
	master_slider.value_changed.connect(_on_master_slider_changed)
	effects_slider.value_changed.connect(_on_effects_slider_changed)
	music_slider.value_changed.connect(_on_music_slider_changed)
	dialogue_slider.value_changed.connect(_on_dialogue_slider_changed)
	visibility_changed.connect(_on_visibility_changed)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Escape/Pause input is intentionally ignored while settings is open.

func set_music_manager(manager: AudioStreamPlayer) -> void:
	_music_manager = manager
	if _all_tracks.is_empty() and _music_manager != null:
		var raw_tracks: Variant = _music_manager.get("tracks")
		if raw_tracks is Array:
			_all_tracks = (raw_tracks as Array).duplicate()
	_ensure_bus_exists(music_bus_name, master_bus_name)
	if _music_manager != null:
		_music_manager.bus = music_bus_name
	_build_playlist()
	_sync_audio_ui()

func _on_back_button_pressed() -> void:
	back_requested.emit()

func _on_apply_button_pressed() -> void:
	var was_suppress := _suppress_save
	_suppress_save = true
	_apply_display_settings()
	_apply_playlist_selection()
	_suppress_save = was_suppress
	_save_settings()
	back_requested.emit()

func _on_visibility_changed() -> void:
	if visible:
		_sync_display_ui()
		_sync_audio_ui()
		_build_playlist()
		back_button.grab_focus()

func _populate_window_modes() -> void:
	window_mode_option.clear()
	for mode_name in window_modes:
		window_mode_option.add_item(mode_name)

func _populate_resolutions() -> void:
	resolution_option.clear()
	_resolution_values.clear()
	for res in available_resolutions:
		_add_resolution_option(res, "%dx%d" % [res.x, res.y])

	var current_size: Vector2i = DisplayServer.window_get_size()
	if not _resolution_values.has(current_size):
		_add_resolution_option(current_size, "%dx%d (Current)" % [current_size.x, current_size.y])

func _add_resolution_option(res: Vector2i, label: String) -> void:
	_resolution_values.append(res)
	resolution_option.add_item(label)

func _sync_display_ui() -> void:
	var mode_label := "Windowed"
	var current_mode: int = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		mode_label = "Fullscreen"
	elif current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		mode_label = "Borderless"
	elif current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
		if borderless:
			mode_label = "Borderless"

	var mode_index := window_modes.find(mode_label)
	if mode_index < 0:
		mode_index = 0
	window_mode_option.select(mode_index)
	_update_resolution_enabled()

	var current_size: Vector2i = DisplayServer.window_get_size()
	_select_resolution_for_size(current_size)

func _select_resolution_for_size(window_size: Vector2i) -> void:
	if not _resolution_values.has(window_size):
		_add_resolution_option(window_size, "%dx%d (Saved)" % [window_size.x, window_size.y])
	var index := _resolution_values.find(window_size)
	if index >= 0:
		resolution_option.select(index)
	else:
		resolution_option.select(0)

func _update_resolution_enabled() -> void:
	var mode_text := window_mode_option.get_item_text(window_mode_option.selected)
	resolution_option.disabled = mode_text == "Fullscreen"

func _on_window_mode_selected(_index: int) -> void:
	_update_resolution_enabled()

func _on_apply_display_button_pressed() -> void:
	_apply_display_settings()

func _apply_display_settings() -> void:
	var mode_text := window_mode_option.get_item_text(window_mode_option.selected)
	if mode_text == "Windowed":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		_apply_resolution_selection()
	elif mode_text == "Fullscreen":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	elif mode_text == "Borderless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_apply_resolution_selection()
	_maybe_save_settings()

func _apply_resolution_selection() -> void:
	if resolution_option.disabled:
		return
	var index := resolution_option.selected
	if index < 0 or index >= _resolution_values.size():
		return
	DisplayServer.window_set_size(_resolution_values[index])

func _sync_audio_ui() -> void:
	_ensure_bus_exists(effects_bus_name, master_bus_name)
	_ensure_bus_exists(dialogue_bus_name, master_bus_name)
	master_slider.value = _db_to_percent(_get_bus_volume_db(master_bus_name))
	effects_slider.value = _db_to_percent(_get_bus_volume_db(effects_bus_name))
	dialogue_slider.value = _db_to_percent(_get_bus_volume_db(dialogue_bus_name))
	music_slider.value = _db_to_percent(_get_music_volume_db())

func _get_bus_volume_db(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return 0.0
	return AudioServer.get_bus_volume_db(index)

func _get_music_volume_db() -> float:
	var bus_index := AudioServer.get_bus_index(music_bus_name)
	if bus_index != -1:
		return AudioServer.get_bus_volume_db(bus_index)
	if _music_manager != null:
		return _music_manager.volume_db
	return 0.0

func _on_master_slider_changed(value: float) -> void:
	_apply_bus_volume(master_bus_name, value)
	_maybe_save_settings()

func _on_effects_slider_changed(value: float) -> void:
	var index := _ensure_bus_exists(effects_bus_name, master_bus_name)
	if index == -1:
		return
	_apply_bus_volume(effects_bus_name, value)
	_maybe_save_settings()

func _on_dialogue_slider_changed(value: float) -> void:
	var index := _ensure_bus_exists(dialogue_bus_name, master_bus_name)
	if index == -1:
		return
	_apply_bus_volume(dialogue_bus_name, value)
	_maybe_save_settings()

func _on_music_slider_changed(value: float) -> void:
	var index := _ensure_bus_exists(music_bus_name, master_bus_name)
	if index != -1:
		_apply_bus_volume(music_bus_name, value)
	if _music_manager != null:
		_music_manager.bus = music_bus_name
		_music_manager.volume_db = _percent_to_db(value)
	_maybe_save_settings()

func _apply_bus_volume(bus_name: String, percent: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, _percent_to_db(percent))

func _ensure_bus_exists(bus_name: String, send_to: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index != -1:
		return index
	var new_index := AudioServer.get_bus_count()
	AudioServer.add_bus(new_index)
	AudioServer.set_bus_name(new_index, bus_name)
	if AudioServer.get_bus_index(send_to) != -1:
		AudioServer.set_bus_send(new_index, send_to)
	return new_index

func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)

func _db_to_percent(db: float) -> float:
	if db <= -80.0:
		return 0.0
	return clamp(db_to_linear(db) * 100.0, 0.0, 100.0)

func _build_playlist() -> void:
	for child in playlist_container.get_children():
		child.queue_free()
	_track_checkboxes.clear()
	_track_indices.clear()

	if _music_manager == null:
		return
	if _all_tracks.is_empty():
		var raw_tracks: Variant = _music_manager.get("tracks")
		if raw_tracks is Array:
			_all_tracks = (raw_tracks as Array).duplicate()
	if _all_tracks.is_empty():
		return

	var current_tracks: Array = []
	var raw_current: Variant = _music_manager.get("tracks")
	if raw_current is Array:
		current_tracks = raw_current as Array

	for i in range(_all_tracks.size()):
		var track := _all_tracks[i]
		if not (track is AudioStream):
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)

		var checkbox := CheckBox.new()
		checkbox.text = _format_track_name(track)
		checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _pending_playlist_paths.is_empty():
			checkbox.button_pressed = current_tracks.has(track)
		else:
			checkbox.button_pressed = _pending_playlist_paths.has(track.resource_path)
		checkbox.toggled.connect(_on_track_toggled)

		var play_button := Button.new()
		play_button.text = "Play"
		play_button.custom_minimum_size = Vector2(80, 36)
		play_button.pressed.connect(_on_track_play_pressed.bind(i))

		row.add_child(checkbox)
		row.add_child(play_button)
		playlist_container.add_child(row)
		_track_checkboxes.append(checkbox)
		_track_indices.append(i)

	if not _pending_playlist_paths.is_empty():
		_suppress_save = true
		_apply_playlist_selection()
		_suppress_save = false
		_pending_playlist_paths.clear()

func _format_track_name(track: AudioStream) -> String:
	var path := track.resource_path
	if path.is_empty():
		return "Track"
	return path.get_file().get_basename()

func _collect_selected_tracks() -> Array[AudioStream]:
	var selected: Array[AudioStream] = []
	for i in range(_track_checkboxes.size()):
		if not _track_checkboxes[i].button_pressed:
			continue
		var track_index := _track_indices[i]
		if track_index < 0 or track_index >= _all_tracks.size():
			continue
		var track := _all_tracks[track_index]
		if track is AudioStream:
			selected.append(track)
	return selected

func _set_checkboxes_from_tracks(selected: Array[AudioStream]) -> void:
	for i in range(_track_checkboxes.size()):
		var track_index := _track_indices[i]
		if track_index < 0 or track_index >= _all_tracks.size():
			continue
		var track := _all_tracks[track_index]
		if not (track is AudioStream):
			continue
		var should_be_pressed := selected.has(track)
		if _track_checkboxes[i].button_pressed != should_be_pressed:
			_track_checkboxes[i].set_pressed_no_signal(should_be_pressed)

func _on_track_toggled(_pressed: bool) -> void:
	_apply_playlist_selection()

func _on_track_play_pressed(track_index: int) -> void:
	if _music_manager == null:
		return
	if track_index < 0 or track_index >= _all_tracks.size():
		return
	var track := _all_tracks[track_index]
	if not (track is AudioStream):
		return

	var selected_tracks := _collect_selected_tracks()
	if not selected_tracks.has(track):
		selected_tracks.append(track)

	if _music_manager.has_method("set_playlist"):
		_music_manager.call("set_playlist", selected_tracks, false)
	if _music_manager.has_method("play_track"):
		var play_index := selected_tracks.find(track)
		if play_index >= 0:
			_music_manager.call("play_track", play_index)

	_set_checkboxes_from_tracks(selected_tracks)
	_maybe_save_settings()

func _apply_playlist_selection() -> void:
	if _music_manager == null:
		return
	var selected_tracks := _collect_selected_tracks()

	if _music_manager.has_method("set_playlist"):
		if selected_tracks.is_empty():
			if _all_tracks.is_empty():
				_music_manager.call("set_playlist", [], false)
				_music_manager.stop()
			else:
				selected_tracks = _all_tracks.duplicate()
				_music_manager.call("set_playlist", selected_tracks, true)
				_set_checkboxes_from_tracks(selected_tracks)
		else:
			_music_manager.call("set_playlist", selected_tracks, true)
	_maybe_save_settings()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	var mode_text := String(config.get_value("display", "window_mode", "Windowed"))
	var resolution_value: Variant = config.get_value("display", "resolution", Vector2i(1920, 1080))
	var resolution := Vector2i(1920, 1080)
	if resolution_value is Vector2i:
		resolution = resolution_value as Vector2i
	elif resolution_value is Vector2:
		var res_vec := resolution_value as Vector2
		resolution = Vector2i(int(res_vec.x), int(res_vec.y))
	var mode_index := window_modes.find(mode_text)
	if mode_index < 0:
		mode_index = 0
	window_mode_option.select(mode_index)
	_update_resolution_enabled()
	_select_resolution_for_size(resolution)
	_apply_display_settings()

	var master_value := float(config.get_value("audio", "master", 100.0))
	var effects_value := float(config.get_value("audio", "effects", 100.0))
	var dialogue_value := float(config.get_value("audio", "dialogue", 100.0))
	var music_value := float(config.get_value("audio", "music", 100.0))
	master_slider.value = master_value
	effects_slider.value = effects_value
	dialogue_slider.value = dialogue_value
	music_slider.value = music_value
	_apply_bus_volume(master_bus_name, master_value)
	_ensure_bus_exists(effects_bus_name, master_bus_name)
	_apply_bus_volume(effects_bus_name, effects_value)
	_ensure_bus_exists(dialogue_bus_name, master_bus_name)
	_apply_bus_volume(dialogue_bus_name, dialogue_value)
	var music_index := _ensure_bus_exists(music_bus_name, master_bus_name)
	if music_index != -1:
		_apply_bus_volume(music_bus_name, music_value)
	if _music_manager != null:
		_music_manager.bus = music_bus_name
		_music_manager.volume_db = _percent_to_db(music_value)

	var playlist_value: Variant = config.get_value("playlist", "tracks", [])
	_pending_playlist_paths.clear()
	if playlist_value is Array:
		for path_value in playlist_value as Array:
			if path_value is String:
				_pending_playlist_paths.append(path_value)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "window_mode", window_mode_option.get_item_text(window_mode_option.selected))
	config.set_value("display", "resolution", DisplayServer.window_get_size())
	config.set_value("audio", "master", master_slider.value)
	config.set_value("audio", "effects", effects_slider.value)
	config.set_value("audio", "dialogue", dialogue_slider.value)
	config.set_value("audio", "music", music_slider.value)

	var selected_paths: Array[String] = []
	for track in _collect_selected_tracks():
		var track_path := track.resource_path
		if not track_path.is_empty():
			selected_paths.append(track_path)
	config.set_value("playlist", "tracks", selected_paths)
	config.save(SETTINGS_PATH)

func _maybe_save_settings() -> void:
	if _suppress_save:
		return
	_save_settings()
