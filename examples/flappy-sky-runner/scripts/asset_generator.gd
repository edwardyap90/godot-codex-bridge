extends RefCounted
class_name AssetGenerator

const ASSET_DIR := "res://assets/generated"


static func ensure_assets() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET_DIR))
	_save_background()
	_save_bird()
	_save_pipe()
	_save_ground()
	_save_cloud()


static func _save_background() -> void:
	var image := Image.create_empty(480, 720, false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		var t := float(y) / float(image.get_height() - 1)
		var color := Color(0.36, 0.78, 1.0).lerp(Color(0.92, 0.96, 1.0), t)
		for x in range(image.get_width()):
			image.set_pixel(x, y, color)
	_draw_circle(image, Vector2i(380, 110), 46, Color(1.0, 0.87, 0.32, 1.0))
	_draw_circle(image, Vector2i(380, 110), 34, Color(1.0, 0.95, 0.55, 1.0))
	_save_png(image, "sky_background.png")


static func _save_bird() -> void:
	var image := _transparent_image(96, 72)
	_draw_ellipse(image, Vector2i(44, 38), Vector2i(32, 24), Color(1.0, 0.77, 0.16, 1.0))
	_draw_ellipse(image, Vector2i(34, 43), Vector2i(18, 13), Color(0.96, 0.49, 0.12, 1.0))
	_draw_ellipse(image, Vector2i(53, 28), Vector2i(16, 13), Color(1.0, 0.9, 0.34, 1.0))
	_draw_triangle(image, Vector2i(73, 36), Vector2i(94, 27), Vector2i(94, 44), Color(1.0, 0.38, 0.16, 1.0))
	_draw_circle(image, Vector2i(59, 29), 7, Color.WHITE)
	_draw_circle(image, Vector2i(62, 30), 3, Color(0.06, 0.08, 0.12, 1.0))
	_draw_rect(image, Rect2i(14, 52, 40, 6), Color(0.77, 0.3, 0.1, 1.0))
	_save_png(image, "bird.png")


static func _save_pipe() -> void:
	var image := _transparent_image(112, 520)
	_draw_rect(image, Rect2i(18, 0, 76, 520), Color(0.19, 0.68, 0.34, 1.0))
	_draw_rect(image, Rect2i(8, 0, 96, 42), Color(0.12, 0.54, 0.27, 1.0))
	_draw_rect(image, Rect2i(8, 478, 96, 42), Color(0.12, 0.54, 0.27, 1.0))
	_draw_rect(image, Rect2i(30, 0, 16, 520), Color(0.4, 0.88, 0.48, 0.8))
	_draw_rect(image, Rect2i(78, 0, 10, 520), Color(0.08, 0.36, 0.18, 0.65))
	_save_png(image, "pipe.png")


static func _save_ground() -> void:
	var image := Image.create_empty(480, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.55, 0.36, 0.18, 1.0))
	_draw_rect(image, Rect2i(0, 0, 480, 26), Color(0.28, 0.72, 0.33, 1.0))
	_draw_rect(image, Rect2i(0, 26, 480, 8), Color(0.16, 0.46, 0.2, 1.0))
	for x in range(0, 480, 24):
		_draw_triangle(image, Vector2i(x, 26), Vector2i(x + 10, 5), Vector2i(x + 22, 26), Color(0.4, 0.84, 0.34, 1.0))
	for x in range(0, 480, 42):
		_draw_rect(image, Rect2i(x, 50, 26, 6), Color(0.66, 0.45, 0.24, 1.0))
	_save_png(image, "ground.png")


static func _save_cloud() -> void:
	var image := _transparent_image(168, 84)
	_draw_circle(image, Vector2i(48, 48), 30, Color(1, 1, 1, 0.92))
	_draw_circle(image, Vector2i(78, 36), 36, Color(1, 1, 1, 0.95))
	_draw_circle(image, Vector2i(112, 48), 28, Color(1, 1, 1, 0.92))
	_draw_rect(image, Rect2i(38, 47, 92, 24), Color(1, 1, 1, 0.92))
	_save_png(image, "cloud.png")


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


static func _draw_ellipse(image: Image, center: Vector2i, radius: Vector2i, color: Color) -> void:
	for y in range(center.y - radius.y, center.y + radius.y + 1):
		for x in range(center.x - radius.x, center.x + radius.x + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var nx := float(x - center.x) / float(radius.x)
			var ny := float(y - center.y) / float(radius.y)
			if nx * nx + ny * ny <= 1.0:
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
