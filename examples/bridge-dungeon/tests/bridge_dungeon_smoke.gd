extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("bridge_dungeon_smoke: could not load main scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var passed := scene.get_node_or_null("World/Player") != null
	passed = passed and scene.get_node_or_null("World/Player/Camera2D") != null
	passed = passed and scene.get_node_or_null("UI/HomePanel/Panel/StartButton") != null
	passed = passed and FileAccess.file_exists("res://assets/generated/player.png")
	passed = passed and FileAccess.file_exists("res://assets/generated/enemy.png")
	if scene.has_method("_start_game") and scene.has_method("_advance_depth"):
		scene.call("_start_game")
		await process_frame
		passed = passed and int(scene.get("depth")) == 1
		passed = passed and scene.get_node("World/EnemyLayer").get_child_count() >= 4
		passed = passed and scene.get_node("World/PropLayer").get_node_or_null("DungeonKey") != null
		scene.call("_advance_depth")
		await process_frame
		passed = passed and int(scene.get("depth")) == 2
		passed = passed and str(scene.get("state")) == "playing"
		passed = passed and scene.get_node("World/EnemyLayer").get_child_count() >= 5
		passed = passed and scene.get_node("World/PropLayer").get_node_or_null("DungeonKey") != null
	else:
		passed = false

	scene.queue_free()
	if passed:
		print("bridge_dungeon_smoke: OK")
		quit(0)
	else:
		push_error("bridge_dungeon_smoke: FAILED")
		quit(1)
