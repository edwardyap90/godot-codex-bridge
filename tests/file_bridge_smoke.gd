extends SceneTree

const BridgeScript = preload("res://addons/godot_codex_bridge/control_bridge.gd")
const FileBridgeScript = preload("res://addons/godot_codex_bridge/file_bridge.gd")
const TEST_ROOT := "user://godot_file_bridge_smoke"


class FakeEditorInterface:
	extends RefCounted

	var scene_root: Node

	func _init(p_scene_root: Node) -> void:
		scene_root = p_scene_root

	func get_edited_scene_root() -> Node:
		return scene_root


func _init() -> void:
	_cleanup()

	var scene_root := Node2D.new()
	scene_root.name = "TestScene"
	root.add_child(scene_root)

	var bridge := BridgeScript.new()
	bridge.setup(FakeEditorInterface.new(scene_root), 9877)
	bridge.token = ""

	var file_bridge := FileBridgeScript.new()
	file_bridge.setup(bridge, TEST_ROOT, 0.05)
	file_bridge.enabled = true

	var inbox := TEST_ROOT.path_join("inbox")
	var outbox := TEST_ROOT.path_join("outbox")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(inbox))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outbox))

	var request_path := inbox.path_join("smoke.json")
	var request := FileAccess.open(request_path, FileAccess.WRITE)
	request.store_string(JSON.stringify({
		"request_id": "smoke",
		"command": "get_project_info"
	}))
	request.close()

	file_bridge.poll_once()
	file_bridge.poll_once()

	var response_path := outbox.path_join("smoke.json")
	var response_text := ""
	if FileAccess.file_exists(response_path):
		response_text = FileAccess.get_file_as_string(response_path)
	var parsed = JSON.parse_string(response_text)
	var response := parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
	var data := response.get("data", {}) as Dictionary
	var project := data.get("project", {}) as Dictionary

	var passed := bool(response.get("ok", false))
	passed = passed and str(response.get("request_id", "")) == "smoke"
	passed = passed and not str(project.get("name", "")).is_empty()
	passed = passed and not FileAccess.file_exists(request_path)
	passed = passed and bridge.history.size() == 1

	file_bridge.free()
	bridge.free()
	scene_root.free()
	_cleanup()

	if passed:
		print("file_bridge_smoke: OK")
		quit(0)
	else:
		push_error("file_bridge_smoke: FAILED " + response_text)
		quit(1)


func _cleanup() -> void:
	var inbox := TEST_ROOT.path_join("inbox")
	var outbox := TEST_ROOT.path_join("outbox")
	_remove_file(inbox.path_join("smoke.json"))
	_remove_file(outbox.path_join("smoke.json"))
	_remove_file(outbox.path_join("smoke.json.tmp"))
	_remove_dir(inbox)
	_remove_dir(outbox)
	_remove_dir(TEST_ROOT)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_dir(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
