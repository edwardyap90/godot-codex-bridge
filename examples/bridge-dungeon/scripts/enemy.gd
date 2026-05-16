extends Node2D

signal defeated(enemy: Node2D)

@export var radius := 22.0
@export var damage := 1
@export var score_value := 100

var health := 2
var speed := 94.0
var alive := true
var sprite: Sprite2D


func _ready() -> void:
	sprite = get_node_or_null("Sprite2D") as Sprite2D


func configure(texture: Texture2D, start_position: Vector2, difficulty: int) -> void:
	position = start_position
	health = 2 + difficulty
	speed = 86.0 + float(difficulty) * 14.0
	score_value = 100 + difficulty * 40
	alive = true
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = texture


func step(delta: float, target_position: Vector2, walls: Array[Rect2]) -> void:
	if not alive:
		return
	var direction := target_position - position
	if direction.length() < 4.0:
		return
	direction = direction.normalized()
	var old_position := position
	position += direction * speed * delta
	if _hits_wall(walls):
		position = old_position + Vector2(direction.x * speed * delta, 0.0)
		if _hits_wall(walls):
			position = old_position + Vector2(0.0, direction.y * speed * delta)
			if _hits_wall(walls):
				position = old_position
	if sprite != null and absf(direction.x) > 0.05:
		sprite.flip_h = direction.x < 0.0


func hit(amount: int) -> bool:
	if not alive:
		return false
	health -= amount
	if health <= 0:
		alive = false
		defeated.emit(self)
		queue_free()
		return true
	return false


func _hits_wall(walls: Array[Rect2]) -> bool:
	for rect in walls:
		if rect.grow(radius).has_point(position):
			return true
	return false
