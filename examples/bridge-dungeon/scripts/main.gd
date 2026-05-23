extends Node2D

const AssetGenerator = preload("res://scripts/asset_generator.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const BulletScript = preload("res://scripts/bullet.gd")

const VIEWPORT_SIZE := Vector2(960, 540)
const LEVEL_BOUNDS := Rect2(Vector2.ZERO, Vector2(1600, 960))
const PLAYER_START := Vector2(160, 480)
const KEY_SCORE := 250
const FLOOR_CLEAR_SCORE := 500
const DEPTH_SCORE_STEP := 100
const HEALTH_RESTORE_PER_DEPTH := 1
const BASE_ENEMY_COUNT := 4
const MAX_ENEMY_COUNT := 12
const MAX_ENEMY_DIFFICULTY := 8
const DOOR_POSITIONS := [
	Vector2(1450, 480),
	Vector2(1440, 180),
	Vector2(1260, 780),
	Vector2(760, 150),
]
const KEY_POSITIONS := [
	Vector2(820, 740),
	Vector2(1350, 240),
	Vector2(500, 760),
	Vector2(1030, 130),
]
const ENEMY_SPAWN_POOL := [
	Vector2(520, 220),
	Vector2(980, 280),
	Vector2(700, 620),
	Vector2(1220, 720),
	Vector2(1400, 210),
	Vector2(260, 760),
	Vector2(780, 150),
	Vector2(1040, 800),
	Vector2(1320, 540),
	Vector2(430, 760),
	Vector2(1470, 780),
	Vector2(760, 430),
]

@onready var world: Node2D = $World
@onready var floor_layer: Node2D = $World/FloorLayer
@onready var wall_layer: Node2D = $World/WallLayer
@onready var prop_layer: Node2D = $World/PropLayer
@onready var bullet_layer: Node2D = $World/BulletLayer
@onready var enemy_layer: Node2D = $World/EnemyLayer
@onready var player = $World/Player
@onready var camera: Camera2D = $World/Player/Camera2D
@onready var hud: Control = $UI/HUD
@onready var health_label: Label = $UI/HUD/HealthLabel
@onready var key_label: Label = $UI/HUD/KeyLabel
@onready var score_label: Label = $UI/HUD/ScoreLabel
@onready var objective_label: Label = $UI/HUD/ObjectiveLabel
@onready var pause_button: Button = $UI/HUD/PauseButton
@onready var home_panel: Control = $UI/HomePanel
@onready var start_button: Button = $UI/HomePanel/Panel/StartButton
@onready var result_panel: Control = $UI/ResultPanel
@onready var result_title: Label = $UI/ResultPanel/Panel/TitleLabel
@onready var result_summary: Label = $UI/ResultPanel/Panel/SummaryLabel
@onready var retry_button: Button = $UI/ResultPanel/Panel/RetryButton
@onready var pause_overlay: Control = $UI/PauseOverlay
@onready var resume_button: Button = $UI/PauseOverlay/Panel/ResumeButton
@onready var pause_retry_button: Button = $UI/PauseOverlay/Panel/PauseRetryButton

var textures: Dictionary = {}
var wall_rects: Array[Rect2] = []
var key_sprite: Sprite2D
var door_sprite: Sprite2D
var rune_sprite: Sprite2D
var state := "home"
var has_key := false
var score := 0
var shoot_cooldown := 0.0
var player_hit_cooldown := 0.0
var elapsed_time := 0.0
var depth := 1
var current_key_position = KEY_POSITIONS[0]
var current_door_position = DOOR_POSITIONS[0]


func _ready() -> void:
	AssetGenerator.ensure_assets()
	_load_textures()
	_setup_buttons()
	_setup_level()
	_setup_player()
	_show_home()


func _process(delta: float) -> void:
	if state == "home":
		_animate_home(delta)
		return
	if state != "playing":
		return

	elapsed_time += delta
	shoot_cooldown = maxf(shoot_cooldown - delta, 0.0)
	player_hit_cooldown = maxf(player_hit_cooldown - delta, 0.0)
	_update_player(delta)
	_update_bullets(delta)
	_update_enemies(delta)
	_update_pickups()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept"):
		if state == "home" or state == "game_over" or state == "won":
			_start_game()
		elif state == "playing":
			_try_shoot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_game"):
		if state == "playing":
			_pause_game()
		elif state == "paused":
			_resume_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart_game"):
		_start_game()
		get_viewport().set_input_as_handled()


func _setup_buttons() -> void:
	start_button.pressed.connect(_start_game)
	retry_button.pressed.connect(_start_game)
	pause_button.pressed.connect(_pause_game)
	resume_button.pressed.connect(_resume_game)
	pause_retry_button.pressed.connect(_start_game)


func _load_textures() -> void:
	for item in ["floor", "wall", "player", "enemy", "bullet", "key", "door_closed", "door_open", "rune"]:
		textures[item] = _texture_from_png("res://assets/generated/" + item + ".png")


func _texture_from_png(path: String) -> Texture2D:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("Could not load texture " + path + ": " + error_string(error))
		return null
	return ImageTexture.create_from_image(image)


func _setup_level() -> void:
	wall_rects = [
		Rect2(0, 0, 1600, 64),
		Rect2(0, 896, 1600, 64),
		Rect2(0, 0, 64, 960),
		Rect2(1536, 0, 64, 960),
		Rect2(320, 128, 64, 520),
		Rect2(576, 0, 64, 360),
		Rect2(576, 520, 64, 376),
		Rect2(900, 170, 64, 540),
		Rect2(1160, 64, 64, 390),
		Rect2(1160, 610, 64, 286),
	]
	_build_floor()
	_build_walls()
	_build_props()


func _setup_player() -> void:
	player.configure(textures["player"])
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = int(LEVEL_BOUNDS.position.x)
	camera.limit_top = int(LEVEL_BOUNDS.position.y)
	camera.limit_right = int(LEVEL_BOUNDS.position.x + LEVEL_BOUNDS.size.x)
	camera.limit_bottom = int(LEVEL_BOUNDS.position.y + LEVEL_BOUNDS.size.y)


func _build_floor() -> void:
	for child in floor_layer.get_children():
		child.queue_free()
	for y in range(0, int(LEVEL_BOUNDS.size.y), 64):
		for x in range(0, int(LEVEL_BOUNDS.size.x), 64):
			var tile := Sprite2D.new()
			tile.name = "FloorTile"
			tile.texture = textures["floor"]
			tile.centered = false
			tile.position = Vector2(x, y)
			floor_layer.add_child(tile)


func _build_walls() -> void:
	for child in wall_layer.get_children():
		child.queue_free()
	for index in range(wall_rects.size()):
		var rect := wall_rects[index]
		var wall := Sprite2D.new()
		wall.name = "Wall" + str(index + 1)
		wall.texture = textures["wall"]
		wall.centered = false
		wall.position = rect.position
		wall.scale = rect.size / Vector2(64, 64)
		wall.z_index = 8
		wall_layer.add_child(wall)


func _build_props() -> void:
	for child in prop_layer.get_children():
		child.free()
	key_sprite = Sprite2D.new()
	key_sprite.name = "DungeonKey"
	key_sprite.texture = textures["key"]
	key_sprite.position = current_key_position
	key_sprite.z_index = 12
	prop_layer.add_child(key_sprite)

	door_sprite = Sprite2D.new()
	door_sprite.name = "ExitDoor"
	door_sprite.texture = textures["door_closed"]
	door_sprite.position = current_door_position
	door_sprite.z_index = 9
	prop_layer.add_child(door_sprite)

	rune_sprite = Sprite2D.new()
	rune_sprite.name = "GoalRune"
	rune_sprite.texture = textures["rune"]
	rune_sprite.position = current_door_position + Vector2(0, 70)
	rune_sprite.z_index = 7
	prop_layer.add_child(rune_sprite)


func _show_home() -> void:
	state = "home"
	has_key = false
	score = 0
	depth = 1
	elapsed_time = 0.0
	_set_depth_positions()
	_clear_runtime_nodes()
	_build_props()
	player.reset(PLAYER_START)
	player.set_active(false)
	hud.visible = false
	home_panel.visible = true
	result_panel.visible = false
	pause_overlay.visible = false
	_update_hud()


func _start_game() -> void:
	state = "playing"
	has_key = false
	score = 0
	depth = 1
	shoot_cooldown = 0.0
	player_hit_cooldown = 0.0
	elapsed_time = 0.0
	_set_depth_positions()
	_clear_runtime_nodes()
	_build_props()
	_spawn_enemies()
	player.reset(PLAYER_START)
	hud.visible = true
	home_panel.visible = false
	result_panel.visible = false
	pause_overlay.visible = false
	pause_button.visible = true
	_update_hud()


func _pause_game() -> void:
	if state != "playing":
		return
	state = "paused"
	player.set_active(false)
	pause_overlay.visible = true
	pause_button.visible = false


func _resume_game() -> void:
	if state != "paused":
		return
	state = "playing"
	player.set_active(true)
	pause_overlay.visible = false
	pause_button.visible = true


func _win_game() -> void:
	_advance_depth()


func _game_over() -> void:
	state = "game_over"
	player.set_active(false)
	pause_button.visible = false
	result_title.text = "Depth Run Ended"
	result_summary.text = "The sentries stopped you at depth " + str(depth) + ".\nScore: " + str(score) + "  Time: " + _format_time(elapsed_time)
	result_panel.visible = true
	pause_overlay.visible = false


func _update_player(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.move(input_vector, delta, LEVEL_BOUNDS, wall_rects)
	player.aim_at(get_global_mouse_position())


func _try_shoot() -> void:
	if shoot_cooldown > 0.0:
		return
	shoot_cooldown = 0.18
	var direction: Vector2 = get_global_mouse_position() - player.global_position
	if direction.length() < 12.0:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var bullet = BulletScript.new()
	bullet.name = "SpellBolt"
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	bullet.add_child(sprite)
	bullet_layer.add_child(bullet)
	bullet.configure(textures["bullet"], player.position + direction * 34.0, direction)


func _update_bullets(delta: float) -> void:
	for child in bullet_layer.get_children():
		var bullet = child
		if bullet.is_queued_for_deletion():
			continue
		if not bullet.step(delta) or _point_hits_wall(bullet.position, bullet.radius):
			bullet.queue_free()
			continue
		for enemy_child in enemy_layer.get_children():
			var enemy = enemy_child
			if enemy.is_queued_for_deletion():
				continue
			if bullet.position.distance_to(enemy.position) <= bullet.radius + enemy.radius:
				enemy.hit(bullet.damage)
				bullet.queue_free()
				break


func _update_enemies(delta: float) -> void:
	for enemy_child in enemy_layer.get_children():
		var enemy = enemy_child
		if enemy.is_queued_for_deletion():
			continue
		enemy.step(delta, player.position, wall_rects)
		if enemy.position.distance_to(player.position) <= enemy.radius + player.radius and player_hit_cooldown <= 0.0:
			player_hit_cooldown = 0.72
			player.hurt(enemy.damage)


func _update_pickups() -> void:
	if not has_key and key_sprite != null and player.position.distance_to(key_sprite.position) <= 46.0:
		has_key = true
		key_sprite.visible = false
		door_sprite.texture = textures["door_open"]
		score += KEY_SCORE
	if has_key and door_sprite != null and player.position.distance_to(door_sprite.position) <= 58.0:
		_win_game()


func _set_depth_positions() -> void:
	current_key_position = KEY_POSITIONS[(depth - 1) % KEY_POSITIONS.size()]
	current_door_position = DOOR_POSITIONS[(depth - 1) % DOOR_POSITIONS.size()]


func _advance_depth() -> void:
	if state != "playing":
		return
	score += FLOOR_CLEAR_SCORE + depth * DEPTH_SCORE_STEP
	depth += 1
	has_key = false
	shoot_cooldown = 0.0
	player_hit_cooldown = 0.0
	_clear_runtime_nodes()
	_set_depth_positions()
	_build_props()
	_spawn_enemies()
	_restore_player_for_next_depth()
	_update_hud()


func _restore_player_for_next_depth() -> void:
	player.position = PLAYER_START
	player.alive = true
	player.active = true
	player.visible = true
	player.health = mini(player.health + HEALTH_RESTORE_PER_DEPTH, player.max_health)
	player.health_changed.emit(player.health, player.max_health)


func _spawn_enemies() -> void:
	var enemy_count := mini(BASE_ENEMY_COUNT + depth - 1, MAX_ENEMY_COUNT)
	for index in range(enemy_count):
		var enemy = EnemyScript.new()
		enemy.name = "Sentry" + str(index + 1)
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		enemy.add_child(sprite)
		enemy_layer.add_child(enemy)
		var spawn_index := (index + depth - 1) % ENEMY_SPAWN_POOL.size()
		var difficulty := mini(depth - 1 + (index % 3), MAX_ENEMY_DIFFICULTY)
		enemy.configure(textures["enemy"], ENEMY_SPAWN_POOL[spawn_index], difficulty)
		enemy.defeated.connect(_on_enemy_defeated)


func _clear_runtime_nodes() -> void:
	for child in enemy_layer.get_children():
		child.queue_free()
	for child in bullet_layer.get_children():
		child.queue_free()


func _point_hits_wall(point: Vector2, radius: float) -> bool:
	for rect in wall_rects:
		if rect.grow(radius).has_point(point):
			return true
	return false


func _on_enemy_defeated(enemy: Node2D) -> void:
	score += int(enemy.get("score_value"))
	_update_hud()


func _on_player_health_changed(_current: int, _maximum: int) -> void:
	_update_hud()


func _on_player_died() -> void:
	_game_over()


func _update_hud() -> void:
	if health_label == null:
		return
	health_label.text = "HP " + str(player.health) + "/" + str(player.max_health)
	key_label.text = "Key " + ("yes" if has_key else "no")
	score_label.text = "Score " + str(score) + "  Depth " + str(depth)
	if state == "home":
		objective_label.text = "Enter the endless dungeon"
	elif has_key:
		objective_label.text = "Depth " + str(depth) + ": reach the open gate"
	else:
		objective_label.text = "Depth " + str(depth) + ": find the key"


func _animate_home(delta: float) -> void:
	if rune_sprite != null:
		rune_sprite.rotation += delta * 0.4


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return str(total / 60).pad_zeros(2) + ":" + str(total % 60).pad_zeros(2)
