extends Node
class_name BackgroundManager

# A dictionary to map level names or IDs to their corresponding Parallax setup scenes
@export var background_sets: Dictionary
@export var default_background: PackedScene
@export var camera_anchor_path: NodePath = NodePath("Background")
@export var fit_to_camera: bool = true
@export var target_resolution: Vector2 = Vector2(1920, 1080)
var current_bg_instance: Node = null

func _ready() -> void:
	if _should_instance_default():
		_apply_background(default_background)
	else:
		current_bg_instance = self
		_apply_canvas_item_defaults(current_bg_instance)
	set_process(true)
	_fit_background_to_camera()

func _process(_delta: float) -> void:
	sync_to_camera()
	_fit_background_to_camera()

func sync_to_camera() -> void:
	if current_bg_instance == null:
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	if not (current_bg_instance is Node2D):
		return
	var anchor_offset := _get_camera_anchor_offset()
	(current_bg_instance as Node2D).global_position = camera.global_position - anchor_offset

func _fit_background_to_camera() -> void:
	if not fit_to_camera:
		return
	if current_bg_instance == null:
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var anchor: Node = current_bg_instance.get_node_or_null(camera_anchor_path)
	if anchor == null:
		return
	if not (anchor is Sprite2D):
		return
	var sprite := anchor as Sprite2D
	if sprite.texture == null:
		return
	var reference_size: Vector2 = target_resolution
	if reference_size.x <= 0.0 or reference_size.y <= 0.0:
		reference_size = get_viewport().get_visible_rect().size
	var zoom: Vector2 = camera.zoom
	if zoom.x == 0.0 or zoom.y == 0.0:
		return
	var visible_size: Vector2 = reference_size / zoom
	var texture_size: Vector2 = sprite.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var scale_factor: float = max(visible_size.x / texture_size.x, visible_size.y / texture_size.y)
	var target_scale: Vector2 = Vector2(scale_factor, scale_factor)
	if not sprite.scale.is_equal_approx(target_scale):
		sprite.scale = target_scale

# Call this function when the level changes, passing the new level name
func load_background(level_id: String) -> void:
	print("BackgroundManager: Requesting to load background for: ", level_id)
	
	print("Available background sets keys: ", background_sets.keys())
	
	# Instantiate and add the new background
	if background_sets.has(level_id):
		var bg_scene: PackedScene = background_sets[level_id]
		_apply_background(bg_scene)
	else:
		push_warning("Background set for level '%s' not found!" % level_id)

func _apply_background(bg_scene: PackedScene) -> void:
	if current_bg_instance != null:
		current_bg_instance.queue_free()
		current_bg_instance = null

	if bg_scene == null:
		return

	current_bg_instance = bg_scene.instantiate()
	_apply_canvas_item_defaults(current_bg_instance)
	add_child(current_bg_instance)
	print("Successfully added background instance.")

func _apply_canvas_item_defaults(node: Node) -> void:
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		# Force background behind gameplay visuals.
		canvas_item.z_as_relative = false
		canvas_item.z_index = -100
		canvas_item.visible = true
		canvas_item.position = Vector2.ZERO

func _should_instance_default() -> bool:
	if default_background == null:
		return false
	var self_scene := scene_file_path
	if self_scene.is_empty():
		return true
	return default_background.resource_path != self_scene

func _get_camera_anchor_offset() -> Vector2:
	if current_bg_instance == null:
		return Vector2.ZERO
	var anchor: Node = current_bg_instance.get_node_or_null(camera_anchor_path)
	if anchor == null:
		return Vector2.ZERO
	if anchor is Sprite2D:
		var sprite := anchor as Sprite2D
		if sprite.texture == null:
			return sprite.global_position - (current_bg_instance as Node2D).global_position
		var size := sprite.texture.get_size() * sprite.global_scale
		var center_global := sprite.global_position
		if not sprite.centered:
			center_global += size * 0.5
		return center_global - (current_bg_instance as Node2D).global_position
	if anchor is Node2D:
		return (anchor as Node2D).global_position - (current_bg_instance as Node2D).global_position
	return Vector2.ZERO
