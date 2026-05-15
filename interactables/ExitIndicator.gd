## ExitIndicator.gd
## Attach to a Node2D child inside LevelExit.tscn
##
## Priority:
##   1. Points at any alive shield projector (checks every frame, order doesn't matter)
##   2. Points at the exit once all projectors are destroyed

extends Node2D

@export var edge_margin: float = 40.0
@export var arrow_half_size: float = 14.0
@export var pulse_speed: float = 3.0

@export var shield_color: Color = Color(1.0, 0.843, 0.0, 1.0)
@export var exit_color: Color = Color(1.0, 0.843, 0.0, 1.0)
@export var outline_color: Color = Color(1.0, 0.941, 0.96, 0.702)

@export var label_shields: String = "DESTROY GENERATORS"
@export var label_exit: String = "EXIT"

var _camera: Camera2D = null
var _time: float = 0.0

var _canvas_layer: CanvasLayer = null
var _draw_node: _ArrowDrawer = null
var _label: Label = null

var _shields: Array = []


func _ready() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	get_tree().current_scene.add_child(_canvas_layer)

	_draw_node = _ArrowDrawer.new()
	_canvas_layer.add_child(_draw_node)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_outline_color", outline_color)
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas_layer.add_child(_label)

	call_deferred("_init_shields")


func _init_shields() -> void:
	_shields = get_tree().get_nodes_in_group("shield_projectors")
	print("[ExitIndicator] Found ", _shields.size(), " shield projectors")


func _get_current_target() -> Node2D:
	# Every frame: scan ALL shields and return the first alive one
	# Works regardless of what order they're destroyed in
	for s in _shields:
		if is_instance_valid(s) and s.has_method("is_alive") and s.is_alive():
			return s as Node2D
	return null


func _process(delta: float) -> void:
	_time += delta
	_find_camera()

	if _camera == null:
		_set_visible(false)
		return

	var current_shield: Node2D = _get_current_target()
	var pointing_at_shield: bool = current_shield != null

	var target_world_pos: Vector2
	var current_color: Color
	var current_label: String

	if pointing_at_shield:
		target_world_pos = current_shield.global_position
		current_color = shield_color
		current_label = label_shields
	else:
		target_world_pos = get_parent().global_position
		current_color = exit_color
		current_label = label_exit

	var screen_pos: Vector2 = _world_to_screen(target_world_pos)
	var screen_size: Vector2 = get_viewport().get_visible_rect().size

	var on_screen_rect := Rect2(
		Vector2(edge_margin, edge_margin),
		screen_size - Vector2(edge_margin * 2.0, edge_margin * 2.0)
	)

	if on_screen_rect.has_point(screen_pos):
		_set_visible(false)
		return

	_set_visible(true)

	var clamped := Vector2(
		clampf(screen_pos.x, edge_margin, screen_size.x - edge_margin),
		clampf(screen_pos.y, edge_margin, screen_size.y - edge_margin)
	)

	var arrow_angle: float = (screen_pos - clamped).angle()
	var pulse_alpha: float = 0.7 + 0.3 * sin(_time * pulse_speed)

	_draw_node.arrow_pos = clamped
	_draw_node.arrow_angle = arrow_angle
	_draw_node.arrow_half_size = arrow_half_size
	_draw_node.arrow_color = Color(current_color, pulse_alpha)
	_draw_node.outline_color = outline_color
	_draw_node.queue_redraw()

	if _label:
		_label.text = current_label
		_label.add_theme_color_override("font_color", current_color)
		_label.position = clamped + Vector2(-40.0, -arrow_half_size - 22.0)
		_label.modulate.a = pulse_alpha


func _set_visible(v: bool) -> void:
	if _draw_node:
		_draw_node.visible = v
	if _label:
		_label.visible = v


func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


func _find_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	_camera = get_viewport().get_camera_2d()


func _exit_tree() -> void:
	if is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()


class _ArrowDrawer extends Node2D:
	var arrow_pos: Vector2 = Vector2.ZERO
	var arrow_angle: float = 0.0
	var arrow_half_size: float = 14.0
	var arrow_color: Color = Color.GREEN
	var outline_color: Color = Color.BLACK

	func _draw() -> void:
		var tip := Vector2(arrow_half_size * 1.6, 0.0).rotated(arrow_angle)
		var base_a := Vector2(-arrow_half_size * 0.8, -arrow_half_size).rotated(arrow_angle)
		var base_b := Vector2(-arrow_half_size * 0.8, arrow_half_size).rotated(arrow_angle)

		draw_colored_polygon(PackedVector2Array([
			arrow_pos + tip * 1.25,
			arrow_pos + base_a * 1.25,
			arrow_pos + base_b * 1.25
		]), outline_color)

		draw_colored_polygon(PackedVector2Array([
			arrow_pos + tip,
			arrow_pos + base_a,
			arrow_pos + base_b
		]), arrow_color)
