extends Area2D
## A portal that teleports PortalEntity objects to its linked partner.
## Think of it as a piston on the other side: when you enter a portal,
## the exit portal pushes you out along its surface normal at the speed
## you came in. "Speedy thing goes in, speedy thing comes out."
##
## The exit offset accounts for the body's collision shape so it clears
## the exit portal without re-triggering.

@export var linked_portal: Area2D

## Extra padding on top of the hitbox-based offset
const EXIT_PADDING := 4.0
## Speed multiplier applied on portal exit (1.0 = no change)
@export var speed_multiplier: float = 1.0
## Cooldown to prevent instant re-teleport between the pair
const COOLDOWN_DURATION := 0.15

var _cooldown: bool = false

func get_normal() -> Vector2:
	return global_transform.x.normalized()

func _physics_process(_delta: float) -> void:
	if not linked_portal or _cooldown or linked_portal._cooldown:
		return

	for body in get_overlapping_bodies():
		if body is PortalEntity:
			_teleport(body)
			break

## Calculates how far to push the body from the exit portal center
## based on which side of the body's hitbox faces the exit direction.
##
## Ceiling portal (pushes down)  → offset by top of hitbox
## Floor portal   (pushes up)    → offset by bottom of hitbox
## Right portal   (pushes right) → offset by left side of hitbox
## Left portal    (pushes left)  → offset by right side of hitbox
func _get_exit_buffer(body: CharacterBody2D) -> float:
	var exit_normal: Vector2 = linked_portal.get_normal()

	# Find the body's main collision shape
	var col_shape: CollisionShape2D = null
	for child in body.get_children():
		if child is CollisionShape2D:
			col_shape = child
			break

	if not col_shape or not col_shape.shape:
		return 32.0 + EXIT_PADDING  # fallback

	var shape = col_shape.shape
	var half_w: float = 0.0
	var half_h: float = 0.0

	if shape is CapsuleShape2D:
		half_w = shape.radius
		half_h = shape.height / 2.0
	elif shape is RectangleShape2D:
		half_w = shape.size.x / 2.0
		half_h = shape.size.y / 2.0
	elif shape is CircleShape2D:
		half_w = shape.radius
		half_h = shape.radius
	else:
		return 32.0 + EXIT_PADDING  # fallback for unknown shapes

	# The collision shape may have a local offset from the body origin
	var shape_offset: Vector2 = col_shape.position

	# Project the full extents (shape center offset + half size) onto the exit normal.
	# This gives us the distance from body origin to the edge of the hitbox
	# in the direction the exit portal is pushing.
	#
	# The exit buffer must clear the TRAILING edge of the hitbox — the side
	# that faces back toward the portal as the body is pushed out.
	#
	# Floor portal (UP / 0,-1):  trailing edge = bottom (y=43) → needs ~43px
	# Ceiling portal (DOWN / 0,1): trailing edge = top (y=3)  → needs ~3px
	# Right portal (RIGHT / 1,0): trailing edge = left (x=-6) → needs ~6px
	# Left portal (LEFT / -1,0): trailing edge = right (x=6)  → needs ~6px
	#
	# Formula: the minimum dot(corner, exit_normal) is the most-negative
	# projection — that's the trailing edge. Negate it to get the distance.
	var corners := [
		shape_offset + Vector2(-half_w, -half_h),
		shape_offset + Vector2( half_w, -half_h),
		shape_offset + Vector2(-half_w,  half_h),
		shape_offset + Vector2( half_w,  half_h),
	]

	var min_proj: float = INF
	for corner in corners:
		var proj: float = corner.dot(exit_normal)
		if proj < min_proj:
			min_proj = proj

	return maxf(-min_proj, 0.0) + EXIT_PADDING

func _teleport(body: PortalEntity) -> void:
	var entry_speed: float = body.velocity.length()

	# Exit direction = the exit portal's outward normal (the piston direction)
	var push_dir: Vector2 = linked_portal.get_normal()

	# Calculate exit buffer based on body hitbox and exit direction
	var exit_buffer: float = _get_exit_buffer(body)

	# Place body at exit portal, pushed out by the piston
	body.global_position = linked_portal.global_position + push_dir * exit_buffer

	# Piston fires at entry speed, scaled by the multiplier.
	var exit_speed: float = entry_speed * linked_portal.speed_multiplier
	body.velocity = push_dir * exit_speed

	body.is_grounded = false
	body.notify_portal_launch()

	# Cooldown both portals
	_start_cooldown()
	linked_portal._start_cooldown()

func _start_cooldown() -> void:
	_cooldown = true
	await get_tree().create_timer(COOLDOWN_DURATION).timeout
	_cooldown = false
