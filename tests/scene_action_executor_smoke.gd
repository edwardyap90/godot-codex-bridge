extends SceneTree

const ExecutorScript = preload("res://addons/godot_codex_bridge/action_executor.gd")
const TEST_DIR := "res://tmp_bridge_scene_validation"


class FakeEditorInterface:
	extends RefCounted

	var scene_root: Node
	var dirty_count := 0

	func _init(p_scene_root: Node) -> void:
		scene_root = p_scene_root

	func get_edited_scene_root() -> Node:
		return scene_root

	func mark_scene_as_unsaved() -> void:
		dirty_count += 1


func _init() -> void:
	var scene_root := Node2D.new()
	scene_root.name = "TestScene"
	root.add_child(scene_root)

	var fake_editor := FakeEditorInterface.new(scene_root)
	var executor := ExecutorScript.new()
	executor.setup(fake_editor)

	var result: Dictionary = executor.apply_actions([
		{
			"type": "make_dir",
			"path": TEST_DIR
		},
		{
			"type": "write_file",
			"path": TEST_DIR + "/receiver.gd",
			"content": "extends Node\n\nfunc _on_child_ready() -> void:\n\tpass\n"
		},
		{
			"type": "add_node",
			"parent_path": ".",
			"node_type": "Node2D",
			"name": "Child",
			"properties": {
				"position": {
					"type": "Vector2",
					"x": 10,
					"y": 20
				}
			}
		},
		{
			"type": "add_node",
			"parent_path": ".",
			"node_type": "Node",
			"name": "Receiver",
			"script_path": TEST_DIR + "/receiver.gd"
		},
		{
			"type": "set_property",
			"node_path": "Child",
			"property": "position",
			"value": {
				"type": "Vector2",
				"x": 30,
				"y": 40
			}
		},
		{
			"type": "connect_signal",
			"source_path": "Child",
			"signal": "ready",
			"target_path": "Receiver",
			"method": "_on_child_ready"
		}
	])

	var child := scene_root.get_node_or_null("Child") as Node2D
	var receiver := scene_root.get_node_or_null("Receiver")
	var connection_ok := false
	if child != null and receiver != null:
		connection_ok = child.is_connected("ready", Callable(receiver, "_on_child_ready"))

	var passed: bool = result.get("applied", 0) == 6
	passed = passed and child != null
	passed = passed and child.position == Vector2(30, 40)
	passed = passed and receiver != null
	passed = passed and receiver.has_method("_on_child_ready")
	passed = passed and connection_ok
	passed = passed and fake_editor.dirty_count >= 3

	scene_root.queue_free()
	_cleanup()

	if passed:
		print("scene_action_executor_smoke: OK")
		quit(0)
	else:
		push_error("scene_action_executor_smoke: FAILED " + JSON.stringify(result))
		quit(1)


func _cleanup() -> void:
	var absolute_dir := ProjectSettings.globalize_path(TEST_DIR)
	var dir := DirAccess.open(absolute_dir)
	if dir == null:
		return

	if dir.file_exists("receiver.gd"):
		dir.remove("receiver.gd")
	DirAccess.remove_absolute(absolute_dir)
