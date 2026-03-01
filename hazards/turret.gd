extends Node2D

@export var bullet_speed: float = 200.0
@export var bullet_lifetime: float = 5.0
@export var shoot_frame: int = 18
@export var shoot_cooldown: float = 1.0

var bullet_scene: PackedScene = preload("res://hazards/TurretBullet.tscn")
var shoot_direction: float = -1.0
var _has_shot_this_cycle: bool = false
var _cooldown_timer: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var bullet_spawn: Marker2D = $BulletSpawn


func _ready() -> void:
	shoot_direction = sign(scale.x) if scale.x != 0.0 else -1.0
	animated_sprite.play("default")
	animated_sprite.frame_changed.connect(_on_frame_changed)
	animated_sprite.animation_looped.connect(_on_animation_looped)


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			animated_sprite.play("default")


func _on_frame_changed() -> void:
	if animated_sprite.frame == shoot_frame and not _has_shot_this_cycle:
		_has_shot_this_cycle = true
		_shoot()


func _on_animation_looped() -> void:
	_has_shot_this_cycle = false
	animated_sprite.stop()
	_cooldown_timer = shoot_cooldown


func _shoot() -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = bullet_spawn.global_position + Vector2(shoot_direction, 0)
	bullet.direction = shoot_direction
	bullet.speed = bullet_speed
	bullet.lifetime = bullet_lifetime
	get_tree().current_scene.add_child(bullet)
	# Initialize direction-dependent visuals now that properties are set
	bullet.initialize()
	# Prevent bullet from colliding with the turret that spawned it
	bullet.add_collision_exception_with($CollisionBox)
