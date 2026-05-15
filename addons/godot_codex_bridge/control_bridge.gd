@tool
extends Node

const ActionExecutor = preload("res://addons/godot_codex_bridge/action_executor.gd")

const DEFAULT_PORT := 8765
const LOCALHOST := "127.0.0.1"
const HISTORY_LIMIT := 50
const RUN_REPORT_LIMIT := 20
const PENDING_ACTION_LIMIT := 20
const SNAPSHOT_LIMIT := 30
const PROPERTY_LIMIT_DEFAULT := 120
const RESOURCE_FILE_LIMIT_DEFAULT := 300
const PLUGIN_ROOT := "res://addons/godot_codex_bridge"

signal request_handled(command: String, ok: bool, message: String, request_id: String)

var editor_interface = null
var executor: RefCounted
var server := TCPServer.new()
var clients: Array = []
var port := DEFAULT_PORT
var token := ""
var running := false
var last_request: Dictionary = {}
var history: Array = []
var last_run_report: Dictionary = {}
var run_reports: Array = []
var pending_action_batches: Array = []
var snapshots: Array = []


func setup(p_editor_interface, p_port: int = DEFAULT_PORT) -> void:
	editor_interface = p_editor_interface
	executor = ActionExecutor.new()
	executor.setup(editor_interface)
	port = _configured_port(p_port)
	token = OS.get_environment("CODEX_GODOT_BRIDGE_TOKEN").strip_edges()
	_load_pending_actions()
	_load_snapshot_index()


func _ready() -> void:
	if executor == null:
		setup(editor_interface)
	if _tcp_bridge_enabled():
		_start_server()
	set_process(_tcp_bridge_enabled())


func _exit_tree() -> void:
	_stop_server()


func _process(_delta: float) -> void:
	if not running:
		return
	_accept_pending_clients()
	_poll_clients()


func handle_request(request: Dictionary) -> Dictionary:
	var command := str(request.get("command", request.get("type", ""))).strip_edges()

	var auth_error := _authorize(request)
	if not auth_error.is_empty():
		return _finish_request(command, request, _response(false, auth_error))

	var target_error := _validate_project_target(request)
	if not target_error.is_empty():
		return _finish_request(command, request, _response(false, target_error, {
			"project": _project_identity()
		}))

	return _finish_request(command, request, _handle_command(command, request))


func _handle_command(command: String, request: Dictionary) -> Dictionary:
	match command:
		"ping":
			return _response(true, "pong", {
				"project": ProjectSettings.get_setting("application/config/name", ""),
				"port": port
			})
		"get_project_identity":
			return _response(true, "ok", {
				"project": _project_identity()
			})
		"get_bridge_status":
			return _response(true, "ok", {
				"status": bridge_status()
			})
		"list_editor_capabilities":
			return _response(true, "ok", {
				"capabilities": _editor_capabilities()
			})
		"execute_editor_command":
			return _execute_editor_command(request)
		"get_command_history":
			return _response(true, "ok", {
				"history": history.duplicate(),
				"history_path": _history_path()
			})
		"get_last_run_report":
			return _response(true, "ok", {
				"report": last_run_report,
				"reports": run_reports.duplicate(),
				"reports_path": _run_reports_path()
			})
		"get_pending_actions":
			return _response(true, "ok", {
				"pending": _pending_action_summaries(true),
				"pending_path": _pending_actions_path()
			})
		"queue_actions":
			return _queue_actions(request)
		"apply_queued_actions":
			return _apply_queued_actions(request)
		"discard_queued_actions":
			return _discard_queued_actions(request)
		"get_snapshots":
			return _response(true, "ok", {
				"snapshots": snapshots.duplicate(true),
				"snapshots_path": _snapshots_index_path()
			})
		"restore_snapshot":
			return _restore_snapshot(request)
		"get_project_info":
			return _response(true, "ok", {
				"project": _project_info()
			})
		"get_open_scene":
			return _response(true, "ok", {
				"scene": _open_scene_info()
			})
		"get_scene_tree":
			return _response(true, "ok", {
				"scene_tree": _scene_tree_snapshot()
			})
		"get_editor_context":
			return _response(true, "ok", {
				"project": _project_info(),
				"scene": _open_scene_info(),
				"selection": _selection_snapshot(),
				"scene_tree": _scene_tree_snapshot()
			})
		"get_selection":
			return _response(true, "ok", {
				"selection": _selection_snapshot()
			})
		"get_inspector_properties":
			return _get_inspector_properties(request)
		"set_inspector_property":
			return _set_inspector_property(request)
		"select_node":
			return _select_node(request)
		"get_node_details":
			return _node_details_response(request)
		"get_project_files":
			return _response(true, "ok", {
				"files": _project_files()
			})
		"get_resource_files":
			return _get_resource_files(request)
		"get_resource_info":
			return _get_resource_info(request)
		"get_resource_import_info":
			return _get_resource_import_info(request)
		"scan_resource_filesystem":
			return _scan_resource_filesystem(request)
		"reimport_resources":
			return _reimport_resources(request)
		"get_animation_players":
			return _get_animation_players(request)
		"get_animation_player_info":
			return _get_animation_player_info(request)
		"create_animation":
			return _create_animation(request)
		"set_animation_properties":
			return _set_animation_properties(request)
		"add_animation_value_key":
			return _add_animation_value_key(request)
		"get_project_settings":
			return _get_project_settings(request)
		"get_project_setting":
			return _get_project_setting(request)
		"set_project_setting":
			return _set_project_setting(request)
		"get_input_actions":
			return _get_input_actions(request)
		"add_input_action":
			return _add_input_action(request)
		"remove_input_action":
			return _remove_input_action(request)
		"get_play_status":
			return _response(true, "ok", {
				"play": _play_status()
			})
		"run_check_only":
			return _run_godot_check("check_only", request)
		"run_project_headless":
			return _run_godot_check("run", request)
		"play_main_scene":
			return _play_main_scene()
		"play_current_scene":
			return _play_current_scene()
		"play_custom_scene":
			return _play_custom_scene(request)
		"stop_playing_scene":
			return _stop_playing_scene()
		"stop_playing":
			return _stop_playing_scene()
		"preview_actions":
			var preview_actions = request.get("actions", [])
			if typeof(preview_actions) != TYPE_ARRAY:
				return _response(false, "preview_actions requires an actions array.")
			return _actions_preview_response(preview_actions as Array)
		"apply_actions":
			var actions = request.get("actions", [])
			if typeof(actions) != TYPE_ARRAY:
				return _response(false, "apply_actions requires an actions array.")
			if bool(request.get("dry_run", false)):
				return _actions_preview_response(actions as Array)
			return _apply_actions_with_snapshot(actions as Array, "direct apply_actions")
		"save_scene":
			return _save_scene()
		_:
			return _response(false, "Unsupported command: " + command)


func bridge_status() -> Dictionary:
	var file_root := _file_bridge_root()
	var file_enabled := _file_bridge_enabled()
	return {
		"project": _project_identity(),
		"primary_transport": "file" if file_enabled else "tcp",
		"running": running,
		"host": LOCALHOST,
		"port": port,
		"token_required": not token.is_empty(),
		"last_request": last_request,
		"history_count": history.size(),
		"history_path": _history_path(),
		"pending_action_count": pending_action_batches.size(),
		"pending_actions_path": _pending_actions_path(),
		"snapshot_count": snapshots.size(),
		"snapshots_path": _snapshots_index_path(),
		"last_snapshot": snapshots.back() if not snapshots.is_empty() else {},
		"last_run_report": _run_report_summary(last_run_report),
		"run_reports_path": _run_reports_path(),
		"tcp": {
			"enabled": _tcp_bridge_enabled(),
			"running": running,
			"host": LOCALHOST,
			"port": port,
			"token_required": not token.is_empty()
		},
		"file": {
			"enabled": file_enabled,
			"root": file_root,
			"inbox": file_root.path_join("inbox"),
			"outbox": file_root.path_join("outbox")
		}
	}


func _editor_capabilities() -> Dictionary:
	return {
		"transports": ["file", "tcp"],
		"project_safety": {
			"project_root_required": true,
			"rejects_project_mismatch": true,
			"protects_bridge_files": true
		},
		"editor_commands": [
			"save_scene",
			"refresh_filesystem",
			"play_main_scene",
			"play_current_scene",
			"stop_playing_scene",
			"run_check_only",
			"run_project_headless"
		],
		"inspector": [
			"get_inspector_properties",
			"set_inspector_property"
		],
		"project_settings": [
			"get_project_settings",
			"get_project_setting",
			"set_project_setting"
		],
		"input_map": [
			"get_input_actions",
			"add_input_action",
			"remove_input_action"
		],
		"resources": [
			"get_resource_files",
			"get_resource_info",
			"get_resource_import_info",
			"scan_resource_filesystem",
			"reimport_resources"
		],
		"animation": [
			"get_animation_players",
			"get_animation_player_info",
			"create_animation",
			"set_animation_properties",
			"add_animation_value_key"
		],
		"scene": [
			"get_open_scene",
			"get_scene_tree",
			"get_selection",
			"select_node",
			"get_node_details",
			"save_scene",
			"open_scene action"
		],
		"safe_changes": [
			"preview_actions",
			"queue_actions",
			"apply_queued_actions",
			"discard_queued_actions",
			"get_snapshots",
			"restore_snapshot"
		]
	}


func _execute_editor_command(request: Dictionary) -> Dictionary:
	var editor_command := str(request.get("editor_command", request.get("name", ""))).strip_edges()
	match editor_command:
		"save_scene":
			return _save_scene()
		"refresh_filesystem":
			_refresh_editor_filesystem()
			return _response(true, "Filesystem refreshed.")
		"play_main_scene":
			return _play_main_scene()
		"play_current_scene":
			return _play_current_scene()
		"stop_playing_scene":
			return _stop_playing_scene()
		"run_check_only":
			return _run_godot_check("check_only", request)
		"run_project_headless":
			return _run_godot_check("run", request)
		_:
			return _response(false, "Unsupported editor command: " + editor_command, {
				"capabilities": _editor_capabilities()
			})


func _start_server() -> void:
	if running:
		return

	var error := server.listen(port, LOCALHOST)
	if error != OK:
		push_warning("Godot Codex Bridge failed to listen on " + LOCALHOST + ":" + str(port) + " - " + error_string(error))
		return

	running = true
	print("Godot Codex Bridge listening on " + LOCALHOST + ":" + str(port))


func _stop_server() -> void:
	for client in clients:
		var peer: StreamPeerTCP = client.get("peer", null)
		if peer != null:
			peer.disconnect_from_host()
	clients.clear()
	server.stop()
	running = false


func _accept_pending_clients() -> void:
	while server.is_connection_available():
		var peer := server.take_connection()
		if peer == null:
			return
		clients.append({
			"peer": peer,
			"buffer": ""
		})


func _poll_clients() -> void:
	var remaining: Array = []
	for client in clients:
		if _poll_client(client):
			remaining.append(client)
	clients = remaining


func _poll_client(client: Dictionary) -> bool:
	var peer: StreamPeerTCP = client.get("peer", null)
	if peer == null:
		return false

	var status := peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		return false

	var available := peer.get_available_bytes()
	if available <= 0:
		return true

	var incoming := peer.get_utf8_string(available)
	client["buffer"] = str(client.get("buffer", "")) + incoming

	var buffer := str(client.get("buffer", ""))
	var newline := buffer.find("\n")
	if newline == -1:
		return true

	var line := buffer.substr(0, newline).strip_edges()
	_send_response(peer, _handle_line(line))
	peer.disconnect_from_host()
	return false


func _handle_line(line: String) -> Dictionary:
	if line.is_empty():
		return _response(false, "Request is empty.")

	var parsed := JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _response(false, "Request is not a JSON object.")

	return handle_request(parsed as Dictionary)


func _send_response(peer: StreamPeerTCP, response: Dictionary) -> void:
	var payload := JSON.stringify(response) + "\n"
	peer.put_data(payload.to_utf8_buffer())


func _authorize(request: Dictionary) -> String:
	if token.is_empty():
		return ""
	if str(request.get("token", "")) == token:
		return ""
	return "Invalid token."


func _validate_project_target(request: Dictionary) -> String:
	if request.has("project_root"):
		var requested_root := _normalize_absolute_path(str(request.get("project_root", "")))
		if not requested_root.is_empty() and requested_root != _project_root():
			return "Project mismatch: requested target is " + requested_root + ", current Godot project is " + _project_root()

	if request.has("project_name"):
		var requested_name := str(request.get("project_name", "")).strip_edges()
		var current_name := str(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
		if not requested_name.is_empty() and requested_name != current_name:
			return "Project mismatch: requested target is " + requested_name + ", current Godot project is " + current_name

	return ""


func _response(ok: bool, message: String, data: Dictionary = {}) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
		"data": data
	}


func _finish_request(command: String, request: Dictionary, response: Dictionary) -> Dictionary:
	var request_id := str(request.get("request_id", ""))
	var entry := {
		"command": command,
		"ok": bool(response.get("ok", false)),
		"message": str(response.get("message", "")),
		"request_id": request_id,
		"updated_at": Time.get_datetime_string_from_system(),
		"dry_run": bool(request.get("dry_run", false)),
		"client_cwd": str(request.get("client_cwd", ""))
	}
	last_request = entry
	_record_history(entry)
	request_handled.emit(command, bool(response.get("ok", false)), str(response.get("message", "")), request_id)
	return response


func _scene_tree_snapshot() -> Dictionary:
	var root := _edited_scene_root()
	if root == null:
		return {}
	return _node_snapshot(root, root)


func _node_snapshot(node: Node, scene_root: Node) -> Dictionary:
	var children: Array = []
	for child in node.get_children():
		if child is Node:
			children.append(_node_snapshot(child as Node, scene_root))

	var path := "." if node == scene_root else str(scene_root.get_path_to(node))
	var snapshot := {
		"name": node.name,
		"class": node.get_class(),
		"path": path,
		"children": children
	}

	var script = node.get_script()
	if script is Resource and not (script as Resource).resource_path.is_empty():
		snapshot["script"] = (script as Resource).resource_path
	if node is Node2D:
		var node_2d := node as Node2D
		snapshot["position"] = {
			"x": node_2d.position.x,
			"y": node_2d.position.y
		}
		snapshot["visible"] = node_2d.visible

	return snapshot


func _project_files() -> Array:
	var files: Array = []
	_collect_files("res://", files, 200)
	return files


func _get_resource_files(request: Dictionary) -> Dictionary:
	var root_path := _normalize_resource_path(str(request.get("root", request.get("path", "res://"))), true)
	if root_path.is_empty():
		return _response(false, "Resource directory path is invalid.")

	var max_count := int(request.get("max_count", RESOURCE_FILE_LIMIT_DEFAULT))
	max_count = mini(maxi(max_count, 1), 1000)
	var extensions := _resource_extension_filter(request.get("extensions", []))
	var include_import_sidecars := bool(request.get("include_import_sidecars", false))

	var files: Array = []
	_collect_resource_file_infos(root_path, files, max_count, extensions, include_import_sidecars)
	return _response(true, "ok", {
		"root": root_path,
		"files": files,
		"max_count": max_count
	})


func _get_resource_info(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty():
		return _response(false, "Resource path is invalid.")

	var include_dependencies := bool(request.get("include_dependencies", true))
	var include_import := bool(request.get("include_import", true))
	var include_loaded := bool(request.get("include_loaded", false))

	var info := _resource_file_info(path, include_loaded)
	if include_dependencies:
		info["dependencies"] = _resource_dependencies(path)
	if include_import:
		info["import"] = _resource_import_info(path)

	return _response(true, "ok", {
		"resource": info
	})


func _get_resource_import_info(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty():
		return _response(false, "Resource path is invalid.")

	return _response(true, "ok", {
		"resource_path": path,
		"import": _resource_import_info(path)
	})


func _scan_resource_filesystem(request: Dictionary) -> Dictionary:
	var filesystem = _editor_resource_filesystem()
	if filesystem == null:
		return _response(false, "EditorFileSystem is not available in this environment.", {
			"available": false
		})

	var used_method := ""
	if bool(request.get("scan_sources", false)) and filesystem.has_method("scan_sources"):
		filesystem.scan_sources()
		used_method = "scan_sources"
	elif filesystem.has_method("scan"):
		filesystem.scan()
		used_method = "scan"
	else:
		return _response(false, "EditorFileSystem does not support scan.", {
			"available": true
		})

	return _response(true, "Resource filesystem scanned.", {
		"method": used_method
	})


func _reimport_resources(request: Dictionary) -> Dictionary:
	var raw_paths = request.get("paths", request.get("path", request.get("resource_path", [])))
	var paths := _normalize_resource_paths(raw_paths)
	if paths.is_empty():
		return _response(false, "Missing valid resource path.")

	var filesystem = _editor_resource_filesystem()
	if filesystem == null:
		return _response(false, "EditorFileSystem is not available in this environment.", {
			"paths": paths,
			"available": false
		})
	if not filesystem.has_method("reimport_files"):
		return _response(false, "EditorFileSystem does not support reimport_files.", {
			"paths": paths,
			"available": true
		})

	filesystem.reimport_files(PackedStringArray(paths))
	if filesystem.has_method("scan"):
		filesystem.scan()
	return _response(true, "Resource reimport requested.", {
		"paths": paths
	})


func _get_animation_players(_request: Dictionary) -> Dictionary:
	var players: Array = []
	var root := _edited_scene_root()
	if root == null:
		return _response(false, "No editable scene is currently open.")

	_collect_animation_players(root, root, players)
	return _response(true, "ok", {
		"players": players
	})


func _get_animation_player_info(request: Dictionary) -> Dictionary:
	var resolved := _resolve_animation_player(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))

	return _response(true, "ok", {
		"player": _animation_player_summary(resolved.get("player") as AnimationPlayer)
	})


func _create_animation(request: Dictionary) -> Dictionary:
	var resolved := _resolve_animation_player(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))

	var player := resolved.get("player") as AnimationPlayer
	var animation_name := _normalize_animation_name(str(request.get("animation_name", request.get("name", ""))))
	if animation_name.is_empty():
		return _response(false, "Animation name is invalid.")

	var library_name := _normalize_animation_library_name(str(request.get("library", request.get("library_name", ""))))
	if library_name == "__invalid__":
		return _response(false, "Animation library name is invalid.")

	var existing := _get_animation_resource(player, animation_name, library_name)
	var replace := bool(request.get("replace", false))
	if existing != null and not replace:
		return _response(false, "Animation already exists: " + _qualified_animation_name(animation_name, library_name), {
			"player": _animation_player_summary(player)
		})

	var snapshot := _create_animation_scene_snapshot("create_animation " + _qualified_animation_name(animation_name, library_name))
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; animation was not created.", {
			"snapshot": snapshot
		})

	var library := _ensure_animation_library(player, library_name)
	if library == null:
		return _response(false, "Cannot create or read animation library: " + library_name)

	var animation := Animation.new()
	animation.length = maxf(float(request.get("length", 1.0)), 0.001)
	var loop_result := _decode_animation_loop_mode(request.get("loop_mode", request.get("loop", "none")))
	if not bool(loop_result.get("ok", false)):
		return _response(false, str(loop_result.get("message", "")))
	animation.loop_mode = int(loop_result.get("value", 0))

	if existing != null and library.has_animation(animation_name):
		library.remove_animation(animation_name)
	var add_error := library.add_animation(animation_name, animation)
	if add_error != OK:
		return _response(false, "Failed to create animation: " + error_string(add_error))

	_set_scene_dirty()
	_focus_editor_node(player)
	return _response(true, "Animation created.", {
		"player": _animation_player_summary(player),
		"animation": _animation_summary(animation, animation_name, library_name),
		"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
	})


func _set_animation_properties(request: Dictionary) -> Dictionary:
	var resolved := _resolve_animation_and_player(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))

	var player := resolved.get("player") as AnimationPlayer
	var animation := resolved.get("animation") as Animation
	var animation_name := str(resolved.get("animation_name", ""))
	var library_name := str(resolved.get("library_name", ""))
	var before := _animation_summary(animation, animation_name, library_name)

	var snapshot := _create_animation_scene_snapshot("set_animation_properties " + _qualified_animation_name(animation_name, library_name))
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; animation was not modified.", {
			"snapshot": snapshot
		})

	if request.has("length"):
		animation.length = maxf(float(request.get("length", 1.0)), 0.001)
	if request.has("loop_mode") or request.has("loop"):
		var loop_result := _decode_animation_loop_mode(request.get("loop_mode", request.get("loop", "none")))
		if not bool(loop_result.get("ok", false)):
			return _response(false, str(loop_result.get("message", "")))
		animation.loop_mode = int(loop_result.get("value", 0))

	_set_scene_dirty()
	_focus_editor_node(player)
	return _response(true, "Animation properties updated.", {
		"before": before,
		"after": _animation_summary(animation, animation_name, library_name),
		"player": _animation_player_summary(player),
		"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
	})


func _add_animation_value_key(request: Dictionary) -> Dictionary:
	var resolved := _resolve_animation_and_player(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))
	if not request.has("value"):
		return _response(false, "Missing value.")

	var property_name := str(request.get("property", "")).strip_edges()
	var target_path := str(request.get("target_path", request.get("target", "."))).strip_edges()
	var track_path := _animation_track_path(target_path, property_name)
	if str(track_path).is_empty():
		return _response(false, "Animation track path is invalid.")

	var player := resolved.get("player") as AnimationPlayer
	var animation := resolved.get("animation") as Animation
	var animation_name := str(resolved.get("animation_name", ""))
	var library_name := str(resolved.get("library_name", ""))
	var time_sec := maxf(float(request.get("time", request.get("time_sec", 0.0))), 0.0)
	if time_sec > animation.length:
		animation.length = time_sec

	var snapshot := _create_animation_scene_snapshot("add_animation_value_key " + _qualified_animation_name(animation_name, library_name))
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; keyframe was not inserted.", {
			"snapshot": snapshot
		})

	var track_index := _find_animation_value_track(animation, track_path)
	var created_track := false
	if track_index == -1:
		track_index = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track_index, track_path)
		created_track = true

	var value = _decode_value(request.get("value"))
	animation.track_insert_key(track_index, time_sec, value)
	_set_scene_dirty()
	_focus_editor_node(player)
	return _response(true, "Animation keyframe inserted.", {
		"player": _animation_player_summary(player),
		"animation_name": _qualified_animation_name(animation_name, library_name),
		"track": _animation_track_summary(animation, track_index),
		"created_track": created_track,
		"time": time_sec,
		"value": _encode_value(value),
		"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
	})


func _project_info() -> Dictionary:
	var features: Array = []
	for feature in ProjectSettings.get_setting("application/config/features", PackedStringArray()):
		features.append(str(feature))

	var identity := _project_identity()
	identity["features"] = features
	return identity


func _project_identity() -> Dictionary:
	var root := _project_root()
	return {
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"resource_path": ProjectSettings.globalize_path("res://"),
		"root": root,
		"root_hash": str(root.hash()),
		"bridge": "Godot Codex Bridge"
	}


func _get_project_settings(request: Dictionary) -> Dictionary:
	var prefix := str(request.get("prefix", "")).strip_edges()
	var include_values := bool(request.get("include_values", true))
	var max_count := int(request.get("max_count", 120))
	max_count = mini(maxi(max_count, 1), 500)

	var settings: Array = []
	for property_info in ProjectSettings.get_property_list():
		if typeof(property_info) != TYPE_DICTIONARY:
			continue
		var info := property_info as Dictionary
		var name := str(info.get("name", ""))
		if name.is_empty():
			continue
		if not prefix.is_empty() and not name.begins_with(prefix):
			continue
		var item := {
			"name": name,
			"type": int(info.get("type", TYPE_NIL)),
			"hint": int(info.get("hint", 0)),
			"hint_string": str(info.get("hint_string", "")),
			"usage": int(info.get("usage", 0))
		}
		if include_values:
			item["value"] = _encode_value(ProjectSettings.get_setting(name))
		settings.append(item)
		if settings.size() >= max_count:
			break

	return _response(true, "ok", {
		"prefix": prefix,
		"settings": settings
	})


func _get_project_setting(request: Dictionary) -> Dictionary:
	var setting := _normalize_setting_name(str(request.get("setting", request.get("name", ""))))
	if setting.is_empty():
		return _response(false, "Missing setting.")
	if not ProjectSettings.has_setting(setting):
		return _response(false, "Project setting does not exist: " + setting)

	return _response(true, "ok", {
		"setting": setting,
		"value": _encode_value(ProjectSettings.get_setting(setting))
	})


func _set_project_setting(request: Dictionary) -> Dictionary:
	var setting := _normalize_setting_name(str(request.get("setting", request.get("name", ""))))
	if setting.is_empty():
		return _response(false, "Project setting name is invalid.")
	if not request.has("value"):
		return _response(false, "Missing value.")

	var before_value = ProjectSettings.get_setting(setting) if ProjectSettings.has_setting(setting) else null
	var existed_before := ProjectSettings.has_setting(setting)
	var snapshot := _create_project_file_snapshot("set_project_setting " + setting)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to snapshot project.godot; setting was not changed.", {
			"snapshot": snapshot
		})

	ProjectSettings.set_setting(setting, _decode_value(request.get("value")))
	var save_result := _save_project_settings_if_requested(request)
	return _response(save_result == OK, "Project setting updated." if save_result == OK else "Project setting updated, but saving failed: " + error_string(save_result), {
		"setting": setting,
		"existed_before": existed_before,
		"before": _encode_value(before_value),
		"after": _encode_value(ProjectSettings.get_setting(setting)),
		"saved": save_result == OK,
		"snapshot": _snapshot_summary(snapshot)
	})


func _get_input_actions(request: Dictionary) -> Dictionary:
	var prefix := str(request.get("prefix", "")).strip_edges()
	var include_builtin := bool(request.get("include_builtin", false))
	var actions: Array = []
	for action in InputMap.get_actions():
		var action_name := str(action)
		if not include_builtin and action_name.begins_with("ui_"):
			continue
		if not prefix.is_empty() and not action_name.begins_with(prefix):
			continue
		actions.append(_input_action_snapshot(action_name))
	actions.sort_custom(func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))
	return _response(true, "ok", {
		"actions": actions
	})


func _add_input_action(request: Dictionary) -> Dictionary:
	var action_name := _normalize_input_action_name(str(request.get("action", request.get("name", ""))))
	if action_name.is_empty():
		return _response(false, "Input action name is invalid.")

	var snapshot := _create_project_file_snapshot("add_input_action " + action_name)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to snapshot project.godot; Input Map was not changed.", {
			"snapshot": snapshot
		})

	var existed_before := InputMap.has_action(action_name)
	if not existed_before:
		InputMap.add_action(action_name, float(request.get("deadzone", 0.5)))
	elif request.has("deadzone"):
		InputMap.action_set_deadzone(action_name, float(request.get("deadzone", 0.5)))

	if bool(request.get("replace_events", false)):
		InputMap.action_erase_events(action_name)

	var added_events: Array = []
	var errors: Array = []
	var event_specs = request.get("events", [])
	if typeof(event_specs) == TYPE_ARRAY:
		var event_specs_array := event_specs as Array
		for event_spec in event_specs_array:
			var event = _decode_input_event(event_spec)
			if event == null:
				errors.append("Could not parse input event: " + JSON.stringify(event_spec))
				continue
			InputMap.action_add_event(action_name, event)
			added_events.append(_encode_input_event(event))

	_sync_input_action_to_project_settings(action_name)
	var save_result := _save_project_settings_if_requested(request)
	var ok := errors.is_empty() and save_result == OK
	return _response(ok, "Input action updated." if ok else "Input action updated with errors.", {
		"action": _input_action_snapshot(action_name),
		"existed_before": existed_before,
		"added_events": added_events,
		"errors": errors,
		"saved": save_result == OK,
		"snapshot": _snapshot_summary(snapshot)
	})


func _remove_input_action(request: Dictionary) -> Dictionary:
	var action_name := _normalize_input_action_name(str(request.get("action", request.get("name", ""))))
	if action_name.is_empty():
		return _response(false, "Input action name is invalid.")

	var existed_before := InputMap.has_action(action_name)
	var before_snapshot := _input_action_snapshot(action_name) if existed_before else {}
	var snapshot := _create_project_file_snapshot("remove_input_action " + action_name)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to snapshot project.godot; Input Map was not changed.", {
			"snapshot": snapshot
		})

	if existed_before:
		InputMap.erase_action(action_name)
	if ProjectSettings.has_setting("input/" + action_name):
		ProjectSettings.clear("input/" + action_name)
	var save_result := _save_project_settings_if_requested(request)
	return _response(save_result == OK, "Input action removed." if save_result == OK else "Input action removed, but saving failed: " + error_string(save_result), {
		"existed_before": existed_before,
		"before": before_snapshot,
		"saved": save_result == OK,
		"snapshot": _snapshot_summary(snapshot)
	})


func _open_scene_info() -> Dictionary:
	var root := _edited_scene_root()
	if root == null:
		return {
			"has_scene": false
		}

	return {
		"has_scene": true,
		"name": root.name,
		"path": root.scene_file_path,
		"root": _node_summary(root, root)
	}


func _selection_snapshot() -> Array:
	var selected: Array = []
	var selection = _editor_selection()
	if selection == null or not selection.has_method("get_selected_nodes"):
		return selected

	var root := _edited_scene_root()
	for item in selection.get_selected_nodes():
		if item is Node:
			selected.append(_node_summary(item as Node, root))
	return selected


func _select_node(request: Dictionary) -> Dictionary:
	var raw_path := str(request.get("node_path", request.get("path", ""))).strip_edges()
	if raw_path.is_empty():
		return _response(false, "Missing node_path.")

	var node: Node = _find_scene_node(raw_path)
	if node == null:
		return _response(false, "Node not found: " + raw_path)

	var selection = _editor_selection()
	if selection == null:
		return _response(false, "EditorSelection is not available in this environment.")
	if selection.has_method("clear"):
		selection.clear()
	if selection.has_method("add_node"):
		selection.add_node(node)
	if editor_interface != null and editor_interface.has_method("edit_node"):
		editor_interface.edit_node(node)

	return _response(true, "Node selected.", {
		"selection": _selection_snapshot()
	})


func _node_details_response(request: Dictionary) -> Dictionary:
	var raw_path := str(request.get("node_path", request.get("path", ""))).strip_edges()
	if raw_path.is_empty():
		return _response(false, "Missing node_path.")

	var node: Node = _find_scene_node(raw_path)
	if node == null:
		return _response(false, "Node not found: " + raw_path)

	return _response(true, "ok", {
		"node": _node_details(node)
	})


func _node_summary(node: Node, scene_root: Node) -> Dictionary:
	var path := "."
	if scene_root != null and node != scene_root:
		path = str(scene_root.get_path_to(node))

	var summary := {
		"name": node.name,
		"class": node.get_class(),
		"path": path,
		"script": _script_path(node),
		"child_count": node.get_child_count()
	}

	if node is Node2D:
		var node_2d := node as Node2D
		summary["position"] = _vector2_dict(node_2d.position)
		summary["global_position"] = _vector2_dict(node_2d.global_position)
		summary["visible"] = node_2d.visible
	elif node is Control:
		var control := node as Control
		summary["position"] = _vector2_dict(control.position)
		summary["size"] = _vector2_dict(control.size)
		summary["visible"] = control.visible

	return summary


func _node_details(node: Node) -> Dictionary:
	var root := _edited_scene_root()
	var details := _node_summary(node, root)
	details["groups"] = _node_groups(node)
	details["owner"] = node.owner.name if node.owner != null else ""

	if node is Node2D:
		var node_2d := node as Node2D
		details["rotation_degrees"] = node_2d.rotation_degrees
		details["scale"] = _vector2_dict(node_2d.scale)
	elif node is Control:
		var control := node as Control
		details["anchors"] = {
			"left": control.anchor_left,
			"top": control.anchor_top,
			"right": control.anchor_right,
			"bottom": control.anchor_bottom
		}

	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			details["texture"] = sprite.texture.resource_path
	if node is Label:
		details["text"] = (node as Label).text

	return details


func _collect_animation_players(node: Node, scene_root: Node, players: Array) -> void:
	if node is AnimationPlayer:
		players.append(_animation_player_summary(node as AnimationPlayer))
	for child in node.get_children():
		if child is Node:
			_collect_animation_players(child as Node, scene_root, players)


func _resolve_animation_player(request: Dictionary) -> Dictionary:
	var raw_path := str(request.get("node_path", request.get("path", ""))).strip_edges()
	var node: Node = null
	if raw_path.is_empty():
		var selected := _selected_nodes()
		if not selected.is_empty():
			node = selected[0] as Node
		else:
			return {
				"ok": false,
				"message": "Missing AnimationPlayer node_path."
			}
	else:
		node = _find_scene_node(raw_path)

	if node == null:
		return {
			"ok": false,
			"message": "Node not found: " + raw_path
		}
	if not node is AnimationPlayer:
		return {
			"ok": false,
			"message": "Node is not an AnimationPlayer: " + raw_path
		}

	return {
		"ok": true,
		"player": node as AnimationPlayer
	}


func _resolve_animation_and_player(request: Dictionary) -> Dictionary:
	var player_result := _resolve_animation_player(request)
	if not bool(player_result.get("ok", false)):
		return player_result

	var player := player_result.get("player") as AnimationPlayer
	var animation_name := _normalize_animation_name(str(request.get("animation_name", request.get("name", ""))))
	if animation_name.is_empty():
		return {
			"ok": false,
			"message": "Animation name is invalid."
		}

	var library_name := _normalize_animation_library_name(str(request.get("library", request.get("library_name", ""))))
	if library_name == "__invalid__":
		return {
			"ok": false,
			"message": "Animation library name is invalid."
		}

	var animation := _get_animation_resource(player, animation_name, library_name)
	if animation == null:
		return {
			"ok": false,
			"message": "Animation not found: " + _qualified_animation_name(animation_name, library_name)
		}

	return {
		"ok": true,
		"player": player,
		"animation": animation,
		"animation_name": animation_name,
		"library_name": library_name
	}


func _animation_player_summary(player: AnimationPlayer) -> Dictionary:
	var root := _edited_scene_root()
	var path := str(player.name)
	if root != null:
		path = "." if player == root else str(root.get_path_to(player))
	var libraries: Array = []
	var animation_count := 0
	for library_name in player.get_animation_library_list():
		var name := str(library_name)
		var library := player.get_animation_library(name)
		if library == null:
			continue
		var animations: Array = []
		for animation_name in library.get_animation_list():
			var animation := library.get_animation(animation_name)
			if animation is Animation:
				animations.append(_animation_summary(animation as Animation, str(animation_name), name))
				animation_count += 1
		libraries.append({
			"name": name,
			"display_name": "default" if name.is_empty() else name,
			"animation_count": animations.size(),
			"animations": animations
		})

	return {
		"name": player.name,
		"path": path,
		"class": player.get_class(),
		"animation_count": animation_count,
		"libraries": libraries
	}


func _animation_summary(animation: Animation, animation_name: String, library_name: String) -> Dictionary:
	var tracks: Array = []
	for track_index in animation.get_track_count():
		tracks.append(_animation_track_summary(animation, track_index))
	return {
		"name": animation_name,
		"qualified_name": _qualified_animation_name(animation_name, library_name),
		"library": library_name,
		"length": animation.length,
		"loop_mode": animation.loop_mode,
		"loop_mode_name": _animation_loop_mode_name(animation.loop_mode),
		"track_count": animation.get_track_count(),
		"tracks": tracks
	}


func _animation_track_summary(animation: Animation, track_index: int) -> Dictionary:
	return {
		"index": track_index,
		"type": animation.track_get_type(track_index),
		"path": str(animation.track_get_path(track_index)),
		"key_count": animation.track_get_key_count(track_index),
		"enabled": animation.track_is_enabled(track_index)
	}


func _ensure_animation_library(player: AnimationPlayer, library_name: String) -> AnimationLibrary:
	if player.has_animation_library(library_name):
		return player.get_animation_library(library_name)

	var library := AnimationLibrary.new()
	var add_error := player.add_animation_library(library_name, library)
	if add_error != OK:
		return null
	return library


func _get_animation_resource(player: AnimationPlayer, animation_name: String, library_name: String) -> Animation:
	var library: AnimationLibrary = null
	if player.has_animation_library(library_name):
		library = player.get_animation_library(library_name)
	if library != null and library.has_animation(animation_name):
		return library.get_animation(animation_name)
	if library_name.is_empty() and player.has_animation(animation_name):
		return player.get_animation(animation_name)
	return null


func _normalize_animation_name(raw_name: String) -> String:
	var animation_name := raw_name.strip_edges()
	if animation_name.is_empty() or animation_name.contains("/") or animation_name.contains(".."):
		return ""
	return animation_name


func _normalize_animation_library_name(raw_name: String) -> String:
	var library_name := raw_name.strip_edges()
	if library_name.contains("/") or library_name.contains(".."):
		return "__invalid__"
	return library_name


func _qualified_animation_name(animation_name: String, library_name: String) -> String:
	return animation_name if library_name.is_empty() else library_name + "/" + animation_name


func _decode_animation_loop_mode(value) -> Dictionary:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var mode := int(value)
		if mode >= 0 and mode <= 2:
			return {
				"ok": true,
				"value": mode
			}
		return {
			"ok": false,
			"message": "loop_mode must be 0, 1, 2, or none/linear/pingpong."
		}

	var text := str(value).strip_edges().to_lower()
	match text:
		"", "none", "loop_none", "off", "false":
			return {
				"ok": true,
				"value": 0
			}
		"linear", "loop", "loop_linear", "true":
			return {
				"ok": true,
				"value": 1
			}
		"pingpong", "ping_pong", "loop_pingpong":
			return {
				"ok": true,
				"value": 2
			}
		_:
			return {
				"ok": false,
				"message": "Unsupported loop_mode: " + text
			}


func _animation_loop_mode_name(loop_mode: int) -> String:
	match int(loop_mode):
		0:
			return "none"
		1:
			return "linear"
		2:
			return "pingpong"
		_:
			return "unknown"


func _animation_track_path(raw_target_path: String, property_name: String) -> NodePath:
	var target_path := raw_target_path.strip_edges()
	if target_path.is_empty():
		target_path = "."
	if target_path.begins_with("/") or target_path.begins_with("res://") or target_path.contains("\\"):
		return NodePath("")
	if target_path.contains(":"):
		return NodePath(target_path)
	if property_name.strip_edges().is_empty():
		return NodePath("")
	return NodePath(target_path + ":" + property_name.strip_edges())


func _find_animation_value_track(animation: Animation, track_path: NodePath) -> int:
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) == Animation.TYPE_VALUE and str(animation.track_get_path(track_index)) == str(track_path):
			return track_index
	return -1


func _create_animation_scene_snapshot(reason: String) -> Dictionary:
	return _create_snapshot([
		{
			"type": "set_property",
			"node_path": ".",
			"property": "_animation_snapshot"
		}
	], reason)


func _focus_editor_node(node: Node) -> void:
	var selection = _editor_selection()
	if selection != null:
		if selection.has_method("clear"):
			selection.clear()
		if selection.has_method("add_node"):
			selection.add_node(node)
	if editor_interface != null and editor_interface.has_method("edit_node"):
		editor_interface.edit_node(node)


func _get_inspector_properties(request: Dictionary) -> Dictionary:
	var resolved := _resolve_inspector_object(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))

	var object := resolved.get("object") as Object
	var include_internal := bool(request.get("include_internal", false))
	var include_values := bool(request.get("include_values", true))
	var max_count := int(request.get("max_count", PROPERTY_LIMIT_DEFAULT))
	max_count = mini(maxi(max_count, 1), 500)

	return _response(true, "ok", {
		"target": resolved.get("target", {}),
		"properties": _object_property_snapshot(object, include_internal, include_values, max_count)
	})


func _set_inspector_property(request: Dictionary) -> Dictionary:
	var property_name := str(request.get("property", "")).strip_edges()
	if property_name.is_empty():
		return _response(false, "Missing property.")

	var resolved := _resolve_inspector_object(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))

	var object := resolved.get("object") as Object
	if not _has_property(object, property_name):
		return _response(false, "Target does not have property: " + property_name)

	var before_value = object.get(property_name)
	var after_value = _decode_value(request.get("value"))
	var snapshot := _create_object_snapshot(object, str(resolved.get("path", "")), "set_inspector_property " + property_name)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; property was not set.", {
			"snapshot": snapshot
		})

	_set_object_property(object, property_name, after_value)
	if object is Node:
		_set_scene_dirty()
		if editor_interface != null and editor_interface.has_method("edit_node"):
			editor_interface.edit_node(object as Node)
	elif object is Resource:
		var resource := object as Resource
		if not resource.resource_path.is_empty():
			ResourceSaver.save(resource, resource.resource_path)

	return _response(true, "Property set.", {
		"target": resolved.get("target", {}),
		"property": property_name,
		"before": _encode_value(before_value),
		"after": _encode_value(object.get(property_name)),
		"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
	})


func _resolve_inspector_object(request: Dictionary) -> Dictionary:
	var resource_path := str(request.get("resource_path", "")).strip_edges()
	if not resource_path.is_empty():
		var normalized_resource_path := _normalize_action_path(resource_path)
		if normalized_resource_path.is_empty():
			return {
				"ok": false,
				"message": "Resource path is invalid or not allowed."
			}
		var resource := load(normalized_resource_path)
		if not resource is Resource:
			return {
				"ok": false,
				"message": "Cannot load resource: " + normalized_resource_path
			}
		return {
			"ok": true,
			"object": resource,
			"path": normalized_resource_path,
			"target": {
				"kind": "resource",
				"path": normalized_resource_path,
				"class": (resource as Resource).get_class()
			}
		}

	var raw_path := str(request.get("node_path", request.get("path", ""))).strip_edges()
	var node: Node = null
	if raw_path.is_empty():
		var selected := _selected_nodes()
		if not selected.is_empty():
			node = selected[0] as Node
		else:
			node = _edited_scene_root()
	else:
		node = _find_scene_node(raw_path)

	if node == null:
		return {
			"ok": false,
			"message": "Inspector target not found."
		}

	var root := _edited_scene_root()
	var path := "." if node == root else str(root.get_path_to(node))
	return {
		"ok": true,
		"object": node,
		"path": path,
		"target": {
			"kind": "node",
			"name": node.name,
			"path": path,
			"class": node.get_class(),
			"script": _script_path(node)
		}
	}


func _object_property_snapshot(object: Object, include_internal: bool, include_values: bool, max_count: int) -> Array:
	var properties: Array = []
	for property_info in object.get_property_list():
		if typeof(property_info) != TYPE_DICTIONARY:
			continue
		var info := property_info as Dictionary
		var name := str(info.get("name", ""))
		if name.is_empty():
			continue
		var usage := int(info.get("usage", 0))
		if not include_internal and (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var item := {
			"name": name,
			"type": int(info.get("type", TYPE_NIL)),
			"class_name": str(info.get("class_name", "")),
			"hint": int(info.get("hint", 0)),
			"hint_string": str(info.get("hint_string", "")),
			"usage": usage,
			"editable": (usage & PROPERTY_USAGE_READ_ONLY) == 0
		}
		if include_values:
			item["value"] = _encode_value(object.get(name))
		properties.append(item)
		if properties.size() >= max_count:
			break
	return properties


func _selected_nodes() -> Array:
	var selected: Array = []
	var selection = _editor_selection()
	if selection == null or not selection.has_method("get_selected_nodes"):
		return selected
	for item in selection.get_selected_nodes():
		if item is Node:
			selected.append(item as Node)
	return selected


func _create_object_snapshot(object: Object, path: String, reason: String) -> Dictionary:
	if object is Node:
		return _create_snapshot([
			{
				"type": "set_property",
				"node_path": path,
				"property": "_inspector_snapshot"
			}
		], reason)
	if object is Resource:
		var resource := object as Resource
		if not resource.resource_path.is_empty():
			return _create_snapshot([
				{
					"type": "write_file",
					"path": resource.resource_path
				}
			], reason)
	return {}


func _set_object_property(object: Object, property_name: String, value) -> void:
	var undo_redo = _editor_undo_redo()
	if undo_redo != null and undo_redo.has_method("create_action") and undo_redo.has_method("add_do_property") and undo_redo.has_method("add_undo_property") and undo_redo.has_method("commit_action"):
		undo_redo.create_action("Set " + property_name)
		undo_redo.add_do_property(object, property_name, value)
		undo_redo.add_undo_property(object, property_name, object.get(property_name))
		undo_redo.commit_action()
	else:
		object.set(property_name, value)


func _editor_undo_redo():
	if editor_interface == null:
		return null
	if editor_interface.has_method("get_editor_undo_redo"):
		return editor_interface.get_editor_undo_redo()
	if editor_interface.has_method("get_undo_redo"):
		return editor_interface.get_undo_redo()
	return null


func _set_scene_dirty() -> void:
	if editor_interface != null and editor_interface.has_method("mark_scene_as_unsaved"):
		editor_interface.mark_scene_as_unsaved()


func _actions_preview_response(actions: Array) -> Dictionary:
	var preview := _preview_actions(actions)
	var ok := bool(preview.get("ok", false))
	return _response(ok, "Dry-run preview completed." if ok else "Dry-run found issues.", {
		"preview": preview
	})


func _queue_actions(request: Dictionary) -> Dictionary:
	var actions = request.get("actions", [])
	if typeof(actions) != TYPE_ARRAY:
		return _response(false, "queue_actions requires an actions array.")

	var action_list := (actions as Array).duplicate(true)
	var preview := _preview_actions(action_list)
	if not bool(preview.get("ok", false)):
		return _response(false, "Action preview found issues; batch was not queued.", {
			"preview": preview
		})

	var requested_id := str(request.get("queue_id", "")).strip_edges()
	var queue_id := _safe_id(requested_id, "queue")
	if _pending_action_index(queue_id) != -1:
		return _response(false, "Pending queue ID already exists: " + queue_id)

	var queued := {
		"queue_id": queue_id,
		"created_at": Time.get_datetime_string_from_system(),
		"summary": str(request.get("summary", "")).strip_edges(),
		"action_count": action_list.size(),
		"actions": action_list,
		"preview": preview
	}
	pending_action_batches.append(queued)
	while pending_action_batches.size() > PENDING_ACTION_LIMIT:
		pending_action_batches.pop_front()
	_save_pending_actions()

	return _response(true, "Added to pending queue.", {
		"queued": _pending_action_summary(queued, true),
		"pending_count": pending_action_batches.size()
	})


func _apply_queued_actions(request: Dictionary) -> Dictionary:
	var queue_id := str(request.get("queue_id", "")).strip_edges()
	if queue_id.is_empty():
		return _response(false, "Missing queue_id.")

	var index := _pending_action_index(queue_id)
	if index == -1:
		return _response(false, "Pending action batch not found: " + queue_id)

	var queued := pending_action_batches[index] as Dictionary
	var actions := (queued.get("actions", []) as Array).duplicate(true)
	var response := _apply_actions_with_snapshot(actions, "queued " + queue_id)
	if bool(response.get("ok", false)):
		pending_action_batches.remove_at(index)
		_save_pending_actions()

	var data := response.get("data", {}) as Dictionary
	data["queue_id"] = queue_id
	data["queued"] = _pending_action_summary(queued, false)
	response["data"] = data
	return response


func _discard_queued_actions(request: Dictionary) -> Dictionary:
	var queue_id := str(request.get("queue_id", "")).strip_edges()
	if queue_id.is_empty():
		return _response(false, "Missing queue_id.")

	var index := _pending_action_index(queue_id)
	if index == -1:
		return _response(false, "Pending action batch not found: " + queue_id)

	var queued := pending_action_batches[index] as Dictionary
	pending_action_batches.remove_at(index)
	_save_pending_actions()
	return _response(true, "Pending action batch discarded.", {
		"discarded": _pending_action_summary(queued, false),
		"pending_count": pending_action_batches.size()
	})


func _apply_actions_with_snapshot(actions: Array, reason: String) -> Dictionary:
	var preview := _preview_actions(actions)
	if not bool(preview.get("ok", false)):
		return _response(false, "Action preview found issues; actions were not applied.", {
			"preview": preview
		})

	var snapshot := _create_snapshot(actions, reason)
	if not bool(snapshot.get("ok", false)):
		return _response(false, "Failed to create pre-change snapshot; actions were not applied.", {
			"snapshot": snapshot
		})

	var action_result: Dictionary = executor.apply_actions(actions)
	return _response(true, "ok", {
		"snapshot": _snapshot_summary(snapshot),
		"action_result": action_result
	})


func _pending_action_index(queue_id: String) -> int:
	for index in pending_action_batches.size():
		var queued := pending_action_batches[index] as Dictionary
		if str(queued.get("queue_id", "")) == queue_id:
			return index
	return -1


func _pending_action_summaries(include_preview: bool) -> Array:
	var summaries: Array = []
	for queued in pending_action_batches:
		if typeof(queued) == TYPE_DICTIONARY:
			summaries.append(_pending_action_summary(queued as Dictionary, include_preview))
	return summaries


func _pending_action_summary(queued: Dictionary, include_preview: bool) -> Dictionary:
	var summary := {
		"queue_id": str(queued.get("queue_id", "")),
		"created_at": str(queued.get("created_at", "")),
		"summary": str(queued.get("summary", "")),
		"action_count": int(queued.get("action_count", 0))
	}
	if include_preview:
		summary["preview"] = queued.get("preview", {})
	return summary


func _preview_actions(actions: Array) -> Dictionary:
	var items: Array = []
	var invalid_count := 0
	for index in actions.size():
		var action = actions[index]
		if typeof(action) != TYPE_DICTIONARY:
			invalid_count += 1
			items.append({
				"index": index,
				"ok": false,
				"type": "unknown",
				"target": "",
				"message": "Action is not a Dictionary."
			})
			continue

		var item := _preview_action(index, action as Dictionary)
		if not bool(item.get("ok", false)):
			invalid_count += 1
		items.append(item)

	return {
		"ok": invalid_count == 0,
		"dry_run": true,
		"would_apply": invalid_count == 0,
		"total": actions.size(),
		"invalid": invalid_count,
		"actions": items
	}


func _preview_action(index: int, action: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", "")).strip_edges()
	var target := _action_target(action_type, action)
	var message := ""
	var ok := true

	if action_type.is_empty():
		ok = false
		message = "Missing type."
	elif not (action_type in [
		"write_file",
		"append_file",
		"make_dir",
		"create_scene",
		"open_scene",
		"refresh_filesystem",
		"add_node",
		"set_property",
		"attach_script",
		"connect_signal"
	]):
		ok = false
		message = "Unsupported action type: " + action_type
	elif action_type in ["write_file", "append_file", "make_dir", "create_scene", "open_scene"]:
		var path := _normalize_action_path(str(action.get("path", "")), action_type == "make_dir")
		if path.is_empty():
			ok = false
			message = "Path is invalid or not allowed."
		else:
			target = path
	elif action_type == "add_node":
		if str(action.get("node_type", "")).strip_edges().is_empty():
			ok = false
			message = "Missing node_type."
	elif action_type == "set_property":
		if str(action.get("property", "")).strip_edges().is_empty():
			ok = false
			message = "Missing property."
	elif action_type == "attach_script":
		var script_path := _normalize_action_path(str(action.get("script_path", "")))
		if script_path.is_empty():
			ok = false
			message = "Script path is invalid or not allowed."
		else:
			target = str(action.get("node_path", action.get("path", ""))) + " -> " + script_path
	elif action_type == "connect_signal":
		if str(action.get("signal", "")).strip_edges().is_empty() or str(action.get("method", "")).strip_edges().is_empty():
			ok = false
			message = "Missing signal or method."

	if message.is_empty():
		message = "Will apply: " + action_type

	return {
		"index": index,
		"ok": ok,
		"type": action_type,
		"target": target,
		"message": message
	}


func _action_target(action_type: String, action: Dictionary) -> String:
	match action_type:
		"write_file", "append_file", "make_dir", "create_scene", "open_scene":
			return str(action.get("path", ""))
		"add_node":
			return str(action.get("parent_path", ".")) + "/" + str(action.get("name", action.get("node_type", "")))
		"set_property":
			return str(action.get("node_path", action.get("path", ""))) + "." + str(action.get("property", ""))
		"attach_script":
			return str(action.get("node_path", action.get("path", ""))) + " -> " + str(action.get("script_path", ""))
		"connect_signal":
			return str(action.get("source_path", "")) + "." + str(action.get("signal", "")) + " -> " + str(action.get("target_path", "")) + "." + str(action.get("method", ""))
		_:
			return ""


func _save_scene() -> Dictionary:
	if editor_interface == null or not editor_interface.has_method("save_scene"):
		return _response(false, "save_scene is not available in this environment.")

	var error: int = editor_interface.save_scene()
	if error != OK:
		return _response(false, "Failed to save scene: " + error_string(error))

	return _response(true, "Scene saved.")


func _play_status() -> Dictionary:
	var can_query: bool = editor_interface != null and editor_interface.has_method("is_playing_scene")
	var is_playing := false
	if can_query:
		is_playing = bool(editor_interface.is_playing_scene())

	return {
		"is_playing": is_playing,
		"can_query": can_query,
		"can_play_main_scene": editor_interface != null and editor_interface.has_method("play_main_scene"),
		"can_play_current_scene": editor_interface != null and editor_interface.has_method("play_current_scene"),
		"can_play_custom_scene": editor_interface != null and editor_interface.has_method("play_custom_scene"),
		"can_stop": editor_interface != null and editor_interface.has_method("stop_playing_scene")
	}


func _run_godot_check(mode: String, request: Dictionary) -> Dictionary:
	var executable := OS.get_executable_path()
	if executable.strip_edges().is_empty() or not FileAccess.file_exists(executable):
		return _response(false, "Godot executable not found.")

	var arguments := PackedStringArray()
	arguments.append("--headless")
	arguments.append("--path")
	arguments.append(_project_root())

	if mode == "check_only":
		arguments.append("--check-only")
		arguments.append("--quit")
	else:
		var duration := float(request.get("duration_sec", 3.0))
		duration = minf(maxf(duration, 1.0), 10.0)
		arguments.append("--quit-after")
		arguments.append(str(duration))

	var started_at := Time.get_datetime_string_from_system()
	var started_ticks := Time.get_ticks_msec()
	var output: Array = []
	var exit_code := OS.execute(executable, arguments, output, true, false)
	var duration_ms := Time.get_ticks_msec() - started_ticks
	var output_text := _join_output(output)
	var errors := _extract_diagnostic_lines(output_text, ["SCRIPT ERROR", "ERROR:", "Parse Error"])
	var warnings := _extract_diagnostic_lines(output_text, ["WARNING:", "WARN:"])

	var report := {
		"mode": mode,
		"ok": exit_code == 0 and errors.is_empty(),
		"exit_code": exit_code,
		"started_at": started_at,
		"duration_ms": duration_ms,
		"executable": executable,
		"arguments": Array(arguments),
		"errors": errors,
		"warnings": warnings,
		"output": output_text,
		"output_tail": _tail_text(output_text, 6000)
	}
	_record_run_report(report)

	var message := "Godot check passed." if bool(report.get("ok", false)) else "Godot check found issues."
	return _response(bool(report.get("ok", false)), message, {
		"report": report
	})


func _play_main_scene() -> Dictionary:
	if editor_interface == null or not editor_interface.has_method("play_main_scene"):
		return _response(false, "play_main_scene is not available in this environment.")

	editor_interface.play_main_scene()
	return _response(true, "Main scene started.", {
		"play": _play_status()
	})


func _play_current_scene() -> Dictionary:
	if editor_interface == null or not editor_interface.has_method("play_current_scene"):
		return _response(false, "play_current_scene is not available in this environment.")

	editor_interface.play_current_scene()
	return _response(true, "Current scene started.", {
		"play": _play_status()
	})


func _play_custom_scene(request: Dictionary) -> Dictionary:
	if editor_interface == null or not editor_interface.has_method("play_custom_scene"):
		return _response(false, "play_custom_scene is not available in this environment.")

	var scene_path := _normalize_scene_path(str(request.get("scene_path", request.get("path", ""))))
	if scene_path.is_empty():
		return _response(false, "Scene path is invalid.")
	if not FileAccess.file_exists(scene_path):
		return _response(false, "Scene does not exist: " + scene_path)

	editor_interface.play_custom_scene(scene_path)
	return _response(true, "Custom scene started.", {
		"scene_path": scene_path,
		"play": _play_status()
	})


func _stop_playing_scene() -> Dictionary:
	if editor_interface == null or not editor_interface.has_method("stop_playing_scene"):
		return _response(false, "stop_playing_scene is not available in this environment.")

	editor_interface.stop_playing_scene()
	return _response(true, "Scene playback stopped.", {
		"play": _play_status()
	})


func _create_snapshot(actions: Array, reason: String) -> Dictionary:
	var snapshot_id := _safe_id("", "snapshot")
	var snapshot_root := _snapshot_root(snapshot_id)
	var manifest_path := snapshot_root.path_join("manifest.json")
	var manifest := {
		"snapshot_id": snapshot_id,
		"created_at": Time.get_datetime_string_from_system(),
		"reason": reason,
		"root": snapshot_root,
		"manifest_path": manifest_path,
		"action_count": actions.size(),
		"ok": true,
		"messages": [],
		"files": [],
		"directories": [],
		"scene": {}
	}

	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(snapshot_root))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		manifest["ok"] = false
		(manifest["messages"] as Array).append("Failed to create snapshot directory: " + error_string(dir_error))
		return manifest

	_snapshot_files(actions, snapshot_root, manifest)
	_snapshot_directories(actions, manifest)
	_snapshot_current_scene(actions, snapshot_root, manifest)

	var write_error := _write_json_file(manifest_path, manifest)
	if write_error != OK:
		manifest["ok"] = false
		(manifest["messages"] as Array).append("Failed to write snapshot manifest: " + error_string(write_error))
		return manifest

	_record_snapshot(manifest)
	return manifest


func _restore_snapshot(request: Dictionary) -> Dictionary:
	var snapshot_id := str(request.get("snapshot_id", request.get("id", ""))).strip_edges()
	if snapshot_id.is_empty():
		return _response(false, "Missing snapshot_id.")

	var manifest := _load_snapshot_manifest(snapshot_id)
	if manifest.is_empty():
		return _response(false, "Snapshot not found: " + snapshot_id)

	var restored: Array = []
	var errors: Array = []
	for item in manifest.get("files", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry := item as Dictionary
		var path := str(entry.get("path", ""))
		var existed := bool(entry.get("existed", false))
		var backup_path := str(entry.get("backup_path", ""))
		if existed:
			var copy_error := _copy_file(backup_path, path)
			if copy_error == OK:
				restored.append(path)
			else:
				errors.append(path + " -> " + error_string(copy_error))
		elif FileAccess.file_exists(path):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if remove_error == OK:
				restored.append(path)
			else:
				errors.append(path + " -> " + error_string(remove_error))

	var directories := manifest.get("directories", []) as Array
	for reverse_index in directories.size():
		var directory = directories[directories.size() - reverse_index - 1]
		if typeof(directory) != TYPE_DICTIONARY:
			continue
		var dir_entry := directory as Dictionary
		var dir_path := str(dir_entry.get("path", ""))
		if bool(dir_entry.get("existed", false)):
			continue
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
			var remove_dir_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))
			if remove_dir_error != OK:
				errors.append(dir_path + " -> " + error_string(remove_dir_error))

	var scene := manifest.get("scene", {}) as Dictionary
	if bool(scene.get("ok", false)):
		var scene_path := str(scene.get("path", ""))
		var scene_backup := str(scene.get("backup_path", ""))
		var scene_error := _copy_file(scene_backup, scene_path)
		if scene_error == OK:
			restored.append(scene_path)
			_reload_editor_scene(scene_path)
		else:
			errors.append(scene_path + " -> " + error_string(scene_error))

	_refresh_editor_filesystem()
	var ok := errors.is_empty()
	return _response(ok, "Snapshot restored." if ok else "Snapshot restore had errors.", {
		"snapshot": _snapshot_summary(manifest),
		"restored": restored,
		"errors": errors
	})


func _snapshot_files(actions: Array, snapshot_root: String, manifest: Dictionary) -> void:
	var paths := _snapshot_file_targets(actions)
	for path in paths:
		var entry := {
			"path": path,
			"existed": FileAccess.file_exists(path),
			"backup_path": snapshot_root.path_join(_backup_file_name(path)),
			"ok": true
		}
		if bool(entry.get("existed", false)):
			var copy_error := _copy_file(path, str(entry.get("backup_path", "")))
			if copy_error != OK:
				entry["ok"] = false
				manifest["ok"] = false
				(manifest["messages"] as Array).append("Failed to back up file: " + path + " - " + error_string(copy_error))
		(manifest["files"] as Array).append(entry)


func _snapshot_directories(actions: Array, manifest: Dictionary) -> void:
	var paths := _snapshot_directory_targets(actions)
	for path in paths:
		(manifest["directories"] as Array).append({
			"path": path,
			"existed": DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
		})


func _snapshot_current_scene(actions: Array, snapshot_root: String, manifest: Dictionary) -> void:
	if not _actions_touch_scene(actions):
		return

	var root := _edited_scene_root()
	if root == null:
		manifest["scene"] = {
			"ok": false,
			"message": "No editable scene is currently open."
		}
		return

	var scene_path := root.scene_file_path
	if scene_path.strip_edges().is_empty():
		manifest["scene"] = {
			"ok": false,
			"skipped": true,
			"message": "Current scene has no saved path; scene snapshot skipped."
		}
		return

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(root)
	if pack_error != OK:
		manifest["ok"] = false
		manifest["scene"] = {
			"ok": false,
			"path": scene_path,
			"message": "Failed to pack current scene: " + error_string(pack_error)
		}
		return

	var backup_path := snapshot_root.path_join("scene_before.tscn")
	var save_error := ResourceSaver.save(packed_scene, backup_path)
	if save_error != OK:
		manifest["ok"] = false
		manifest["scene"] = {
			"ok": false,
			"path": scene_path,
			"backup_path": backup_path,
			"message": "Failed to save scene snapshot: " + error_string(save_error)
		}
		return

	manifest["scene"] = {
		"ok": true,
		"path": scene_path,
		"backup_path": backup_path
	}


func _snapshot_file_targets(actions: Array) -> Array:
	var paths: Array = []
	for item in actions:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action := item as Dictionary
		var action_type := str(action.get("type", "")).strip_edges()
		if not (action_type in ["write_file", "append_file", "create_scene"]):
			continue
		var path := _normalize_action_path(str(action.get("path", "")))
		if not path.is_empty() and not (path in paths):
			paths.append(path)
	return paths


func _snapshot_directory_targets(actions: Array) -> Array:
	var paths: Array = []
	for item in actions:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action := item as Dictionary
		if str(action.get("type", "")).strip_edges() != "make_dir":
			continue
		var path := _normalize_action_path(str(action.get("path", "")), true)
		if not path.is_empty() and not (path in paths):
			paths.append(path)
	return paths


func _actions_touch_scene(actions: Array) -> bool:
	for item in actions:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action_type := str((item as Dictionary).get("type", "")).strip_edges()
		if action_type in ["add_node", "set_property", "attach_script", "connect_signal"]:
			return true
	return false


func _record_snapshot(manifest: Dictionary) -> void:
	snapshots.append(_snapshot_summary(manifest))
	while snapshots.size() > SNAPSHOT_LIMIT:
		snapshots.pop_front()
	_save_snapshot_index()


func _snapshot_summary(manifest: Dictionary) -> Dictionary:
	var files := manifest.get("files", []) as Array
	var directories := manifest.get("directories", []) as Array
	var scene := manifest.get("scene", {}) as Dictionary
	return {
		"snapshot_id": str(manifest.get("snapshot_id", "")),
		"created_at": str(manifest.get("created_at", "")),
		"reason": str(manifest.get("reason", "")),
		"ok": bool(manifest.get("ok", false)),
		"manifest_path": str(manifest.get("manifest_path", "")),
		"action_count": int(manifest.get("action_count", 0)),
		"file_count": files.size(),
		"directory_count": directories.size(),
		"scene_path": str(scene.get("path", ""))
	}


func _collect_files(dir_path: String, files: Array, max_count: int) -> void:
	if files.size() >= max_count:
		return

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	while files.size() < max_count:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue

		var full_path := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_files(full_path, files, max_count)
		else:
			files.append(full_path)
	dir.list_dir_end()


func _edited_scene_root() -> Node:
	if editor_interface == null or not editor_interface.has_method("get_edited_scene_root"):
		return null
	var root = editor_interface.get_edited_scene_root()
	if root is Node:
		return root as Node
	return null


func _editor_selection():
	if editor_interface == null or not editor_interface.has_method("get_selection"):
		return null
	return editor_interface.get_selection()


func _find_scene_node(raw_path: String) -> Node:
	var root := _edited_scene_root()
	if root == null:
		return null

	var path := raw_path.strip_edges()
	if path.is_empty() or path == "." or path == root.name:
		return root
	if path.begins_with("res://") or path.contains(".."):
		return null
	if path.begins_with("/"):
		path = path.substr(1)
	if path.begins_with(root.name + "/"):
		path = path.substr(root.name.length() + 1)
	if path.is_empty() or path == ".":
		return root

	var node := root.get_node_or_null(NodePath(path))
	if node is Node:
		return node as Node
	return null


func _normalize_action_path(raw_path: String, allow_directory: bool = false) -> String:
	var path := raw_path.strip_edges().replace("\\", "/")
	if path.is_empty():
		return ""
	if not path.begins_with("res://"):
		if path.begins_with("/") or path.begins_with("user://"):
			return ""
		path = "res://" + path
	if path.contains(".."):
		return ""
	if path == "res://" and not allow_directory:
		return ""
	if path.begins_with(PLUGIN_ROOT):
		return ""
	return path


func _normalize_scene_path(raw_path: String) -> String:
	var path := raw_path.strip_edges().replace("\\", "/")
	if path.is_empty():
		return ""
	if not path.begins_with("res://"):
		if path.begins_with("/") or path.begins_with("user://"):
			return ""
		path = "res://" + path
	if path.contains("..") or path.get_extension() != "tscn":
		return ""
	return path


func _normalize_resource_path(raw_path: String, allow_directory: bool = false) -> String:
	var path := raw_path.strip_edges().replace("\\", "/")
	if path.is_empty():
		return ""
	if not path.begins_with("res://"):
		if path.begins_with("/") or path.begins_with("user://"):
			return ""
		path = "res://" + path
	if path.contains("..") or path.begins_with("res://.godot"):
		return ""
	if path == "res://" and not allow_directory:
		return ""
	return path.trim_suffix("/") if allow_directory and path != "res://" else path


func _normalize_resource_paths(raw_paths) -> Array:
	var paths: Array = []
	if typeof(raw_paths) == TYPE_ARRAY:
		for item in raw_paths as Array:
			var path := _normalize_resource_path(str(item))
			if not path.is_empty() and not (path in paths):
				paths.append(path)
	else:
		var path := _normalize_resource_path(str(raw_paths))
		if not path.is_empty():
			paths.append(path)
	return paths


func _resource_extension_filter(raw_extensions) -> Array:
	var extensions: Array = []
	if typeof(raw_extensions) == TYPE_STRING:
		raw_extensions = [raw_extensions]
	if typeof(raw_extensions) != TYPE_ARRAY:
		return extensions
	for item in raw_extensions as Array:
		var extension := str(item).strip_edges().trim_prefix(".").to_lower()
		if not extension.is_empty() and not (extension in extensions):
			extensions.append(extension)
	return extensions


func _normalize_setting_name(raw_setting: String) -> String:
	var setting := raw_setting.strip_edges().replace("\\", "/")
	if setting.is_empty() or setting.begins_with("/") or setting.contains(".."):
		return ""
	return setting


func _normalize_input_action_name(raw_action: String) -> String:
	var action := raw_action.strip_edges()
	if action.is_empty():
		return ""
	for index in action.length():
		var character := action.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int() or character in ["_", "-", "."]:
			continue
		return ""
	return action


func _project_root() -> String:
	return _normalize_absolute_path(ProjectSettings.globalize_path("res://"))


func _history_path() -> String:
	return _file_bridge_root().path_join("history.jsonl")


func _run_reports_path() -> String:
	return _file_bridge_root().path_join("run_reports.jsonl")


func _pending_actions_path() -> String:
	return _file_bridge_root().path_join("pending_actions.json")


func _snapshots_root() -> String:
	return _file_bridge_root().path_join("snapshots")


func _snapshot_root(snapshot_id: String) -> String:
	return _snapshots_root().path_join(snapshot_id)


func _snapshots_index_path() -> String:
	return _snapshots_root().path_join("index.json")


func _create_project_file_snapshot(reason: String) -> Dictionary:
	return _create_snapshot([
		{
			"type": "write_file",
			"path": "res://project.godot"
		}
	], reason)


func _save_project_settings_if_requested(request: Dictionary) -> int:
	if not bool(request.get("save", true)):
		return OK
	return ProjectSettings.save()


func _input_action_snapshot(action_name: String) -> Dictionary:
	if not InputMap.has_action(action_name):
		return {
			"name": action_name,
			"exists": false
		}

	var events: Array = []
	for event in InputMap.action_get_events(action_name):
		if event is InputEvent:
			events.append(_encode_input_event(event as InputEvent))

	return {
		"name": action_name,
		"exists": true,
		"deadzone": InputMap.action_get_deadzone(action_name),
		"events": events
	}


func _sync_input_action_to_project_settings(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	ProjectSettings.set_setting("input/" + action_name, {
		"deadzone": InputMap.action_get_deadzone(action_name),
		"events": InputMap.action_get_events(action_name)
	})


func _decode_input_event(spec):
	if typeof(spec) != TYPE_DICTIONARY:
		return null

	var event_spec := spec as Dictionary
	var event_type := str(event_spec.get("type", "")).strip_edges()
	match event_type:
		"key":
			var key_event := InputEventKey.new()
			key_event.keycode = _decode_keycode(event_spec.get("keycode", event_spec.get("key", 0)))
			if event_spec.has("physical_keycode"):
				key_event.physical_keycode = _decode_keycode(event_spec.get("physical_keycode"))
			key_event.shift_pressed = bool(event_spec.get("shift", false))
			key_event.alt_pressed = bool(event_spec.get("alt", false))
			key_event.ctrl_pressed = bool(event_spec.get("ctrl", false))
			key_event.meta_pressed = bool(event_spec.get("meta", false))
			return key_event
		"mouse_button":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(event_spec.get("button_index", event_spec.get("button", 1)))
			return mouse_event
		"joypad_button":
			var joy_button_event := InputEventJoypadButton.new()
			joy_button_event.button_index = int(event_spec.get("button_index", event_spec.get("button", 0)))
			return joy_button_event
		"joypad_motion":
			var joy_motion_event := InputEventJoypadMotion.new()
			joy_motion_event.axis = int(event_spec.get("axis", 0))
			joy_motion_event.axis_value = float(event_spec.get("axis_value", event_spec.get("value", 1.0)))
			return joy_motion_event
		_:
			return null


func _decode_keycode(value) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var text := str(value).strip_edges()
	if text.is_empty():
		return 0
	if text.begins_with("KEY_"):
		text = text.substr(4)
	return OS.find_keycode_from_string(text)


func _encode_input_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return {
			"type": "key",
			"keycode": key_event.keycode,
			"key": OS.get_keycode_string(key_event.keycode),
			"physical_keycode": key_event.physical_keycode,
			"physical_key": OS.get_keycode_string(key_event.physical_keycode),
			"shift": key_event.shift_pressed,
			"alt": key_event.alt_pressed,
			"ctrl": key_event.ctrl_pressed,
			"meta": key_event.meta_pressed
		}
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return {
			"type": "mouse_button",
			"button_index": mouse_event.button_index
		}
	if event is InputEventJoypadButton:
		var joy_button_event := event as InputEventJoypadButton
		return {
			"type": "joypad_button",
			"button_index": joy_button_event.button_index
		}
	if event is InputEventJoypadMotion:
		var joy_motion_event := event as InputEventJoypadMotion
		return {
			"type": "joypad_motion",
			"axis": joy_motion_event.axis,
			"axis_value": joy_motion_event.axis_value
		}
	return {
		"type": "unknown",
		"class": event.get_class(),
		"text": event.as_text()
	}


func _save_pending_actions() -> void:
	var payload := {
		"updated_at": Time.get_datetime_string_from_system(),
		"pending": pending_action_batches
	}
	var error := _write_json_file(_pending_actions_path(), payload)
	if error != OK:
		push_warning("Godot Codex Bridge could not write pending actions: " + error_string(error))


func _load_pending_actions() -> void:
	var payload := _read_json_file(_pending_actions_path())
	if payload.is_empty():
		return
	var pending := payload.get("pending", [])
	if typeof(pending) != TYPE_ARRAY:
		return
	pending_action_batches = (pending as Array).duplicate(true)
	while pending_action_batches.size() > PENDING_ACTION_LIMIT:
		pending_action_batches.pop_front()


func _save_snapshot_index() -> void:
	var payload := {
		"updated_at": Time.get_datetime_string_from_system(),
		"snapshots": snapshots
	}
	var error := _write_json_file(_snapshots_index_path(), payload)
	if error != OK:
		push_warning("Godot Codex Bridge could not write snapshot index: " + error_string(error))


func _load_snapshot_index() -> void:
	var payload := _read_json_file(_snapshots_index_path())
	if payload.is_empty():
		return
	var items := payload.get("snapshots", [])
	if typeof(items) != TYPE_ARRAY:
		return
	snapshots = (items as Array).duplicate(true)
	while snapshots.size() > SNAPSHOT_LIMIT:
		snapshots.pop_front()


func _load_snapshot_manifest(snapshot_id: String) -> Dictionary:
	for snapshot in snapshots:
		if typeof(snapshot) != TYPE_DICTIONARY:
			continue
		var summary := snapshot as Dictionary
		if str(summary.get("snapshot_id", "")) != snapshot_id:
			continue
		var manifest_path := str(summary.get("manifest_path", ""))
		if manifest_path.is_empty():
			return {}
		return _read_json_file(manifest_path)

	var fallback_path := _snapshot_root(snapshot_id).path_join("manifest.json")
	return _read_json_file(fallback_path)


func _read_json_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _write_json_file(path: String, payload: Dictionary) -> int:
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return dir_error

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(payload, "\t"))
	file.store_string("\n")
	return OK


func _copy_file(source_path: String, target_path: String) -> int:
	if source_path.is_empty() or target_path.is_empty() or not FileAccess.file_exists(source_path):
		return ERR_FILE_NOT_FOUND

	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return dir_error

	var bytes := FileAccess.get_file_as_bytes(source_path)
	var read_error := FileAccess.get_open_error()
	if read_error != OK:
		return read_error

	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	return OK


func _collect_resource_file_infos(dir_path: String, files: Array, max_count: int, extensions: Array, include_import_sidecars: bool) -> void:
	if files.size() >= max_count:
		return

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	while files.size() < max_count:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue

		var full_path := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_resource_file_infos(full_path, files, max_count, extensions, include_import_sidecars)
			continue

		if not include_import_sidecars and full_path.ends_with(".import"):
			continue
		var extension := full_path.get_extension().to_lower()
		if not extensions.is_empty() and not (extension in extensions):
			continue
		files.append(_resource_file_info(full_path, false))
	dir.list_dir_end()


func _resource_file_info(path: String, include_loaded: bool) -> Dictionary:
	var filesystem_type := _editor_file_type(path)
	var info := {
		"path": path,
		"name": path.get_file(),
		"extension": path.get_extension().to_lower(),
		"exists": FileAccess.file_exists(path),
		"resource_exists": ResourceLoader.exists(path),
		"resource_type": filesystem_type,
		"filesystem_type": filesystem_type,
		"imported": FileAccess.file_exists(path + ".import")
	}
	if include_loaded and bool(info.get("resource_exists", false)):
		var resource := load(path)
		if resource is Resource:
			if str(info.get("resource_type", "")).is_empty():
				info["resource_type"] = (resource as Resource).get_class()
			info["loaded"] = {
				"ok": true,
				"class": (resource as Resource).get_class(),
				"resource_path": (resource as Resource).resource_path
			}
		else:
			info["loaded"] = {
				"ok": false
			}
	return info


func _resource_dependencies(path: String) -> Array:
	var dependencies: Array = []
	if not ResourceLoader.exists(path):
		return dependencies
	for dependency in ResourceLoader.get_dependencies(path):
		dependencies.append(str(dependency))
	return dependencies


func _resource_import_info(path: String) -> Dictionary:
	var import_path := path + ".import"
	var info := {
		"import_file": import_path,
		"exists": FileAccess.file_exists(import_path),
		"sections": {}
	}
	if not bool(info.get("exists", false)):
		return info

	var config := ConfigFile.new()
	var error := config.load(import_path)
	info["load_error"] = error
	if error != OK:
		info["message"] = error_string(error)
		return info

	var sections := {}
	for section in config.get_sections():
		sections[str(section)] = _config_section_to_dict(config, str(section))
	info["sections"] = sections
	info["importer"] = str((sections.get("remap", {}) as Dictionary).get("importer", ""))
	info["type"] = str((sections.get("remap", {}) as Dictionary).get("type", ""))
	return info


func _config_section_to_dict(config: ConfigFile, section: String) -> Dictionary:
	var values := {}
	for key in config.get_section_keys(section):
		values[str(key)] = _encode_value(config.get_value(section, str(key)))
	return values


func _editor_file_type(path: String) -> String:
	var filesystem = _editor_resource_filesystem()
	if filesystem != null and filesystem.has_method("get_file_type"):
		return str(filesystem.get_file_type(path))
	return ""


func _editor_resource_filesystem():
	if editor_interface == null or not editor_interface.has_method("get_resource_filesystem"):
		return null
	return editor_interface.get_resource_filesystem()


func _refresh_editor_filesystem() -> void:
	var filesystem = _editor_resource_filesystem()
	if filesystem != null and filesystem.has_method("scan"):
		filesystem.scan()


func _reload_editor_scene(scene_path: String) -> void:
	if editor_interface == null:
		return
	if editor_interface.has_method("reload_scene_from_path"):
		editor_interface.reload_scene_from_path(scene_path)
	elif editor_interface.has_method("open_scene_from_path"):
		editor_interface.open_scene_from_path(scene_path)


func _safe_id(raw_id: String, prefix: String) -> String:
	var value := raw_id.strip_edges()
	if value.is_empty():
		value = prefix + "_" + str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec())

	var safe := ""
	for index in value.length():
		var character := value.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int() or character in ["-", "_"]:
			safe += character
		else:
			safe += "_"
	if safe.is_empty():
		return prefix + "_" + str(Time.get_ticks_msec())
	return safe


func _backup_file_name(path: String) -> String:
	var safe := path.replace("res://", "res__").replace("user://", "user__")
	safe = safe.replace("/", "__").replace("\\", "__").replace(":", "_")
	if safe.is_empty():
		safe = "file"
	return safe


func _has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return true
	return false


func _encode_value(value):
	if value == null:
		return null

	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return {
				"type": "StringName",
				"value": str(value)
			}
		TYPE_NODE_PATH:
			return {
				"type": "NodePath",
				"path": str(value)
			}
		TYPE_VECTOR2:
			return {
				"type": "Vector2",
				"x": value.x,
				"y": value.y
			}
		TYPE_VECTOR2I:
			return {
				"type": "Vector2i",
				"x": value.x,
				"y": value.y
			}
		TYPE_VECTOR3:
			return {
				"type": "Vector3",
				"x": value.x,
				"y": value.y,
				"z": value.z
			}
		TYPE_COLOR:
			return {
				"type": "Color",
				"r": value.r,
				"g": value.g,
				"b": value.b,
				"a": value.a
			}
		TYPE_ARRAY:
			var encoded_array: Array = []
			for item in value:
				encoded_array.append(_encode_value(item))
			return encoded_array
		TYPE_DICTIONARY:
			var encoded_dict := {}
			for key in value.keys():
				encoded_dict[str(key)] = _encode_value(value[key])
			return encoded_dict
		TYPE_OBJECT:
			if value is InputEvent:
				return _encode_input_event(value as InputEvent)
			if value is Resource:
				var resource := value as Resource
				return {
					"type": "Resource",
					"class": resource.get_class(),
					"resource_path": resource.resource_path
				}
			if value is Node:
				var node := value as Node
				var root := _edited_scene_root()
				return {
					"type": "Node",
					"class": node.get_class(),
					"path": "." if node == root else str(root.get_path_to(node)) if root != null else str(node.get_path())
				}
			return {
				"type": "Object",
				"class": (value as Object).get_class()
			}
		TYPE_PACKED_STRING_ARRAY:
			return Array(value)
		TYPE_PACKED_VECTOR2_ARRAY:
			var vector2_array: Array = []
			for item in value:
				vector2_array.append(_encode_value(item))
			return {
				"type": "PackedVector2Array",
				"points": vector2_array
			}
		_:
			return str(value)


func _decode_value(value):
	if typeof(value) != TYPE_DICTIONARY:
		return value

	var value_dict := value as Dictionary
	if value_dict.has("resource_path") and str(value_dict.get("type", "")) != "Resource":
		var resource_path := _normalize_action_path(str(value_dict.get("resource_path", "")))
		return load(resource_path) if not resource_path.is_empty() else null

	var value_type := str(value_dict.get("type", "")).strip_edges()
	match value_type:
		"Vector2":
			return Vector2(float(value_dict.get("x", 0.0)), float(value_dict.get("y", 0.0)))
		"Vector2i":
			return Vector2i(int(value_dict.get("x", 0)), int(value_dict.get("y", 0)))
		"Vector3":
			return Vector3(float(value_dict.get("x", 0.0)), float(value_dict.get("y", 0.0)), float(value_dict.get("z", 0.0)))
		"Color":
			return Color(float(value_dict.get("r", 1.0)), float(value_dict.get("g", 1.0)), float(value_dict.get("b", 1.0)), float(value_dict.get("a", 1.0)))
		"NodePath":
			return NodePath(str(value_dict.get("path", "")))
		"StringName":
			return StringName(str(value_dict.get("value", "")))
		"PackedStringArray":
			var strings := PackedStringArray()
			for item in value_dict.get("values", []):
				strings.append(str(item))
			return strings
		"PackedVector2Array":
			var points: Array = []
			for point in value_dict.get("points", []):
				points.append(_decode_value(point))
			return PackedVector2Array(points)
		"Resource":
			var resource_path := _normalize_action_path(str(value_dict.get("resource_path", "")))
			return load(resource_path) if not resource_path.is_empty() else null
		_:
			return value


func _record_history(entry: Dictionary) -> void:
	history.append(entry.duplicate())
	while history.size() > HISTORY_LIMIT:
		history.pop_front()

	var path := _history_path()
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_warning("Godot Codex Bridge could not create history directory: " + error_string(dir_error))
		return

	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Godot Codex Bridge could not write history: " + error_string(FileAccess.get_open_error()))
		return

	file.seek_end()
	file.store_string(JSON.stringify(entry))
	file.store_string("\n")


func _record_run_report(report: Dictionary) -> void:
	last_run_report = report.duplicate()
	run_reports.append(_run_report_summary(report))
	while run_reports.size() > RUN_REPORT_LIMIT:
		run_reports.pop_front()

	var path := _run_reports_path()
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_warning("Godot Codex Bridge could not create run report directory: " + error_string(dir_error))
		return

	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Godot Codex Bridge could not write run report: " + error_string(FileAccess.get_open_error()))
		return

	file.seek_end()
	file.store_string(JSON.stringify(_run_report_summary(report)))
	file.store_string("\n")


func _run_report_summary(report: Dictionary) -> Dictionary:
	if report.is_empty():
		return {}
	return {
		"mode": report.get("mode", ""),
		"ok": bool(report.get("ok", false)),
		"exit_code": int(report.get("exit_code", -1)),
		"started_at": str(report.get("started_at", "")),
		"duration_ms": int(report.get("duration_ms", 0)),
		"error_count": (report.get("errors", []) as Array).size(),
		"warning_count": (report.get("warnings", []) as Array).size(),
		"errors": report.get("errors", []),
		"warnings": report.get("warnings", []),
		"output_tail": report.get("output_tail", "")
	}


func _join_output(output: Array) -> String:
	var text := ""
	for chunk in output:
		text += str(chunk)
	return text


func _extract_diagnostic_lines(text: String, patterns: Array) -> Array:
	var lines: Array = []
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		var lower_line := line.to_lower()
		for pattern in patterns:
			if lower_line.contains(str(pattern).to_lower()):
				lines.append(line)
				break
	return lines


func _tail_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(text.length() - max_length, max_length)


func _normalize_absolute_path(raw_path: String) -> String:
	var path := raw_path.strip_edges().replace("\\", "/")
	while path.ends_with("/") and path.length() > 1:
		path = path.substr(0, path.length() - 1)
	return path


func _configured_port(fallback_port: int) -> int:
	var raw_port := OS.get_environment("CODEX_GODOT_BRIDGE_PORT").strip_edges()
	if raw_port.is_empty() or not raw_port.is_valid_int():
		return fallback_port

	var parsed_port := int(raw_port)
	if parsed_port < 1024 or parsed_port > 65535:
		return fallback_port
	return parsed_port


func _tcp_bridge_enabled() -> bool:
	var raw_enabled := OS.get_environment("CODEX_GODOT_TCP_BRIDGE_ENABLED").strip_edges().to_lower()
	if raw_enabled in ["1", "true", "yes", "on"]:
		return true
	if raw_enabled in ["0", "false", "no", "off"]:
		return false
	return bool(ProjectSettings.get_setting("codex_bridge/tcp_bridge_enabled", false))


func _file_bridge_enabled() -> bool:
	var raw_enabled := OS.get_environment("CODEX_GODOT_FILE_BRIDGE_ENABLED").strip_edges().to_lower()
	if raw_enabled in ["1", "true", "yes", "on"]:
		return true
	if raw_enabled in ["0", "false", "no", "off"]:
		return false
	return bool(ProjectSettings.get_setting("codex_bridge/file_bridge_enabled", true))


func _file_bridge_root() -> String:
	var env_root := OS.get_environment("CODEX_GODOT_FILE_BRIDGE_ROOT").strip_edges()
	if not env_root.is_empty():
		return env_root.trim_suffix("/")

	var configured := str(ProjectSettings.get_setting("codex_bridge/file_bridge_root", "res://.godot/godot_codex_bridge")).strip_edges()
	if configured.is_empty():
		return "res://.godot/godot_codex_bridge"
	return configured.trim_suffix("/")


func _script_path(node: Node) -> String:
	var script = node.get_script()
	if script is Resource:
		return (script as Resource).resource_path
	return ""


func _node_groups(node: Node) -> Array:
	var groups: Array = []
	for group in node.get_groups():
		groups.append(str(group))
	return groups


func _vector2_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y
	}
