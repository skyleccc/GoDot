extends Control

signal dialogue_started(dialogue_id: String)
signal dialogue_finished(dialogue_id: String)

@export var dialogue_folder: String = "res://dialogues"
@export var level_dialogue_pattern: String = "level_%d_intro.json"
@export var auto_start_by_level: bool = true
@export var auto_start_delay_seconds: float = 1.0
@export var continue_hint_text: String = "Click or Space to continue"
@export var pause_gameplay_while_active: bool = true
@export var speaker_name_colors: Dictionary = {
	"ARIA": Color(1.0, 0.6, 0.6),
	"ECHO": Color(0.45, 0.85, 1.0),
	"NARRATOR": Color(0.9, 0.9, 0.9),
	"SABLE": Color(0.85, 0.75, 1.0)
}
@export var speaker_portraits: Dictionary = {
	"ARIA": preload("res://asssets/character/ARIA.png"),
	"ECHO": preload("res://asssets/character/ECHO.png")
}
@export var narrator_name: String = "NARRATOR"
@export var default_speaker_color: Color = Color(1.0, 1.0, 1.0)

@onready var speaker_label: Label = $DialoguePanel/VBoxContainer/HBoxContainer/SpeakerVBox/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $DialoguePanel/VBoxContainer/HBoxContainer/SpeakerVBox/DialogueText
@onready var continue_label: Label = $DialoguePanel/VBoxContainer/ContinueLabel
@onready var speaker_frame: TextureRect = $DialoguePanel/VBoxContainer/HBoxContainer/SpeakerFrame
@onready var speaker_portrait: TextureRect = $DialoguePanel/VBoxContainer/HBoxContainer/SpeakerFrame/SpeakerPortrait

var _lines: Array = []
var _line_index := 0
var _current_dialogue_id := ""
var _level_manager: Node = null
var _played_dialogues: Dictionary = {}
var _paused_by_dialogue: bool = false
var _previous_pause_state: bool = false
var _playing_area: Node = null
var _playing_area_mode_overridden: bool = false
var _previous_playing_area_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _start_token: int = 0
var _dialogue_pending: bool = false

func _ready() -> void:
	add_to_group("dialogue_hud")
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_update_continue_hint()
	_bind_level_manager()

func _process(_delta: float) -> void:
	if _level_manager == null or not is_instance_valid(_level_manager):
		_bind_level_manager()

func _input(event: InputEvent) -> void:
	if _current_dialogue_id.is_empty():
		return
	if not visible:
		if _dialogue_pending and _is_skip_input(event):
			get_viewport().set_input_as_handled()
		return
	if _is_skip_input(event):
		_finish_dialogue()
		get_viewport().set_input_as_handled()
		return
	if _is_advance_input(event):
		_advance_dialogue()
	get_viewport().set_input_as_handled()

func start_dialogue(dialogue_id: String) -> bool:
	var file_name := "%s.json" % dialogue_id
	var dialogue_path := dialogue_folder.path_join(file_name)
	return start_dialogue_from_file(dialogue_path)

func start_dialogue_from_file(dialogue_path: String, show_delay_seconds: float = 0.0) -> bool:
	var data := _load_dialogue_data(dialogue_path)
	if data.is_empty():
		return false

	var lines: Array = data.get("lines", [])
	if typeof(lines) != TYPE_ARRAY or (lines as Array).is_empty():
		push_warning("Dialogue data has no lines: %s" % dialogue_path)
		return false

	_start_token += 1
	var start_token := _start_token
	_current_dialogue_id = str(data.get("id", dialogue_path.get_file().get_basename()))
	_lines = lines
	_line_index = 0
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_dialogue_pending = show_delay_seconds > 0.0

	if show_delay_seconds > 0.0:
		var timer := get_tree().create_timer(show_delay_seconds)
		timer.timeout.connect(func(): _show_dialogue_if_token(start_token))
		return true

	_show_dialogue_if_token(start_token)
	return true

func _bind_level_manager() -> void:
	_level_manager = get_tree().get_first_node_in_group("level_manager")
	if _level_manager == null:
		return

	var level_loaded_callable := Callable(self, "_on_level_loaded")
	if _level_manager.has_signal("level_loaded") and not _level_manager.is_connected("level_loaded", level_loaded_callable):
		_level_manager.connect("level_loaded", level_loaded_callable)

	if _level_manager.has_method("get_current_level_number"):
		_on_level_loaded(_level_manager.get_current_level_number())

func _on_level_loaded(level_number: int) -> void:
	if not auto_start_by_level:
		return

	var file_name := level_dialogue_pattern % level_number
	var dialogue_path := dialogue_folder.path_join(file_name)
	if not ResourceLoader.exists(dialogue_path):
		return
	if _played_dialogues.get(dialogue_path, false):
		return
	if is_dialogue_active():
		return

	if start_dialogue_from_file(dialogue_path, auto_start_delay_seconds):
		_played_dialogues[dialogue_path] = true

func _load_dialogue_data(dialogue_path: String) -> Dictionary:
	if not ResourceLoader.exists(dialogue_path):
		push_warning("Dialogue file not found: %s" % dialogue_path)
		return {}

	var file := FileAccess.open(dialogue_path, FileAccess.READ)
	if file == null:
		push_warning("Unable to open dialogue file: %s" % dialogue_path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Dialogue file must contain a JSON object: %s" % dialogue_path)
		return {}

	return parsed as Dictionary

func _show_current_line() -> void:
	if _line_index < 0 or _line_index >= _lines.size():
		_finish_dialogue()
		return

	var line_data = _lines[_line_index]
	var speaker := ""
	var text := ""

	if line_data is Dictionary:
		speaker = str(line_data.get("speaker", ""))
		text = str(line_data.get("text", ""))
	elif line_data is String:
		text = line_data

	var is_narrator := _is_narrator(speaker)
	if is_narrator:
		speaker_label.visible = false
		speaker_label.text = ""
	else:
		speaker_label.visible = not speaker.is_empty()
		speaker_label.text = speaker
		speaker_label.add_theme_color_override("font_color", _get_speaker_color(speaker))

	_apply_speaker_portrait(speaker, is_narrator)
	_set_dialogue_text(text, is_narrator)
	_update_continue_hint_for_line()

func _advance_dialogue() -> void:
	if _lines.is_empty():
		_finish_dialogue()
		return

	_line_index += 1
	if _line_index >= _lines.size():
		_finish_dialogue()
		return

	_show_current_line()

func _finish_dialogue() -> void:
	var finished_id := _current_dialogue_id
	_start_token += 1
	_lines.clear()
	_line_index = 0
	_current_dialogue_id = ""
	_dialogue_pending = false
	visible = false
	_apply_dialogue_pause(false)
	dialogue_finished.emit(finished_id)

func _update_continue_hint() -> void:
	continue_label.text = continue_hint_text
	continue_label.visible = not continue_hint_text.is_empty()

func _update_continue_hint_for_line() -> void:
	if continue_hint_text.is_empty():
		continue_label.visible = false
		return

	var is_last := _line_index >= _lines.size() - 1
	continue_label.visible = true
	continue_label.text = "Click or Space to finish" if is_last else continue_hint_text

func _is_advance_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return false
		return key_event.keycode == KEY_SPACE or key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER
	return false

func _is_skip_input(event: InputEvent) -> bool:
	if event.is_action_pressed("Pause") or event.is_action_pressed("ui_cancel"):
		return true
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE
	return false

func is_dialogue_active() -> bool:
	return not _current_dialogue_id.is_empty()

func _show_dialogue_if_token(start_token: int) -> void:
	if start_token != _start_token:
		return
	if _lines.is_empty() or _current_dialogue_id.is_empty():
		return

	_dialogue_pending = false
	visible = true
	_show_current_line()
	_apply_dialogue_pause(true)
	dialogue_started.emit(_current_dialogue_id)

func _apply_dialogue_pause(should_pause: bool) -> void:
	if not pause_gameplay_while_active:
		return
	if should_pause:
		_set_playing_area_pause_override(true)
		if _paused_by_dialogue:
			return
		_previous_pause_state = get_tree().paused
		if not _previous_pause_state:
			get_tree().paused = true
			_paused_by_dialogue = true
		return

	if _paused_by_dialogue:
		get_tree().paused = _previous_pause_state
		_paused_by_dialogue = false
	_set_playing_area_pause_override(false)

func _set_playing_area_pause_override(should_override: bool) -> void:
	var playing_area := _get_playing_area()
	if playing_area == null:
		return

	if should_override:
		if _playing_area_mode_overridden:
			return
		_previous_playing_area_mode = playing_area.process_mode
		playing_area.process_mode = Node.PROCESS_MODE_PAUSABLE
		_playing_area_mode_overridden = true
		return

	if _playing_area_mode_overridden and is_instance_valid(playing_area):
		playing_area.process_mode = _previous_playing_area_mode
	_playing_area_mode_overridden = false

func _get_playing_area() -> Node:
	if _playing_area != null and is_instance_valid(_playing_area):
		return _playing_area

	var root := get_tree().current_scene
	if root == null:
		return null

	_playing_area = root.get_node_or_null("PlayingArea")
	return _playing_area

func _get_speaker_color(speaker: String) -> Color:
	if speaker.is_empty():
		return default_speaker_color
	var color_key := _normalize_speaker(speaker)
	var color_value: Variant = speaker_name_colors.get(color_key, default_speaker_color)
	return color_value if color_value is Color else default_speaker_color

func _get_speaker_portrait(speaker: String) -> Texture2D:
	if speaker.is_empty():
		return null
	var portrait_key := _normalize_speaker(speaker)
	var portrait_value: Variant = speaker_portraits.get(portrait_key, null)
	return portrait_value if portrait_value is Texture2D else null

func _apply_speaker_portrait(speaker: String, is_narrator: bool) -> void:
	if is_narrator:
		speaker_frame.visible = false
		speaker_portrait.texture = null
		speaker_portrait.visible = false
		return

	speaker_frame.visible = true
	var portrait := _get_speaker_portrait(speaker)
	if portrait == null:
		speaker_portrait.texture = null
		speaker_portrait.visible = false
		return

	speaker_portrait.texture = portrait
	speaker_portrait.visible = true

func _set_dialogue_text(text: String, italicize: bool) -> void:
	dialogue_text.clear()
	if italicize:
		dialogue_text.push_italics()
	dialogue_text.add_text(text)
	if italicize:
		dialogue_text.pop()

func _normalize_speaker(speaker: String) -> String:
	return speaker.strip_edges().to_upper()

func _is_narrator(speaker: String) -> bool:
	return _normalize_speaker(speaker) == narrator_name.strip_edges().to_upper()
