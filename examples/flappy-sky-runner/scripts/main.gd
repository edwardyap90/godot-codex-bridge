extends Node2D

const AssetGenerator = preload("res://scripts/asset_generator.gd")

const VIEWPORT_SIZE := Vector2(480, 720)
const BIRD_START := Vector2(142, 330)
const BIRD_RADIUS := 22.0
const GROUND_Y := 640.0
const PIPE_WIDTH := 112.0
const PIPE_HEIGHT := 520.0
const PIPE_GAP := 184.0
const PIPE_SPEED := 185.0
const PIPE_INTERVAL := 1.38
const SAVE_PATH := "user://flappy_sky_runner.cfg"

@onready var background: Sprite2D = $Background
@onready var world: Node2D = $World
@onready var cloud_layer: Node2D = $World/CloudLayer
@onready var pipe_layer: Node2D = $World/PipeLayer
@onready var bird = $World/Bird
@onready var bird_sprite: Sprite2D = $World/Bird/Sprite2D
@onready var ground_a: Sprite2D = $World/GroundA
@onready var ground_b: Sprite2D = $World/GroundB
@onready var score_label: Label = $UI/HUD/ScoreLabel
@onready var best_label: Label = $UI/HUD/BestLabel
@onready var pause_button: Button = $UI/HUD/PauseButton
@onready var home_panel: Control = $UI/HomePanel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var pause_overlay: Control = $UI/PauseOverlay
@onready var final_score_label: Label = $UI/GameOverPanel/Panel/FinalScoreLabel
@onready var best_game_over_label: Label = $UI/GameOverPanel/Panel/BestScoreLabel
@onready var start_button: Button = $UI/HomePanel/Panel/StartButton
@onready var retry_button: Button = $UI/GameOverPanel/Panel/RetryButton
@onready var resume_button: Button = $UI/PauseOverlay/Panel/ResumeButton
@onready var pause_retry_button: Button = $UI/PauseOverlay/Panel/PauseRetryButton

var rng := RandomNumberGenerator.new()
var pipe_texture: Texture2D
var cloud_texture: Texture2D
var state := "home"
var score := 0
var best_score := 0
var pipe_timer := 0.0
var ground_scroll := 0.0
var cloud_scroll_speed := 26.0


func _ready() -> void:
	rng.randomize()
	AssetGenerator.ensure_assets()
	_load_textures()
	_load_best_score()
	_setup_buttons()
	_setup_clouds()
	_show_home()


func _process(delta: float) -> void:
	if state == "home":
		_bob_bird(delta)
		_scroll_ground(delta * 0.35)
		_scroll_clouds(delta)
		return

	if state != "playing":
		return

	pipe_timer -= delta
	if pipe_timer <= 0.0:
		_spawn_pipe_pair()
		pipe_timer = PIPE_INTERVAL

	_move_pipes(delta)
	_scroll_ground(delta)
	_scroll_clouds(delta)
	_check_collisions()
	_update_score_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flap") or event.is_action_pressed("ui_accept"):
		if state == "home" or state == "game_over":
			_start_game()
		elif state == "playing":
			bird.flap()
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
	resume_button.pressed.connect(_resume_game)
	pause_retry_button.pressed.connect(_start_game)
	pause_button.pressed.connect(_pause_game)


func _load_textures() -> void:
	background.texture = _texture_from_png("res://assets/generated/sky_background.png")
	bird_sprite.texture = _texture_from_png("res://assets/generated/bird.png")
	pipe_texture = _texture_from_png("res://assets/generated/pipe.png")
	cloud_texture = _texture_from_png("res://assets/generated/cloud.png")
	ground_a.texture = _texture_from_png("res://assets/generated/ground.png")
	ground_b.texture = ground_a.texture
	ground_a.position = Vector2(0, GROUND_Y)
	ground_b.position = Vector2(480, GROUND_Y)


func _texture_from_png(path: String) -> Texture2D:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("Could not load texture " + path + ": " + error_string(error))
		return null
	return ImageTexture.create_from_image(image)


func _show_home() -> void:
	state = "home"
	score = 0
	pipe_timer = 0.0
	_clear_pipes()
	bird.reset(BIRD_START)
	bird.stop()
	home_panel.visible = true
	game_over_panel.visible = false
	pause_overlay.visible = false
	pause_button.visible = false
	_update_score_labels()


func _start_game() -> void:
	state = "playing"
	score = 0
	pipe_timer = 0.25
	_clear_pipes()
	bird.reset(BIRD_START)
	home_panel.visible = false
	game_over_panel.visible = false
	pause_overlay.visible = false
	pause_button.visible = true
	_update_score_labels()
	bird.flap()


func _pause_game() -> void:
	if state != "playing":
		return
	state = "paused"
	bird.stop()
	pause_overlay.visible = true
	pause_button.visible = false


func _resume_game() -> void:
	if state != "paused":
		return
	state = "playing"
	bird.alive = true
	pause_overlay.visible = false
	pause_button.visible = true


func _game_over() -> void:
	if state == "game_over":
		return
	state = "game_over"
	bird.stop()
	pause_button.visible = false
	if score > best_score:
		best_score = score
		_save_best_score()
	final_score_label.text = "Score: " + str(score)
	best_game_over_label.text = "Best: " + str(best_score)
	game_over_panel.visible = true
	pause_overlay.visible = false
	_update_score_labels()


func _spawn_pipe_pair() -> void:
	var pair := Node2D.new()
	pair.name = "PipePair"
	pair.position = Vector2(560, 0)
	var gap_y := rng.randf_range(210.0, 500.0)
	pair.set_meta("gap_y", gap_y)
	pair.set_meta("scored", false)

	var top_pipe := Sprite2D.new()
	top_pipe.name = "TopPipe"
	top_pipe.texture = pipe_texture
	top_pipe.flip_v = true
	top_pipe.position = Vector2(0, gap_y - PIPE_GAP * 0.5 - PIPE_HEIGHT * 0.5)
	pair.add_child(top_pipe)

	var bottom_pipe := Sprite2D.new()
	bottom_pipe.name = "BottomPipe"
	bottom_pipe.texture = pipe_texture
	bottom_pipe.position = Vector2(0, gap_y + PIPE_GAP * 0.5 + PIPE_HEIGHT * 0.5)
	pair.add_child(bottom_pipe)

	pipe_layer.add_child(pair)


func _move_pipes(delta: float) -> void:
	for pair in pipe_layer.get_children():
		if not pair is Node2D:
			continue
		var pipe_pair := pair as Node2D
		pipe_pair.position.x -= PIPE_SPEED * delta
		if not bool(pipe_pair.get_meta("scored")) and pipe_pair.position.x + PIPE_WIDTH * 0.5 < bird.position.x:
			pipe_pair.set_meta("scored", true)
			score += 1
		if pipe_pair.position.x < -100.0:
			pipe_pair.queue_free()


func _check_collisions() -> void:
	if bird.position.y > GROUND_Y - BIRD_RADIUS or bird.position.y < BIRD_RADIUS:
		_game_over()
		return

	for pair in pipe_layer.get_children():
		if not pair is Node2D:
			continue
		var pipe_pair := pair as Node2D
		if absf(pipe_pair.position.x - bird.position.x) > PIPE_WIDTH * 0.5 + BIRD_RADIUS:
			continue
		var gap_y := float(pipe_pair.get_meta("gap_y"))
		var safe_top := gap_y - PIPE_GAP * 0.5 + BIRD_RADIUS
		var safe_bottom := gap_y + PIPE_GAP * 0.5 - BIRD_RADIUS
		if bird.position.y < safe_top or bird.position.y > safe_bottom:
			_game_over()
			return


func _clear_pipes() -> void:
	for child in pipe_layer.get_children():
		child.queue_free()


func _setup_clouds() -> void:
	for child in cloud_layer.get_children():
		child.queue_free()
	for index in range(6):
		var cloud := Sprite2D.new()
		cloud.name = "Cloud" + str(index + 1)
		cloud.texture = cloud_texture
		cloud.scale = Vector2.ONE * rng.randf_range(0.55, 1.05)
		cloud.position = Vector2(rng.randf_range(-80.0, 560.0), rng.randf_range(70.0, 420.0))
		cloud.modulate = Color(1, 1, 1, rng.randf_range(0.38, 0.75))
		cloud_layer.add_child(cloud)


func _scroll_clouds(delta: float) -> void:
	for child in cloud_layer.get_children():
		if not child is Sprite2D:
			continue
		var cloud := child as Sprite2D
		cloud.position.x -= cloud_scroll_speed * delta * cloud.scale.x
		if cloud.position.x < -150.0:
			cloud.position.x = 570.0
			cloud.position.y = rng.randf_range(70.0, 420.0)


func _scroll_ground(delta: float) -> void:
	ground_scroll = fmod(ground_scroll + PIPE_SPEED * delta, 480.0)
	ground_a.position.x = -ground_scroll
	ground_b.position.x = 480.0 - ground_scroll


func _bob_bird(delta: float) -> void:
	bird.position = BIRD_START + Vector2(0, sin(Time.get_ticks_msec() / 260.0) * 8.0)
	bird.rotation_degrees = sin(Time.get_ticks_msec() / 420.0) * 5.0


func _update_score_labels() -> void:
	score_label.text = str(score)
	best_label.text = "Best " + str(best_score)


func _load_best_score() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		best_score = int(config.get_value("score", "best", 0))


func _save_best_score() -> void:
	var config := ConfigFile.new()
	config.set_value("score", "best", best_score)
	config.save(SAVE_PATH)
