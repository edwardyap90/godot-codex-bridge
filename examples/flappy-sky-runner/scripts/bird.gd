extends Area2D

signal crashed

@export var gravity_force := 1250.0
@export var flap_velocity := -420.0
@export var max_fall_speed := 620.0

var velocity_y := 0.0
var alive := false


func _physics_process(delta: float) -> void:
	if not alive:
		return

	velocity_y = minf(velocity_y + gravity_force * delta, max_fall_speed)
	position.y += velocity_y * delta
	rotation_degrees = clampf(velocity_y / 14.0, -24.0, 68.0)
	if position.y < -40.0 or position.y > 680.0:
		crashed.emit()


func reset(start_position: Vector2) -> void:
	position = start_position
	velocity_y = 0.0
	rotation_degrees = 0.0
	alive = true
	show()


func flap() -> void:
	if not alive:
		return
	velocity_y = flap_velocity


func stop() -> void:
	alive = false
