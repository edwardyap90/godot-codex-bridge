extends RefCounted

const ASSET_DIR := "res://assets/generated"


static func ensure_assets() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET_DIR))
	_save_floor()
	_save_wall()
	_save_player()
	_save_enemy()
	_save_bullet()
	_save_key()
	_save_door_closed()
	_save_door_open()
	_save_rune()


static func _save_floor() -> void:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.13, 0.16, 0.21, 1.0))
	_draw_rect(image, Rect2i(0, 0, 64, 2), Color(0.2, 0.23, 0.3, 1.0))
	_draw_rect(image, Rect2i(0, 0, 2, 64), Color(0.08, 0.1, 0.14, 1.0))
	_draw_rect(image, Rect2i(18, 22, 26, 3), Color(0.18, 0.21, 0.28, 1.0))
	_draw_rect(image, Rect2i(8, 48, 18, 2), Color(0.08, 0.1, 0.14, 0.75))
	_save_png(image, "floor.png")


static func _save_wall() -> void:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.22, 0.24, 0.31, 1.0))
	for y in range(0, 64, 16):
		_draw_rect(image, Rect2i(0, y, 64, 2), Color(0.08, 0.09, 0.13, 0.95))
	for y in range(0, 64, 32):
		_draw_rect(image, Rect2i(30, y, 2, 16), Color(0.08, 0.09, 0.13, 0.95))
		_draw_rect(image, Rect2i(12, y + 16, 2, 16), Color(0.08, 0.09, 0.13, 0.95))
	_draw_rect(image, Rect2i(0, 0, 64, 5), Color(0.34, 0.36, 0.44, 1.0))
	_save_png(image, "wall.png")


static func _save_player() -> void:
	var image := _transparent_image(72, 72)
	_draw_circle(image, Vector2i(36, 36), 25, Color(0.25, 0.64, 1.0, 1.0))
	_draw_circle(image, Vector2i(36, 36), 17, Color(0.46, 0.82, 1.0, 1.0))
	_draw_rect(image, Rect2i(32, 10, 8, 36), Color(0.93, 0.97, 1.0, 1.0))
	_draw_rect(image, Rect2i(24, 45, 24, 7), Color(0.08, 0.12, 0.18, 0.85))
	_draw_circle(image, Vector2i(28, 30), 4, Color(0.02, 0.04, 0.08, 1.0))
	_draw_circle(image, Vector2i(44, 30), 4, Color(0.02, 0.04, 0.08, 1.0))
	_save_png(image, "player.png")


static func _save_enemy() -> void:
	var image := _transparent_image(72, 72)
	_draw_circle(image, Vector2i(36, 38), 25, Color(0.95, 0.29, 0.22, 1.0))
	_draw_circle(image, Vector2i(36, 38), 15, Color(0.64, 0.1, 0.16, 1.0))
	_draw_triangle(image, Vector2i(18, 20), Vector2i(28, 2), Vector2i(33, 26), Color(1.0, 0.71, 0.36, 1.0))
	_draw_triangle(image, Vector2i(54, 20), Vector2i(44, 2), Vector2i(39, 26), Color(1.0, 0.71, 0.36, 1.0))
	_draw_circle(image, Vector2i(28, 34), 4, Color(1.0, 0.91, 0.25, 1.0))
	_draw_circle(image, Vector2i(44, 34), 4, Color(1.0, 0.91, 0.25, 1.0))
	_save_png(image, "enemy.png")


static func _save_bullet() -> void:
	var image := _transparent_image(32, 32)
	_draw_circle(image, Vector2i(16, 16), 11, Color(0.5, 0.94, 1.0, 0.95))
	_draw_circle(image, Vector2i(16, 16), 5, Color(1.0, 1.0, 1.0, 1.0))
	_save_png(image, "bullet.png")


static func _save_key() -> void:
	var image := _transparent_image(56, 56)
	_draw_circle(image, Vector2i(18, 28), 12, Color(1.0, 0.79, 0.18, 1.0))
	_draw_circle(image, Vector2i(18, 28), 6, Color(0, 0, 0, 0))
	_draw_rect(image, Rect2i(28, 25, 22, 7), Color(1.0, 0.79, 0.18, 1.0))
	_draw_rect(image, Rect2i(43, 31, 5, 11), Color(1.0, 0.79, 0.18, 1.0))
	_draw_rect(image, Rect2i(35, 31, 5, 8), Color(1.0, 0.79, 0.18, 1.0))
	_save_png(image, "key.png")


static func _save_door_closed() -> void:
	var image := _transparent_image(96, 128)
	_draw_rect(image, Rect2i(12, 8, 72, 112), Color(0.34, 0.18, 0.09, 1.0))
	_draw_rect(image, Rect2i(18, 16, 60, 96), Color(0.49, 0.26, 0.12, 1.0))
	_draw_rect(image, Rect2i(44, 16, 5, 96), Color(0.2, 0.1, 0.05, 0.75))
	_draw_circle(image, Vector2i(62, 64), 5, Color(1.0, 0.75, 0.22, 1.0))
	_save_png(image, "door_closed.png")


static func _save_door_open() -> void:
	var image := _transparent_image(96, 128)
	_draw_rect(image, Rect2i(12, 8, 72, 112), Color(0.08, 0.12, 0.18, 1.0))
	_draw_rect(image, Rect2i(22, 18, 44, 92), Color(0.13, 0.3, 0.39, 1.0))
	_draw_rect(image, Rect2i(18, 16, 12, 96), Color(0.52, 0.28, 0.12, 1.0))
	_draw_circle(image, Vector2i(48, 64), 18, Color(0.48, 0.91, 1.0, 0.28))
	_save_png(image, "door_open.png")


static func _save_rune() -> void:
	var image := _transparent_image(96, 96)
	_draw_circle(image, Vector2i(48, 48), 34, Color(0.44, 0.22, 0.86, 0.52))
	_draw_circle(image, Vector2i(48, 48), 23, Color(0.64, 0.86, 1.0, 0.45))
	_draw_rect(image, Rect2i(44, 22, 8, 52), Color(0.86, 0.96, 1.0, 0.88))
	_draw_rect(image, Rect2i(24, 44, 48, 8), Color(0.86, 0.96, 1.0, 0.88))
	_save_png(image, "rune.png")


static func _transparent_image(width: int, height: int) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


static func _save_png(image: Image, file_name: String) -> void:
	var path := ProjectSettings.globalize_path(ASSET_DIR.path_join(file_name))
	var error := image.save_png(path)
	if error != OK:
		push_warning("Could not save generated asset " + file_name + ": " + error_string(error))


static func _draw_rect(image: Image, rect: Rect2i, color: Color) -> void:
	var min_x := maxi(rect.position.x, 0)
	var min_y := maxi(rect.position.y, 0)
	var max_x := mini(rect.position.x + rect.size.x, image.get_width())
	var max_y := mini(rect.position.y + rect.size.y, image.get_height())
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			image.set_pixel(x, y, color)


static func _draw_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	var radius_squared := radius * radius
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy <= radius_squared:
				image.set_pixel(x, y, color)


static func _draw_triangle(image: Image, a: Vector2i, b: Vector2i, c: Vector2i, color: Color) -> void:
	var min_x := maxi(mini(a.x, mini(b.x, c.x)), 0)
	var max_x := mini(maxi(a.x, maxi(b.x, c.x)), image.get_width() - 1)
	var min_y := maxi(mini(a.y, mini(b.y, c.y)), 0)
	var max_y := mini(maxi(a.y, maxi(b.y, c.y)), image.get_height() - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _point_in_triangle(Vector2(x, y), Vector2(a), Vector2(b), Vector2(c)):
				image.set_pixel(x, y, color)


static func _point_in_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var area := _triangle_sign(point, a, b)
	var area_2 := _triangle_sign(point, b, c)
	var area_3 := _triangle_sign(point, c, a)
	var has_negative := area < 0.0 or area_2 < 0.0 or area_3 < 0.0
	var has_positive := area > 0.0 or area_2 > 0.0 or area_3 > 0.0
	return not (has_negative and has_positive)


static func _triangle_sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
