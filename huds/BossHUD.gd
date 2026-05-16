## BossHUD.gd
## Instance BossHUD.tscn (CanvasLayer root) into boss levels.
## Level 5: Shows only boss HP bar
## Level 10: Shows 3 shield HP bars side by side, then swaps to boss HP bar.

extends CanvasLayer

const SHIELD_COLOR        := Color(1.0, 0.2, 0.2, 1.0)
const BOSS_COLOR          := Color(1.0, 0.55, 0.1, 1.0)
const BG_COLOR            := Color(0.05, 0.05, 0.1, 0.85)
const BORDER_COLOR        := Color(0.0, 0.85, 1.0, 1.0)

@export var broken_message_duration: float = 2.0
@export var force_no_shields: bool = false  ## Set to true in Level 5 inspector

var _shields: Array = []

var _shield_bars: Array = []      # Array of ProgressBar
var _shield_labels: Array = []    # Array of Label
var _shield_panels: Array = []    # Array of PanelContainer
var _broken_labels: Array = []    # Array of Label
var _broken_timers: Array = []    # Array of float
var _shield_destroyed: Array = [] # Array of bool

var _boss: Node = null
var _boss_row: Control = null
var _boss_bar: ProgressBar = null
var _boss_label: Label = null

var _root_hbox: HBoxContainer = null
var _all_broken: bool = false


func _ready() -> void:
	layer = 10
	call_deferred("_setup")


func _setup() -> void:
	await _build_ui()
	# Wait for boss node to finish its own _ready() before binding
	await get_tree().create_timer(0.3).timeout
	_bind_nodes()


# ── UI Construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	await get_tree().create_timer(0.1).timeout

	if force_no_shields:
		print("[BossHUD] force_no_shields is true - building boss-only UI")
		_build_boss_only_ui()
		return

	_shields = get_tree().get_nodes_in_group("shield_projectors")
	print("[BossHUD] Found ", _shields.size(), " shield projectors")

	if _shields.size() == 0:
		_build_boss_only_ui()
		return

	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.custom_minimum_size = Vector2(0, 60)
	add_child(anchor)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.add_child(margin)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(center)

	_root_hbox = HBoxContainer.new()
	_root_hbox.add_theme_constant_override("separation", 10)
	center.add_child(_root_hbox)

	for i in range(_shields.size()):
		var row := _make_bar_row("GEN %d" % (i + 1), SHIELD_COLOR)
		_root_hbox.add_child(row.panel)
		_shield_panels.append(row.panel)
		_shield_bars.append(row.bar)
		_shield_labels.append(row.name_label)
		_broken_labels.append(row.broken_label)
		_broken_timers.append(0.0)
		_shield_destroyed.append(false)

	var boss_row := _make_bar_row("BOSS", BOSS_COLOR, 360)
	_root_hbox.add_child(boss_row.panel)
	_boss_row = boss_row.panel
	_boss_bar = boss_row.bar
	_boss_label = boss_row.name_label
	_boss_row.visible = false


func _build_boss_only_ui() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.custom_minimum_size = Vector2(0, 60)
	add_child(anchor)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.add_child(margin)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(center)

	_root_hbox = HBoxContainer.new()
	center.add_child(_root_hbox)

	var boss_row := _make_bar_row("BOSS", BOSS_COLOR, 360)
	_root_hbox.add_child(boss_row.panel)
	_boss_row = boss_row.panel
	_boss_bar = boss_row.bar
	_boss_label = boss_row.name_label
	_boss_row.visible = true
	_all_broken = true


func _make_bar_row(title: String, bar_color: Color, min_width: int = 160) -> Dictionary:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(min_width, 44)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var prog := ProgressBar.new()
	prog.min_value = 0.0
	prog.max_value = 100.0  # Will be overwritten in _bind_nodes with real max_hp
	prog.value = 100.0
	prog.custom_minimum_size = Vector2(min_width - 16, 14)
	prog.show_percentage = false

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = bar_color
	fill_style.set_corner_radius_all(3)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.12, 0.12, 1.0)
	bg_style.set_corner_radius_all(3)

	prog.add_theme_stylebox_override("fill", fill_style)
	prog.add_theme_stylebox_override("background", bg_style)
	vbox.add_child(prog)

	var broken_lbl := Label.new()
	broken_lbl.text = "BROKEN!"
	broken_lbl.add_theme_font_size_override("font_size", 10)
	broken_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	broken_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	broken_lbl.add_theme_constant_override("outline_size", 3)
	broken_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	broken_lbl.visible = false
	vbox.add_child(broken_lbl)

	return {
		"panel": panel,
		"bar": prog,
		"name_label": name_lbl,
		"broken_label": broken_lbl
	}


# ── Node Binding ───────────────────────────────────────────────────────────────

func _bind_nodes() -> void:
	# Filter out any freed/invalid nodes that may linger from a previous level
	_shields = []
	for node in get_tree().get_nodes_in_group("shield_projectors"):
		if is_instance_valid(node):
			_shields.append(node)
	print("[BossHUD] Found ", _shields.size(), " shield projectors")
	print("[BossHUD] _bind_nodes called, _boss_bar is: ", _boss_bar)

	if _shields.size() > 0:
		for i in range(_shields.size()):
			var shield: Node = _shields[i]
			if shield.has_method("get") and shield.get("max_hp") != null:
				_shield_bars[i].max_value = float(shield.get("max_hp"))
				_shield_bars[i].value = float(shield.get("max_hp"))
			if shield.has_signal("crystal_destroyed"):
				shield.crystal_destroyed.connect(_on_shield_destroyed.bind(i))

	# Find boss
	_boss = get_tree().get_first_node_in_group("boss")
	if _boss == null:
		_boss = get_tree().get_first_node_in_group("warden_boss")
	if _boss == null:
		for node in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(node):
				continue
			if node.has_method("_are_shields_active"):
				_boss = node
				break

	if _boss != null and _boss_bar != null:
		print("[BossHUD] Boss found: ", _boss.name)
		var max_hp = _boss.get("max_hp")
		var current_hp = _boss.get("current_hp")
		print("[BossHUD] max_hp=", max_hp, " current_hp=", current_hp)
		if max_hp != null and max_hp > 0:
			_boss_bar.max_value = float(max_hp)
			_boss_bar.value = float(current_hp) if current_hp != null else float(max_hp)
			print("[BossHUD] Bar set: max=", _boss_bar.max_value, " val=", _boss_bar.value)
		else:
			print("[BossHUD] WARNING: max_hp null or zero, bar may not display correctly!")
	else:
		if _boss == null:
			print("[BossHUD] WARNING: Boss not found!")
		if _boss_bar == null:
			print("[BossHUD] WARNING: Boss bar not created!")


# ── Per-frame Update ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Update shield bars
	for i in range(mini(_shields.size(), _shield_bars.size())):
		if _shield_destroyed[i]:
			continue
		# Check validity BEFORE typed assignment to avoid
		# "Trying to assign invalid previously freed instance" error
		if not is_instance_valid(_shields[i]):
			_shield_destroyed[i] = true
			continue
		var shield: Node = _shields[i]
		if shield.has_method("get"):
			var hp = shield.get("current_hp")
			if hp != null:
				_shield_bars[i].value = float(hp)

		if _broken_timers[i] > 0.0:
			_broken_timers[i] -= delta
			if _broken_timers[i] <= 0.0:
				var tween := create_tween()
				tween.tween_property(_shield_panels[i], "modulate:a", 0.0, 0.4)

	# Always update boss bar as long as boss exists — not gated on _all_broken
	if _boss != null and is_instance_valid(_boss) and _boss_bar != null and _boss_row != null and _boss_row.visible:
		var boss_hp = _boss.get("current_hp")
		if boss_hp != null:
			_boss_bar.value = float(boss_hp)


# ── Signal Handlers ────────────────────────────────────────────────────────────

func _on_shield_destroyed(index: int) -> void:
	print("[BossHUD] Shield ", index + 1, " destroyed")
	_shield_destroyed[index] = true
	_shield_bars[index].value = 0.0
	_broken_labels[index].visible = true
	_broken_timers[index] = broken_message_duration

	var all_gone := true
	for i in range(_shields.size()):
		if not _shield_destroyed[i]:
			all_gone = false
			break

	if all_gone and not _all_broken:
		_all_broken = true
		await get_tree().create_timer(broken_message_duration).timeout
		_show_boss_bar()


func _show_boss_bar() -> void:
	for panel in _shield_panels:
		panel.visible = false
	_boss_row.visible = true
	_boss_row.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_boss_row, "modulate:a", 1.0, 0.5)
