extends CanvasLayer

## Debug HUD — all debug visuals in one place.
## 1. Top-left text overlay (velocity, state, mouse, portal info)
## 2. Player hitbox outline (reads CollisionShape2D from player)
## 3. Aim angle / laser sight (reads from PortalGun node)
## 4. Portal hitbox + face direction (reads CollisionShape2D from each portal)
## Attach as a child of the Character node.

var _label: Label
var _draw_node: Node2D  # world-space drawing

func _ready() -> void:
	layer = 100

	# --- Text label ---
	var label := Label.new()
	label.name = "DebugLabel"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	_label = label

	# --- World-space draw node (added to scene root so it uses world coords) ---
	_draw_node = _DebugDrawNode.new()
	_draw_node.name = "DebugDraw"
	_draw_node.hud = self
	_draw_node.z_index = 4096
	call_deferred("_add_draw_node")

func _add_draw_node() -> void:
	var scene := get_tree().current_scene
	if scene and is_instance_valid(scene):
		scene.add_child(_draw_node)

func _process(_delta: float) -> void:
	if not _label:
		return

	if _draw_node and is_instance_valid(_draw_node):
		_draw_node.queue_redraw()

	var player := _get_player()
	if not player:
		_label.text = "Player not found"
		return

	var gun := _get_portal_gun(player)

	# --- Velocity / Speed ---
	var vel: Vector2 = player.velocity
	var speed := vel.length()

	# --- Direction ---
	var dir_text := "Idle"
	if speed > 5.0:
		if abs(vel.x) > 30 and abs(vel.y) > 30:
			var h := "Right" if vel.x > 0 else "Left"
			var v := "Up" if vel.y < 0 else "Down"
			dir_text = v + "-" + h
		else:
			var angle := rad_to_deg(vel.angle())
			if abs(angle) < 45:
				dir_text = "Right"
			elif abs(angle) > 135:
				dir_text = "Left"
			elif angle < 0:
				dir_text = "Up"
			else:
				dir_text = "Down"

	# --- Player state ---
	var state_text := "Grounded" if player.is_grounded else "Airborne"
	if player.launched_by_portal:
		state_text += " [FLUNG]"

	# --- Mouse ---
	var mouse_pos: Vector2 = player.get_global_mouse_position()

	# --- Portal state ---
	var blue_text := "not placed"
	var orange_text := "not placed"
	var link_text := "not linked"
	var blue_pos_text := "\u2014"
	var orange_pos_text := "\u2014"

	if gun:
		var bp: Node2D = gun.active_blue_portal
		var op: Node2D = gun.active_orange_portal
		if bp and is_instance_valid(bp):
			blue_text = "placed"
			blue_pos_text = "(%d, %d)" % [int(bp.global_position.x), int(bp.global_position.y)]
		if op and is_instance_valid(op):
			orange_text = "placed"
			orange_pos_text = "(%d, %d)" % [int(op.global_position.x), int(op.global_position.y)]
		if bp and is_instance_valid(bp) and op and is_instance_valid(op):
			if bp.linked_portal == op:
				link_text = "LINKED"

	_label.text = \
		"Velocity:   (%d, %d)" % [int(vel.x), int(vel.y)] + \
		"\nSpeed:      %.0f px/s" % speed + \
		"\nDirection:  %s" % dir_text + \
		"\nState:      %s" % state_text + \
		"\n" + \
		"\nMouse:      (%d, %d)" % [int(mouse_pos.x), int(mouse_pos.y)] + \
		"\n" + \
		"\nBlue:       %s" % blue_text + \
		"\nBlue Pos:   %s" % blue_pos_text + \
		"\nOrange:     %s" % orange_text + \
		"\nOrange Pos: %s" % orange_pos_text + \
		"\nPortals:    %s" % link_text

# ------------------------------------------------------------------ helpers

func _get_player() -> PortalEntity:
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.get_node_or_null("Character") as PortalEntity

func _get_portal_gun(player: Node) -> Node2D:
	return player.get_node_or_null("PortalGun") as Node2D

func get_portals() -> Array:
	var player := _get_player()
	if not player:
		return []
	var gun := _get_portal_gun(player)
	if not gun:
		return []
	var portals: Array = []
	if gun.active_blue_portal and is_instance_valid(gun.active_blue_portal):
		portals.append(gun.active_blue_portal)
	if gun.active_orange_portal and is_instance_valid(gun.active_orange_portal):
		portals.append(gun.active_orange_portal)
	return portals

# ---------------------------------------- inner class: world-space drawing

class _DebugDrawNode extends Node2D:
	var hud: Node

	func _draw() -> void:
		if not hud or not is_instance_valid(hud):
			return

		var player: PortalEntity = hud._get_player()
		if not player:
			return

		# 2. Aim angle / laser sight
		var gun: Node2D = hud._get_portal_gun(player)
		if gun:
			_draw_aim_line(gun)

		# 3. Portal face direction
		var portals: Array = hud.get_portals()
		for portal in portals:
			if is_instance_valid(portal):
				_draw_portal(portal)

	# ---- 2. Aim line / laser sight ----
	func _draw_aim_line(gun: Node2D) -> void:
		# Read cached aim data from the PortalGun script
		var hit_pos: Vector2 = gun.get("_aim_hit_pos")
		var aim_valid: bool = gun.get("_aim_valid")
		if hit_pos == null:
			return

		# Laser line from gun origin to aim point
		draw_line(gun.global_position, hit_pos, Color(1, 1, 1, 0.3), 1.0)

		# Crosshair dot at impact point
		if aim_valid:
			draw_circle(hit_pos, 3.0, Color.WHITE)

	# ---- 3. Portal face direction ----
	func _draw_portal(portal: Node2D) -> void:
		var portal_color := Color.CYAN if portal.name.contains("Blue") else Color.ORANGE
		var xf: Transform2D = portal.global_transform
		var up := xf.y.normalized()   # along the portal opening
		var normal := xf.x.normalized()  # outward normal

		# --- Read CollisionShape2D for positioning ---
		var half_height := 0.0
		var shape_offset := Vector2.ZERO
		var col_shape: CollisionShape2D = portal.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col_shape and col_shape.shape is RectangleShape2D:
			var rect_shape: RectangleShape2D = col_shape.shape as RectangleShape2D
			half_height = rect_shape.size.y / 2.0
			shape_offset = col_shape.position

		# Read EXIT_BUFFER from the portal script
		var exit_buffer: float = portal.EXIT_BUFFER if "EXIT_BUFFER" in portal else 40.0

		# Shape center in world space
		var center: Vector2 = xf * shape_offset

		# --- Portal opening line ---
		var top: Vector2 = center - up * half_height
		var bot: Vector2 = center + up * half_height
		draw_line(top, bot, portal_color, 3.0)

		# --- Normal arrow (face direction) ---
		var arrow_end: Vector2 = center + normal * exit_buffer
		draw_line(center, arrow_end, Color.WHITE, 1.5)
		draw_circle(arrow_end, 3.0, Color.WHITE)
