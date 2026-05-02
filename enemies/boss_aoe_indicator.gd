extends Area2D

@export var radius: float = 60.0
@export var telegraph_time: float = 1.0
@export var warning_after_telegraph: float = 0.75
@export var linger_time: float = 0.15
@export var damage: int = 25

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var fill: Polygon2D = $Fill
@onready var outline: Line2D = $Outline

var _follow_node: Node2D = null
var _offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = false
	monitorable = true

	var circle_shape := collision_shape.shape as CircleShape2D
	if circle_shape:
		circle_shape.radius = radius

	_build_circle_visuals()
	_detonate_after_delay()

	set_process(true)

func set_follow_node(node: Node2D, offset: Vector2 = Vector2.ZERO) -> void:
	_follow_node = node
	_offset = offset
	if _follow_node != null:
		global_position = _follow_node.global_position + _offset

func _process(_delta: float) -> void:
	if _follow_node != null and collision_layer == 0:
		if is_instance_valid(_follow_node):
			global_position = _follow_node.global_position + _offset
		else:
			_follow_node = null

func _build_circle_visuals() -> void:
	var points := PackedVector2Array()
	var segments := 48
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	fill.polygon = points
	fill.color = Color(1.0, 0.75, 0.15, 0.35)

	outline.points = points
	outline.width = 3.0
	outline.closed = true
	outline.default_color = Color(1.0, 0.9, 0.35, 0.9)

func _detonate_after_delay() -> void:
	await get_tree().create_timer(telegraph_time).timeout
	fill.color = Color(1.0, 0.2, 0.2, 0.45)
	outline.default_color = Color(1.0, 0.3, 0.3, 1.0)
	collision_layer = 8
	monitoring = true
	await get_tree().process_frame

	await get_tree().create_timer(warning_after_telegraph).timeout

	for body in get_overlapping_bodies():
		if body != null and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage, global_position, true, false)

	await get_tree().create_timer(linger_time).timeout
	queue_free()
