extends Node2D

@export var speed := 620.0
@export var lifetime := 0.85
@export var damage := 1
@export var radius := 8.0

var velocity := Vector2.RIGHT
var age := 0.0
var sprite: Sprite2D


func _ready() -> void:
	sprite = get_node_or_null("Sprite2D") as Sprite2D


func configure(texture: Texture2D, start_position: Vector2, direction: Vector2) -> void:
	position = start_position
	velocity = direction.normalized() * speed
	rotation = direction.angle()
	age = 0.0
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = texture


func step(delta: float) -> bool:
	position += velocity * delta
	age += delta
	return age <= lifetime
