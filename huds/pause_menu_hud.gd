extends Control

signal resume_requested
signal settings_requested
signal exit_requested

@onready var resume_button: Button = $MenuPanel/VBoxContainer/ResumeButton
@onready var settings_button: Button = $MenuPanel/VBoxContainer/SettingsButton
@onready var exit_button: Button = $MenuPanel/VBoxContainer/ExitButton
@onready var menu_panel: Panel = $MenuPanel
@onready var confirm_panel: Panel = $ConfirmPanel
@onready var confirm_yes_button: Button = $ConfirmPanel/VBoxContainer/HBoxContainer/ConfirmYesButton
@onready var confirm_no_button: Button = $ConfirmPanel/VBoxContainer/HBoxContainer/ConfirmNoButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	resume_button.pressed.connect(_on_resume_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	confirm_yes_button.pressed.connect(_on_confirm_yes_button_pressed)
	confirm_no_button.pressed.connect(_on_confirm_no_button_pressed)
	visibility_changed.connect(_on_visibility_changed)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("Pause") or event.is_action_pressed("ui_cancel"):
		if confirm_panel.visible:
			_hide_exit_confirmation()
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()

func _on_resume_button_pressed() -> void:
	resume_requested.emit()

func _on_settings_button_pressed() -> void:
	settings_requested.emit()

func _on_exit_button_pressed() -> void:
	_show_exit_confirmation()

func _on_confirm_yes_button_pressed() -> void:
	exit_requested.emit()

func _on_confirm_no_button_pressed() -> void:
	_hide_exit_confirmation()

func _on_visibility_changed() -> void:
	if visible:
		_hide_exit_confirmation()
		resume_button.grab_focus()

func _show_exit_confirmation() -> void:
	menu_panel.visible = false
	confirm_panel.visible = true
	confirm_yes_button.grab_focus()

func _hide_exit_confirmation() -> void:
	confirm_panel.visible = false
	menu_panel.visible = true
