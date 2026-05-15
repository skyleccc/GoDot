## ExitIndicator.gd
## Attach to a Node2D child inside LevelExit.tscn
## Uses a CanvasLayer so the arrow always draws in screen space correctly.

extends Node2D

@export var edge_margin: float = 40.0
@export var arrow_half_size: float = 14.0
@export var arrow_color: Color = Color(0.993, 0.83, 0.0, 1.0)
@export var outline_color: Color = Color(1.0, 1.0, 1.0, 0.7)
@export var pulse_speed: float = 3.0
@export var label_text: String = "EXIT"

var _camera: Camera2D = null
var _is_on_screen: bool = false
var _time: float = 0.0

# CanvasLayer holds the actual drawing node (screen space)
var _canvas_layer: CanvasLayer = null
var _draw_node: _ArrowDrawer = null
var _label: Label = null


func _ready() -> void:
	# Create a CanvasLayer so everything draws in screen space
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	get_tree().current_scene.add_child(_canvas_layer)

	# The node that actually calls _draw()
	_draw_node = _ArrowDrawer.new()
	_draw_node.indicator = self
	_canvas_layer.add_child(_draw_node)

	# Label
	_label = Label.new()
	_label.text = label_text
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", arrow_color)
	_label.add_theme_color_override("font_outline_color", outline_color)
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas_layer.add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	_find_camera()

	if _camera == null:
		_set_visible(false)
		return

	var exit_world_pos: Vector2 = get_parent().global_position
	var screen_pos: Vector2 = _world_to_screen(exit_world_pos)
	var screen_size: Vector2 = get_viewport().get_visible_rect().size

	var on_screen_rect := Rect2(
		Vector2(edge_margin, edge_margin),
		screen_size - Vector2(edge_margin * 2.0, edge_margin * 2.0)
	)
	_is_on_screen = on_screen_rect.has_point(screen_pos)

	if _is_on_screen:
		_set_visible(false)
		return

	_set_visible(true)

	# Clamp arrow to screen edge
	var clamped := Vector2(
		clampf(screen_pos.x, edge_margin, screen_size.x - edge_margin),
		clampf(screen_pos.y, edge_margin, screen_size.y - edge_margin)
	)

	var arrow_angle: float = (screen_pos - clamped).angle()
	var pulse_alpha: float = 0.7 + 0.3 * sin(_time * pulse_speed)

	# Pass data to draw node
	_draw_node.arrow_pos = clamped
	_draw_node.arrow_angle = arrow_angle
	_draw_node.arrow_half_size = arrow_half_size
	_draw_node.arrow_color = Color(arrow_color, pulse_alpha)
	_draw_node.outline_color = outline_color
	_draw_node.queue_redraw()

	# Position label above arrow
	if _label:
		_label.position = clamped + Vector2(-24.0, -arrow_half_size - 22.0)
		_label.modulate.a = pulse_alpha


func _set_visible(v: bool) -> void:
	if _draw_node:
		_draw_node.visible = v
	if _label:
		_label.visible = v


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var canvas_transform := get_viewport().get_canvas_transform()
	return canvas_transform * world_pos


func _find_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	var vp := get_viewport()
	if vp == null:
		return
	_camera = vp.get_camera_2d()


func _exit_tree() -> void:
	# Clean up the canvas layer when this node is removed
	if is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()


# Inner class that handles the actual drawing in screen space
class _ArrowDrawer extends Node2D:
	var indicator: Node2D = null
	var arrow_pos: Vector2 = Vector2.ZERO
	var arrow_angle: float = 0.0
	var arrow_half_size: float = 14.0
	var arrow_color: Color = Color.GREEN
	var outline_color: Color = Color.BLACK

	func _draw() -> void:
		var tip := Vector2(arrow_half_size * 1.6, 0.0).rotated(arrow_angle)
		var base_a := Vector2(-arrow_half_size * 0.8, -arrow_half_size).rotated(arrow_angle)
		var base_b := Vector2(-arrow_half_size * 0.8, arrow_half_size).rotated(arrow_angle)

		var outline_pts := PackedVector2Array([
			arrow_pos + tip * 1.25,
			arrow_pos + base_a * 1.25,
			arrow_pos + base_b * 1.25
		])
		draw_colored_polygon(outline_pts, outline_color)

		var pts := PackedVector2Array([
			arrow_pos + tip,
			arrow_pos + base_a,
			arrow_pos + base_b
		])
		draw_colored_polygon(pts, arrow_color)
