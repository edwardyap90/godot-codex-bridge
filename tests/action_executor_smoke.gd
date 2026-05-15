extends SceneTree

const ExecutorScript = preload("res://addons/godot_codex_bridge/action_executor.gd")
const TEST_DIR := "res://tmp_bridge_validation"


func _init() -> void:
	var executor := ExecutorScript.new()
	var result: Dictionary = executor.apply_actions([
		{
			"type": "write_file",
			"path": TEST_DIR + "/test_node.gd",
			"content": "extends Node\n"
		},
		{
			"type": "create_scene",
			"path": TEST_DIR + "/test_scene.tscn",
			"root_type": "Node2D",
			"root_name": "TestScene"
		},
		{
			"type": "write_file",
			"path": "res://addons/godot_codex_bridge/blocked.gd",
			"content": "extends Node\n"
		}
	])

	var results: Array = result.get("results", [])
	var passed: bool = result.get("applied", 0) == 2
	passed = passed and results.size() == 3
	if results.size() == 3:
		passed = passed and bool((results[0] as Dictionary).get("ok", false))
		passed = passed and bool((results[1] as Dictionary).get("ok", false))
		passed = passed and not bool((results[2] as Dictionary).get("ok", false))
		passed = passed and FileAccess.file_exists(TEST_DIR + "/test_node.gd")
		passed = passed and FileAccess.file_exists(TEST_DIR + "/test_scene.tscn")

	_cleanup()

	if passed:
		print("action_executor_smoke: OK")
		quit(0)
	else:
		push_error("action_executor_smoke: FAILED " + JSON.stringify(result))
		quit(1)


func _cleanup() -> void:
	var absolute_dir := ProjectSettings.globalize_path(TEST_DIR)
	var dir := DirAccess.open(absolute_dir)
	if dir == null:
		return

	for file_name in ["test_node.gd", "test_scene.tscn"]:
		if dir.file_exists(file_name):
			dir.remove(file_name)
	DirAccess.remove_absolute(absolute_dir)
