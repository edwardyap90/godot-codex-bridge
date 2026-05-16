extends SceneTree

const OUT_DIR := "res://showcase_frames"
const FRAME_COUNT := 96
const CAPTURE_EVERY := 2
const VIEW_SIZE := Vector2i(960, 540)

var _scene: Node
var _player: Node2D
var _frame_index := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW_SIZE
	_clean_output_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("showcase capture: could not load main scene")
		quit(1)
		return

	_scene = packed.instantiate()
	root.add_child(_scene)
	await _settle()
	await _capture_hold(10)

	if _scene.has_method("_start_game"):
		_scene.call("_start_game")
	await _settle()
	_player = _scene.get_node_or_null("World/Player") as Node2D
	await _capture_path([
		Vector2(160, 480),
		Vector2(430, 300),
		Vector2(720, 620),
		Vector2(920, 740),
	], 46)
	_force_key_pickup()
	await _capture_path([
		Vector2(920, 740),
		Vector2(1180, 650),
		Vector2(1450, 480),
	], 28)
	_force_win()
	await _capture_hold(12)

	_scene.queue_free()
	print("bridge_dungeon_showcase: wrote " + str(_frame_index) + " frames")
	quit(0)


func _settle() -> void:
	for _i in range(4):
		await process_frame


func _capture_hold(frame_count: int) -> void:
	for _i in range(frame_count):
		await _advance_and_capture()


func _capture_path(points: Array[Vector2], frame_count: int) -> void:
	if _player == null or points.size() < 2:
		await _capture_hold(frame_count)
		return

	for index in range(frame_count):
		var t := float(index) / float(maxi(frame_count - 1, 1))
		var segment_position := t * float(points.size() - 1)
		var segment := mini(int(floor(segment_position)), points.size() - 2)
		var local_t := segment_position - float(segment)
		_player.position = points[segment].lerp(points[segment + 1], local_t)
		if index % 12 == 0 and _scene.has_method("_try_shoot"):
			_scene.call("_try_shoot")
		await _advance_and_capture()


func _advance_and_capture() -> void:
	for _i in range(CAPTURE_EVERY):
		await process_frame
	_capture_frame()


func _capture_frame() -> void:
	var image := root.get_texture().get_image()
	if image.is_empty():
		push_error("showcase capture: empty frame")
		quit(1)
		return
	image.resize(VIEW_SIZE.x, VIEW_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join("frame_%04d.png" % _frame_index))
	var error := image.save_png(path)
	if error != OK:
		push_error("showcase capture: failed to save frame: " + error_string(error))
		quit(1)
		return
	_frame_index += 1


func _force_key_pickup() -> void:
	if _player != null:
		_player.position = Vector2(820, 740)
	if _scene.has_method("_update_pickups"):
		_scene.call("_update_pickups")


func _force_win() -> void:
	if _player != null:
		_player.position = Vector2(1450, 480)
	if _scene.has_method("_update_pickups"):
		_scene.call("_update_pickups")
	if _scene.has_method("_win_game"):
		_scene.call("_win_game")


func _clean_output_dir() -> void:
	var absolute := ProjectSettings.globalize_path(OUT_DIR)
	var dir := DirAccess.open(absolute)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if not dir.current_is_dir():
			dir.remove(file_name)
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)
