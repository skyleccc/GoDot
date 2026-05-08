extends Control

const INACTIVE_PORTAL_COLOR := Color("646464")
const ACTIVE_PORTAL_COLOR := Color("ffffff")
const LOW_HP_TINT := Color(1.0, 0.45, 0.45, 1.0)
const NORMAL_TINT := Color(1.0, 1.0, 1.0, 1.0)
const LOW_HP_THRESHOLD := 0.3

@onready var hp_bar: TextureProgressBar = $HpBar
@onready var level_display: RichTextLabel = $HpBar/LevelDisplay
@onready var character_icon: AnimatedSprite2D = $HpBar/CharacterIconPanel/CharacterIcon
@onready var portal_blue: AnimatedSprite2D = $PortalIndicatorsPanel/PortalBlue
@onready var portal_orange: AnimatedSprite2D = $PortalIndicatorsPanel/PortalOrange

var _player: Node = null
var _level_manager: Node = null
var _portal_gun: Node = null

func _ready() -> void:
	_set_portal_indicator(false, false)
	_bind_player()
	_bind_level_manager()

func _process(_delta: float) -> void:
	# Keep trying until all dependencies are bound (scene load order can vary).
	if _player == null or not is_instance_valid(_player):
		_bind_player()
	if _level_manager == null or not is_instance_valid(_level_manager):
		_bind_level_manager()

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	var hp_changed_callable := Callable(self, "_on_player_hp_changed")
	if _player.has_signal("hp_changed") and not _player.is_connected("hp_changed", hp_changed_callable):
		_player.connect("hp_changed", hp_changed_callable)

	if _player.has_method("get"):
		var current_hp := int(_player.get("current_hp"))
		var max_hp := int(_player.get("max_hp"))
		_on_player_hp_changed(current_hp, max_hp)

	_portal_gun = _player.get_node_or_null("PortalGun")
	var portal_state_changed_callable := Callable(self, "_on_portal_state_changed")
	if _portal_gun and _portal_gun.has_signal("portal_state_changed") and not _portal_gun.is_connected("portal_state_changed", portal_state_changed_callable):
		_portal_gun.connect("portal_state_changed", portal_state_changed_callable)
		var has_blue := _portal_gun.get("active_blue_portal") != null
		var has_orange := _portal_gun.get("active_orange_portal") != null
		_on_portal_state_changed(has_blue, has_orange)

func _bind_level_manager() -> void:
	_level_manager = get_tree().get_first_node_in_group("level_manager")
	if _level_manager == null:
		return

	var level_loaded_callable := Callable(self, "_on_level_loaded")
	if _level_manager.has_signal("level_loaded") and not _level_manager.is_connected("level_loaded", level_loaded_callable):
		_level_manager.connect("level_loaded", level_loaded_callable)

	if _level_manager.has_method("get_current_level_number"):
		_on_level_loaded(_level_manager.get_current_level_number())

func _on_player_hp_changed(current_hp_value: int, max_hp_value: int) -> void:
	var clamped_max := maxi(max_hp_value, 1)
	var clamped_hp := clampi(current_hp_value, 0, clamped_max)
	hp_bar.max_value = float(clamped_max)
	hp_bar.value = float(clamped_hp)

	var ratio := float(clamped_hp) / float(clamped_max)
	character_icon.modulate = LOW_HP_TINT if ratio <= LOW_HP_THRESHOLD else NORMAL_TINT

func _on_level_loaded(level_number: int) -> void:
	level_display.text = "[font_size=48][b]Level %d[/b][/font_size]" % level_number

func _on_portal_state_changed(has_blue: bool, has_orange: bool) -> void:
	_set_portal_indicator(has_blue, has_orange)

func _set_portal_indicator(has_blue: bool, has_orange: bool) -> void:
	portal_blue.modulate = ACTIVE_PORTAL_COLOR if has_blue else INACTIVE_PORTAL_COLOR
	portal_orange.modulate = ACTIVE_PORTAL_COLOR if has_orange else INACTIVE_PORTAL_COLOR
