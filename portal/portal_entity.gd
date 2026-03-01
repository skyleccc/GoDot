class_name PortalEntity
extends CharacterBody2D

## Base class for any object that can travel through portals.
## Implements custom collision handling that respects portal surfaces
## and tracks portal-launch state for momentum preservation.

var is_grounded := false

## True for a short window after exiting a portal — used to reduce
## air friction so the "fling" carries properly (Portal's golden rule:
## "Speedy thing goes in, speedy thing comes out").
var launched_by_portal := false
var _portal_launch_timer := 0.0
const PORTAL_LAUNCH_DURATION := 1.5  # seconds of reduced air friction after fling



## Velocity captured right before teleport — useful for debugging
var pre_teleport_velocity := Vector2.ZERO

## Maximum number of slide iterations per frame to prevent infinite loops
const MAX_SLIDES := 4

func _process(delta: float) -> void:
	if launched_by_portal:
		_portal_launch_timer -= delta
		if _portal_launch_timer <= 0.0:
			launched_by_portal = false
			_portal_launch_timer = 0.0

## Call this from the portal after teleporting this entity
func notify_portal_launch() -> void:
	launched_by_portal = true
	_portal_launch_timer = PORTAL_LAUNCH_DURATION

func custom_move_and_slide(delta: float) -> void:
	is_grounded = false
	var motion := velocity * delta
	var slides := 0

	while motion.length() > 0.001 and slides < MAX_SLIDES:
		var collision := move_and_collide(motion)

		if not collision:
			break  # no collision, full motion applied

		# Check if we hit a portal surface — if so, stop sliding so
		# the portal's own overlap detection handles teleportation
		if _find_portal_at_collision(collision):
			break

		# Ground detection: surface normal pointing mostly upward
		if collision.get_normal().dot(Vector2.UP) > 0.7:
			is_grounded = true

		# Slide velocity along the collision surface
		velocity = velocity.slide(collision.get_normal())

		# Continue with the remaining motion projected onto the surface
		motion = collision.get_remainder().slide(collision.get_normal())
		slides += 1

	# Extra ground check: tiny raycast downward (catches standing still)
	if not is_grounded:
		var test_collision := move_and_collide(Vector2.DOWN * 2.0, true)  # test only
		if test_collision and test_collision.get_normal().dot(Vector2.UP) > 0.7:
			is_grounded = true

func _find_portal_at_collision(collision: KinematicCollision2D) -> Area2D:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	# Sample slightly behind the collision surface to find the portal area
	query.position = collision.get_position() + collision.get_normal() * -4.0
	query.collide_with_areas = true
	query.collide_with_bodies = false

	for result in space_state.intersect_point(query):
		if result.collider.is_in_group("portals"):
			return result.collider
	return null
