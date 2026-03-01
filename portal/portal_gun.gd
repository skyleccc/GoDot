extends Node2D

## Portal gun that fires portals onto surfaces using raycasts.
## Left-click places the blue portal, right-click places the orange portal.
## Press R to clear both portals.
##
## Portals can only be placed on static collision surfaces (walls, floors, ceilings).
## A laser sight line shows where the portal will land.

@export var blue_portal_scene: PackedScene
@export var orange_portal_scene: PackedScene

## How far the raycast reaches
const RAY_LENGTH := 2000.0
## Collision mask for portal-able surfaces (layer 2 = Walls, layer 6 = PortalSurfaces)
const SURFACE_MASK := 34

var active_blue_portal: Node2D = null
var active_orange_portal: Node2D = null

## Cached aim result for drawing the laser sight
var _aim_hit_pos: Vector2 = Vector2.ZERO
var _aim_hit_normal: Vector2 = Vector2.ZERO
var _aim_valid := false

func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())

	# Update aim data for the laser sight
	_update_aim()

	# Fire portals
	if Input.is_action_just_pressed("BluePortal"):
		_spawn_portal("blue")
	elif Input.is_action_just_pressed("OrangePortal"):
		_spawn_portal("orange")

	# Reset both portals
	if Input.is_action_just_pressed("ResetPortals"):
		_clear_portals()

func _update_aim() -> void:
	var result := _raycast_to_surface()
	if result:
		_aim_hit_pos = result.position
		_aim_hit_normal = result.normal
		_aim_valid = true
	else:
		_aim_hit_pos = global_position + global_transform.x * RAY_LENGTH
		_aim_valid = false

func _spawn_portal(type: String) -> void:
	var result := _raycast_to_surface()
	if not result:
		return  # No valid surface hit

	# Create the portal instance
	var new_portal: Node2D
	if type == "blue":
		if active_blue_portal:
			active_blue_portal.queue_free()
		new_portal = blue_portal_scene.instantiate()
		active_blue_portal = new_portal
	else:
		if active_orange_portal:
			active_orange_portal.queue_free()
		new_portal = orange_portal_scene.instantiate()
		active_orange_portal = new_portal

	# Add to the scene tree
	get_tree().current_scene.add_child(new_portal)

	# Position and orient: local X axis = surface normal (outward)
	new_portal.global_position = result.position
	new_portal.global_rotation = result.normal.angle()
	new_portal.add_to_group("portals")

	# Link portals together if both exist
	_link_portals()

func _raycast_to_surface() -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	var from := global_position
	var to := from + global_transform.x * RAY_LENGTH
	var query := PhysicsRayQueryParameters2D.create(from, to, SURFACE_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)

func _link_portals() -> void:
	if active_blue_portal and active_orange_portal:
		active_blue_portal.linked_portal = active_orange_portal
		active_orange_portal.linked_portal = active_blue_portal
	elif active_blue_portal:
		active_blue_portal.linked_portal = null
	elif active_orange_portal:
		active_orange_portal.linked_portal = null

func _clear_portals() -> void:
	if active_blue_portal:
		active_blue_portal.queue_free()
		active_blue_portal = null
	if active_orange_portal:
		active_orange_portal.queue_free()
		active_orange_portal = null


