extends Node2D

signal health_changed(current: int, maximum: int)
signal died

@export var speed := 260.0
@export var max_health := 5
@export var radius := 22.0

var health := 5
var alive := true
var active := false

@onready var sprite: Sprite2D = $Sprite2D


func configure(texture: Texture2D) -> void:
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = texture


func reset(start_position: Vector2) -> void:
	position = start_position
	health = max_health
	alive = true
	active = true
	visible = true
	health_changed.emit(health, max_health)


func set_active(value: bool) -> void:
	active = value


func move(input_vector: Vector2, delta: float, bounds: Rect2, walls: Array[Rect2]) -> void:
	if not alive or not active:
		return
	var direction := input_vector
	if direction.length() > 1.0:
		direction = direction.normalized()
	if direction == Vector2.ZERO:
		return

	var old_position := position
	position += direction * speed * delta
	position.x = clampf(position.x, bounds.position.x + radius, bounds.position.x + bounds.size.x - radius)
	position.y = clampf(position.y, bounds.position.y + radius, bounds.position.y + bounds.size.y - radius)
	if _hits_wall(walls):
		position = old_position
	if sprite != null and absf(direction.x) > 0.05:
		sprite.flip_h = direction.x < 0.0


func aim_at(world_position: Vector2) -> void:
	if sprite == null:
		return
	var direction := world_position - global_position
	if direction.length() > 4.0:
		sprite.rotation = clampf(direction.angle() * 0.12, -0.18, 0.18)


func hurt(amount: int) -> void:
	if not alive:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		alive = false
		active = false
		died.emit()


func _hits_wall(walls: Array[Rect2]) -> bool:
	for rect in walls:
		if rect.grow(radius).has_point(position):
			return true
	return false
