extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("flappy_smoke: could not load main scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	var passed := scene.get_node_or_null("World/Bird") != null
	passed = passed and scene.get_node_or_null("UI/HomePanel/Panel/StartButton") != null
	passed = passed and FileAccess.file_exists("res://assets/generated/bird.png")
	scene.queue_free()
	if passed:
		print("flappy_smoke: OK")
		quit(0)
	else:
		push_error("flappy_smoke: FAILED")
		quit(1)
