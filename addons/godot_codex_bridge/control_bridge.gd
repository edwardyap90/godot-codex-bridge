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
const CONTROL_PLANE_SCHEMA_VERSION := 2
const RAW_AUDIT_LIMIT := 100
const BRIDGE_VERSION := "0.7.0"
const DESIGN_IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg", "tga", "bmp", "exr", "hdr"]
const DESIGN_AUDIO_EXTENSIONS := ["wav", "ogg", "mp3"]
const DESIGN_FONT_EXTENSIONS := ["ttf", "otf", "woff", "woff2"]
const DESIGN_RESOURCE_EXTENSIONS := ["tres", "res", "tscn", "scn", "material", "gdshader"]
const LAYER_FAMILIES := {
	"2d_physics": {
		"prefix": "layer_names/2d_physics/layer_",
		"count": 20
	},
	"2d_render": {
		"prefix": "layer_names/2d_render/layer_",
		"count": 20
	},
	"3d_physics": {
		"prefix": "layer_names/3d_physics/layer_",
		"count": 32
	},
	"3d_render": {
		"prefix": "layer_names/3d_render/layer_",
		"count": 20
	},
	"2d_navigation": {
		"prefix": "layer_names/2d_navigation/layer_",
		"count": 32
	},
	"3d_navigation": {
		"prefix": "layer_names/3d_navigation/layer_",
		"count": 32
	}
}
const COMMON_PROJECT_SETTINGS := {
	"project_name": "application/config/name",
	"main_scene": "application/run/main_scene",
	"window_width": "display/window/size/viewport_width",
	"window_height": "display/window/size/viewport_height",
	"stretch_mode": "display/window/stretch/mode",
	"stretch_aspect": "display/window/stretch/aspect",
	"rendering_method": "rendering/renderer/rendering_method",
	"physics_ticks_per_second": "physics/common/physics_ticks_per_second",
	"audio_mix_rate": "audio/driver/mix_rate"
}

signal request_handled(command: String, ok: bool, message: String, request_id: String)
signal request_observed(entry: Dictionary)

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
var raw_audit_entries: Array = []


func setup(p_editor_interface, p_port: int = DEFAULT_PORT) -> void:
	editor_interface = p_editor_interface
	executor = ActionExecutor.new()
	executor.setup(editor_interface)
	port = _configured_port(p_port)
	token = OS.get_environment("CODEX_GODOT_BRIDGE_TOKEN").strip_edges()
	_load_pending_actions()
	_load_snapshot_index()
	_load_raw_audit()


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
	request["_bridge_started_ticks"] = Time.get_ticks_msec()
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
				"port": port,
				"schema_version": CONTROL_PLANE_SCHEMA_VERSION
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
		"list_capabilities_v2":
			return _response(true, "ok", {
				"capabilities": _editor_capabilities_v2()
			})
		"get_command_schema":
			return _response(true, "ok", {
				"schema": _command_schema()
			})
		"get_command_timeline":
			return _response(true, "ok", {
				"timeline": history.duplicate(true),
				"history_path": _history_path()
			})
		"get_raw_mode_status":
			return _response(true, "ok", {
				"raw_mode": _raw_mode_status()
			})
		"raw_editor_call":
			return _raw_editor_call(request)
		"raw_object_call":
			return _raw_object_call(request)
		"raw_classdb_query":
			return _raw_classdb_query(request)
		"raw_project_call":
			return _raw_project_call(request)
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
		"get_queue_summary":
			return _queue_summary()
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
		"set_inspector_properties":
			return _set_inspector_properties(request)
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
		"create_resource":
			return _create_resource(request)
		"set_resource_property":
			return _set_resource_property(request)
		"save_resource":
			return _save_resource(request)
		"create_material":
			return _create_material(request)
		"create_theme":
			return _create_theme(request)
		"get_design_status":
			return _get_design_status(request)
		"get_design_system":
			return _get_design_system(request)
		"create_design_system":
			return _create_design_system(request)
		"update_design_system":
			return _update_design_system(request)
		"validate_design_system":
			return _validate_design_system(request)
		"export_design_tokens":
			return _export_design_tokens(request)
		"create_palette":
			return _create_palette(request)
		"create_ui_theme":
			return _create_ui_theme(request)
		"apply_ui_theme":
			return _apply_ui_theme(request)
		"create_ui_template":
			return _create_ui_template(request)
		"inspect_ui_scene":
			return _inspect_ui_scene(request)
		"create_material_pack":
			return _create_material_pack(request)
		"create_placeholder_sprite":
			return _create_placeholder_sprite(request)
		"create_placeholder_icon_set":
			return _create_placeholder_icon_set(request)
		"create_sprite_frames":
			return _create_sprite_frames(request)
		"inspect_sprite_frames":
			return _inspect_sprite_frames(request)
		"create_animated_sprite":
			return _create_animated_sprite(request)
		"create_animation_preview":
			return _create_animation_preview(request)
		"set_texture_import_preset":
			return _set_texture_import_preset(request)
		"create_asset_manifest":
			return _create_asset_manifest(request)
		"create_asset_contact_sheet":
			return _create_asset_contact_sheet(request)
		"create_scene_preview":
			return _create_scene_preview(request)
		"inspect_art_assets":
			return _inspect_art_assets(request)
		"run_design_lint":
			return _run_design_lint(request)
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
		"get_common_project_settings":
			return _get_common_project_settings(request)
		"set_common_project_settings":
			return _set_common_project_settings(request)
		"get_autoloads":
			return _get_autoloads(request)
		"add_autoload":
			return _add_autoload(request)
		"remove_autoload":
			return _remove_autoload(request)
		"get_layer_names":
			return _get_layer_names(request)
		"set_layer_name":
			return _set_layer_name(request)
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
		"bridge_version": BRIDGE_VERSION,
		"schema_version": CONTROL_PLANE_SCHEMA_VERSION,
		"control_plane": _control_plane_status(),
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
		"raw_mode": _raw_mode_status(),
		"raw_audit_count": raw_audit_entries.size(),
		"raw_audit_path": _raw_audit_path(),
		"last_run_report": _run_report_summary(last_run_report),
		"run_reports_path": _run_reports_path(),
		"play": _play_status(),
		"design": _design_status({}),
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


func console_state() -> Dictionary:
	return {
		"status": bridge_status(),
		"pending": _pending_action_summaries(true),
		"snapshots": snapshots.duplicate(true),
		"run_reports": run_reports.duplicate(true),
		"last_run_report": _run_report_summary(last_run_report),
		"play": _play_status(),
		"design": _design_status({}),
		"raw_mode": _raw_mode_status(),
		"raw_audit": raw_audit_entries.duplicate(true)
	}


func _control_plane_status() -> Dictionary:
	return {
		"name": "Godot Control Plane",
		"bridge_version": BRIDGE_VERSION,
		"schema_version": CONTROL_PLANE_SCHEMA_VERSION,
		"godot_version": Engine.get_version_info(),
		"default_mode": "safe",
		"supported_modes": ["safe", "raw"],
		"raw_mode_enabled": _raw_api_enabled()
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
			"set_inspector_property",
			"set_inspector_properties"
		],
		"project_settings": [
			"get_project_settings",
			"get_project_setting",
			"set_project_setting",
			"get_common_project_settings",
			"set_common_project_settings",
			"get_autoloads",
			"add_autoload",
			"remove_autoload",
			"get_layer_names",
			"set_layer_name"
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
			"create_resource",
			"set_resource_property",
			"save_resource",
			"create_material",
			"create_theme",
			"get_design_status",
			"get_design_system",
			"create_design_system",
			"update_design_system",
			"validate_design_system",
			"export_design_tokens",
			"create_palette",
			"create_ui_theme",
			"apply_ui_theme",
			"create_ui_template",
			"inspect_ui_scene",
			"create_material_pack",
				"create_placeholder_sprite",
				"create_placeholder_icon_set",
				"create_sprite_frames",
				"inspect_sprite_frames",
				"create_animated_sprite",
				"create_animation_preview",
				"set_texture_import_preset",
			"create_asset_manifest",
			"create_asset_contact_sheet",
			"create_scene_preview",
			"inspect_art_assets",
			"run_design_lint",
			"scan_resource_filesystem",
			"reimport_resources"
		],
		"design": [
			"get_design_status",
			"get_design_system",
			"create_design_system",
			"update_design_system",
			"validate_design_system",
			"export_design_tokens",
			"create_palette",
			"create_ui_theme",
			"apply_ui_theme",
			"create_ui_template",
			"inspect_ui_scene",
			"create_material_pack",
				"create_placeholder_sprite",
				"create_placeholder_icon_set",
				"create_sprite_frames",
				"inspect_sprite_frames",
				"create_animated_sprite",
				"create_animation_preview",
				"set_texture_import_preset",
			"create_asset_manifest",
			"create_asset_contact_sheet",
			"create_scene_preview",
			"inspect_art_assets",
			"run_design_lint"
		],
			"animation": [
				"get_animation_players",
				"get_animation_player_info",
				"inspect_sprite_frames",
				"create_animated_sprite",
				"create_animation_preview",
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
			"restore_snapshot",
			"get_queue_summary"
		],
		"project_surface": [
			"get_common_project_settings",
			"set_common_project_settings",
			"get_autoloads",
			"add_autoload",
			"remove_autoload",
			"get_layer_names",
			"set_layer_name"
		],
		"resource_helpers": [
			"create_material",
			"create_theme",
			"create_design_system",
			"update_design_system",
			"validate_design_system",
			"export_design_tokens",
			"create_palette",
			"create_ui_theme",
			"create_ui_template",
			"inspect_ui_scene",
			"create_material_pack",
				"create_placeholder_sprite",
				"create_placeholder_icon_set",
				"create_sprite_frames",
				"inspect_sprite_frames",
				"create_animated_sprite",
				"create_animation_preview",
				"set_texture_import_preset",
			"create_asset_manifest",
			"create_asset_contact_sheet",
			"create_scene_preview",
			"inspect_art_assets",
			"run_design_lint"
		],
		"schema": [
			"get_command_schema"
		]
	}


func _editor_capabilities_v2() -> Dictionary:
	var legacy := _editor_capabilities()
	var safe_commands: Array = []
	for key in legacy.keys():
		if typeof(legacy[key]) == TYPE_ARRAY:
			for item in legacy[key] as Array:
				if not safe_commands.has(str(item)):
					safe_commands.append(str(item))

	return {
		"schema_version": CONTROL_PLANE_SCHEMA_VERSION,
		"godot_version": Engine.get_version_info(),
		"project": _project_identity(),
		"transports": legacy.get("transports", []),
		"modes": {
			"default": "safe",
			"safe": {
				"enabled": true,
				"commands": safe_commands
			},
			"raw": _raw_mode_status()
		},
		"protocol": {
			"request_fields": ["schema_version", "request_id", "project_root", "mode", "dry_run", "transaction_id", "command"],
			"response_fields": ["ok", "message", "data", "ui_feedback", "warnings", "changed_paths", "schema_version"]
		},
		"safe_action_types": _supported_action_types(),
		"raw_commands": [
			"raw_editor_call",
			"raw_object_call",
			"raw_classdb_query",
			"raw_project_call"
		],
		"auditing": {
			"history_path": _history_path(),
			"raw_audit_path": _raw_audit_path(),
			"timeline_command": "get_command_timeline"
		},
		"legacy": legacy
	}


func _command_schema() -> Dictionary:
	return {
		"schema_version": CONTROL_PLANE_SCHEMA_VERSION,
		"bridge_version": BRIDGE_VERSION,
		"request_fields": ["schema_version", "request_id", "project_root", "mode", "dry_run", "transaction_id", "command"],
		"response_fields": ["schema_version", "ok", "message", "data", "ui_feedback", "warnings", "changed_paths"],
		"encoded_value_types": ["Vector2", "Vector2i", "Vector3", "Color", "NodePath", "StringName", "PackedStringArray", "PackedFloat32Array", "PackedVector2Array", "Resource"],
		"commands": _command_schema_entries()
	}


func _command_schema_entries() -> Array:
	return [
		_command_schema_entry("ping", "status", false, [], []),
		_command_schema_entry("get_project_identity", "status", false, [], []),
		_command_schema_entry("get_bridge_status", "status", false, [], []),
		_command_schema_entry("list_editor_capabilities", "status", false, [], []),
		_command_schema_entry("list_capabilities_v2", "status", false, [], []),
		_command_schema_entry("get_command_schema", "schema", false, [], []),
		_command_schema_entry("get_command_history", "status", false, [], []),
		_command_schema_entry("get_command_timeline", "status", false, [], []),
		_command_schema_entry("get_queue_summary", "queue", false, [], []),
		_command_schema_entry("get_pending_actions", "queue", false, [], []),
		_command_schema_entry("preview_actions", "queue", false, ["actions"], []),
		_command_schema_entry("queue_actions", "queue", true, ["actions"], ["summary", "queue_id"]),
		_command_schema_entry("apply_queued_actions", "queue", true, ["queue_id"], []),
		_command_schema_entry("discard_queued_actions", "queue", true, ["queue_id"], []),
		_command_schema_entry("apply_actions", "queue", true, ["actions"], ["dry_run"]),
		_command_schema_entry("get_snapshots", "snapshot", false, [], []),
		_command_schema_entry("restore_snapshot", "snapshot", true, ["snapshot_id"], []),
		_command_schema_entry("get_project_info", "project", false, [], []),
		_command_schema_entry("get_open_scene", "scene", false, [], []),
		_command_schema_entry("get_editor_context", "scene", false, [], []),
		_command_schema_entry("get_scene_tree", "scene", false, [], []),
		_command_schema_entry("get_selection", "scene", false, [], []),
		_command_schema_entry("get_node_details", "scene", false, ["node_path"], []),
		_command_schema_entry("select_node", "scene", false, ["node_path"], []),
		_command_schema_entry("save_scene", "scene", true, [], []),
		_command_schema_entry("get_inspector_properties", "inspector", false, [], ["node_path", "resource_path", "include_internal", "include_values", "max_count"]),
		_command_schema_entry("set_inspector_property", "inspector", true, ["property", "value"], ["node_path", "resource_path"]),
		_command_schema_entry("set_inspector_properties", "inspector", true, ["properties"], ["node_path", "resource_path"]),
		_command_schema_entry("get_project_settings", "project", false, [], ["prefix", "include_values", "max_count"]),
		_command_schema_entry("get_project_setting", "project", false, ["setting"], []),
		_command_schema_entry("set_project_setting", "project", true, ["setting", "value"], ["save"]),
		_command_schema_entry("get_common_project_settings", "project", false, [], []),
		_command_schema_entry("set_common_project_settings", "project", true, ["settings"], ["save"]),
		_command_schema_entry("get_autoloads", "project", false, [], []),
		_command_schema_entry("add_autoload", "project", true, ["name", "path"], ["singleton", "save"]),
		_command_schema_entry("remove_autoload", "project", true, ["name"], ["save"]),
		_command_schema_entry("get_layer_names", "project", false, [], ["family", "max_count"]),
		_command_schema_entry("set_layer_name", "project", true, ["family", "layer", "name"], ["save"]),
		_command_schema_entry("get_input_actions", "input", false, [], ["prefix", "include_builtin"]),
		_command_schema_entry("add_input_action", "input", true, ["action"], ["deadzone", "events", "replace_events", "save"]),
		_command_schema_entry("remove_input_action", "input", true, ["action"], ["save"]),
		_command_schema_entry("get_project_files", "resource", false, [], []),
		_command_schema_entry("get_resource_files", "resource", false, [], ["root", "extensions", "max_count"]),
		_command_schema_entry("get_resource_info", "resource", false, ["path"], ["include_loaded", "include_dependencies", "include_import"]),
		_command_schema_entry("get_resource_import_info", "resource", false, ["path"], []),
		_command_schema_entry("create_resource", "resource", true, ["path", "resource_type"], ["replace", "properties"]),
		_command_schema_entry("create_material", "resource", true, ["path"], ["material_type", "replace", "properties"]),
		_command_schema_entry("create_theme", "resource", true, ["path"], ["replace", "colors", "constants", "font_sizes"]),
		_command_schema_entry("get_design_status", "design", false, [], ["root"]),
		_command_schema_entry("get_design_system", "design", false, [], ["root"]),
		_command_schema_entry("create_design_system", "design", true, [], ["root", "name", "style", "palette", "tokens", "asset_roles", "replace"]),
		_command_schema_entry("update_design_system", "design", true, [], ["root", "updates", "tokens", "asset_roles", "style", "create_if_missing"]),
		_command_schema_entry("validate_design_system", "design", false, [], ["root"]),
		_command_schema_entry("export_design_tokens", "design", true, [], ["root", "path", "replace"]),
		_command_schema_entry("create_palette", "design", true, [], ["path", "root", "name", "colors", "replace"]),
		_command_schema_entry("create_ui_theme", "design", true, [], ["path", "palette_path", "palette", "colors", "replace"]),
		_command_schema_entry("apply_ui_theme", "design", true, ["theme_path"], ["node_path", "recursive"]),
		_command_schema_entry("create_ui_template", "design", true, ["template"], ["path", "root", "title", "theme_path", "replace", "open_after"]),
		_command_schema_entry("inspect_ui_scene", "design", false, [], ["node_path", "scene_path", "min_touch_size"]),
		_command_schema_entry("create_material_pack", "design", true, [], ["root", "palette_path", "palette", "materials", "replace"]),
		_command_schema_entry("create_placeholder_sprite", "design", true, [], ["path", "root", "name", "role", "width", "height", "shape", "color", "replace"]),
		_command_schema_entry("create_placeholder_icon_set", "design", true, [], ["root", "icons", "size", "palette_path", "replace"]),
		_command_schema_entry("create_sprite_frames", "design", true, ["path", "animations"], ["replace"]),
		_command_schema_entry("inspect_sprite_frames", "animation", true, ["path"], ["expected_animations", "write_report", "report_path"]),
		_command_schema_entry("create_animated_sprite", "animation", true, ["sprite_frames_path"], ["parent_path", "name", "animation", "position", "speed_scale", "autoplay", "centered"]),
		_command_schema_entry("create_animation_preview", "animation", true, ["sprite_frames_path"], ["root", "path", "report_path", "thumb_size", "columns", "replace"]),
		_command_schema_entry("set_texture_import_preset", "design", true, ["paths"], ["preset", "settings", "create_sidecar", "reimport"]),
		_command_schema_entry("create_asset_manifest", "design", true, [], ["root", "path", "replace"]),
		_command_schema_entry("create_asset_contact_sheet", "design", true, [], ["root", "path", "report_path", "thumb_size", "columns", "max_count", "replace"]),
		_command_schema_entry("create_scene_preview", "design", true, [], ["root", "path", "report_path", "scene_path", "width", "height", "replace"]),
		_command_schema_entry("inspect_art_assets", "design", true, [], ["root", "extensions", "max_count", "write_report"]),
		_command_schema_entry("run_design_lint", "design", true, [], ["root", "node_path", "scene_path", "write_report"]),
		_command_schema_entry("set_resource_property", "resource", true, ["path", "property", "value"], []),
		_command_schema_entry("save_resource", "resource", true, ["path"], []),
		_command_schema_entry("scan_resource_filesystem", "import", false, [], ["scan_sources"]),
		_command_schema_entry("reimport_resources", "import", true, ["paths"], []),
		_command_schema_entry("get_animation_players", "animation", false, [], []),
		_command_schema_entry("get_animation_player_info", "animation", false, ["node_path"], []),
		_command_schema_entry("create_animation", "animation", true, ["node_path", "animation_name"], ["length", "loop_mode", "library", "replace"]),
		_command_schema_entry("set_animation_properties", "animation", true, ["node_path", "animation_name"], ["length", "loop_mode", "library"]),
		_command_schema_entry("add_animation_value_key", "animation", true, ["node_path", "animation_name", "target_path", "property", "time", "value"], ["library"]),
		_command_schema_entry("execute_editor_command", "editor", true, ["editor_command"], []),
		_command_schema_entry("run_check_only", "run", false, [], []),
		_command_schema_entry("run_project_headless", "run", false, [], ["duration_sec"]),
		_command_schema_entry("get_last_run_report", "run", false, [], []),
		_command_schema_entry("get_play_status", "run", false, [], []),
		_command_schema_entry("play_main_scene", "run", true, [], []),
		_command_schema_entry("play_current_scene", "run", true, [], []),
		_command_schema_entry("play_custom_scene", "run", true, ["scene_path"], []),
		_command_schema_entry("stop_playing_scene", "run", true, [], []),
		_command_schema_entry("stop_playing", "run", true, [], []),
		_command_schema_entry("get_raw_mode_status", "raw", false, [], []),
		_command_schema_entry("raw_editor_call", "raw", true, ["target", "method"], ["args"]),
		_command_schema_entry("raw_object_call", "raw", true, ["method"], ["node_path", "resource_path", "args"]),
		_command_schema_entry("raw_classdb_query", "raw", false, ["query"], ["class", "method", "property", "signal"]),
		_command_schema_entry("raw_project_call", "raw", true, ["target", "method"], ["args"])
	]


func _command_schema_entry(command: String, family: String, mutates: bool, required: Array, optional: Array) -> Dictionary:
	return {
		"command": command,
		"family": family,
		"mode": "raw" if command.begins_with("raw_") else "safe",
		"mutates": mutates,
		"required": required,
		"optional": optional
	}


func _raw_mode_status() -> Dictionary:
	return {
		"enabled": _raw_api_enabled(),
		"setting": "codex_bridge/raw_api_enabled",
		"env": "CODEX_GODOT_RAW_API_ENABLED",
		"executes_arbitrary_code": false,
		"allowed_commands": [
			"raw_editor_call",
			"raw_object_call",
			"raw_classdb_query",
			"raw_project_call"
		],
		"allowed_editor_targets": {
			"editor_interface": _raw_allowed_editor_methods("editor_interface"),
			"selection": _raw_allowed_editor_methods("selection"),
			"resource_filesystem": _raw_allowed_editor_methods("resource_filesystem")
		},
		"allowed_project_targets": {
			"ProjectSettings": _raw_allowed_project_methods("ProjectSettings"),
			"InputMap": _raw_allowed_project_methods("InputMap"),
			"ResourceLoader": _raw_allowed_project_methods("ResourceLoader")
		},
		"audit_path": _raw_audit_path(),
		"audit_count": raw_audit_entries.size()
	}


func _raw_api_enabled() -> bool:
	var raw_enabled := OS.get_environment("CODEX_GODOT_RAW_API_ENABLED").strip_edges().to_lower()
	if raw_enabled in ["1", "true", "yes", "on"]:
		return true
	if raw_enabled in ["0", "false", "no", "off"]:
		return false
	return bool(ProjectSettings.get_setting("codex_bridge/raw_api_enabled", false))


func _raw_disabled_response(command: String) -> Dictionary:
	return _response(false, "Raw API mode is disabled. Set codex_bridge/raw_api_enabled=true to enable controlled raw calls.", {
		"raw_mode": _raw_mode_status(),
		"command": command
	}, ["Raw commands are rejected while raw mode is disabled."])


func _raw_editor_call(request: Dictionary) -> Dictionary:
	if not _raw_api_enabled():
		return _raw_disabled_response("raw_editor_call")

	var target_name := str(request.get("target", "editor_interface")).strip_edges()
	var method := str(request.get("method", request.get("name", ""))).strip_edges()
	if method.is_empty():
		return _response(false, "Missing raw editor method.")
	if not _raw_allowed_editor_methods(target_name).has(method):
		return _response(false, "Raw editor method is not allowed: " + target_name + "." + method, {
			"allowed": _raw_allowed_editor_methods(target_name)
		})

	var target = _raw_editor_target(target_name)
	if target == null:
		return _response(false, "Raw editor target is not available: " + target_name)
	if not target.has_method(method):
		return _response(false, "Raw editor target does not have method: " + method)

	var args := _decode_raw_args(request.get("args", []))
	if bool(request.get("dry_run", false)):
		return _response(true, "Raw editor call preview.", {
			"target": target_name,
			"method": method,
			"arg_count": args.size(),
			"dry_run": true
		})

	var result = target.callv(method, args)
	return _response(true, "Raw editor call executed.", {
		"target": target_name,
		"method": method,
		"result": _encode_value(result)
	}, [], [], {
		"type": "raw_editor_call",
		"target": target_name,
		"method": method
	})


func _raw_object_call(request: Dictionary) -> Dictionary:
	if not _raw_api_enabled():
		return _raw_disabled_response("raw_object_call")

	var resolved := _resolve_raw_object(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))

	var object := resolved.get("object") as Object
	var method := str(request.get("method", request.get("name", ""))).strip_edges()
	if method.is_empty():
		return _response(false, "Missing raw object method.")
	var kind := str(resolved.get("kind", "object"))
	if not _raw_allowed_object_methods(kind).has(method):
		return _response(false, "Raw object method is not allowed: " + kind + "." + method, {
			"allowed": _raw_allowed_object_methods(kind)
		})
	if not object.has_method(method):
		return _response(false, "Raw object target does not have method: " + method)

	var args := _decode_raw_args(request.get("args", []))
	var snapshot := {}
	if _raw_mutating_object_methods().has(method):
		snapshot = _create_object_snapshot(object, str(resolved.get("path", "")), "raw_object_call " + method)
		if not bool(snapshot.get("ok", true)):
			return _response(false, "Failed to create raw call snapshot; method was not called.", {
				"snapshot": snapshot
			})

	if bool(request.get("dry_run", false)):
		return _response(true, "Raw object call preview.", {
			"target": resolved.get("target", {}),
			"method": method,
			"arg_count": args.size(),
			"dry_run": true,
			"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
		})

	var result = object.callv(method, args)
	if object is Node and _raw_mutating_object_methods().has(method):
		_set_scene_dirty()
		_focus_editor_node(object as Node)
	elif object is Resource and _raw_mutating_object_methods().has(method):
		var resource := object as Resource
		if not resource.resource_path.is_empty():
			ResourceSaver.save(resource, resource.resource_path)

	return _response(true, "Raw object call executed.", {
		"target": resolved.get("target", {}),
		"method": method,
		"result": _encode_value(result),
		"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
	}, [], _changed_paths_for_raw_object(resolved), {
		"type": "raw_object_call",
		"target": resolved.get("target", {}),
		"method": method
	})


func _raw_classdb_query(request: Dictionary) -> Dictionary:
	if not _raw_api_enabled():
		return _raw_disabled_response("raw_classdb_query")

	var query := str(request.get("query", request.get("query_type", "class_exists"))).strip_edges()
	var db_class_name := str(request.get("class", request.get("class_name", ""))).strip_edges()
	match query:
		"class_exists":
			return _response(true, "ok", {
				"query": query,
				"class": db_class_name,
				"exists": ClassDB.class_exists(db_class_name)
			})
		"can_instantiate":
			return _response(true, "ok", {
				"query": query,
				"class": db_class_name,
				"can_instantiate": ClassDB.class_exists(db_class_name) and ClassDB.can_instantiate(db_class_name)
			})
		"property_list":
			if not ClassDB.class_exists(db_class_name):
				return _response(false, "Class does not exist: " + db_class_name)
			return _response(true, "ok", {
				"query": query,
				"class": db_class_name,
				"properties": _encode_value(ClassDB.class_get_property_list(db_class_name, true))
			})
		"method_list":
			if not ClassDB.class_exists(db_class_name):
				return _response(false, "Class does not exist: " + db_class_name)
			return _response(true, "ok", {
				"query": query,
				"class": db_class_name,
				"methods": _encode_value(ClassDB.class_get_method_list(db_class_name, true))
			})
		"signal_list":
			if not ClassDB.class_exists(db_class_name):
				return _response(false, "Class does not exist: " + db_class_name)
			return _response(true, "ok", {
				"query": query,
				"class": db_class_name,
				"signals": _encode_value(ClassDB.class_get_signal_list(db_class_name, true))
			})
		_:
			return _response(false, "Unsupported ClassDB raw query: " + query, {
				"allowed": ["class_exists", "can_instantiate", "property_list", "method_list", "signal_list"]
			})


func _raw_project_call(request: Dictionary) -> Dictionary:
	if not _raw_api_enabled():
		return _raw_disabled_response("raw_project_call")

	var target_name := str(request.get("target", "ProjectSettings")).strip_edges()
	var method := str(request.get("method", request.get("name", ""))).strip_edges()
	if method.is_empty():
		return _response(false, "Missing raw project method.")
	if not _raw_allowed_project_methods(target_name).has(method):
		return _response(false, "Raw project method is not allowed: " + target_name + "." + method, {
			"allowed": _raw_allowed_project_methods(target_name)
		})

	var target = _raw_project_target(target_name)
	if target == null:
		return _response(false, "Raw project target is not available: " + target_name)
	if not target.has_method(method):
		return _response(false, "Raw project target does not have method: " + method)

	var args := _decode_raw_args(request.get("args", []))
	var snapshot := {}
	if target_name in ["ProjectSettings", "InputMap"] and _raw_mutating_project_methods().has(method):
		snapshot = _create_project_file_snapshot("raw_project_call " + target_name + "." + method)
		if not bool(snapshot.get("ok", true)):
			return _response(false, "Failed to create project snapshot; raw project call was not executed.", {
				"snapshot": snapshot
			})

	if bool(request.get("dry_run", false)):
		return _response(true, "Raw project call preview.", {
			"target": target_name,
			"method": method,
			"arg_count": args.size(),
			"dry_run": true,
			"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
		})

	var result = target.callv(method, args)
	var changed_paths: Array = []
	if target_name in ["ProjectSettings", "InputMap"] and _raw_mutating_project_methods().has(method):
		_append_unique_path(changed_paths, "res://project.godot")
	return _response(true, "Raw project call executed.", {
		"target": target_name,
		"method": method,
		"result": _encode_value(result),
		"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
	}, [], changed_paths, {
		"type": "raw_project_call",
		"target": target_name,
		"method": method
	})


func _raw_allowed_editor_methods(target_name: String) -> Array:
	match target_name:
		"editor_interface":
			return ["save_scene", "open_scene_from_path", "reload_scene_from_path", "play_main_scene", "play_current_scene", "play_custom_scene", "stop_playing_scene", "edit_node", "mark_scene_as_unsaved"]
		"selection":
			return ["clear", "add_node"]
		"resource_filesystem":
			return ["scan", "scan_sources", "reimport_files"]
		_:
			return []


func _raw_editor_target(target_name: String):
	match target_name:
		"editor_interface":
			return editor_interface
		"selection":
			return _editor_selection()
		"resource_filesystem":
			return _editor_resource_filesystem()
		_:
			return null


func _raw_allowed_object_methods(kind: String) -> Array:
	match kind:
		"node":
			return ["get", "set", "add_to_group", "remove_from_group", "set_meta", "remove_meta"]
		"resource":
			return ["get", "set", "set_meta", "remove_meta"]
		_:
			return ["get"]


func _raw_mutating_object_methods() -> Array:
	return ["set", "add_to_group", "remove_from_group", "set_meta", "remove_meta"]


func _raw_allowed_project_methods(target_name: String) -> Array:
	match target_name:
		"ProjectSettings":
			return ["get_setting", "has_setting", "set_setting", "clear", "save"]
		"InputMap":
			return ["get_actions", "has_action", "add_action", "erase_action", "action_set_deadzone", "action_erase_events"]
		"ResourceLoader":
			return ["exists", "load", "get_dependencies"]
		_:
			return []


func _raw_mutating_project_methods() -> Array:
	return ["set_setting", "clear", "save", "add_action", "erase_action", "action_set_deadzone", "action_erase_events"]


func _raw_project_target(target_name: String):
	match target_name:
		"ProjectSettings":
			return ProjectSettings
		"InputMap":
			return InputMap
		"ResourceLoader":
			return ResourceLoader
		_:
			return null


func _resolve_raw_object(request: Dictionary) -> Dictionary:
	var resource_path := str(request.get("resource_path", "")).strip_edges()
	if not resource_path.is_empty():
		var normalized_resource_path := _normalize_resource_path(resource_path)
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
			"kind": "resource",
			"path": normalized_resource_path,
			"target": {
				"kind": "resource",
				"path": normalized_resource_path,
				"class": (resource as Resource).get_class()
			}
		}

	var node_path := str(request.get("node_path", request.get("path", ""))).strip_edges()
	var node := _find_scene_node(node_path)
	if node == null:
		return {
			"ok": false,
			"message": "Node target not found."
		}
	var root := _edited_scene_root()
	var normalized_node_path := "." if node == root else str(root.get_path_to(node))
	return {
		"ok": true,
		"object": node,
		"kind": "node",
		"path": normalized_node_path,
		"target": {
			"kind": "node",
			"path": normalized_node_path,
			"class": node.get_class(),
			"script": _script_path(node)
		}
	}


func _decode_raw_args(raw_args) -> Array:
	var args: Array = []
	if typeof(raw_args) != TYPE_ARRAY:
		return args
	for item in raw_args as Array:
		args.append(_decode_raw_arg(item))
	return args


func _decode_raw_arg(value):
	if typeof(value) == TYPE_DICTIONARY:
		var value_dict := value as Dictionary
		if value_dict.has("node_path"):
			return _find_scene_node(str(value_dict.get("node_path", "")))
		if value_dict.has("resource_path") and str(value_dict.get("type", "")) != "Resource":
			var resource_path := _normalize_resource_path(str(value_dict.get("resource_path", "")))
			return load(resource_path) if not resource_path.is_empty() else null
		if value_dict.has("packed_string_array"):
			return PackedStringArray(value_dict.get("packed_string_array", []))
	return _decode_value(value)


func _changed_paths_for_raw_object(resolved: Dictionary) -> Array:
	var paths: Array = []
	var path := str(resolved.get("path", ""))
	if str(resolved.get("kind", "")) == "resource":
		_append_unique_path(paths, path)
	else:
		var root := _edited_scene_root()
		if root != null and not root.scene_file_path.is_empty():
			_append_unique_path(paths, root.scene_file_path)
	return paths


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


func _response(ok: bool, message: String, data: Dictionary = {}, warnings: Array = [], changed_paths: Array = [], ui_feedback: Dictionary = {}) -> Dictionary:
	return {
		"schema_version": CONTROL_PLANE_SCHEMA_VERSION,
		"ok": ok,
		"message": message,
		"data": data,
		"warnings": warnings,
		"changed_paths": changed_paths,
		"ui_feedback": ui_feedback
	}


func _request_summary(command: String, data: Dictionary) -> String:
	match command:
		"queue_actions":
			var queued := data.get("queued", {}) as Dictionary
			var queue_id := str(queued.get("queue_id", ""))
			var action_count := int(queued.get("action_count", 0))
			return "Queued " + str(action_count) + " actions" + (" as " + queue_id if not queue_id.is_empty() else "")
		"apply_queued_actions", "apply_actions":
			var action_result := data.get("action_result", {}) as Dictionary
			return "Applied " + str(action_result.get("applied", 0)) + " / " + str(action_result.get("total", 0)) + " actions"
		"preview_actions":
			var preview := data.get("preview", {}) as Dictionary
			return "Previewed " + str(preview.get("total", 0)) + " actions, invalid " + str(preview.get("invalid", 0))
		"restore_snapshot":
			var snapshot := data.get("snapshot", {}) as Dictionary
			return "Restored snapshot " + str(snapshot.get("snapshot_id", ""))
		"add_autoload", "remove_autoload":
			var after := data.get("after", {}) as Dictionary
			var before := data.get("before", {}) as Dictionary
			var item := after if not after.is_empty() else before
			return "Autoload " + str(item.get("name", ""))
		"set_layer_name":
			return "Layer " + str(data.get("family", "")) + "/" + str(data.get("layer", "")) + " -> " + str(data.get("after", ""))
		"set_common_project_settings":
			return "Updated " + str((data.get("changes", []) as Array).size()) + " common project settings"
		"create_material", "create_theme":
			return "Created " + str(data.get("path", ""))
		"create_design_system":
			return "Created design system at " + str(data.get("root", ""))
		"update_design_system":
			return "Updated design system at " + str(data.get("path", ""))
		"validate_design_system":
			return "Design system " + ("valid" if bool(data.get("valid", false)) else "has issues")
		"export_design_tokens":
			return "Exported design tokens to " + str(data.get("path", ""))
		"create_palette", "create_ui_theme":
			return "Created " + str(data.get("path", ""))
		"apply_ui_theme":
			return "Applied theme to " + str(data.get("applied_count", 0)) + " Control node(s)"
		"create_ui_template":
			return "Created " + str(data.get("template", "")) + " UI template"
		"inspect_ui_scene":
			return "Inspected " + str((data.get("controls", []) as Array).size()) + " Control node(s)"
		"create_material_pack":
			return "Created " + str((data.get("paths", []) as Array).size()) + " material resource(s)"
		"create_placeholder_sprite":
			return "Created placeholder sprite " + str(data.get("path", ""))
		"create_placeholder_icon_set":
			return "Created " + str((data.get("paths", []) as Array).size()) + " placeholder icon(s)"
		"create_sprite_frames":
			return "Created SpriteFrames " + str(data.get("path", ""))
		"inspect_sprite_frames":
			return "Inspected SpriteFrames " + str(data.get("path", ""))
		"create_animated_sprite":
			return "Created AnimatedSprite2D " + str((data.get("node", {}) as Dictionary).get("path", ""))
		"create_animation_preview":
			return "Created animation preview " + str(data.get("path", ""))
		"set_texture_import_preset":
			return "Updated " + str((data.get("updated", []) as Array).size()) + " texture import preset(s)"
		"create_asset_manifest":
			return "Created asset manifest " + str(data.get("path", ""))
		"create_asset_contact_sheet":
			return "Created asset contact sheet " + str(data.get("path", ""))
		"create_scene_preview":
			return "Created scene preview " + str(data.get("path", ""))
		"inspect_art_assets":
			return "Inspected " + str((data.get("files", []) as Array).size()) + " art asset(s)"
		"run_design_lint":
			return "Design lint found " + str(data.get("issue_count", 0)) + " issue(s)"
		"get_queue_summary":
			return str(data.get("pending_count", 0)) + " pending batches / " + str(data.get("action_count", 0)) + " actions"
		"play_main_scene", "play_current_scene", "play_custom_scene", "stop_playing_scene", "stop_playing":
			var play := data.get("play", {}) as Dictionary
			return "playing " + str(play.get("is_playing", false))
		"select_node":
			var selection := data.get("selection", []) as Array
			return "Selected " + str(selection.size()) + " node(s)"
		_:
			return ""


func _request_mode(request: Dictionary) -> String:
	var mode := str(request.get("mode", "safe")).strip_edges().to_lower()
	if mode.is_empty():
		return "safe"
	return mode


func _ui_feedback_for_response(command: String, data: Dictionary) -> Dictionary:
	if data.has("visual_feedback"):
		return {
			"type": "visual_feedback",
			"command": command,
			"details": data.get("visual_feedback", {})
		}
	if data.has("selection"):
		return {
			"type": "selection",
			"command": command,
			"details": data.get("selection", [])
		}
	if data.has("target"):
		return {
			"type": "inspector_target",
			"command": command,
			"details": data.get("target", {})
		}
	if data.has("report"):
		var report := data.get("report", {}) as Dictionary
		return {
			"type": "run_report",
			"command": command,
			"ok": bool(report.get("ok", false)),
			"errors": (report.get("errors", []) as Array).size(),
			"warnings": (report.get("warnings", []) as Array).size()
		}
	return {
		"type": "command",
		"command": command
	}


func _changed_paths_for_response(command: String, data: Dictionary) -> Array:
	var paths: Array = []
	if data.has("changed_paths") and typeof(data.get("changed_paths")) == TYPE_ARRAY:
		for item in data.get("changed_paths", []) as Array:
			_append_unique_path(paths, str(item))
	if data.has("snapshot"):
		var snapshot := data.get("snapshot", {}) as Dictionary
		var scene_path := str(snapshot.get("scene_path", ""))
		_append_unique_path(paths, scene_path)
	if data.has("action_result"):
		var action_result := data.get("action_result", {}) as Dictionary
		for item in action_result.get("results", []) as Array:
			if typeof(item) == TYPE_DICTIONARY:
				_append_unique_path(paths, str((item as Dictionary).get("path", "")))
	if data.has("path"):
		_append_unique_path(paths, str(data.get("path", "")))
	if data.has("paths") and typeof(data.get("paths")) == TYPE_ARRAY:
		for item in data.get("paths", []) as Array:
			_append_unique_path(paths, str(item))
	match command:
		"set_project_setting", "set_common_project_settings", "add_autoload", "remove_autoload", "set_layer_name", "add_input_action", "remove_input_action":
			_append_unique_path(paths, "res://project.godot")
	return paths


func _append_unique_path(paths: Array, path: String) -> void:
	var value := path.strip_edges()
	if value.is_empty() or value == ".":
		return
	if not paths.has(value):
		paths.append(value)


func _finish_request(command: String, request: Dictionary, response: Dictionary) -> Dictionary:
	var request_id := str(request.get("request_id", ""))
	var data := response.get("data", {}) as Dictionary
	var started_ticks := int(request.get("_bridge_started_ticks", Time.get_ticks_msec()))
	var duration_ms := maxi(Time.get_ticks_msec() - started_ticks, 0)
	var ui_feedback := response.get("ui_feedback", {})
	if typeof(ui_feedback) != TYPE_DICTIONARY or (ui_feedback as Dictionary).is_empty():
		ui_feedback = _ui_feedback_for_response(command, data)
	var changed_paths := response.get("changed_paths", [])
	if typeof(changed_paths) != TYPE_ARRAY or (changed_paths as Array).is_empty():
		changed_paths = _changed_paths_for_response(command, data)
	var warnings := response.get("warnings", [])
	if typeof(warnings) != TYPE_ARRAY:
		warnings = []
	response["schema_version"] = int(response.get("schema_version", CONTROL_PLANE_SCHEMA_VERSION))
	response["ui_feedback"] = ui_feedback
	response["changed_paths"] = changed_paths
	response["warnings"] = warnings
	var entry := {
		"schema_version": int(response.get("schema_version", CONTROL_PLANE_SCHEMA_VERSION)),
		"command": command,
		"ok": bool(response.get("ok", false)),
		"message": str(response.get("message", "")),
		"request_id": request_id,
		"transaction_id": str(request.get("transaction_id", "")),
		"mode": _request_mode(request),
		"updated_at": Time.get_datetime_string_from_system(),
		"duration_ms": duration_ms,
		"dry_run": bool(request.get("dry_run", false)),
		"client_cwd": str(request.get("client_cwd", "")),
		"summary": _request_summary(command, data),
		"visual_feedback": data.get("visual_feedback", {}),
		"ui_feedback": ui_feedback,
		"changed_paths": changed_paths,
		"warnings": warnings
	}
	last_request = entry
	_record_history(entry)
	if command.begins_with("raw_"):
		_record_raw_audit(entry)
	request_handled.emit(command, bool(response.get("ok", false)), str(response.get("message", "")), request_id)
	request_observed.emit(entry)
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


func _create_resource(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty():
		return _response(false, "Resource path is invalid.")
	if not (path.get_extension().to_lower() in ["tres", "res"]):
		return _response(false, "Resource path must end with .tres or .res.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "Resource already exists: " + path)
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create resource directory: " + error_string(dir_error), {
			"path": path
		})

	var resource_type := str(request.get("resource_type", request.get("type", "Resource"))).strip_edges()
	var resource := _instantiate_resource(resource_type, request.get("properties", {}))
	if resource == null:
		return _response(false, "Cannot instantiate Resource type: " + resource_type)
	resource.resource_path = path

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		}
	], "create_resource " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; resource was not saved.", {
			"snapshot": snapshot
		})

	var save_error := ResourceSaver.save(resource, path)
	if save_error != OK:
		return _response(false, "Failed to save resource: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		}, [], [path])
	_refresh_editor_filesystem()
	return _response(true, "Resource created.", {
		"path": path,
		"resource": _resource_file_info(path, true),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _set_resource_property(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty():
		return _response(false, "Resource path is invalid.")
	var property_name := str(request.get("property", "")).strip_edges()
	if property_name.is_empty():
		return _response(false, "Missing property.")

	var resource := load(path)
	if not resource is Resource:
		return _response(false, "Cannot load resource: " + path)
	if not _has_property(resource, property_name):
		return _response(false, "Resource does not have property: " + property_name)

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		}
	], "set_resource_property " + path + "." + property_name)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; resource was not modified.", {
			"snapshot": snapshot
		})

	var before_value = resource.get(property_name)
	resource.set(property_name, _decode_value(request.get("value")))
	var save_error := ResourceSaver.save(resource, path)
	return _response(save_error == OK, "Resource property updated." if save_error == OK else "Resource property updated, but saving failed: " + error_string(save_error), {
		"path": path,
		"property": property_name,
		"before": _encode_value(before_value),
		"after": _encode_value(resource.get(property_name)),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _save_resource(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty():
		return _response(false, "Resource path is invalid.")
	var resource := load(path)
	if not resource is Resource:
		return _response(false, "Cannot load resource: " + path)
	var save_error := ResourceSaver.save(resource, path)
	return _response(save_error == OK, "Resource saved." if save_error == OK else "Failed to save resource: " + error_string(save_error), {
		"path": path,
		"resource": _resource_file_info(path, true)
	}, [], [path] if save_error == OK else [])


func _create_material(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty():
		return _response(false, "Material path is invalid.")
	if not (path.get_extension().to_lower() in ["tres", "res"]):
		return _response(false, "Material path must end with .tres or .res.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "Material resource already exists: " + path)

	var material_type := str(request.get("material_type", request.get("resource_type", "CanvasItemMaterial"))).strip_edges()
	var material := _instantiate_resource(material_type, request.get("properties", {}))
	if material == null or not material is Material:
		return _response(false, "Cannot instantiate Material type: " + material_type)
	material.resource_path = path
	return _save_new_resource(material, path, "Material created.", "create_material " + path)


func _create_theme(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty():
		return _response(false, "Theme path is invalid.")
	if not (path.get_extension().to_lower() in ["tres", "res"]):
		return _response(false, "Theme path must end with .tres or .res.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "Theme resource already exists: " + path)

	var theme := Theme.new()
	theme.resource_path = path
	var errors: Array = []
	errors.append_array(_apply_theme_values(theme, "colors", request.get("colors", {})))
	errors.append_array(_apply_theme_values(theme, "constants", request.get("constants", {})))
	errors.append_array(_apply_theme_values(theme, "font_sizes", request.get("font_sizes", {})))
	if not errors.is_empty():
		return _response(false, "Theme entries contained errors.", {
			"errors": errors
		})
	return _save_new_resource(theme, path, "Theme created.", "create_theme " + path)


func _get_design_status(request: Dictionary) -> Dictionary:
	return _response(true, "ok", {
		"design": _design_status(request)
	})


func _get_design_system(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Design root is invalid or protected.")
	var path := _design_system_path(root)
	var payload := _read_json_file(path)
	return _response(true, "ok", {
		"root": root,
		"path": path,
		"exists": FileAccess.file_exists(path),
		"design_system": payload
	})


func _create_design_system(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", request.get("path", "res://art"))))
	if root.is_empty():
		return _response(false, "Design root is invalid or protected.")

	var name := str(request.get("name", ProjectSettings.get_setting("application/config/name", "Game Art"))).strip_edges()
	if name.is_empty():
		name = "Game Art"
	var style := str(request.get("style", request.get("art_direction", "playful game UI"))).strip_edges()
	var replace := bool(request.get("replace", false))
	var system_path := _design_system_path(root)
	if FileAccess.file_exists(system_path) and not replace:
		return _response(false, "Design system already exists: " + system_path)

	var palette_entries := _design_palette_entries(request.get("palette", request.get("colors", {})))
	var tokens := _default_design_tokens(palette_entries, request)
	if request.has("tokens") and typeof(request.get("tokens")) == TYPE_DICTIONARY:
		_deep_merge_dictionary(tokens, request.get("tokens") as Dictionary)
	var directories := [
		root,
		root.path_join("palettes"),
		root.path_join("themes"),
		root.path_join("materials"),
		root.path_join("sprites"),
		root.path_join("ui"),
		root.path_join("references"),
		root.path_join("reports")
	]
	var snapshot_actions: Array = [
		{
			"type": "write_file",
			"path": system_path
		}
	]
	for directory in directories:
		snapshot_actions.append({
			"type": "make_dir",
			"path": str(directory)
		})
	var snapshot := _create_snapshot(snapshot_actions, "create_design_system " + root)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; design system was not created.", {
			"snapshot": snapshot
		})

	for directory in directories:
		var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(directory)))
		if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
			return _response(false, "Failed to create design directory: " + error_string(dir_error), {
				"directory": str(directory),
				"snapshot": _snapshot_summary(snapshot)
			})

	var payload := {
		"schema_version": 2,
		"name": name,
		"style": style,
		"root": root,
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system(),
		"palette": _design_palette_payload(palette_entries),
		"tokens": tokens,
		"asset_roles": request.get("asset_roles", _default_design_asset_roles()),
		"ui_templates": ["main_menu", "hud", "pause_menu"],
		"directories": directories,
		"notes": [
			"Keep generated art, themes, palettes, and reports under this project-local root.",
			"Use bridge design commands so Godot can show snapshots, changed files, and UI feedback."
		]
	}
	var write_error := _write_json_file(system_path, payload)
	if write_error != OK:
		return _response(false, "Failed to write design system: " + error_string(write_error), {
			"path": system_path,
			"snapshot": _snapshot_summary(snapshot)
		})

	_refresh_editor_filesystem()
	return _response(true, "Design system created.", {
		"root": root,
		"path": system_path,
		"palette": payload.get("palette", []),
		"directories": directories,
		"design": _design_status({
			"root": root
		}),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [system_path])


func _update_design_system(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Design root is invalid or protected.")
	var path := _design_system_path(root)
	var exists := FileAccess.file_exists(path)
	if not exists and not bool(request.get("create_if_missing", false)):
		return _response(false, "Design system does not exist: " + path)

	var payload := _read_json_file(path) if exists else _default_design_system_payload(root, request)
	if payload.is_empty():
		payload = _default_design_system_payload(root, request)
	var updates = request.get("updates", {})
	if typeof(updates) == TYPE_DICTIONARY:
		_deep_merge_dictionary(payload, updates as Dictionary)
	if request.has("style"):
		payload["style"] = str(request.get("style", ""))
	if request.has("tokens") and typeof(request.get("tokens")) == TYPE_DICTIONARY:
		if not payload.has("tokens") or typeof(payload.get("tokens")) != TYPE_DICTIONARY:
			payload["tokens"] = {}
		_deep_merge_dictionary(payload["tokens"] as Dictionary, request.get("tokens") as Dictionary)
	if request.has("asset_roles"):
		payload["asset_roles"] = request.get("asset_roles")
	payload["schema_version"] = 2
	payload["root"] = root
	payload["updated_at"] = Time.get_datetime_string_from_system()

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		}
	], "update_design_system " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; design system was not updated.", {
			"snapshot": snapshot
		})
	var write_error := _write_json_file(path, payload)
	if write_error != OK:
		return _response(false, "Failed to write design system: " + error_string(write_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Design system updated.", {
		"root": root,
		"path": path,
		"design_system": payload,
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _validate_design_system(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Design root is invalid or protected.")
	return _response(true, "Design system validation completed.", _design_system_validation(root, request))


func _export_design_tokens(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Design root is invalid or protected.")
	var design_system := _read_json_file(_design_system_path(root))
	if design_system.is_empty():
		return _response(false, "Design system does not exist: " + _design_system_path(root))
	var path := _normalize_resource_path(str(request.get("path", root.path_join("design_tokens.json"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "Design tokens path is invalid or protected.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "Design tokens already exist: " + path)

	var tokens := design_system.get("tokens", {})
	if typeof(tokens) != TYPE_DICTIONARY or (tokens as Dictionary).is_empty():
		tokens = _default_design_tokens(_design_palette_entries(design_system), request)
	var payload := {
		"schema_version": 1,
		"source": _design_system_path(root),
		"generated_at": Time.get_datetime_string_from_system(),
		"tokens": tokens
	}
	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		}
	], "export_design_tokens " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; tokens were not exported.", {
			"snapshot": snapshot
		})
	var write_error := _write_json_file(path, payload)
	if write_error != OK:
		return _response(false, "Failed to write design tokens: " + error_string(write_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Design tokens exported.", {
		"root": root,
		"path": path,
		"tokens": tokens,
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _create_palette(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Palette root is invalid or protected.")
	var name := str(request.get("name", "game_palette")).strip_edges()
	if name.is_empty():
		name = "game_palette"
	var path := _normalize_resource_path(str(request.get("path", root.path_join("palettes").path_join(_safe_design_slug(name, "palette") + ".json"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "Palette path is invalid or protected.")
	if path.get_extension().to_lower() != "json":
		return _response(false, "Palette path must end with .json.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "Palette already exists: " + path)

	var palette_entries := _design_palette_entries(request.get("colors", request.get("palette", {})))
	var payload := {
		"schema_version": 1,
		"name": name,
		"created_at": Time.get_datetime_string_from_system(),
		"colors": _design_palette_payload(palette_entries)
	}
	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		}
	], "create_palette " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; palette was not saved.", {
			"snapshot": snapshot
		})

	var write_error := _write_json_file(path, payload)
	if write_error != OK:
		return _response(false, "Failed to write palette: " + error_string(write_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Palette created.", {
		"path": path,
		"palette": payload.get("colors", []),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _create_ui_theme(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "UI theme root is invalid or protected.")
	var name := str(request.get("name", "game_theme")).strip_edges()
	if name.is_empty():
		name = "game_theme"
	var path := _normalize_resource_path(str(request.get("path", root.path_join("themes").path_join(_safe_design_slug(name, "theme") + ".tres"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "UI theme path is invalid or protected.")
	if not (path.get_extension().to_lower() in ["tres", "res"]):
		return _response(false, "UI theme path must end with .tres or .res.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "UI theme already exists: " + path)

	var palette_result := _design_palette_entries_from_request(request)
	if not bool(palette_result.get("ok", false)):
		return _response(false, str(palette_result.get("message", "")))
	var palette_entries := palette_result.get("palette", []) as Array
	var theme := _build_ui_theme_from_palette(palette_entries, request)
	theme.resource_path = path
	var errors: Array = []
	errors.append_array(_apply_theme_values(theme, "colors", request.get("colors", {})))
	errors.append_array(_apply_theme_values(theme, "constants", request.get("constants", {})))
	errors.append_array(_apply_theme_values(theme, "font_sizes", request.get("font_sizes", {})))
	if not errors.is_empty():
		return _response(false, "UI theme entries contained errors.", {
			"errors": errors
		})

	var save_response := _save_new_resource(theme, path, "UI theme created.", "create_ui_theme " + path)
	if bool(save_response.get("ok", false)):
		var data := save_response.get("data", {}) as Dictionary
		data["palette"] = _design_palette_payload(palette_entries)
		data["design"] = _design_status({
			"root": root
		})
		save_response["data"] = data
	return save_response


func _apply_ui_theme(request: Dictionary) -> Dictionary:
	var theme_path := _normalize_resource_path(str(request.get("theme_path", request.get("path", ""))))
	if theme_path.is_empty() or not _design_path_allowed(theme_path):
		return _response(false, "Theme path is invalid or protected.")
	var theme = load(theme_path)
	if not theme is Theme:
		return _response(false, "Cannot load Theme resource: " + theme_path)

	var node_path := str(request.get("node_path", request.get("target", "."))).strip_edges()
	if node_path.is_empty():
		node_path = "."
	var target := _find_scene_node(node_path)
	if target == null:
		return _response(false, "Theme target node was not found: " + node_path)

	var controls: Array = []
	_collect_control_nodes(target, bool(request.get("recursive", true)), controls)
	if controls.is_empty():
		return _response(false, "Theme target does not contain Control nodes: " + node_path)

	var snapshot := _create_snapshot([
		{
			"type": "set_property",
			"node_path": node_path,
			"property": "theme"
		}
	], "apply_ui_theme " + theme_path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; theme was not applied.", {
			"snapshot": snapshot
		})

	for item in controls:
		if item is Control:
			(item as Control).theme = theme as Theme
	_set_scene_dirty()
	_focus_editor_node(target)
	return _response(true, "UI theme applied.", {
		"theme_path": theme_path,
		"target_path": node_path,
		"applied_count": controls.size(),
		"snapshot": _snapshot_summary(snapshot),
		"visual_feedback": _visual_feedback_for_node(target)
	})


func _create_ui_template(request: Dictionary) -> Dictionary:
	var template := _safe_design_slug(str(request.get("template", request.get("name", ""))), "")
	if not (template in ["main_menu", "hud", "pause_menu"]):
		return _response(false, "Unsupported UI template. Use main_menu, hud, or pause_menu.")
	var root_dir := _normalize_design_root(str(request.get("root", "res://ui")))
	if root_dir.is_empty():
		return _response(false, "UI template root is invalid or protected.")
	var path := _normalize_resource_path(str(request.get("path", root_dir.path_join(template + ".tscn"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "UI template path is invalid or protected.")
	if path.get_extension().to_lower() != "tscn":
		return _response(false, "UI template path must end with .tscn.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "UI template scene already exists: " + path)

	var theme: Theme = null
	var theme_path := _normalize_resource_path(str(request.get("theme_path", "")))
	if not theme_path.is_empty():
		var loaded_theme = load(theme_path)
		if not loaded_theme is Theme:
			return _response(false, "Cannot load UI theme: " + theme_path)
		theme = loaded_theme as Theme

	var scene_root := _build_ui_template_scene(template, request, theme)
	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(scene_root)
	if pack_error != OK:
		scene_root.free()
		return _response(false, "Failed to pack UI template: " + error_string(pack_error))

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		},
		{
			"type": "make_dir",
			"path": path.get_base_dir()
		}
	], "create_ui_template " + path)
	if not bool(snapshot.get("ok", true)):
		scene_root.free()
		return _response(false, "Failed to create pre-change snapshot; UI template was not saved.", {
			"snapshot": snapshot
		})

	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		scene_root.free()
		return _response(false, "Failed to create UI template directory: " + error_string(dir_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var save_error := ResourceSaver.save(packed_scene, path)
	var node_count := _count_nodes(scene_root)
	scene_root.free()
	if save_error != OK:
		return _response(false, "Failed to save UI template: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	if bool(request.get("open_after", false)) and editor_interface != null and editor_interface.has_method("open_scene_from_path"):
		editor_interface.open_scene_from_path(path)
	return _response(true, "UI template created.", {
		"template": template,
		"path": path,
		"node_count": node_count,
		"theme_path": theme_path,
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _inspect_ui_scene(request: Dictionary) -> Dictionary:
	var inspection := _inspect_ui_scene_data(request)
	if not bool(inspection.get("ok", false)):
		return _response(false, str(inspection.get("message", "")))
	return _response(true, "UI scene inspected.", inspection)


func _create_material_pack(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art/materials")))
	if root.is_empty():
		return _response(false, "Material pack root is invalid or protected.")
	var replace := bool(request.get("replace", false))
	var palette_result := _design_palette_entries_from_request(request)
	if not bool(palette_result.get("ok", false)):
		return _response(false, str(palette_result.get("message", "")))
	var palette_entries := palette_result.get("palette", []) as Array
	var specs := _design_material_specs(request.get("materials", []), palette_entries)
	if specs.is_empty():
		return _response(false, "No material specs were provided.")

	var shader_path := root.path_join("tint_canvas_item.gdshader")
	if FileAccess.file_exists(shader_path) and not replace:
		return _response(false, "Tint shader already exists: " + shader_path)
	var paths: Array = [shader_path]
	for spec in specs:
		var spec_dict := spec as Dictionary
		var material_path := root.path_join(_safe_design_slug(str(spec_dict.get("name", "")), "material") + ".tres")
		if FileAccess.file_exists(material_path) and not replace:
			return _response(false, "Material already exists: " + material_path)
		spec_dict["path"] = material_path
		paths.append(material_path)

	var snapshot_actions: Array = [
		{
			"type": "make_dir",
			"path": root
		}
	]
	for path in paths:
		snapshot_actions.append({
			"type": "write_file",
			"path": str(path)
		})
	var snapshot := _create_snapshot(snapshot_actions, "create_material_pack " + root)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; material pack was not saved.", {
			"snapshot": snapshot
		})

	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create material directory: " + error_string(dir_error), {
			"root": root,
			"snapshot": _snapshot_summary(snapshot)
		})

	var shader := Shader.new()
	shader.code = _design_tint_shader_code()
	shader.resource_path = shader_path
	var shader_save_error := ResourceSaver.save(shader, shader_path)
	if shader_save_error != OK:
		return _response(false, "Failed to save tint shader: " + error_string(shader_save_error), {
			"path": shader_path,
			"snapshot": _snapshot_summary(snapshot)
		})

	var saved: Array = [shader_path]
	var materials: Array = []
	var errors: Array = []
	for spec in specs:
		var spec_dict := spec as Dictionary
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("tint_color", spec_dict.get("color", Color.WHITE))
		material.resource_path = str(spec_dict.get("path", ""))
		var save_error := ResourceSaver.save(material, material.resource_path)
		if save_error == OK:
			saved.append(material.resource_path)
			materials.append({
				"name": str(spec_dict.get("name", "")),
				"path": material.resource_path,
				"color": _encode_value(spec_dict.get("color", Color.WHITE))
			})
		else:
			errors.append(material.resource_path + " -> " + error_string(save_error))

	_refresh_editor_filesystem()
	return _response(errors.is_empty(), "Material pack created." if errors.is_empty() else "Material pack had errors.", {
		"root": root,
		"shader_path": shader_path,
		"paths": saved,
		"materials": materials,
		"errors": errors,
		"snapshot": _snapshot_summary(snapshot)
	}, [], saved)


func _create_placeholder_sprite(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art/sprites")))
	if root.is_empty():
		return _response(false, "Placeholder sprite root is invalid or protected.")
	var name := str(request.get("name", request.get("role", "sprite"))).strip_edges()
	if name.is_empty():
		name = "sprite"
	var role := _safe_design_slug(str(request.get("role", name)), "sprite")
	var path := _normalize_resource_path(str(request.get("path", root.path_join(_safe_design_slug(name, "sprite") + ".png"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "Placeholder sprite path is invalid or protected.")
	if path.get_extension().to_lower() != "png":
		return _response(false, "Placeholder sprite path must end with .png.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "Placeholder sprite already exists: " + path)

	var width := mini(maxi(int(request.get("width", request.get("size", 64))), 8), 1024)
	var height := mini(maxi(int(request.get("height", request.get("size", 64))), 8), 1024)
	var shape := _safe_design_slug(str(request.get("shape", role)), "diamond")
	var fallback_color := _placeholder_color_for_role(role)
	var color := _decode_design_color(request.get("color", fallback_color), fallback_color)
	var outline := _decode_design_color(request.get("outline_color", "#edf5ff"), Color(0.93, 0.96, 1.0, 1.0))
	var image := _build_placeholder_image(width, height, shape, color, outline)

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		},
		{
			"type": "make_dir",
			"path": path.get_base_dir()
		}
	], "create_placeholder_sprite " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; placeholder sprite was not saved.", {
			"snapshot": snapshot
		})
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create sprite directory: " + error_string(dir_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var save_error := image.save_png(path)
	if save_error != OK:
		return _response(false, "Failed to save placeholder sprite: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Placeholder sprite created.", {
		"path": path,
		"role": role,
		"width": width,
		"height": height,
		"shape": shape,
		"color": _encode_value(color),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _create_placeholder_icon_set(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art/icons")))
	if root.is_empty():
		return _response(false, "Placeholder icon root is invalid or protected.")
	var replace := bool(request.get("replace", false))
	var size := mini(maxi(int(request.get("size", 48)), 8), 512)
	var palette_result := _design_palette_entries_from_request(request)
	if not bool(palette_result.get("ok", false)):
		return _response(false, str(palette_result.get("message", "")))
	var palette_map := _design_palette_color_map(palette_result.get("palette", []) as Array)
	var icon_specs := _placeholder_icon_specs(request.get("icons", []), palette_map)
	if icon_specs.is_empty():
		return _response(false, "No placeholder icons were provided.")

	var paths: Array = []
	for spec in icon_specs:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var spec_dict := spec as Dictionary
		var path := root.path_join(_safe_design_slug(str(spec_dict.get("name", "icon")), "icon") + ".png")
		if FileAccess.file_exists(path) and not replace:
			return _response(false, "Placeholder icon already exists: " + path)
		spec_dict["path"] = path
		paths.append(path)

	var snapshot_actions: Array = [
		{
			"type": "make_dir",
			"path": root
		}
	]
	for path in paths:
		snapshot_actions.append({
			"type": "write_file",
			"path": str(path)
		})
	var snapshot := _create_snapshot(snapshot_actions, "create_placeholder_icon_set " + root)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; icons were not saved.", {
			"snapshot": snapshot
		})
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create icon directory: " + error_string(dir_error), {
			"root": root,
			"snapshot": _snapshot_summary(snapshot)
		})

	var saved: Array = []
	var icons: Array = []
	var errors: Array = []
	for spec in icon_specs:
		var spec_dict := spec as Dictionary
		var icon_path := str(spec_dict.get("path", ""))
		var image := _build_placeholder_image(size, size, str(spec_dict.get("shape", "diamond")), spec_dict.get("color", Color.WHITE), Color(0.93, 0.96, 1.0, 1.0))
		var save_error := image.save_png(icon_path)
		if save_error == OK:
			saved.append(icon_path)
			icons.append({
				"name": str(spec_dict.get("name", "")),
				"path": icon_path,
				"shape": str(spec_dict.get("shape", "")),
				"color": _encode_value(spec_dict.get("color", Color.WHITE))
			})
		else:
			errors.append(icon_path + " -> " + error_string(save_error))
	_refresh_editor_filesystem()
	return _response(errors.is_empty(), "Placeholder icon set created." if errors.is_empty() else "Placeholder icon set had errors.", {
		"root": root,
		"paths": saved,
		"icons": icons,
		"errors": errors,
		"snapshot": _snapshot_summary(snapshot)
	}, [], saved)


func _create_sprite_frames(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("resource_path", ""))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "SpriteFrames path is invalid or protected.")
	if not (path.get_extension().to_lower() in ["tres", "res"]):
		return _response(false, "SpriteFrames path must end with .tres or .res.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "SpriteFrames already exists: " + path)
	var raw_animations := request.get("animations", [])
	if typeof(raw_animations) != TYPE_ARRAY or (raw_animations as Array).is_empty():
		return _response(false, "create_sprite_frames requires a non-empty animations array.")

	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")
	var animations: Array = []
	var dependencies: Array = []
	for item in raw_animations as Array:
		if typeof(item) != TYPE_DICTIONARY:
			return _response(false, "Animation spec must be a Dictionary.")
		var spec := item as Dictionary
		var animation_name := _safe_design_slug(str(spec.get("name", "default")), "default")
		var frame_paths := _normalize_resource_paths(spec.get("frames", spec.get("paths", [])))
		if frame_paths.is_empty():
			return _response(false, "Animation has no valid frame paths: " + animation_name)
		if not sprite_frames.has_animation(animation_name):
			sprite_frames.add_animation(animation_name)
		sprite_frames.set_animation_speed(animation_name, maxf(float(spec.get("fps", spec.get("speed", 8.0))), 0.1))
		sprite_frames.set_animation_loop(animation_name, bool(spec.get("loop", true)))
		var frame_count := 0
		for frame_path in frame_paths:
			var texture := _texture_from_image_path(frame_path)
			if texture == null:
				return _response(false, "Cannot load frame texture: " + frame_path)
			sprite_frames.add_frame(animation_name, texture)
			frame_count += 1
			if not dependencies.has(frame_path):
				dependencies.append(frame_path)
		animations.append({
			"name": animation_name,
			"frame_count": frame_count,
			"fps": sprite_frames.get_animation_speed(animation_name),
			"loop": sprite_frames.get_animation_loop(animation_name)
		})

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		},
		{
			"type": "make_dir",
			"path": path.get_base_dir()
		}
	], "create_sprite_frames " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; SpriteFrames were not saved.", {
			"snapshot": snapshot
		})
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create SpriteFrames directory: " + error_string(dir_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	sprite_frames.resource_path = path
	var save_error := ResourceSaver.save(sprite_frames, path)
	if save_error != OK:
		return _response(false, "Failed to save SpriteFrames: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "SpriteFrames created.", {
		"path": path,
		"animations": animations,
		"dependencies": dependencies,
		"snapshot": _snapshot_summary(snapshot)
		}, [], [path])


func _inspect_sprite_frames(request: Dictionary) -> Dictionary:
	var path := _normalize_resource_path(str(request.get("path", request.get("sprite_frames_path", request.get("resource_path", "")))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "SpriteFrames path is invalid or protected.")
	if not FileAccess.file_exists(path):
		return _response(false, "SpriteFrames file does not exist: " + path)
	var resource = load(path)
	if not resource is SpriteFrames:
		return _response(false, "Resource is not SpriteFrames: " + path)

	var report := _sprite_frames_report(resource as SpriteFrames, path, request.get("expected_animations", []))
	var changed_paths: Array = []
	if bool(request.get("write_report", false)):
		var report_path := _normalize_resource_path(str(request.get("report_path", path.get_basename() + "_animation_report.json")))
		if report_path.is_empty() or not _design_path_allowed(report_path):
			return _response(false, "SpriteFrames report path is invalid or protected.")
		if report_path.get_extension().to_lower() != "json":
			return _response(false, "SpriteFrames report path must end with .json.")
		var snapshot := _create_snapshot([
			{
				"type": "write_file",
				"path": report_path
			}
		], "inspect_sprite_frames " + path)
		if not bool(snapshot.get("ok", true)):
			return _response(false, "Failed to create pre-change snapshot; SpriteFrames report was not saved.", {
				"snapshot": snapshot
			})
		report["report_path"] = report_path
		report["snapshot"] = _snapshot_summary(snapshot)
		var write_error := _write_json_file(report_path, report)
		if write_error != OK:
			return _response(false, "Failed to write SpriteFrames report: " + error_string(write_error), {
				"path": report_path,
				"snapshot": _snapshot_summary(snapshot)
			})
		changed_paths.append(report_path)
		_refresh_editor_filesystem()

	return _response(true, "SpriteFrames inspected.", report, report.get("issues", []) as Array, changed_paths)


func _create_animated_sprite(request: Dictionary) -> Dictionary:
	var sprite_frames_path := _normalize_resource_path(str(request.get("sprite_frames_path", request.get("path", ""))))
	if sprite_frames_path.is_empty() or not _design_path_allowed(sprite_frames_path):
		return _response(false, "SpriteFrames path is invalid or protected.")
	if not FileAccess.file_exists(sprite_frames_path):
		return _response(false, "SpriteFrames file does not exist: " + sprite_frames_path)
	var resource = load(sprite_frames_path)
	if not resource is SpriteFrames:
		return _response(false, "Resource is not SpriteFrames: " + sprite_frames_path)
	var sprite_frames := resource as SpriteFrames
	var animation_names := _sprite_frame_animation_names(sprite_frames)
	if animation_names.is_empty():
		return _response(false, "SpriteFrames has no animations: " + sprite_frames_path)

	var parent_path := str(request.get("parent_path", ".")).strip_edges()
	if parent_path.is_empty():
		parent_path = "."
	var parent := _find_scene_node(parent_path)
	if parent == null:
		return _response(false, "Parent node not found: " + parent_path)
	var scene_root := _edited_scene_root()
	if scene_root == null:
		return _response(false, "No editable scene is currently open.")

	var node_name := str(request.get("name", "AnimatedSprite2D")).strip_edges()
	if node_name.is_empty() or node_name.contains("/") or node_name.contains("\\") or node_name.contains(".."):
		return _response(false, "AnimatedSprite2D name is invalid.")
	if parent.get_node_or_null(NodePath(node_name)) != null:
		return _response(false, "Parent already has a child named: " + node_name)

	var animation_name := _normalize_animation_name(str(request.get("animation", request.get("default_animation", ""))))
	if animation_name.is_empty():
		animation_name = str(animation_names[0])
	if not sprite_frames.has_animation(animation_name):
		return _response(false, "SpriteFrames animation not found: " + animation_name, {
			"available_animations": animation_names
		})

	var snapshot := _create_animation_scene_snapshot("create_animated_sprite " + node_name)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; AnimatedSprite2D was not added.", {
			"snapshot": snapshot
		})

	var node := AnimatedSprite2D.new()
	node.name = node_name
	node.sprite_frames = sprite_frames
	node.animation = animation_name
	node.speed_scale = maxf(float(request.get("speed_scale", 1.0)), 0.01)
	node.centered = bool(request.get("centered", true))
	if request.has("position"):
		var decoded_position = _decode_value(request.get("position"))
		if decoded_position is Vector2:
			node.position = decoded_position as Vector2
	parent.add_child(node)
	node.owner = scene_root
	if bool(request.get("autoplay", false)):
		if _has_property(node, "autoplay"):
			node.set("autoplay", animation_name)
		node.play(animation_name)
	_focus_editor_node(node)
	_set_scene_dirty()

	var changed_paths: Array = []
	if not scene_root.scene_file_path.is_empty():
		changed_paths.append(scene_root.scene_file_path)
	return _response(true, "AnimatedSprite2D created.", {
		"sprite_frames_path": sprite_frames_path,
		"animation": animation_name,
		"node": _node_summary(node, scene_root),
		"snapshot": _snapshot_summary(snapshot)
	}, [], changed_paths, {
		"type": "scene_selection",
		"node_path": str(scene_root.get_path_to(node)),
		"inspector_focused": true
	})


func _create_animation_preview(request: Dictionary) -> Dictionary:
	var sprite_frames_path := _normalize_resource_path(str(request.get("sprite_frames_path", request.get("path", ""))))
	if sprite_frames_path.is_empty() or not _design_path_allowed(sprite_frames_path):
		return _response(false, "SpriteFrames path is invalid or protected.")
	if not FileAccess.file_exists(sprite_frames_path):
		return _response(false, "SpriteFrames file does not exist: " + sprite_frames_path)
	var resource = load(sprite_frames_path)
	if not resource is SpriteFrames:
		return _response(false, "Resource is not SpriteFrames: " + sprite_frames_path)
	var sprite_frames := resource as SpriteFrames

	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Animation preview root is invalid or protected.")
	var default_name := _safe_design_slug(sprite_frames_path.get_file().get_basename(), "sprite_frames") + "_animation_preview.png"
	var path := _normalize_resource_path(str(request.get("path", root.path_join("reports").path_join(default_name))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "Animation preview path is invalid or protected.")
	if path.get_extension().to_lower() != "png":
		return _response(false, "Animation preview path must end with .png.")
	var report_path := _normalize_resource_path(str(request.get("report_path", path.get_basename() + ".json")))
	if report_path.is_empty() or not _design_path_allowed(report_path):
		return _response(false, "Animation preview report path is invalid or protected.")
	if report_path.get_extension().to_lower() != "json":
		return _response(false, "Animation preview report path must end with .json.")
	if not bool(request.get("replace", false)):
		if FileAccess.file_exists(path):
			return _response(false, "Animation preview already exists: " + path)
		if FileAccess.file_exists(report_path):
			return _response(false, "Animation preview report already exists: " + report_path)

	var thumb_size := mini(maxi(int(request.get("thumb_size", 64)), 24), 256)
	var columns := mini(maxi(int(request.get("columns", 8)), 1), 24)
	var preview_data := _build_animation_preview_image(sprite_frames, sprite_frames_path, thumb_size, columns)
	var preview_image = preview_data.get("image", null)
	if not preview_image is Image:
		return _response(false, "Failed to build animation preview image.")

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		},
		{
			"type": "write_file",
			"path": report_path
		},
		{
			"type": "make_dir",
			"path": path.get_base_dir()
		}
	], "create_animation_preview " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; animation preview was not saved.", {
			"snapshot": snapshot
		})
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create animation preview directory: " + error_string(dir_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var save_error := (preview_image as Image).save_png(path)
	if save_error != OK:
		return _response(false, "Failed to save animation preview: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var report := _sprite_frames_report(sprite_frames, sprite_frames_path, request.get("expected_animations", []))
	report["preview_path"] = path
	report["report_path"] = report_path
	report["preview"] = {
		"width": int(preview_data.get("width", 0)),
		"height": int(preview_data.get("height", 0)),
		"thumb_size": thumb_size,
		"columns": columns,
		"rows": int(preview_data.get("rows", 0))
	}
	report["snapshot"] = _snapshot_summary(snapshot)
	var write_error := _write_json_file(report_path, report)
	if write_error != OK:
		return _response(false, "Failed to write animation preview report: " + error_string(write_error), {
			"path": report_path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Animation preview created.", {
		"path": path,
		"report_path": report_path,
		"sprite_frames_path": sprite_frames_path,
		"animation_count": int(report.get("animation_count", 0)),
		"frame_count": int(report.get("frame_count", 0)),
		"preview": report.get("preview", {}),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path, report_path])


func _set_texture_import_preset(request: Dictionary) -> Dictionary:
	var paths := _normalize_resource_paths(request.get("paths", request.get("path", [])))
	if paths.is_empty():
		return _response(false, "set_texture_import_preset requires one or more paths.")
	var preset := _safe_design_slug(str(request.get("preset", "pixel_2d")), "pixel_2d")
	var settings := _texture_import_preset_settings(preset)
	if request.has("settings") and typeof(request.get("settings")) == TYPE_DICTIONARY:
		_deep_merge_dictionary(settings, request.get("settings") as Dictionary)
	var create_sidecar := bool(request.get("create_sidecar", true))
	var changed_paths: Array = []
	var updated: Array = []
	var errors: Array = []
	var snapshot_actions: Array = []
	for path_item in paths:
		var path := str(path_item)
		if not FileAccess.file_exists(path):
			errors.append(path + " -> source texture is missing")
			continue
		var extension := path.get_extension().to_lower()
		if not (extension in DESIGN_IMAGE_EXTENSIONS):
			errors.append(path + " -> not a supported image texture")
			continue
		var sidecar := path + ".import"
		if not FileAccess.file_exists(sidecar) and not create_sidecar:
			errors.append(sidecar + " -> import sidecar is missing")
			continue
		snapshot_actions.append({
			"type": "write_file",
			"path": sidecar
		})
	if not errors.is_empty():
		return _response(false, "Texture import preset found invalid paths.", {
			"errors": errors
		})
	var snapshot := _create_snapshot(snapshot_actions, "set_texture_import_preset " + preset)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; import presets were not changed.", {
			"snapshot": snapshot
		})
	for path_item in paths:
		var path := str(path_item)
		var sidecar := path + ".import"
		var result := _write_texture_import_sidecar(path, sidecar, settings)
		if int(result.get("error", OK)) == OK:
			updated.append({
				"path": path,
				"import_path": sidecar,
				"preset": preset
			})
			changed_paths.append(sidecar)
		else:
			errors.append(sidecar + " -> " + error_string(int(result.get("error", FAILED))))
	var reimport_requested := false
	if bool(request.get("reimport", false)):
		var filesystem = _editor_resource_filesystem()
		if filesystem != null and filesystem.has_method("reimport_files"):
			filesystem.reimport_files(PackedStringArray(paths))
			reimport_requested = true
		_refresh_editor_filesystem()
	return _response(errors.is_empty(), "Texture import presets updated." if errors.is_empty() else "Texture import presets had errors.", {
		"preset": preset,
		"settings": settings,
		"updated": updated,
		"errors": errors,
		"reimport_requested": reimport_requested,
		"snapshot": _snapshot_summary(snapshot)
	}, [], changed_paths)


func _create_asset_manifest(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Asset manifest root is invalid or protected.")
	var path := _normalize_resource_path(str(request.get("path", root.path_join("asset_manifest.json"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "Asset manifest path is invalid or protected.")
	if path.get_extension().to_lower() != "json":
		return _response(false, "Asset manifest path must end with .json.")
	if FileAccess.file_exists(path) and not bool(request.get("replace", false)):
		return _response(false, "Asset manifest already exists: " + path)
	var asset_data := _design_asset_report_data(root, request)
	var payload := {
		"schema_version": 1,
		"root": root,
		"generated_at": Time.get_datetime_string_from_system(),
		"counts": asset_data.get("counts", {}),
		"assets": _asset_manifest_entries(asset_data.get("files", []) as Array)
	}
	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		}
	], "create_asset_manifest " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; asset manifest was not saved.", {
			"snapshot": snapshot
		})
	var write_error := _write_json_file(path, payload)
	if write_error != OK:
		return _response(false, "Failed to write asset manifest: " + error_string(write_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Asset manifest created.", {
		"path": path,
		"root": root,
		"asset_count": (payload.get("assets", []) as Array).size(),
		"counts": payload.get("counts", {}),
		"issues": asset_data.get("issues", []),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


func _create_asset_contact_sheet(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Asset contact sheet root is invalid or protected.")
	var path := _normalize_resource_path(str(request.get("path", root.path_join("reports").path_join("asset_contact_sheet.png"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "Asset contact sheet path is invalid or protected.")
	if path.get_extension().to_lower() != "png":
		return _response(false, "Asset contact sheet path must end with .png.")
	var report_path := _normalize_resource_path(str(request.get("report_path", path.get_basename() + ".json")))
	if report_path.is_empty() or not _design_path_allowed(report_path):
		return _response(false, "Asset contact sheet report path is invalid or protected.")
	if report_path.get_extension().to_lower() != "json":
		return _response(false, "Asset contact sheet report path must end with .json.")
	if not bool(request.get("replace", false)):
		if FileAccess.file_exists(path):
			return _response(false, "Asset contact sheet already exists: " + path)
		if FileAccess.file_exists(report_path):
			return _response(false, "Asset contact sheet report already exists: " + report_path)

	var max_count := mini(maxi(int(request.get("max_count", 48)), 1), 240)
	var thumb_size := mini(maxi(int(request.get("thumb_size", 72)), 24), 256)
	var columns := mini(maxi(int(request.get("columns", 5)), 1), 12)
	var files: Array = []
	_collect_resource_file_infos(root, files, max_count, DESIGN_IMAGE_EXTENSIONS, false)
	if files.is_empty():
		return _response(false, "No image assets found under " + root + ".")

	var sheet_data := _build_asset_contact_sheet(files, thumb_size, columns)
	var sheet_image = sheet_data.get("image", null)
	if not sheet_image is Image:
		return _response(false, "Failed to build asset contact sheet image.")

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		},
		{
			"type": "write_file",
			"path": report_path
		},
		{
			"type": "make_dir",
			"path": path.get_base_dir()
		}
	], "create_asset_contact_sheet " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; contact sheet was not saved.", {
			"snapshot": snapshot
		})
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create contact sheet directory: " + error_string(dir_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var save_error := (sheet_image as Image).save_png(path)
	if save_error != OK:
		return _response(false, "Failed to save asset contact sheet: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var report_payload := {
		"schema_version": 1,
		"root": root,
		"path": path,
		"generated_at": Time.get_datetime_string_from_system(),
		"image_count": int(sheet_data.get("image_count", 0)),
		"columns": columns,
		"thumb_size": thumb_size,
		"sheet_size": {
			"width": int(sheet_data.get("width", 0)),
			"height": int(sheet_data.get("height", 0))
		},
		"assets": sheet_data.get("assets", [])
	}
	var write_error := _write_json_file(report_path, report_payload)
	if write_error != OK:
		return _response(false, "Failed to write asset contact sheet report: " + error_string(write_error), {
			"path": report_path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Asset contact sheet created.", {
		"path": path,
		"report_path": report_path,
		"root": root,
		"image_count": int(sheet_data.get("image_count", 0)),
		"sheet_size": report_payload.get("sheet_size", {}),
		"assets": sheet_data.get("assets", []),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path, report_path])


func _create_scene_preview(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Scene preview root is invalid or protected.")
	var path := _normalize_resource_path(str(request.get("path", root.path_join("reports").path_join("scene_preview.png"))))
	if path.is_empty() or not _design_path_allowed(path):
		return _response(false, "Scene preview path is invalid or protected.")
	if path.get_extension().to_lower() != "png":
		return _response(false, "Scene preview path must end with .png.")
	var report_path := _normalize_resource_path(str(request.get("report_path", path.get_basename() + ".json")))
	if report_path.is_empty() or not _design_path_allowed(report_path):
		return _response(false, "Scene preview report path is invalid or protected.")
	if report_path.get_extension().to_lower() != "json":
		return _response(false, "Scene preview report path must end with .json.")
	if not bool(request.get("replace", false)):
		if FileAccess.file_exists(path):
			return _response(false, "Scene preview already exists: " + path)
		if FileAccess.file_exists(report_path):
			return _response(false, "Scene preview report already exists: " + report_path)

	var scene_path := _normalize_resource_path(str(request.get("scene_path", "")))
	var temporary_root: Node = null
	var scene_root: Node = null
	if not scene_path.is_empty():
		if not FileAccess.file_exists(scene_path):
			return _response(false, "Scene preview scene does not exist: " + scene_path)
		var packed = load(scene_path)
		if not packed is PackedScene:
			return _response(false, "Scene preview path is not a PackedScene: " + scene_path)
		temporary_root = (packed as PackedScene).instantiate()
		scene_root = temporary_root
	else:
		scene_root = _edited_scene_root()
	if scene_root == null:
		return _response(false, "No editable scene is currently open.")

	var max_nodes := mini(maxi(int(request.get("max_nodes", 160)), 1), 500)
	var nodes: Array = []
	_collect_scene_preview_nodes(scene_root, scene_root, nodes, max_nodes, 0)
	if temporary_root != null:
		temporary_root.free()
	if nodes.is_empty():
		return _response(false, "Scene preview found no nodes.")

	var width := mini(maxi(int(request.get("width", 720)), 240), 2048)
	var height := mini(maxi(int(request.get("height", 420)), 180), 2048)
	var preview_data := _build_scene_preview_image(nodes, width, height)
	var preview_image = preview_data.get("image", null)
	if not preview_image is Image:
		return _response(false, "Failed to build scene preview image.")

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		},
		{
			"type": "write_file",
			"path": report_path
		},
		{
			"type": "make_dir",
			"path": path.get_base_dir()
		}
	], "create_scene_preview " + path)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; scene preview was not saved.", {
			"snapshot": snapshot
		})
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create scene preview directory: " + error_string(dir_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var save_error := (preview_image as Image).save_png(path)
	if save_error != OK:
		return _response(false, "Failed to save scene preview: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		})
	var report_payload := {
		"schema_version": 1,
		"path": path,
		"scene_path": scene_path,
		"scene_root": str(nodes[0].get("name", "")) if not nodes.is_empty() else "",
		"generated_at": Time.get_datetime_string_from_system(),
		"node_count": nodes.size(),
		"canvas_size": {
			"width": width,
			"height": height
		},
		"nodes": preview_data.get("nodes", [])
	}
	var write_error := _write_json_file(report_path, report_payload)
	if write_error != OK:
		return _response(false, "Failed to write scene preview report: " + error_string(write_error), {
			"path": report_path,
			"snapshot": _snapshot_summary(snapshot)
		})
	_refresh_editor_filesystem()
	return _response(true, "Scene preview created.", {
		"path": path,
		"report_path": report_path,
		"scene_path": scene_path,
		"node_count": nodes.size(),
		"canvas_size": report_payload.get("canvas_size", {}),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path, report_path])


func _inspect_art_assets(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://")))
	if root.is_empty():
		return _response(false, "Art asset root is invalid or protected.")

	var max_count := int(request.get("max_count", RESOURCE_FILE_LIMIT_DEFAULT))
	max_count = mini(maxi(max_count, 1), 1000)
	var extensions := _resource_extension_filter(request.get("extensions", []))
	if extensions.is_empty():
		extensions = _design_all_asset_extensions()

	var files: Array = []
	_collect_resource_file_infos(root, files, max_count, extensions, false)
	var counts := {}
	var issues: Array = []
	var max_texture_size := int(request.get("max_texture_size", 4096))
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var info := item as Dictionary
		var extension := str(info.get("extension", "")).to_lower()
		counts[extension] = int(counts.get(extension, 0)) + 1
		issues.append_array(_design_asset_issues(info, max_texture_size))

	var data := {
		"root": root,
		"files": files,
		"counts": counts,
		"issues": issues,
		"issue_count": issues.size()
	}
	var changed_paths: Array = []
	if bool(request.get("write_report", false)):
		var report_path := _normalize_resource_path(str(request.get("report_path", root.path_join("reports").path_join("art_assets_report.json"))))
		if report_path.is_empty() or not _design_path_allowed(report_path):
			return _response(false, "Art asset report path is invalid or protected.")
		var snapshot := _create_snapshot([
			{
				"type": "write_file",
				"path": report_path
			}
		], "inspect_art_assets " + root)
		if not bool(snapshot.get("ok", true)):
			return _response(false, "Failed to create pre-change snapshot; report was not written.", {
				"snapshot": snapshot
			})
		var payload := data.duplicate(true)
		payload["generated_at"] = Time.get_datetime_string_from_system()
		var write_error := _write_json_file(report_path, payload)
		if write_error != OK:
			return _response(false, "Failed to write art asset report: " + error_string(write_error), {
				"path": report_path,
				"snapshot": _snapshot_summary(snapshot)
			})
		data["report_path"] = report_path
		data["snapshot"] = _snapshot_summary(snapshot)
		changed_paths.append(report_path)
		_refresh_editor_filesystem()

	return _response(true, "Art assets inspected.", data, [], changed_paths)


func _run_design_lint(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return _response(false, "Design root is invalid or protected.")
	var validation := _design_system_validation(root, request)
	var ui_inspection := _inspect_ui_scene_data(request)
	var asset_data := _design_asset_report_data(root, request)
	var issues: Array = []
	issues.append_array(validation.get("issues", []) as Array)
	if bool(ui_inspection.get("ok", false)):
		issues.append_array(ui_inspection.get("issues", []) as Array)
	else:
		issues.append({
			"severity": "info",
			"type": "ui_scene_unavailable",
			"path": "",
			"message": str(ui_inspection.get("message", "No UI scene available."))
		})
	issues.append_array(asset_data.get("issues", []) as Array)
	var summary := _design_issue_summary(issues)
	var data := {
		"root": root,
		"valid": int(summary.get("error", 0)) == 0,
		"issue_count": issues.size(),
		"summary": summary,
		"issues": issues,
		"design_system": validation,
		"ui": ui_inspection,
		"assets": asset_data
	}
	var changed_paths: Array = []
	if bool(request.get("write_report", false)):
		var report_path := _normalize_resource_path(str(request.get("report_path", root.path_join("reports").path_join("design_lint_report.json"))))
		if report_path.is_empty() or not _design_path_allowed(report_path):
			return _response(false, "Design lint report path is invalid or protected.")
		var snapshot := _create_snapshot([
			{
				"type": "write_file",
				"path": report_path
			}
		], "run_design_lint " + root)
		if not bool(snapshot.get("ok", true)):
			return _response(false, "Failed to create pre-change snapshot; lint report was not written.", {
				"snapshot": snapshot
			})
		var payload := data.duplicate(true)
		payload["generated_at"] = Time.get_datetime_string_from_system()
		var write_error := _write_json_file(report_path, payload)
		if write_error != OK:
			return _response(false, "Failed to write design lint report: " + error_string(write_error), {
				"path": report_path,
				"snapshot": _snapshot_summary(snapshot)
			})
		data["report_path"] = report_path
		data["snapshot"] = _snapshot_summary(snapshot)
		changed_paths.append(report_path)
		_refresh_editor_filesystem()
	return _response(true, "Design lint completed.", data, [], changed_paths)


func _design_status(request: Dictionary) -> Dictionary:
	var root := _normalize_design_root(str(request.get("root", "res://art")))
	if root.is_empty():
		return {
			"root": "",
			"available": false,
			"message": "Design root is invalid or protected."
		}

	var palette_files: Array = []
	var theme_files: Array = []
	var material_files: Array = []
	var image_files: Array = []
	var sprite_files: Array = []
	var icon_files: Array = []
	var audio_files: Array = []
	var font_files: Array = []
	var report_files: Array = []
	var preview_files: Array = []
	var manifest_candidates: Array = []
	var asset_manifests: Array = []
	_collect_resource_file_infos(root.path_join("palettes"), palette_files, 50, ["json"], false)
	_collect_resource_file_infos(root.path_join("themes"), theme_files, 50, ["tres", "res"], false)
	_collect_resource_file_infos(root.path_join("materials"), material_files, 80, ["tres", "res", "material", "gdshader"], false)
	_collect_resource_file_infos(root.path_join("reports"), report_files, 50, ["json"], false)
	_collect_resource_file_infos(root.path_join("reports"), preview_files, 50, ["png"], false)
	_collect_resource_file_infos(root.path_join("sprites"), sprite_files, 120, DESIGN_IMAGE_EXTENSIONS + ["tres", "res"], false)
	_collect_resource_file_infos(root.path_join("icons"), icon_files, 120, DESIGN_IMAGE_EXTENSIONS, false)
	_collect_resource_file_infos(root, image_files, 120, DESIGN_IMAGE_EXTENSIONS, false)
	_collect_resource_file_infos(root, audio_files, 80, DESIGN_AUDIO_EXTENSIONS, false)
	_collect_resource_file_infos(root, font_files, 40, DESIGN_FONT_EXTENSIONS, false)
	_collect_resource_file_infos(root, manifest_candidates, 100, ["json"], false)
	for item in manifest_candidates:
		if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("name", "")) == "asset_manifest.json":
			asset_manifests.append(item)
	var design_system_path := _design_system_path(root)
	return {
		"root": root,
		"available": DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)),
		"design_system_path": design_system_path,
		"design_system_exists": FileAccess.file_exists(design_system_path),
		"palette_count": palette_files.size(),
		"theme_count": theme_files.size(),
		"material_count": material_files.size(),
		"image_count": image_files.size(),
		"sprite_count": sprite_files.size(),
		"icon_count": icon_files.size(),
		"audio_count": audio_files.size(),
			"font_count": font_files.size(),
			"report_count": report_files.size(),
			"preview_count": preview_files.size(),
			"asset_manifest_count": asset_manifests.size(),
		"palettes": palette_files,
		"themes": theme_files,
		"materials": material_files,
		"sprites": sprite_files,
			"icons": icon_files,
			"asset_manifests": asset_manifests,
			"previews": preview_files,
			"reports": report_files
	}


func _design_system_path(root: String) -> String:
	return root.path_join("design_system.json")


func _default_design_system_payload(root: String, request: Dictionary) -> Dictionary:
	var palette_entries := _design_palette_entries(request.get("palette", request.get("colors", {})))
	return {
		"schema_version": 2,
		"name": str(request.get("name", ProjectSettings.get_setting("application/config/name", "Game Art"))),
		"style": str(request.get("style", "playful game UI")),
		"root": root,
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system(),
		"palette": _design_palette_payload(palette_entries),
		"tokens": _default_design_tokens(palette_entries, request),
		"asset_roles": request.get("asset_roles", _default_design_asset_roles()),
		"ui_templates": ["main_menu", "hud", "pause_menu"],
		"directories": [
			root,
			root.path_join("palettes"),
			root.path_join("themes"),
			root.path_join("materials"),
			root.path_join("sprites"),
			root.path_join("ui"),
			root.path_join("references"),
			root.path_join("reports")
		]
	}


func _default_design_tokens(palette_entries: Array, request: Dictionary) -> Dictionary:
	return {
		"colors": _design_palette_payload(palette_entries),
		"typography": {
			"base_font_size": int(request.get("font_size", 18)),
			"small_font_size": int(request.get("small_font_size", 14)),
			"title_font_size": int(request.get("title_font_size", 32))
		},
		"spacing": {
			"xs": 4,
			"sm": 8,
			"md": 12,
			"lg": 20,
			"xl": 32
		},
		"radius": {
			"sm": 4,
			"md": int(request.get("corner_radius", 6)),
			"lg": 10
		}
	}


func _default_design_asset_roles() -> Dictionary:
	return {
		"player": {
			"type": "sprite",
			"status": "placeholder_allowed",
			"recommended_path": "res://art/sprites/player.png"
		},
		"enemy": {
			"type": "sprite",
			"status": "placeholder_allowed",
			"recommended_path": "res://art/sprites/enemy.png"
		},
		"projectile": {
			"type": "sprite",
			"status": "placeholder_allowed",
			"recommended_path": "res://art/sprites/projectile.png"
		},
		"pickup": {
			"type": "sprite",
			"status": "placeholder_allowed",
			"recommended_path": "res://art/sprites/pickup.png"
		},
		"panel": {
			"type": "ui",
			"status": "theme_generated",
			"recommended_path": "res://art/themes/game_theme.tres"
		}
	}


func _design_system_validation(root: String, _request: Dictionary) -> Dictionary:
	var path := _design_system_path(root)
	var issues: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)):
		issues.append(_design_issue("error", "missing_design_root", root, "Design root directory does not exist."))
	if not FileAccess.file_exists(path):
		issues.append(_design_issue("error", "missing_design_system", path, "design_system.json does not exist."))
		return {
			"root": root,
			"path": path,
			"valid": false,
			"issues": issues,
			"issue_count": issues.size(),
			"summary": _design_issue_summary(issues)
		}

	var payload := _read_json_file(path)
	if payload.is_empty():
		issues.append(_design_issue("error", "invalid_design_system_json", path, "design_system.json is not valid JSON."))
	else:
		if int(payload.get("schema_version", 0)) < 2:
			issues.append(_design_issue("warning", "old_design_system_schema", path, "Design system schema is older than v2."))
		var palette_entries := _design_palette_entries(payload)
		var color_names: Array = []
		for entry in palette_entries:
			if typeof(entry) == TYPE_DICTIONARY:
				color_names.append(str((entry as Dictionary).get("name", "")))
		for required_color in ["background", "surface", "primary", "accent", "danger", "text"]:
			if not color_names.has(required_color):
				issues.append(_design_issue("warning", "missing_design_color", path, "Missing required color token: " + required_color))
		var tokens = payload.get("tokens", {})
		if typeof(tokens) != TYPE_DICTIONARY or (tokens as Dictionary).is_empty():
			issues.append(_design_issue("warning", "missing_design_tokens", path, "Design system has no tokens block."))
		var directories := payload.get("directories", []) as Array
		for item in directories:
			var directory := _normalize_design_root(str(item))
			if not directory.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
				issues.append(_design_issue("info", "missing_design_directory", directory, "Design directory is listed but does not exist."))
		var asset_roles = payload.get("asset_roles", {})
		if typeof(asset_roles) != TYPE_DICTIONARY or (asset_roles as Dictionary).is_empty():
			issues.append(_design_issue("info", "missing_asset_roles", path, "No asset roles are defined."))
		else:
			for role in (asset_roles as Dictionary).keys():
				var role_data = (asset_roles as Dictionary)[role]
				if typeof(role_data) == TYPE_DICTIONARY:
					var recommended_path := _normalize_resource_path(str((role_data as Dictionary).get("recommended_path", "")))
					if not recommended_path.is_empty() and not FileAccess.file_exists(recommended_path):
						issues.append(_design_issue("info", "asset_role_missing_file", recommended_path, "Asset role has no file yet: " + str(role)))
	var summary := _design_issue_summary(issues)
	return {
		"root": root,
		"path": path,
		"valid": int(summary.get("error", 0)) == 0,
		"issues": issues,
		"issue_count": issues.size(),
		"summary": summary
	}


func _design_asset_report_data(root: String, request: Dictionary) -> Dictionary:
	var max_count := int(request.get("max_count", RESOURCE_FILE_LIMIT_DEFAULT))
	max_count = mini(maxi(max_count, 1), 1000)
	var extensions := _resource_extension_filter(request.get("extensions", []))
	if extensions.is_empty():
		extensions = _design_all_asset_extensions()
	var files: Array = []
	_collect_resource_file_infos(root, files, max_count, extensions, false)
	var counts := {}
	var issues: Array = []
	var max_texture_size := int(request.get("max_texture_size", 4096))
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var info := item as Dictionary
		var extension := str(info.get("extension", "")).to_lower()
		counts[extension] = int(counts.get(extension, 0)) + 1
		issues.append_array(_design_asset_issues(info, max_texture_size))
	return {
		"root": root,
		"files": files,
		"counts": counts,
		"issues": issues,
		"issue_count": issues.size()
	}


func _design_issue(severity: String, issue_type: String, path: String, message: String) -> Dictionary:
	return {
		"severity": severity,
		"type": issue_type,
		"path": path,
		"message": message
	}


func _design_issue_summary(issues: Array) -> Dictionary:
	var summary := {
		"error": 0,
		"warning": 0,
		"info": 0
	}
	for item in issues:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var severity := str((item as Dictionary).get("severity", "info"))
		summary[severity] = int(summary.get(severity, 0)) + 1
	return summary


func _deep_merge_dictionary(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		var source_value = source[key]
		if target.has(key) and typeof(target[key]) == TYPE_DICTIONARY and typeof(source_value) == TYPE_DICTIONARY:
			_deep_merge_dictionary(target[key] as Dictionary, source_value as Dictionary)
		else:
			target[key] = source_value


func _normalize_design_root(raw_root: String) -> String:
	var root := _normalize_resource_path(raw_root, true)
	if root.is_empty() or not _design_path_allowed(root):
		return ""
	return root


func _design_path_allowed(path: String) -> bool:
	if path.is_empty():
		return false
	if path.begins_with(PLUGIN_ROOT) or path.begins_with("res://.godot"):
		return false
	return true


func _design_all_asset_extensions() -> Array:
	var extensions: Array = []
	for item in DESIGN_IMAGE_EXTENSIONS + DESIGN_AUDIO_EXTENSIONS + DESIGN_FONT_EXTENSIONS + DESIGN_RESOURCE_EXTENSIONS + ["json"]:
		if not extensions.has(item):
			extensions.append(item)
	return extensions


func _safe_design_slug(raw_value: String, fallback: String) -> String:
	var value := raw_value.strip_edges().to_lower()
	var slug := ""
	for index in value.length():
		var character := value.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int() or character in ["-", "_"]:
			slug += character
		elif character in [" ", ".", "/"]:
			slug += "_"
	while slug.contains("__"):
		slug = slug.replace("__", "_")
	slug = slug.trim_prefix("_").trim_suffix("_")
	return fallback if slug.is_empty() else slug


func _design_palette_entries(raw_palette) -> Array:
	if typeof(raw_palette) == TYPE_DICTIONARY:
		var palette_dict := raw_palette as Dictionary
		if palette_dict.has("tokens") and typeof(palette_dict.get("tokens")) == TYPE_DICTIONARY:
			var tokens := palette_dict.get("tokens") as Dictionary
			if tokens.has("colors"):
				return _design_palette_entries(tokens.get("colors", {}))
		if palette_dict.has("colors"):
			return _design_palette_entries(palette_dict.get("colors", {}))
		if palette_dict.has("palette"):
			return _design_palette_entries(palette_dict.get("palette", {}))
		var entries: Array = []
		for raw_name in palette_dict.keys():
			var name := str(raw_name).strip_edges()
			if name.is_empty():
				continue
			entries.append({
				"name": _safe_design_slug(name, "color"),
				"label": name,
				"color": _decode_design_color(palette_dict[raw_name], _default_design_color(name))
			})
		return _default_design_palette() if entries.is_empty() else entries
	if typeof(raw_palette) == TYPE_ARRAY:
		var entries: Array = []
		for item in raw_palette as Array:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var entry := item as Dictionary
			var name := str(entry.get("name", entry.get("label", ""))).strip_edges()
			if name.is_empty():
				name = "color_" + str(entries.size() + 1)
			entries.append({
				"name": _safe_design_slug(name, "color"),
				"label": name,
				"color": _decode_design_color(entry.get("color", entry.get("value", entry)), _default_design_color(name))
			})
		return _default_design_palette() if entries.is_empty() else entries
	return _default_design_palette()


func _design_palette_entries_from_request(request: Dictionary) -> Dictionary:
	var palette_path := _normalize_resource_path(str(request.get("palette_path", "")))
	if not palette_path.is_empty():
		if not _design_path_allowed(palette_path) or not FileAccess.file_exists(palette_path):
			return {
				"ok": false,
				"message": "Palette file is invalid or missing: " + palette_path
			}
		var payload := _read_json_file(palette_path)
		if payload.is_empty():
			return {
				"ok": false,
				"message": "Palette file is not valid JSON: " + palette_path
			}
		return {
			"ok": true,
			"palette": _design_palette_entries(payload)
		}
	if request.has("palette"):
		return {
			"ok": true,
			"palette": _design_palette_entries(request.get("palette"))
		}
	if request.has("colors"):
		return {
			"ok": true,
			"palette": _design_palette_entries(request.get("colors"))
		}
	return {
		"ok": true,
		"palette": _default_design_palette()
	}


func _default_design_palette() -> Array:
	return [
		{
			"name": "background",
			"label": "Background",
			"color": Color(0.05, 0.07, 0.10, 1.0)
		},
		{
			"name": "surface",
			"label": "Surface",
			"color": Color(0.12, 0.16, 0.23, 1.0)
		},
		{
			"name": "primary",
			"label": "Primary",
			"color": Color(0.25, 0.62, 1.0, 1.0)
		},
		{
			"name": "accent",
			"label": "Accent",
			"color": Color(0.39, 0.86, 0.58, 1.0)
		},
		{
			"name": "danger",
			"label": "Danger",
			"color": Color(1.0, 0.36, 0.36, 1.0)
		},
		{
			"name": "text",
			"label": "Text",
			"color": Color(0.92, 0.95, 1.0, 1.0)
		}
	]


func _default_design_color(name: String) -> Color:
	var slug := _safe_design_slug(name, "color")
	for entry in _default_design_palette():
		if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("name", "")) == slug:
			return (entry as Dictionary).get("color", Color.WHITE) as Color
	return Color.WHITE


func _decode_design_color(raw_value, fallback: Color) -> Color:
	if raw_value is Color:
		return raw_value as Color
	if typeof(raw_value) == TYPE_STRING:
		var text := str(raw_value).strip_edges()
		if not text.is_empty():
			return Color.from_string(text, fallback)
	if typeof(raw_value) == TYPE_DICTIONARY:
		var decoded = _decode_value(raw_value)
		if decoded is Color:
			return decoded as Color
		var value_dict := raw_value as Dictionary
		if value_dict.has("value"):
			return _decode_design_color(value_dict.get("value"), fallback)
	return fallback


func _design_palette_payload(entries: Array) -> Array:
	var payload: Array = []
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry := item as Dictionary
		var color: Color = entry.get("color", Color.WHITE)
		payload.append({
			"name": str(entry.get("name", "")),
			"label": str(entry.get("label", entry.get("name", ""))),
			"value": "#" + color.to_html(true),
			"color": _encode_value(color)
		})
	return payload


func _design_palette_color_map(entries: Array) -> Dictionary:
	var colors := {}
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry := item as Dictionary
		colors[str(entry.get("name", ""))] = entry.get("color", Color.WHITE)
	return colors


func _build_ui_theme_from_palette(palette_entries: Array, request: Dictionary) -> Theme:
	var colors := _design_palette_color_map(palette_entries)
	var background: Color = colors.get("background", Color(0.05, 0.07, 0.10, 1.0))
	var surface: Color = colors.get("surface", Color(0.12, 0.16, 0.23, 1.0))
	var primary: Color = colors.get("primary", Color(0.25, 0.62, 1.0, 1.0))
	var accent: Color = colors.get("accent", Color(0.39, 0.86, 0.58, 1.0))
	var danger: Color = colors.get("danger", Color(1.0, 0.36, 0.36, 1.0))
	var text: Color = colors.get("text", Color(0.92, 0.95, 1.0, 1.0))
	var radius := int(request.get("corner_radius", 6))
	var font_size := int(request.get("font_size", 18))

	var theme := Theme.new()
	theme.set_color("font_color", "Label", text)
	theme.set_color("font_color", "Button", text)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_color", "RichTextLabel", text)
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_color", "TextEdit", text)
	theme.set_color("font_color", "CheckBox", text)
	theme.set_color("font_color", "OptionButton", text)
	theme.set_color("font_color", "ItemList", text)
	theme.set_color("selection_color", "ItemList", primary)
	theme.set_font_size("font_size", "Label", font_size)
	theme.set_font_size("font_size", "Button", font_size)
	theme.set_font_size("normal_font_size", "RichTextLabel", font_size)
	theme.set_font_size("font_size", "LineEdit", font_size)
	theme.set_font_size("font_size", "TextEdit", font_size)
	theme.set_constant("margin_left", "MarginContainer", 12)
	theme.set_constant("margin_right", "MarginContainer", 12)
	theme.set_constant("margin_top", "MarginContainer", 10)
	theme.set_constant("margin_bottom", "MarginContainer", 10)
	theme.set_stylebox("panel", "Panel", _design_stylebox(surface, primary.darkened(0.25), radius, 1))
	theme.set_stylebox("normal", "Button", _design_stylebox(primary.darkened(0.18), primary, radius, 1))
	theme.set_stylebox("hover", "Button", _design_stylebox(primary, accent, radius, 1))
	theme.set_stylebox("pressed", "Button", _design_stylebox(accent.darkened(0.12), accent, radius, 1))
	theme.set_stylebox("disabled", "Button", _design_stylebox(surface.darkened(0.12), surface.lightened(0.08), radius, 1))
	theme.set_stylebox("normal", "LineEdit", _design_stylebox(background, surface.lightened(0.14), radius, 1))
	theme.set_stylebox("normal", "TextEdit", _design_stylebox(background, surface.lightened(0.14), radius, 1))
	theme.set_stylebox("panel", "PopupPanel", _design_stylebox(surface, danger.darkened(0.35), radius, 1))
	return theme


func _design_stylebox(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _collect_control_nodes(node: Node, recursive: bool, controls: Array) -> void:
	if node is Control:
		controls.append(node)
	if not recursive:
		return
	for child in node.get_children():
		if child is Node:
			_collect_control_nodes(child as Node, recursive, controls)


func _build_ui_template_scene(template: String, request: Dictionary, theme: Theme) -> Control:
	var scene_root := Control.new()
	scene_root.name = _template_root_name(template)
	_set_control_full_rect(scene_root)
	if theme != null:
		scene_root.theme = theme
	match template:
		"main_menu":
			_build_main_menu_template(scene_root, request)
		"hud":
			_build_hud_template(scene_root, request)
		"pause_menu":
			_build_pause_menu_template(scene_root, request)
	_set_owner_recursive(scene_root, scene_root)
	return scene_root


func _build_main_menu_template(root: Control, request: Dictionary) -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = _decode_design_color(request.get("background_color", "#101826"), Color(0.06, 0.09, 0.15, 1.0))
	_set_control_full_rect(background)
	root.add_child(background)

	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -180
	panel.offset_top = -150
	panel.offset_right = 180
	panel.offset_bottom = 150
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "MenuColumn"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = str(request.get("title", ProjectSettings.get_setting("application/config/name", "Game")))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)

	for button_name in ["Start", "Settings", "Quit"]:
		var button := Button.new()
		button.name = button_name + "Button"
		button.text = button_name
		button.custom_minimum_size = Vector2(220, 46)
		column.add_child(button)


func _build_hud_template(root: Control, _request: Dictionary) -> void:
	var margin := MarginContainer.new()
	margin.name = "HudMargin"
	_set_control_full_rect(margin)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "TopBar"
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var health := Label.new()
	health.name = "HealthLabel"
	health.text = "HP 3"
	health.custom_minimum_size = Vector2(90, 32)
	row.add_child(health)

	var score := Label.new()
	score.name = "ScoreLabel"
	score.text = "Score 0"
	score.custom_minimum_size = Vector2(120, 32)
	row.add_child(score)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var pause := Button.new()
	pause.name = "PauseButton"
	pause.text = "Pause"
	pause.custom_minimum_size = Vector2(92, 44)
	row.add_child(pause)


func _build_pause_menu_template(root: Control, request: Dictionary) -> void:
	root.visible = bool(request.get("visible", true))
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	_set_control_full_rect(overlay)
	root.add_child(overlay)

	var panel := PanelContainer.new()
	panel.name = "PausePanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -150
	panel.offset_top = -120
	panel.offset_right = 150
	panel.offset_bottom = 120
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "PauseColumn"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := Label.new()
	title.name = "PauseTitle"
	title.text = str(request.get("title", "Paused"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)

	for button_name in ["Resume", "Restart", "MainMenu"]:
		var button := Button.new()
		button.name = button_name + "Button"
		button.text = "Main Menu" if button_name == "MainMenu" else button_name
		button.custom_minimum_size = Vector2(200, 44)
		column.add_child(button)


func _template_root_name(template: String) -> String:
	match template:
		"main_menu":
			return "MainMenu"
		"hud":
			return "HUD"
		"pause_menu":
			return "PauseMenu"
		_:
			return "UIRoot"


func _set_control_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child is Node:
			(child as Node).owner = owner
			_set_owner_recursive(child as Node, owner)


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		if child is Node:
			count += _count_nodes(child as Node)
	return count


func _inspect_ui_scene_data(request: Dictionary) -> Dictionary:
	var min_touch_size := float(request.get("min_touch_size", 44.0))
	var temporary_root: Node = null
	var root_node: Node = null
	var scene_path := _normalize_resource_path(str(request.get("scene_path", "")))
	if not scene_path.is_empty():
		var packed = load(scene_path)
		if not packed is PackedScene:
			return {
				"ok": false,
				"message": "Cannot load UI scene: " + scene_path
			}
		temporary_root = (packed as PackedScene).instantiate()
		root_node = temporary_root
	else:
		root_node = _edited_scene_root()
	if root_node == null:
		return {
			"ok": false,
			"message": "No editable scene is currently open."
		}

	var target := root_node
	var node_path := str(request.get("node_path", "")).strip_edges()
	if not node_path.is_empty():
		if temporary_root != null:
			target = temporary_root.get_node_or_null(NodePath(node_path))
		else:
			target = _find_scene_node(node_path)
		if target == null:
			if temporary_root != null:
				temporary_root.free()
			return {
				"ok": false,
				"message": "UI target node was not found: " + node_path
			}

	var controls: Array = []
	_collect_control_nodes(target, true, controls)
	var issues: Array = []
	var summaries: Array = []
	for item in controls:
		if not item is Control:
			continue
		var control := item as Control
		summaries.append(_ui_control_summary(control, root_node))
		issues.append_array(_ui_control_issues(control, root_node, min_touch_size))
	if temporary_root != null:
		temporary_root.free()
	var summary := _design_issue_summary(issues)
	return {
		"ok": true,
		"root": scene_path if not scene_path.is_empty() else str(root_node.name),
		"target": node_path,
		"controls": summaries,
		"control_count": summaries.size(),
		"issues": issues,
		"issue_count": issues.size(),
		"summary": summary
	}


func _ui_control_summary(control: Control, scene_root: Node) -> Dictionary:
	var item := {
		"name": str(control.name),
		"class": control.get_class(),
		"path": _node_path_from_root(control, scene_root),
		"anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom],
		"custom_minimum_size": _encode_value(control.custom_minimum_size),
		"size": _encode_value(control.size),
		"has_theme": control.theme != null
	}
	if _has_property(control, "text"):
		item["text"] = str(control.get("text"))
	if control is Label:
		item["autowrap_mode"] = int((control as Label).autowrap_mode)
	return item


func _ui_control_issues(control: Control, scene_root: Node, min_touch_size: float) -> Array:
	var issues: Array = []
	var path := _node_path_from_root(control, scene_root)
	if control is Label:
		var label := control as Label
		if not label.text.is_empty() and label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			issues.append(_design_issue("warning", "label_autowrap_disabled", path, "Label has text but autowrap is disabled."))
	if control is Button:
		var button := control as Button
		if button.text.strip_edges().is_empty():
			issues.append(_design_issue("info", "button_missing_text", path, "Button has no visible text."))
		var min_size := button.custom_minimum_size
		if min_size.x > 0 and min_size.x < min_touch_size or min_size.y > 0 and min_size.y < min_touch_size:
			issues.append(_design_issue("warning", "touch_target_too_small", path, "Button custom_minimum_size is below " + str(min_touch_size) + " px."))
	if control != scene_root and control.anchor_left == 0.0 and control.anchor_top == 0.0 and control.anchor_right == 0.0 and control.anchor_bottom == 0.0 and control.custom_minimum_size == Vector2.ZERO:
		issues.append(_design_issue("info", "fixed_control_without_min_size", path, "Control uses fixed top-left anchors without a minimum size."))
	return issues


func _node_path_from_root(node: Node, scene_root: Node) -> String:
	if node == scene_root:
		return "."
	if scene_root != null and scene_root.is_ancestor_of(node):
		return str(scene_root.get_path_to(node))
	return str(node.get_path())


func _visual_feedback_for_node(node: Node) -> Dictionary:
	return {
		"focused": node != null,
		"reason": "selected target node" if node != null else "no focusable scene node",
		"node": _node_summary(node, _edited_scene_root()) if node != null else {}
	}


func _design_material_specs(raw_materials, palette_entries: Array) -> Array:
	var specs: Array = []
	if typeof(raw_materials) == TYPE_ARRAY:
		for item in raw_materials as Array:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var material := item as Dictionary
			var name := str(material.get("name", material.get("role", ""))).strip_edges()
			if name.is_empty():
				name = "material_" + str(specs.size() + 1)
			specs.append({
				"name": name,
				"color": _decode_design_color(material.get("color", material.get("value", {})), _default_design_color(name))
			})
	if not specs.is_empty():
		return specs

	var colors := _design_palette_color_map(palette_entries)
	var roles := ["primary", "accent", "danger", "surface", "background"]
	for role in roles:
		if colors.has(role):
			specs.append({
				"name": role,
				"color": colors.get(role)
			})
	return specs


func _design_tint_shader_code() -> String:
	return "shader_type canvas_item;\nuniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, UV) * tint_color;\n}\n"


func _design_asset_issues(info: Dictionary, max_texture_size: int) -> Array:
	var issues: Array = []
	var path := str(info.get("path", ""))
	var extension := str(info.get("extension", "")).to_lower()
	var filename := path.get_file()
	if filename.contains(" "):
		issues.append({
			"severity": "warning",
			"type": "asset_naming",
			"path": path,
			"message": "Asset filename contains spaces."
		})
	if filename != filename.to_lower():
		issues.append({
			"severity": "info",
			"type": "asset_naming",
			"path": path,
			"message": "Asset filename uses uppercase characters."
		})
	if (extension in DESIGN_IMAGE_EXTENSIONS or extension in DESIGN_AUDIO_EXTENSIONS or extension in DESIGN_FONT_EXTENSIONS) and not bool(info.get("imported", false)):
		issues.append({
			"severity": "warning",
			"type": "missing_import_sidecar",
			"path": path,
			"message": "Imported asset has no .import sidecar yet; refresh or reimport in Godot."
		})
	if extension in ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr"]:
		var image := Image.new()
		var load_error := image.load(ProjectSettings.globalize_path(path))
		if load_error == OK and (image.get_width() > max_texture_size or image.get_height() > max_texture_size):
			issues.append({
				"severity": "warning",
				"type": "large_texture",
				"path": path,
				"message": "Texture is larger than " + str(max_texture_size) + " px on one axis.",
				"width": image.get_width(),
				"height": image.get_height()
			})
	return issues


func _placeholder_color_for_role(role: String) -> Color:
	match _safe_design_slug(role, "sprite"):
		"player", "hero":
			return Color(0.25, 0.64, 1.0, 1.0)
		"enemy", "danger":
			return Color(1.0, 0.36, 0.36, 1.0)
		"projectile", "bullet":
			return Color(0.5, 0.94, 1.0, 1.0)
		"pickup", "coin", "key":
			return Color(1.0, 0.78, 0.24, 1.0)
		"ui", "button", "panel":
			return Color(0.25, 0.62, 1.0, 1.0)
		"health", "heart":
			return Color(1.0, 0.3, 0.42, 1.0)
		_:
			return Color(0.39, 0.86, 0.58, 1.0)


func _build_placeholder_image(width: int, height: int, raw_shape: String, fill_color: Color, outline_color: Color) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var shape := _safe_design_slug(raw_shape, "diamond")
	var center := Vector2i(width / 2, height / 2)
	var min_side := mini(width, height)
	var outline_radius := maxi(int(min_side * 0.42), 2)
	var fill_radius := maxi(outline_radius - maxi(int(min_side * 0.08), 2), 1)
	match shape:
		"player", "hero":
			_draw_placeholder_circle(image, center, outline_radius, outline_color)
			_draw_placeholder_circle(image, center, fill_radius, fill_color)
			_draw_placeholder_rect(image, Rect2i(center.x - maxi(width / 18, 2), center.y - outline_radius, maxi(width / 9, 4), outline_radius + fill_radius / 2), outline_color)
			_draw_placeholder_circle(image, Vector2i(center.x - fill_radius / 3, center.y - fill_radius / 5), maxi(fill_radius / 7, 2), Color(0.02, 0.04, 0.08, 1.0))
			_draw_placeholder_circle(image, Vector2i(center.x + fill_radius / 3, center.y - fill_radius / 5), maxi(fill_radius / 7, 2), Color(0.02, 0.04, 0.08, 1.0))
		"enemy":
			_draw_placeholder_triangle(image, Vector2i(center.x - fill_radius, center.y - fill_radius / 2), Vector2i(center.x - fill_radius / 3, center.y - outline_radius), Vector2i(center.x, center.y - fill_radius / 4), outline_color)
			_draw_placeholder_triangle(image, Vector2i(center.x + fill_radius, center.y - fill_radius / 2), Vector2i(center.x + fill_radius / 3, center.y - outline_radius), Vector2i(center.x, center.y - fill_radius / 4), outline_color)
			_draw_placeholder_circle(image, center, outline_radius, outline_color)
			_draw_placeholder_circle(image, center, fill_radius, fill_color)
			_draw_placeholder_circle(image, Vector2i(center.x - fill_radius / 3, center.y - fill_radius / 8), maxi(fill_radius / 7, 2), Color(1.0, 0.92, 0.25, 1.0))
			_draw_placeholder_circle(image, Vector2i(center.x + fill_radius / 3, center.y - fill_radius / 8), maxi(fill_radius / 7, 2), Color(1.0, 0.92, 0.25, 1.0))
		"projectile", "bullet", "circle":
			_draw_placeholder_circle(image, center, outline_radius, outline_color)
			_draw_placeholder_circle(image, center, fill_radius, fill_color)
			_draw_placeholder_circle(image, center, maxi(fill_radius / 3, 1), Color(1, 1, 1, 0.85))
		"key":
			_draw_placeholder_circle(image, Vector2i(width / 3, center.y), maxi(min_side / 5, 3), outline_color)
			_draw_placeholder_circle(image, Vector2i(width / 3, center.y), maxi(min_side / 8, 2), Color(0, 0, 0, 0))
			_draw_placeholder_rect(image, Rect2i(width / 2 - min_side / 10, center.y - min_side / 16, width / 3, maxi(min_side / 8, 3)), fill_color)
			_draw_placeholder_rect(image, Rect2i(width * 3 / 4, center.y, maxi(min_side / 12, 2), height / 5), fill_color)
		"heart", "health":
			_draw_placeholder_circle(image, Vector2i(center.x - fill_radius / 3, center.y - fill_radius / 5), fill_radius / 2, outline_color)
			_draw_placeholder_circle(image, Vector2i(center.x + fill_radius / 3, center.y - fill_radius / 5), fill_radius / 2, outline_color)
			_draw_placeholder_triangle(image, Vector2i(center.x - outline_radius, center.y), Vector2i(center.x + outline_radius, center.y), Vector2i(center.x, center.y + outline_radius), outline_color)
			_draw_placeholder_circle(image, Vector2i(center.x - fill_radius / 3, center.y - fill_radius / 5), maxi(fill_radius / 2 - 2, 1), fill_color)
			_draw_placeholder_circle(image, Vector2i(center.x + fill_radius / 3, center.y - fill_radius / 5), maxi(fill_radius / 2 - 2, 1), fill_color)
			_draw_placeholder_triangle(image, Vector2i(center.x - fill_radius, center.y), Vector2i(center.x + fill_radius, center.y), Vector2i(center.x, center.y + fill_radius), fill_color)
		"triangle":
			_draw_placeholder_triangle(image, Vector2i(center.x, center.y - outline_radius), Vector2i(center.x - outline_radius, center.y + outline_radius), Vector2i(center.x + outline_radius, center.y + outline_radius), outline_color)
			_draw_placeholder_triangle(image, Vector2i(center.x, center.y - fill_radius), Vector2i(center.x - fill_radius, center.y + fill_radius), Vector2i(center.x + fill_radius, center.y + fill_radius), fill_color)
		"square", "rect", "panel", "button":
			var outline_rect := Rect2i(center.x - outline_radius, center.y - outline_radius, outline_radius * 2, outline_radius * 2)
			var fill_rect := Rect2i(center.x - fill_radius, center.y - fill_radius, fill_radius * 2, fill_radius * 2)
			_draw_placeholder_rect(image, outline_rect, outline_color)
			_draw_placeholder_rect(image, fill_rect, fill_color)
		_:
			_draw_placeholder_diamond(image, center, outline_radius, outline_radius, outline_color)
			_draw_placeholder_diamond(image, center, fill_radius, fill_radius, fill_color)
			_draw_placeholder_circle(image, center, maxi(fill_radius / 4, 1), Color(1, 1, 1, 0.8))
	return image


func _placeholder_icon_specs(raw_icons, palette_map: Dictionary) -> Array:
	var raw_list: Array = []
	if typeof(raw_icons) == TYPE_ARRAY:
		raw_list = raw_icons as Array
	if raw_list.is_empty():
		raw_list = [
			{"name": "health", "shape": "heart", "color": palette_map.get("danger", _placeholder_color_for_role("health"))},
			{"name": "coin", "shape": "circle", "color": _placeholder_color_for_role("coin")},
			{"name": "key", "shape": "key", "color": _placeholder_color_for_role("key")},
			{"name": "ability", "shape": "diamond", "color": palette_map.get("primary", _placeholder_color_for_role("ui"))}
		]

	var specs: Array = []
	for item in raw_list:
		if typeof(item) == TYPE_STRING:
			var icon_name := _safe_design_slug(str(item), "icon")
			specs.append({
				"name": icon_name,
				"shape": icon_name,
				"color": _placeholder_color_for_role(icon_name)
			})
		elif typeof(item) == TYPE_DICTIONARY:
			var icon := item as Dictionary
			var name := _safe_design_slug(str(icon.get("name", icon.get("role", "icon"))), "icon")
			var role := _safe_design_slug(str(icon.get("role", name)), name)
			var shape := _safe_design_slug(str(icon.get("shape", role)), "diamond")
			var fallback_color: Color = palette_map.get(role, _placeholder_color_for_role(role))
			specs.append({
				"name": name,
				"role": role,
				"shape": shape,
				"color": _decode_design_color(icon.get("color", fallback_color), fallback_color)
			})
	return specs


func _texture_from_image_path(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			return resource as Texture2D
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(path))
	if load_error != OK:
		return null
	return ImageTexture.create_from_image(image)


func _sprite_frame_animation_names(sprite_frames: SpriteFrames) -> Array:
	var names: Array = []
	if sprite_frames == null:
		return names
	for animation_name in sprite_frames.get_animation_names():
		names.append(str(animation_name))
	return names


func _expected_sprite_animation_names(raw_expected) -> Array:
	var expected: Array = []
	if typeof(raw_expected) == TYPE_STRING:
		var raw_text := str(raw_expected).strip_edges()
		if raw_text.is_empty():
			return expected
		raw_expected = raw_text.split(",", false)
	if typeof(raw_expected) != TYPE_ARRAY:
		return expected
	for item in raw_expected as Array:
		var animation_name := _normalize_animation_name(str(item))
		if not animation_name.is_empty() and not expected.has(animation_name):
			expected.append(animation_name)
	return expected


func _sprite_frames_report(sprite_frames: SpriteFrames, path: String, raw_expected) -> Dictionary:
	var animation_names := _sprite_frame_animation_names(sprite_frames)
	var expected := _expected_sprite_animation_names(raw_expected)
	var issues: Array = []
	var animations: Array = []
	var total_frames := 0
	var all_sizes: Array = []

	if animation_names.is_empty():
		issues.append("SpriteFrames has no animations.")
	for expected_name in expected:
		if not sprite_frames.has_animation(str(expected_name)):
			issues.append("Missing expected animation: " + str(expected_name))

	for animation_name in animation_names:
		var frame_count := sprite_frames.get_frame_count(animation_name)
		var frames: Array = []
		var animation_sizes: Array = []
		if frame_count <= 0:
			issues.append("Animation has no frames: " + animation_name)
		for frame_index in frame_count:
			var texture := sprite_frames.get_frame_texture(animation_name, frame_index)
			var frame_issue := ""
			var size := Vector2i.ZERO
			var texture_path := ""
			if texture == null:
				frame_issue = "missing_texture"
				issues.append(animation_name + "[" + str(frame_index) + "] has no texture.")
			else:
				size = Vector2i(texture.get_width(), texture.get_height())
				texture_path = str(texture.resource_path)
				if size.x <= 0 or size.y <= 0:
					frame_issue = "invalid_size"
					issues.append(animation_name + "[" + str(frame_index) + "] has invalid texture size.")
				var size_key := str(size.x) + "x" + str(size.y)
				if not animation_sizes.has(size_key):
					animation_sizes.append(size_key)
				if not all_sizes.has(size_key):
					all_sizes.append(size_key)
			frames.append({
				"index": frame_index,
				"texture_path": texture_path,
				"width": size.x,
				"height": size.y,
				"duration": sprite_frames.get_frame_duration(animation_name, frame_index),
				"issue": frame_issue
			})
		if animation_sizes.size() > 1:
			issues.append("Animation has inconsistent frame sizes: " + animation_name)
		total_frames += frame_count
		animations.append({
			"name": animation_name,
			"frame_count": frame_count,
			"fps": sprite_frames.get_animation_speed(animation_name),
			"loop": sprite_frames.get_animation_loop(animation_name),
			"sizes": animation_sizes,
			"frames": frames
		})

	return {
		"schema_version": 1,
		"path": path,
		"generated_at": Time.get_datetime_string_from_system(),
		"animation_count": animation_names.size(),
		"frame_count": total_frames,
		"expected_animations": expected,
		"available_animations": animation_names,
		"sizes": all_sizes,
		"valid": issues.is_empty(),
		"issue_count": issues.size(),
		"issues": issues,
		"animations": animations
	}


func _build_animation_preview_image(sprite_frames: SpriteFrames, path: String, thumb_size: int, columns: int) -> Dictionary:
	var animation_names := _sprite_frame_animation_names(sprite_frames)
	var padding := 10
	var rail_width := 14
	var tile_width := thumb_size + padding * 2
	var tile_height := thumb_size + padding * 2 + 8
	var rows := 0
	for animation_name in animation_names:
		var frame_count := maxi(sprite_frames.get_frame_count(animation_name), 1)
		rows += maxi(int(ceil(float(frame_count) / float(columns))), 1)
	rows = maxi(rows, 1)
	var width := rail_width + padding * 2 + columns * tile_width
	var height := padding + rows * tile_height
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.045, 0.055, 0.075, 1.0))

	var row_offset := 0
	for animation_name in animation_names:
		var frame_count := sprite_frames.get_frame_count(animation_name)
		var animation_rows := maxi(int(ceil(float(maxi(frame_count, 1)) / float(columns))), 1)
		var marker := _stable_preview_color(path + ":" + animation_name)
		_draw_placeholder_rect(image, Rect2i(padding, padding + row_offset * tile_height, rail_width, animation_rows * tile_height - padding), marker)
		if frame_count <= 0:
			var empty_rect := Rect2i(padding + rail_width + padding, padding + row_offset * tile_height, tile_width - padding, tile_height - padding)
			_draw_placeholder_rect(image, empty_rect, Color(0.08, 0.12, 0.18, 1.0))
			_draw_preview_rect_outline(image, empty_rect, marker, 1)
		for frame_index in frame_count:
			var local_row := frame_index / columns
			var column := frame_index % columns
			var origin := Vector2i(padding + rail_width + padding + column * tile_width, padding + (row_offset + local_row) * tile_height)
			var tile_rect := Rect2i(origin, Vector2i(tile_width - padding, tile_height - padding))
			_draw_placeholder_rect(image, tile_rect, Color(0.08, 0.12, 0.18, 1.0))
			_draw_preview_rect_outline(image, tile_rect, Color(0.18, 0.3, 0.48, 1.0), 1)
			_draw_placeholder_rect(image, Rect2i(origin.x + 4, origin.y + tile_rect.size.y - 8, tile_rect.size.x - 8, 4), marker)
			var thumbnail := _thumbnail_from_texture(sprite_frames.get_frame_texture(animation_name, frame_index), thumb_size)
			if thumbnail != null:
				var destination := Vector2i(origin.x + padding + (thumb_size - thumbnail.get_width()) / 2, origin.y + padding + (thumb_size - thumbnail.get_height()) / 2)
				image.blend_rect(thumbnail, Rect2i(0, 0, thumbnail.get_width(), thumbnail.get_height()), destination)
			else:
				_draw_placeholder_diamond(image, Vector2i(origin.x + tile_rect.size.x / 2, origin.y + padding + thumb_size / 2), thumb_size / 3, thumb_size / 3, marker)
		row_offset += animation_rows

	return {
		"image": image,
		"rows": rows,
		"width": width,
		"height": height
	}


func _thumbnail_from_texture(texture: Texture2D, thumb_size: int) -> Image:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return null
	var image := texture.get_image()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return null
	if image.is_compressed():
		var decompress_error := image.decompress()
		if decompress_error != OK:
			return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var scale := minf(float(thumb_size) / float(image.get_width()), float(thumb_size) / float(image.get_height()))
	var resized_width := maxi(int(round(float(image.get_width()) * scale)), 1)
	var resized_height := maxi(int(round(float(image.get_height()) * scale)), 1)
	image.resize(resized_width, resized_height, Image.INTERPOLATE_NEAREST)
	return image


func _texture_import_preset_settings(preset: String) -> Dictionary:
	var params := {
		"compress/mode": 0,
		"compress/high_quality": false,
		"compress/lossy_quality": 0.7,
		"compress/uastc_level": 0,
		"compress/rdo_quality_loss": 0.0,
		"compress/hdr_compression": 1,
		"compress/normal_map": 0,
		"compress/channel_pack": 0,
		"mipmaps/generate": false,
		"mipmaps/limit": -1,
		"roughness/mode": 0,
		"roughness/src_normal": "",
		"process/channel_remap/red": 0,
		"process/channel_remap/green": 1,
		"process/channel_remap/blue": 2,
		"process/channel_remap/alpha": 3,
		"process/fix_alpha_border": true,
		"process/premult_alpha": false,
		"process/normal_map_invert_y": false,
		"process/hdr_as_srgb": false,
		"process/hdr_clamp_exposure": false,
		"process/size_limit": 0,
		"detect_3d/compress_to": 1
	}
	match _safe_design_slug(preset, "pixel_2d"):
		"pixel", "pixel_art", "pixel_2d":
			params["mipmaps/generate"] = false
			params["process/fix_alpha_border"] = false
		"ui", "ui_2d":
			params["mipmaps/generate"] = false
			params["process/fix_alpha_border"] = true
		"smooth", "filtered":
			params["mipmaps/generate"] = true
			params["process/fix_alpha_border"] = true
		"vram", "3d":
			params["compress/mode"] = 2
			params["mipmaps/generate"] = true
	return {
		"remap": {
			"importer": "texture",
			"type": "CompressedTexture2D",
			"metadata": {
				"vram_texture": false
			}
		},
		"deps": {},
		"params": params
	}


func _write_texture_import_sidecar(source_path: String, sidecar_path: String, settings: Dictionary) -> Dictionary:
	var config := ConfigFile.new()
	if FileAccess.file_exists(sidecar_path):
		var load_error := config.load(sidecar_path)
		if load_error != OK:
			return {
				"error": load_error
			}

	var remap := settings.get("remap", {}) as Dictionary
	if remap.is_empty():
		remap = {
			"importer": "texture",
			"type": "CompressedTexture2D"
		}
	for key in remap.keys():
		config.set_value("remap", str(key), remap[key])
	config.set_value("deps", "source_file", source_path)
	if settings.has("deps") and typeof(settings.get("deps")) == TYPE_DICTIONARY:
		for key in (settings.get("deps") as Dictionary).keys():
			config.set_value("deps", str(key), (settings.get("deps") as Dictionary)[key])

	var params := {}
	if settings.has("params") and typeof(settings.get("params")) == TYPE_DICTIONARY:
		params = settings.get("params") as Dictionary
	else:
		params = settings
	for key in params.keys():
		config.set_value("params", str(key), params[key])

	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sidecar_path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return {
			"error": dir_error
		}
	return {
		"error": config.save(sidecar_path)
	}


func _asset_manifest_entries(files: Array) -> Array:
	var entries: Array = []
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var info := item as Dictionary
		entries.append({
			"path": str(info.get("path", "")),
			"name": str(info.get("name", "")),
			"extension": str(info.get("extension", "")),
			"kind": _asset_kind_for_extension(str(info.get("extension", ""))),
			"resource_type": str(info.get("resource_type", "")),
			"imported": bool(info.get("imported", false))
		})
	return entries


func _asset_kind_for_extension(extension: String) -> String:
	var normalized := extension.strip_edges().trim_prefix(".").to_lower()
	if normalized in DESIGN_IMAGE_EXTENSIONS:
		return "image"
	if normalized in DESIGN_AUDIO_EXTENSIONS:
		return "audio"
	if normalized in DESIGN_FONT_EXTENSIONS:
		return "font"
	if normalized in DESIGN_RESOURCE_EXTENSIONS:
		return "resource"
	if normalized == "json":
		return "metadata"
	return "unknown"


func _build_asset_contact_sheet(files: Array, thumb_size: int, columns: int) -> Dictionary:
	var padding := 10
	var tile_width := thumb_size + padding * 2
	var tile_height := thumb_size + padding * 2 + 10
	var rows := int(ceil(float(files.size()) / float(columns)))
	rows = maxi(rows, 1)
	var width := columns * tile_width + padding
	var height := rows * tile_height + padding
	var sheet := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.07, 0.1, 1.0))
	var assets: Array = []
	for index in files.size():
		var info := files[index] as Dictionary
		var asset_path := str(info.get("path", ""))
		var column := index % columns
		var row := index / columns
		var origin := Vector2i(padding + column * tile_width, padding + row * tile_height)
		var tile_rect := Rect2i(origin, Vector2i(tile_width - padding, tile_height - padding))
		var marker := _stable_preview_color(asset_path)
		_draw_placeholder_rect(sheet, tile_rect, Color(0.08, 0.12, 0.18, 1.0))
		_draw_preview_rect_outline(sheet, tile_rect, Color(0.18, 0.3, 0.48, 1.0), 1)
		_draw_placeholder_rect(sheet, Rect2i(origin.x + 4, origin.y + tile_rect.size.y - 8, tile_rect.size.x - 8, 4), marker)
		var thumbnail := _load_contact_sheet_thumbnail(asset_path, thumb_size)
		var loaded := thumbnail != null
		if loaded:
			var destination := Vector2i(origin.x + padding + (thumb_size - thumbnail.get_width()) / 2, origin.y + padding + (thumb_size - thumbnail.get_height()) / 2)
			sheet.blend_rect(thumbnail, Rect2i(0, 0, thumbnail.get_width(), thumbnail.get_height()), destination)
		else:
			_draw_placeholder_diamond(sheet, Vector2i(origin.x + tile_rect.size.x / 2, origin.y + padding + thumb_size / 2), thumb_size / 3, thumb_size / 3, marker)
		assets.append({
			"path": asset_path,
			"name": str(info.get("name", asset_path.get_file())),
			"extension": str(info.get("extension", "")),
			"loaded": loaded,
			"index": index,
			"column": column,
			"row": row,
			"marker": "#" + marker.to_html(true)
		})
	return {
		"image": sheet,
		"assets": assets,
		"image_count": assets.size(),
		"columns": columns,
		"rows": rows,
		"width": width,
		"height": height
	}


func _load_contact_sheet_thumbnail(path: String, thumb_size: int) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(path))
	if load_error != OK or image.get_width() <= 0 or image.get_height() <= 0:
		return null
	var scale := minf(float(thumb_size) / float(image.get_width()), float(thumb_size) / float(image.get_height()))
	var resized_width := maxi(int(round(float(image.get_width()) * scale)), 1)
	var resized_height := maxi(int(round(float(image.get_height()) * scale)), 1)
	image.resize(resized_width, resized_height, Image.INTERPOLATE_NEAREST)
	return image


func _collect_scene_preview_nodes(node: Node, scene_root: Node, items: Array, max_count: int, depth: int) -> void:
	if node == null or items.size() >= max_count:
		return
	var item := {
		"name": str(node.name),
		"class": node.get_class(),
		"path": _node_path_from_root(node, scene_root),
		"parent_path": "",
		"depth": depth,
		"index": items.size(),
		"kind": "node",
		"has_position": false,
		"position": _encode_value(Vector2.ZERO),
		"size": _encode_value(Vector2.ZERO)
	}
	var parent := node.get_parent()
	if parent != null and parent != scene_root.get_parent():
		item["parent_path"] = _node_path_from_root(parent, scene_root)
	if node is Node2D:
		var node_2d := node as Node2D
		item["kind"] = "node2d"
		item["has_position"] = true
		item["position"] = _encode_value(node_2d.global_position)
		item["size"] = _encode_value(Vector2(24, 24))
	elif node is Control:
		var control := node as Control
		var rect := control.get_global_rect()
		var control_size := rect.size
		if control_size == Vector2.ZERO:
			control_size = control.custom_minimum_size
		if control_size == Vector2.ZERO:
			control_size = Vector2(48, 32)
		item["kind"] = "control"
		item["has_position"] = true
		item["position"] = _encode_value(rect.position + control_size * 0.5)
		item["size"] = _encode_value(control_size)
	items.append(item)
	for child in node.get_children():
		if child is Node:
			_collect_scene_preview_nodes(child as Node, scene_root, items, max_count, depth + 1)


func _build_scene_preview_image(nodes: Array, width: int, height: int) -> Dictionary:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.045, 0.055, 0.075, 1.0))
	var padding := 28
	var positioned: Array = []
	for item in nodes:
		if typeof(item) == TYPE_DICTIONARY and bool((item as Dictionary).get("has_position", false)):
			positioned.append(item)
	var use_world_layout := positioned.size() >= 2
	var min_position := Vector2(INF, INF)
	var max_position := Vector2(-INF, -INF)
	if use_world_layout:
		for item in positioned:
			var position := _decode_value((item as Dictionary).get("position", _encode_value(Vector2.ZERO))) as Vector2
			min_position.x = minf(min_position.x, position.x)
			min_position.y = minf(min_position.y, position.y)
			max_position.x = maxf(max_position.x, position.x)
			max_position.y = maxf(max_position.y, position.y)
		if absf(max_position.x - min_position.x) < 1.0 and absf(max_position.y - min_position.y) < 1.0:
			use_world_layout = false

	var preview_nodes: Array = []
	var path_to_position := {}
	for index in nodes.size():
		var item := (nodes[index] as Dictionary).duplicate(true)
		var preview_position := Vector2.ZERO
		if use_world_layout and bool(item.get("has_position", false)):
			var position := _decode_value(item.get("position", _encode_value(Vector2.ZERO))) as Vector2
			var span := max_position - min_position
			var normalized := Vector2(0.5, 0.5)
			if absf(span.x) >= 1.0:
				normalized.x = (position.x - min_position.x) / span.x
			if absf(span.y) >= 1.0:
				normalized.y = (position.y - min_position.y) / span.y
			preview_position = Vector2(padding + normalized.x * float(width - padding * 2), padding + normalized.y * float(height - padding * 2))
		else:
			var row_height := maxf(float(height - padding * 2) / maxf(float(nodes.size()), 1.0), 18.0)
			preview_position = Vector2(minf(float(padding + int(item.get("depth", 0)) * 78), float(width - padding)), float(padding) + float(index) * row_height + row_height * 0.5)
		var color := _scene_preview_color(item)
		item["preview_position"] = _encode_value(preview_position)
		item["preview_color"] = "#" + color.to_html(true)
		preview_nodes.append(item)
		path_to_position[str(item.get("path", ""))] = preview_position

	for item in preview_nodes:
		var parent_path := str((item as Dictionary).get("parent_path", ""))
		if parent_path.is_empty() or not path_to_position.has(parent_path):
			continue
		var from_position: Vector2 = path_to_position[parent_path]
		var to_position := _decode_value((item as Dictionary).get("preview_position", _encode_value(Vector2.ZERO))) as Vector2
		_draw_preview_line(image, Vector2i(from_position), Vector2i(to_position), Color(0.18, 0.28, 0.42, 0.95), 1)

	for item in preview_nodes:
		var item_dict := item as Dictionary
		var center := Vector2i(_decode_value(item_dict.get("preview_position", _encode_value(Vector2.ZERO))) as Vector2)
		var color := Color.from_string(str(item_dict.get("preview_color", "#64d995ff")), Color(0.39, 0.86, 0.58, 1.0))
		match str(item_dict.get("kind", "node")):
			"control":
				var size := _decode_value(item_dict.get("size", _encode_value(Vector2(48, 32)))) as Vector2
				var preview_size := Vector2i(mini(maxi(int(size.x * 0.18), 12), 54), mini(maxi(int(size.y * 0.18), 10), 42))
				var rect := Rect2i(center - preview_size / 2, preview_size)
				_draw_placeholder_rect(image, rect, color.darkened(0.25))
				_draw_preview_rect_outline(image, rect, color, 2)
			"node2d":
				_draw_placeholder_circle(image, center, 8, color.lightened(0.2))
				_draw_placeholder_circle(image, center, 5, color)
			_:
				_draw_placeholder_diamond(image, center, 8, 8, color)
		if str(item_dict.get("path", "")) == ".":
			_draw_preview_rect_outline(image, Rect2i(center - Vector2i(12, 12), Vector2i(24, 24)), Color(1.0, 0.82, 0.28, 1.0), 1)

	return {
		"image": image,
		"nodes": preview_nodes,
		"layout": "world" if use_world_layout else "tree"
	}


func _scene_preview_color(item: Dictionary) -> Color:
	var node_class := str(item.get("class", ""))
	if node_class.contains("Camera"):
		return Color(0.55, 0.72, 1.0, 1.0)
	if node_class.contains("Collision"):
		return Color(1.0, 0.65, 0.3, 1.0)
	if node_class.contains("Sprite") or node_class.contains("Animated"):
		return Color(0.42, 0.86, 0.62, 1.0)
	if node_class.contains("Button") or node_class.contains("Label") or str(item.get("kind", "")) == "control":
		return Color(0.64, 0.56, 1.0, 1.0)
	if str(item.get("path", "")) == ".":
		return Color(1.0, 0.82, 0.28, 1.0)
	return _stable_preview_color(str(item.get("path", "")))


func _stable_preview_color(text: String) -> Color:
	var hash := 0
	for index in text.length():
		hash = int((hash * 31 + text.unicode_at(index)) % 9973)
	var hue := fmod(float(hash) / 9973.0 + 0.18, 1.0)
	return Color.from_hsv(hue, 0.58, 0.92, 1.0)


func _draw_preview_rect_outline(image: Image, rect: Rect2i, color: Color, thickness: int) -> void:
	var t := maxi(thickness, 1)
	_draw_placeholder_rect(image, Rect2i(rect.position.x, rect.position.y, rect.size.x, t), color)
	_draw_placeholder_rect(image, Rect2i(rect.position.x, rect.position.y + rect.size.y - t, rect.size.x, t), color)
	_draw_placeholder_rect(image, Rect2i(rect.position.x, rect.position.y, t, rect.size.y), color)
	_draw_placeholder_rect(image, Rect2i(rect.position.x + rect.size.x - t, rect.position.y, t, rect.size.y), color)


func _draw_preview_line(image: Image, start: Vector2i, end: Vector2i, color: Color, thickness: int) -> void:
	var delta := end - start
	var steps := maxi(maxi(abs(delta.x), abs(delta.y)), 1)
	for index in range(steps + 1):
		var ratio := float(index) / float(steps)
		var point := Vector2i(roundi(lerpf(float(start.x), float(end.x), ratio)), roundi(lerpf(float(start.y), float(end.y), ratio)))
		_draw_placeholder_circle(image, point, maxi(thickness, 1), color)


func _draw_placeholder_rect(image: Image, rect: Rect2i, color: Color) -> void:
	var min_x := maxi(rect.position.x, 0)
	var min_y := maxi(rect.position.y, 0)
	var max_x := mini(rect.position.x + rect.size.x, image.get_width())
	var max_y := mini(rect.position.y + rect.size.y, image.get_height())
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			image.set_pixel(x, y, color)


func _draw_placeholder_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	var radius_squared := radius * radius
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy <= radius_squared:
				image.set_pixel(x, y, color)


func _draw_placeholder_diamond(image: Image, center: Vector2i, radius_x: int, radius_y: int, color: Color) -> void:
	for y in range(center.y - radius_y, center.y + radius_y + 1):
		for x in range(center.x - radius_x, center.x + radius_x + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var dx: float = abs(x - center.x) / maxf(float(radius_x), 1.0)
			var dy: float = abs(y - center.y) / maxf(float(radius_y), 1.0)
			if dx + dy <= 1.0:
				image.set_pixel(x, y, color)


func _draw_placeholder_triangle(image: Image, a: Vector2i, b: Vector2i, c: Vector2i, color: Color) -> void:
	var min_x := maxi(mini(a.x, mini(b.x, c.x)), 0)
	var max_x := mini(maxi(a.x, maxi(b.x, c.x)), image.get_width() - 1)
	var min_y := maxi(mini(a.y, mini(b.y, c.y)), 0)
	var max_y := mini(maxi(a.y, maxi(b.y, c.y)), image.get_height() - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _placeholder_point_in_triangle(Vector2(x, y), Vector2(a), Vector2(b), Vector2(c)):
				image.set_pixel(x, y, color)


func _placeholder_point_in_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var area := _placeholder_triangle_sign(point, a, b)
	var area_2 := _placeholder_triangle_sign(point, b, c)
	var area_3 := _placeholder_triangle_sign(point, c, a)
	var has_negative := area < 0.0 or area_2 < 0.0 or area_3 < 0.0
	var has_positive := area > 0.0 or area_2 > 0.0 or area_3 > 0.0
	return not (has_negative and has_positive)


func _placeholder_triangle_sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


func _save_new_resource(resource: Resource, path: String, success_message: String, snapshot_reason: String) -> Dictionary:
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return _response(false, "Failed to create resource directory: " + error_string(dir_error), {
			"path": path
		})

	var snapshot := _create_snapshot([
		{
			"type": "write_file",
			"path": path
		}
	], snapshot_reason)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; resource was not saved.", {
			"snapshot": snapshot
		})

	var save_error := ResourceSaver.save(resource, path)
	if save_error != OK:
		return _response(false, "Failed to save resource: " + error_string(save_error), {
			"path": path,
			"snapshot": _snapshot_summary(snapshot)
		}, [], [path])
	_refresh_editor_filesystem()
	return _response(true, success_message, {
		"path": path,
		"resource": _resource_file_info(path, true),
		"snapshot": _snapshot_summary(snapshot)
	}, [], [path])


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


func _get_common_project_settings(_request: Dictionary) -> Dictionary:
	var settings := {}
	for key in COMMON_PROJECT_SETTINGS.keys():
		var setting := str(COMMON_PROJECT_SETTINGS[key])
		settings[str(key)] = {
			"setting": setting,
			"exists": ProjectSettings.has_setting(setting),
			"value": _encode_value(ProjectSettings.get_setting(setting, null))
		}
	return _response(true, "ok", {
		"settings": settings
	})


func _set_common_project_settings(request: Dictionary) -> Dictionary:
	var raw_settings = request.get("settings", {})
	if typeof(raw_settings) != TYPE_DICTIONARY:
		return _response(false, "set_common_project_settings requires a settings Dictionary.")
	var requested := raw_settings as Dictionary
	var changes: Array = []
	var decoded_values := {}
	for key in requested.keys():
		var name := str(key)
		if not COMMON_PROJECT_SETTINGS.has(name):
			return _response(false, "Unsupported common project setting: " + name, {
				"supported": COMMON_PROJECT_SETTINGS.keys()
			})
		var decoded := _decode_common_project_setting(name, requested[key])
		if not bool(decoded.get("ok", false)):
			return _response(false, str(decoded.get("message", "")))
		decoded_values[name] = decoded.get("value")

	if decoded_values.is_empty():
		return _response(false, "No common project settings provided.")

	var snapshot := _create_project_file_snapshot("set_common_project_settings")
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to snapshot project.godot; settings were not changed.", {
			"snapshot": snapshot
		})

	for key in decoded_values.keys():
		var setting := str(COMMON_PROJECT_SETTINGS[key])
		var before_value = ProjectSettings.get_setting(setting, null)
		ProjectSettings.set_setting(setting, decoded_values[key])
		changes.append({
			"key": str(key),
			"setting": setting,
			"before": _encode_value(before_value),
			"after": _encode_value(ProjectSettings.get_setting(setting))
		})

	var save_result := _save_project_settings_if_requested(request)
	return _response(save_result == OK, "Common project settings updated." if save_result == OK else "Common project settings updated, but saving failed: " + error_string(save_result), {
		"changes": changes,
		"saved": save_result == OK,
		"snapshot": _snapshot_summary(snapshot)
	}, [], ["res://project.godot"])


func _get_autoloads(_request: Dictionary) -> Dictionary:
	var autoloads: Array = []
	for property_info in ProjectSettings.get_property_list():
		if typeof(property_info) != TYPE_DICTIONARY:
			continue
		var setting := str((property_info as Dictionary).get("name", ""))
		if not setting.begins_with("autoload/"):
			continue
		var name := setting.trim_prefix("autoload/")
		autoloads.append(_autoload_snapshot(name))
	autoloads.sort_custom(func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))
	return _response(true, "ok", {
		"autoloads": autoloads
	})


func _add_autoload(request: Dictionary) -> Dictionary:
	var name := _normalize_autoload_name(str(request.get("name", "")))
	if name.is_empty():
		return _response(false, "Autoload name is invalid.")
	var path := _normalize_action_path(str(request.get("path", request.get("script_path", ""))))
	if path.is_empty():
		return _response(false, "Autoload path is invalid or not allowed.")
	if not (path.get_extension().to_lower() in ["gd", "tscn", "scn"]):
		return _response(false, "Autoload path must be a .gd, .tscn, or .scn file.")
	if not FileAccess.file_exists(path):
		return _response(false, "Autoload file does not exist: " + path)

	var setting := "autoload/" + name
	var before := _autoload_snapshot(name)
	var snapshot := _create_project_file_snapshot("add_autoload " + name)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to snapshot project.godot; autoload was not changed.", {
			"snapshot": snapshot
		})

	var singleton := bool(request.get("singleton", true))
	ProjectSettings.set_setting(setting, ("*" if singleton else "") + path)
	var save_result := _save_project_settings_if_requested(request)
	return _response(save_result == OK, "Autoload updated." if save_result == OK else "Autoload updated, but saving failed: " + error_string(save_result), {
		"before": before,
		"after": _autoload_snapshot(name),
		"saved": save_result == OK,
		"snapshot": _snapshot_summary(snapshot)
	}, [], ["res://project.godot"])


func _remove_autoload(request: Dictionary) -> Dictionary:
	var name := _normalize_autoload_name(str(request.get("name", "")))
	if name.is_empty():
		return _response(false, "Autoload name is invalid.")
	var setting := "autoload/" + name
	var before := _autoload_snapshot(name)
	var snapshot := _create_project_file_snapshot("remove_autoload " + name)
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to snapshot project.godot; autoload was not changed.", {
			"snapshot": snapshot
		})

	if ProjectSettings.has_setting(setting):
		ProjectSettings.clear(setting)
	var save_result := _save_project_settings_if_requested(request)
	return _response(save_result == OK, "Autoload removed." if save_result == OK else "Autoload removed, but saving failed: " + error_string(save_result), {
		"before": before,
		"after": _autoload_snapshot(name),
		"saved": save_result == OK,
		"snapshot": _snapshot_summary(snapshot)
	}, [], ["res://project.godot"])


func _get_layer_names(request: Dictionary) -> Dictionary:
	var family_filter := str(request.get("family", "")).strip_edges()
	var max_count := int(request.get("max_count", 32))
	max_count = mini(maxi(max_count, 1), 32)
	var families: Array = []
	for family in LAYER_FAMILIES.keys():
		var family_name := str(family)
		if not family_filter.is_empty() and family_name != family_filter:
			continue
		families.append(_layer_family_snapshot(family_name, max_count))
	if not family_filter.is_empty() and families.is_empty():
		return _response(false, "Unsupported layer family: " + family_filter, {
			"supported": LAYER_FAMILIES.keys()
		})
	families.sort_custom(func(a, b): return str(a.get("family", "")) < str(b.get("family", "")))
	return _response(true, "ok", {
		"families": families
	})


func _set_layer_name(request: Dictionary) -> Dictionary:
	var family := str(request.get("family", "")).strip_edges()
	if not LAYER_FAMILIES.has(family):
		return _response(false, "Unsupported layer family: " + family, {
			"supported": LAYER_FAMILIES.keys()
		})
	var layer := int(request.get("layer", request.get("index", 0)))
	var family_info := LAYER_FAMILIES[family] as Dictionary
	var layer_count := int(family_info.get("count", 20))
	if layer < 1 or layer > layer_count:
		return _response(false, "Layer index must be between 1 and " + str(layer_count) + ".")
	var layer_name := str(request.get("name", request.get("value", ""))).strip_edges()
	var setting := str(family_info.get("prefix", "")) + str(layer)
	var before_value = ProjectSettings.get_setting(setting, "")
	var snapshot := _create_project_file_snapshot("set_layer_name " + family + " " + str(layer))
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to snapshot project.godot; layer name was not changed.", {
			"snapshot": snapshot
		})

	ProjectSettings.set_setting(setting, layer_name)
	var save_result := _save_project_settings_if_requested(request)
	return _response(save_result == OK, "Layer name updated." if save_result == OK else "Layer name updated, but saving failed: " + error_string(save_result), {
		"family": family,
		"layer": layer,
		"setting": setting,
		"before": _encode_value(before_value),
		"after": _encode_value(ProjectSettings.get_setting(setting, "")),
		"saved": save_result == OK,
		"snapshot": _snapshot_summary(snapshot)
	}, [], ["res://project.godot"])


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


func _set_inspector_properties(request: Dictionary) -> Dictionary:
	var resolved := _resolve_inspector_object(request)
	if not bool(resolved.get("ok", false)):
		return _response(false, str(resolved.get("message", "")))

	var object := resolved.get("object") as Object
	var raw_properties = request.get("properties", {})
	var property_items: Array = []
	if typeof(raw_properties) == TYPE_DICTIONARY:
		var property_dict := raw_properties as Dictionary
		for property_name in property_dict.keys():
			property_items.append({
				"property": str(property_name),
				"value": property_dict[property_name]
			})
	elif typeof(raw_properties) == TYPE_ARRAY:
		property_items = raw_properties as Array
	else:
		return _response(false, "set_inspector_properties requires properties as Dictionary or Array.")

	if property_items.is_empty():
		return _response(false, "No properties provided.")

	for item in property_items:
		if typeof(item) != TYPE_DICTIONARY:
			return _response(false, "Property item is not a Dictionary.")
		var property_name := str((item as Dictionary).get("property", "")).strip_edges()
		if property_name.is_empty():
			return _response(false, "Missing property.")
		if not _has_property(object, property_name):
			return _response(false, "Target does not have property: " + property_name)

	var snapshot := _create_object_snapshot(object, str(resolved.get("path", "")), "set_inspector_properties")
	if not bool(snapshot.get("ok", true)):
		return _response(false, "Failed to create pre-change snapshot; properties were not set.", {
			"snapshot": snapshot
		})

	var changes: Array = []
	for item in property_items:
		var property_item := item as Dictionary
		var property_name := str(property_item.get("property", "")).strip_edges()
		var before_value = object.get(property_name)
		_set_object_property(object, property_name, _decode_value(property_item.get("value")))
		changes.append({
			"property": property_name,
			"before": _encode_value(before_value),
			"after": _encode_value(object.get(property_name))
		})

	var changed_paths := _changed_paths_for_raw_object(resolved)
	if object is Node:
		_set_scene_dirty()
		_focus_editor_node(object as Node)
	elif object is Resource:
		var resource := object as Resource
		if not resource.resource_path.is_empty():
			ResourceSaver.save(resource, resource.resource_path)

	return _response(true, "Properties set.", {
		"target": resolved.get("target", {}),
		"changes": changes,
		"snapshot": _snapshot_summary(snapshot) if not snapshot.is_empty() else {}
	}, [], changed_paths, {
		"type": "inspector_target",
		"target": resolved.get("target", {})
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


func _queue_summary() -> Dictionary:
	var pending := _pending_action_summaries(true)
	var action_count := 0
	var changed_paths: Array = []
	for item in pending:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var queued := item as Dictionary
		action_count += int(queued.get("action_count", 0))
		var preview := queued.get("preview", {}) as Dictionary
		for action_item in preview.get("actions", []) as Array:
			if typeof(action_item) != TYPE_DICTIONARY:
				continue
			_append_unique_path(changed_paths, str((action_item as Dictionary).get("target", "")))

	return _response(true, "ok", {
		"pending_count": pending.size(),
		"action_count": action_count,
		"pending": pending,
		"changed_targets": changed_paths,
		"pending_path": _pending_actions_path()
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
	var visual_feedback := _focus_after_actions(actions, action_result)
	return _response(true, "ok", {
		"snapshot": _snapshot_summary(snapshot),
		"action_result": action_result,
		"visual_feedback": visual_feedback
	})


func _focus_after_actions(actions: Array, action_result: Dictionary) -> Dictionary:
	var results = action_result.get("results", [])
	if typeof(results) != TYPE_ARRAY:
		return {
			"focused": false,
			"reason": "action result did not include result items"
		}

	var result_items := results as Array
	for index in range(result_items.size() - 1, -1, -1):
		var result_item = result_items[index]
		if typeof(result_item) != TYPE_DICTIONARY:
			continue
		var result := result_item as Dictionary
		if not bool(result.get("ok", false)):
			continue

		var action := {}
		if index < actions.size() and typeof(actions[index]) == TYPE_DICTIONARY:
			action = actions[index] as Dictionary

		var node_path := _focus_path_for_action(action, result)
		if node_path.is_empty():
			continue

		var node := _find_scene_node(node_path)
		if node == null:
			continue

		_focus_editor_node(node)
		return {
			"focused": true,
			"reason": "last successful scene action",
			"action_type": str(result.get("type", "")),
			"node": _node_summary(node, _edited_scene_root())
		}

	return {
		"focused": false,
		"reason": "no focusable scene node"
	}


func _focus_path_for_action(action: Dictionary, result: Dictionary) -> String:
	var action_type := str(result.get("type", action.get("type", ""))).strip_edges()
	match action_type:
		"add_node":
			return str(result.get("path", "")).strip_edges()
		"set_property", "attach_script", "rename_node", "duplicate_node", "move_node", "set_owner", "set_unique_name", "add_group", "remove_group", "set_metadata", "remove_metadata":
			return str(action.get("node_path", action.get("path", ""))).strip_edges()
		"reparent_node":
			return str(result.get("path", action.get("node_path", action.get("path", "")))).strip_edges()
		"connect_signal":
			var target_path := str(action.get("target_path", "")).strip_edges()
			if not target_path.is_empty():
				return target_path
			return str(action.get("source_path", "")).strip_edges()
		_:
			return ""


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
	elif not (action_type in _supported_action_types()):
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
	elif action_type in ["remove_node", "rename_node", "duplicate_node", "reparent_node", "move_node", "set_owner", "set_unique_name", "add_group", "remove_group", "set_metadata", "remove_metadata"]:
		if str(action.get("node_path", action.get("path", ""))).strip_edges().is_empty():
			ok = false
			message = "Missing node_path."
		elif action_type == "rename_node" and str(action.get("name", "")).strip_edges().is_empty():
			ok = false
			message = "Missing name."
		elif action_type == "reparent_node" and str(action.get("new_parent_path", action.get("parent_path", ""))).strip_edges().is_empty():
			ok = false
			message = "Missing new_parent_path."
		elif action_type in ["add_group", "remove_group"] and str(action.get("group", "")).strip_edges().is_empty():
			ok = false
			message = "Missing group."
		elif action_type in ["set_metadata", "remove_metadata"] and str(action.get("key", "")).strip_edges().is_empty():
			ok = false
			message = "Missing metadata key."

	if message.is_empty():
		message = "Will apply: " + action_type

	return {
		"index": index,
		"ok": ok,
		"type": action_type,
		"target": target,
		"message": message
	}


func _supported_action_types() -> Array:
	return [
		"write_file",
		"append_file",
		"make_dir",
		"create_scene",
		"open_scene",
		"refresh_filesystem",
		"add_node",
		"set_property",
		"attach_script",
		"connect_signal",
		"remove_node",
		"rename_node",
		"duplicate_node",
		"reparent_node",
		"move_node",
		"set_owner",
		"set_unique_name",
		"add_group",
		"remove_group",
		"set_metadata",
		"remove_metadata"
	]


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
		"remove_node", "rename_node", "duplicate_node", "move_node", "set_owner", "set_unique_name", "add_group", "remove_group", "set_metadata", "remove_metadata":
			return str(action.get("node_path", action.get("path", "")))
		"reparent_node":
			return str(action.get("node_path", action.get("path", ""))) + " -> " + str(action.get("new_parent_path", action.get("parent_path", "")))
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
	var report := _play_command_report("play_main_scene", true, "Main scene started.")
	_record_run_report(report)
	return _response(true, "Main scene started.", {
		"play": report.get("play", {}),
		"report": report
	})


func _play_current_scene() -> Dictionary:
	if editor_interface == null or not editor_interface.has_method("play_current_scene"):
		return _response(false, "play_current_scene is not available in this environment.")

	editor_interface.play_current_scene()
	var report := _play_command_report("play_current_scene", true, "Current scene started.")
	_record_run_report(report)
	return _response(true, "Current scene started.", {
		"play": report.get("play", {}),
		"report": report
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
	var report := _play_command_report("play_custom_scene", true, "Custom scene started.")
	report["scene_path"] = scene_path
	_record_run_report(report)
	return _response(true, "Custom scene started.", {
		"scene_path": scene_path,
		"play": report.get("play", {}),
		"report": report
	})


func _stop_playing_scene() -> Dictionary:
	if editor_interface == null or not editor_interface.has_method("stop_playing_scene"):
		return _response(false, "stop_playing_scene is not available in this environment.")

	editor_interface.stop_playing_scene()
	var report := _play_command_report("stop_playing_scene", true, "Scene playback stopped.")
	_record_run_report(report)
	return _response(true, "Scene playback stopped.", {
		"play": report.get("play", {}),
		"report": report
	})


func _play_command_report(mode: String, ok: bool, message: String) -> Dictionary:
	return {
		"mode": mode,
		"ok": ok,
		"exit_code": 0 if ok else 1,
		"started_at": Time.get_datetime_string_from_system(),
		"duration_ms": 0,
		"executable": OS.get_executable_path(),
		"arguments": [],
		"errors": [],
		"warnings": [],
		"message": message,
		"play": _play_status(),
		"output": message,
		"output_tail": message
	}


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
		if action_type in ["add_node", "set_property", "attach_script", "connect_signal", "remove_node", "rename_node", "duplicate_node", "reparent_node", "move_node", "set_owner", "set_unique_name", "add_group", "remove_group", "set_metadata", "remove_metadata"]:
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


func _normalize_autoload_name(raw_name: String) -> String:
	var name := raw_name.strip_edges()
	if name.is_empty() or not name.is_valid_identifier():
		return ""
	return name


func _project_root() -> String:
	return _normalize_absolute_path(ProjectSettings.globalize_path("res://"))


func _history_path() -> String:
	return _file_bridge_root().path_join("history.jsonl")


func _run_reports_path() -> String:
	return _file_bridge_root().path_join("run_reports.jsonl")


func _raw_audit_path() -> String:
	return _file_bridge_root().path_join("raw_audit.jsonl")


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


func _decode_common_project_setting(name: String, raw_value) -> Dictionary:
	match name:
		"project_name":
			var project_name := str(raw_value).strip_edges()
			if project_name.is_empty():
				return {
					"ok": false,
					"message": "project_name cannot be empty."
				}
			return {
				"ok": true,
				"value": project_name
			}
		"main_scene":
			var scene_path := _normalize_scene_path(str(raw_value))
			if scene_path.is_empty():
				return {
					"ok": false,
					"message": "main_scene must be a valid .tscn path."
				}
			return {
				"ok": true,
				"value": scene_path
			}
		"window_width", "window_height":
			var dimension := int(raw_value)
			if dimension < 1 or dimension > 16384:
				return {
					"ok": false,
					"message": name + " must be between 1 and 16384."
				}
			return {
				"ok": true,
				"value": dimension
			}
		"physics_ticks_per_second":
			var ticks := int(raw_value)
			if ticks < 1 or ticks > 1000:
				return {
					"ok": false,
					"message": "physics_ticks_per_second must be between 1 and 1000."
				}
			return {
				"ok": true,
				"value": ticks
			}
		"audio_mix_rate":
			var mix_rate := int(raw_value)
			if mix_rate < 8000 or mix_rate > 384000:
				return {
					"ok": false,
					"message": "audio_mix_rate must be between 8000 and 384000."
				}
			return {
				"ok": true,
				"value": mix_rate
			}
		_:
			return {
				"ok": true,
				"value": _decode_value(raw_value)
			}


func _autoload_snapshot(name: String) -> Dictionary:
	var setting := "autoload/" + name
	if not ProjectSettings.has_setting(setting):
		return {
			"name": name,
			"exists": false,
			"setting": setting
		}
	var raw_value := str(ProjectSettings.get_setting(setting, ""))
	var singleton := raw_value.begins_with("*")
	var path := raw_value.substr(1) if singleton else raw_value
	return {
		"name": name,
		"exists": true,
		"setting": setting,
		"path": path,
		"singleton": singleton,
		"raw_value": raw_value
	}


func _layer_family_snapshot(family: String, requested_max_count: int) -> Dictionary:
	var family_info := LAYER_FAMILIES[family] as Dictionary
	var layer_count := mini(int(family_info.get("count", 20)), requested_max_count)
	var prefix := str(family_info.get("prefix", ""))
	var layers: Array = []
	for layer_index in range(1, layer_count + 1):
		var setting := prefix + str(layer_index)
		layers.append({
			"layer": layer_index,
			"setting": setting,
			"name": str(ProjectSettings.get_setting(setting, "")),
			"exists": ProjectSettings.has_setting(setting)
		})
	return {
		"family": family,
		"prefix": prefix,
		"layer_count": int(family_info.get("count", 20)),
		"layers": layers
	}


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
		TYPE_PACKED_FLOAT32_ARRAY:
			return {
				"type": "PackedFloat32Array",
				"values": Array(value)
			}
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
	if value_dict.has("resource_type"):
		return _instantiate_resource(str(value_dict.get("resource_type", "")), value_dict.get("properties", {}))

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
		"PackedFloat32Array":
			var floats := PackedFloat32Array()
			for item in value_dict.get("values", []):
				floats.append(float(item))
			return floats
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


func _instantiate_resource(resource_type: String, raw_properties) -> Resource:
	var type_name := resource_type.strip_edges()
	if type_name.is_empty() or not ClassDB.class_exists(type_name) or not ClassDB.can_instantiate(type_name):
		return null

	var object = ClassDB.instantiate(type_name)
	if not object is Resource:
		if object != null and object.has_method("free"):
			object.free()
		return null

	var resource := object as Resource
	if typeof(raw_properties) == TYPE_DICTIONARY:
		var properties := raw_properties as Dictionary
		for property_name in properties.keys():
			var name := str(property_name)
			if _has_property(resource, name):
				resource.set(name, _decode_value(properties[property_name]))
	return resource


func _apply_theme_values(theme: Theme, section: String, raw_values) -> Array:
	var errors: Array = []
	var entries := _theme_entries(raw_values)
	for entry in entries:
		var name := str(entry.get("name", "")).strip_edges()
		var type_name := str(entry.get("type_name", entry.get("type", ""))).strip_edges()
		if name.is_empty() or type_name.is_empty():
			errors.append(section + " entry is missing name or type_name.")
			continue
		match section:
			"colors":
				var color_value = _decode_value(entry.get("value"))
				if not color_value is Color:
					errors.append("Theme color " + type_name + "/" + name + " is not a Color.")
					continue
				theme.set_color(StringName(name), StringName(type_name), color_value)
			"constants":
				theme.set_constant(StringName(name), StringName(type_name), int(entry.get("value", 0)))
			"font_sizes":
				theme.set_font_size(StringName(name), StringName(type_name), int(entry.get("value", 0)))
	return errors


func _theme_entries(raw_values) -> Array:
	var entries: Array = []
	if typeof(raw_values) == TYPE_DICTIONARY:
		var values := raw_values as Dictionary
		for raw_key in values.keys():
			var key := str(raw_key)
			var parts := key.split("/", false, 1)
			if parts.size() != 2:
				entries.append({
					"name": "",
					"type_name": "",
					"value": values[raw_key]
				})
				continue
			entries.append({
				"type_name": str(parts[0]),
				"name": str(parts[1]),
				"value": values[raw_key]
			})
	elif typeof(raw_values) == TYPE_ARRAY:
		for item in raw_values as Array:
			if typeof(item) == TYPE_DICTIONARY:
				entries.append(item as Dictionary)
	return entries


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


func _record_raw_audit(entry: Dictionary) -> void:
	var audit_entry := entry.duplicate(true)
	audit_entry["raw_mode_enabled"] = _raw_api_enabled()
	raw_audit_entries.append(audit_entry)
	while raw_audit_entries.size() > RAW_AUDIT_LIMIT:
		raw_audit_entries.pop_front()

	var path := _raw_audit_path()
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_warning("Godot Codex Bridge could not create raw audit directory: " + error_string(dir_error))
		return

	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Godot Codex Bridge could not write raw audit: " + error_string(FileAccess.get_open_error()))
		return

	file.seek_end()
	file.store_string(JSON.stringify(audit_entry))
	file.store_string("\n")


func _load_raw_audit() -> void:
	raw_audit_entries.clear()
	var path := _raw_audit_path()
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			raw_audit_entries.append(parsed as Dictionary)
	while raw_audit_entries.size() > RAW_AUDIT_LIMIT:
		raw_audit_entries.pop_front()


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
