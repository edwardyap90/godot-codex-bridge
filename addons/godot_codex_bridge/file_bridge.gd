@tool
extends Node

const DEFAULT_ROOT := "res://.godot/godot_codex_bridge"
const DEFAULT_POLL_INTERVAL := 0.2

var control_bridge: Node
var enabled := true
var root_path := DEFAULT_ROOT
var inbox_path := DEFAULT_ROOT.path_join("inbox")
var outbox_path := DEFAULT_ROOT.path_join("outbox")
var poll_interval := DEFAULT_POLL_INTERVAL
var _elapsed := 0.0


func setup(p_control_bridge: Node, p_root_path: String = "", p_poll_interval: float = DEFAULT_POLL_INTERVAL) -> void:
	control_bridge = p_control_bridge
	root_path = _configured_root(p_root_path)
	inbox_path = root_path.path_join("inbox")
	outbox_path = root_path.path_join("outbox")
	poll_interval = _configured_poll_interval(p_poll_interval)
	enabled = _file_bridge_enabled()


func _ready() -> void:
	if control_bridge == null:
		push_warning("Godot Codex Bridge file bridge has no control bridge.")
		enabled = false
		set_process(false)
		return

	_ensure_directories()
	set_process(enabled)
	if enabled:
		print("Godot Codex Bridge file bridge watching " + inbox_path)


func _process(delta: float) -> void:
	if not enabled:
		return

	_elapsed += delta
	if _elapsed < poll_interval:
		return
	_elapsed = 0.0
	poll_once()


func poll_once() -> void:
	if not enabled or control_bridge == null:
		return

	_ensure_directories()
	var dir := DirAccess.open(inbox_path)
	if dir == null:
		return

	var files: Array = []
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if file_name.ends_with(".json"):
			files.append(file_name)
	dir.list_dir_end()

	files.sort()
	for file_name in files:
		_process_request_file(file_name)


func bridge_status() -> Dictionary:
	return {
		"transport": "file",
		"enabled": enabled,
		"root": root_path,
		"inbox": inbox_path,
		"outbox": outbox_path,
		"poll_interval": poll_interval
	}


func _process_request_file(file_name: String) -> void:
	var request_id := file_name.get_basename()
	var request_path := inbox_path.path_join(file_name)
	var response_path := outbox_path.path_join(request_id + ".json")
	var file := FileAccess.open(request_path, FileAccess.READ)
	if file == null:
		return

	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	var response: Dictionary
	if typeof(parsed) == TYPE_DICTIONARY:
		var request := parsed as Dictionary
		request_id = _safe_request_id(str(request.get("request_id", request_id)))
		response_path = outbox_path.path_join(request_id + ".json")
		response = control_bridge.handle_request(request)
	else:
		response = {
			"ok": false,
			"message": "Request is not a JSON object.",
			"data": {}
		}

	response["request_id"] = request_id
	_write_response(response_path, response)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))


func _write_response(path: String, response: Dictionary) -> void:
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_warning("Godot Codex Bridge file bridge failed to write " + temporary_path)
		return

	file.store_string(JSON.stringify(response, "\t"))
	file.store_string("\n")
	file.close()

	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
	DirAccess.rename_absolute(absolute_temporary, absolute_path)


func _ensure_directories() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(inbox_path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outbox_path))


func _configured_root(fallback_root: String) -> String:
	var env_root := OS.get_environment("CODEX_GODOT_FILE_BRIDGE_ROOT").strip_edges()
	if not env_root.is_empty():
		return env_root.trim_suffix("/")

	if not fallback_root.strip_edges().is_empty():
		return fallback_root.strip_edges().trim_suffix("/")

	var configured := str(ProjectSettings.get_setting("codex_bridge/file_bridge_root", "")).strip_edges()
	if not configured.is_empty():
		return configured.trim_suffix("/")

	return DEFAULT_ROOT


func _file_bridge_enabled() -> bool:
	var raw_enabled := OS.get_environment("CODEX_GODOT_FILE_BRIDGE_ENABLED").strip_edges().to_lower()
	if raw_enabled in ["1", "true", "yes", "on"]:
		return true
	if raw_enabled in ["0", "false", "no", "off"]:
		return false
	return bool(ProjectSettings.get_setting("codex_bridge/file_bridge_enabled", true))


func _configured_poll_interval(fallback_interval: float) -> float:
	var raw_interval := OS.get_environment("CODEX_GODOT_FILE_BRIDGE_POLL_INTERVAL_SEC").strip_edges()
	if raw_interval.is_valid_float():
		return maxf(float(raw_interval), 0.05)

	var configured := float(ProjectSettings.get_setting("codex_bridge/file_bridge_poll_interval_sec", fallback_interval))
	return maxf(configured, 0.05)


func _safe_request_id(raw_id: String) -> String:
	var value := raw_id.strip_edges()
	if value.is_empty():
		value = str(Time.get_unix_time_from_system())

	var safe := ""
	for index in value.length():
		var character := value.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int() or character in ["-", "_"]:
			safe += character
		else:
			safe += "_"
	return safe
