extends Control

signal dialogue_started(dialogue_id: String)
signal dialogue_finished(dialogue_id: String)

@export var dialogue_folder: String = "res://dialogues"
@export var level_dialogue_pattern: String = "level_%d_intro.json"
@export var auto_start_by_level: bool = true
@export var continue_hint_text: String = "Click or Space to continue"

@onready var speaker_label: Label = $DialoguePanel/VBoxContainer/HBoxContainer/SpeakerVBox/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $DialoguePanel/VBoxContainer/HBoxContainer/SpeakerVBox/DialogueText
@onready var continue_label: Label = $DialoguePanel/VBoxContainer/ContinueLabel

var _lines: Array = []
var _line_index := 0
var _current_dialogue_id := ""
var _level_manager: Node = null
var _played_dialogues: Dictionary = {}

func _ready() -> void:
	add_to_group("dialogue_hud")
	visible = false
	_update_continue_hint()
	_bind_level_manager()

func _process(_delta: float) -> void:
	if _level_manager == null or not is_instance_valid(_level_manager):
		_bind_level_manager()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_advance_input(event):
		_advance_dialogue()
		get_viewport().set_input_as_handled()

func start_dialogue(dialogue_id: String) -> bool:
	var file_name := "%s.json" % dialogue_id
	var dialogue_path := dialogue_folder.path_join(file_name)
	return start_dialogue_from_file(dialogue_path)

func start_dialogue_from_file(dialogue_path: String) -> bool:
	var data := _load_dialogue_data(dialogue_path)
	if data.is_empty():
		return false

	var lines: Array = data.get("lines", [])
	if typeof(lines) != TYPE_ARRAY or (lines as Array).is_empty():
		push_warning("Dialogue data has no lines: %s" % dialogue_path)
		return false

	_current_dialogue_id = str(data.get("id", dialogue_path.get_file().get_basename()))
	_lines = lines
	_line_index = 0
	visible = true
	_show_current_line()
	dialogue_started.emit(_current_dialogue_id)
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

	if start_dialogue_from_file(dialogue_path):
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

	speaker_label.visible = not speaker.is_empty()
	speaker_label.text = speaker
	dialogue_text.text = text
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
	_lines.clear()
	_line_index = 0
	_current_dialogue_id = ""
	visible = false
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
