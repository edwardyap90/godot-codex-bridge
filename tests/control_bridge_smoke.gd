extends SceneTree

const BridgeScript = preload("res://addons/godot_codex_bridge/control_bridge.gd")


class FakeSelection:
	extends RefCounted

	var selected_nodes: Array[Node] = []

	func get_selected_nodes() -> Array[Node]:
		return selected_nodes

	func clear() -> void:
		selected_nodes.clear()

	func add_node(node: Node) -> void:
		selected_nodes.append(node)


class FakeResourceFilesystem:
	extends RefCounted

	var scan_count := 0
	var scan_sources_count := 0
	var reimported_paths: Array = []

	func scan() -> void:
		scan_count += 1

	func scan_sources() -> void:
		scan_sources_count += 1

	func reimport_files(paths: PackedStringArray) -> void:
		reimported_paths = Array(paths)

	func get_file_type(path: String) -> String:
		if path.ends_with(".tscn"):
			return "PackedScene"
		if path.ends_with(".gd"):
			return "GDScript"
		return ""


class FakeEditorInterface:
	extends RefCounted

	var scene_root: Node
	var selection := FakeSelection.new()
	var filesystem := FakeResourceFilesystem.new()
	var dirty_count := 0
	var edit_count := 0
	var last_edited_node_name := ""
	var playing := false
	var last_played_scene := ""

	func _init(p_scene_root: Node) -> void:
		scene_root = p_scene_root

	func get_edited_scene_root() -> Node:
		return scene_root

	func get_selection() -> FakeSelection:
		return selection

	func get_resource_filesystem() -> FakeResourceFilesystem:
		return filesystem

	func edit_node(node: Node) -> void:
		edit_count += 1
		last_edited_node_name = node.name

	func mark_scene_as_unsaved() -> void:
		dirty_count += 1

	func is_playing_scene() -> bool:
		return playing

	func play_main_scene() -> void:
		playing = true
		last_played_scene = ProjectSettings.get_setting("application/run/main_scene", "")

	func play_current_scene() -> void:
		playing = true
		last_played_scene = scene_root.scene_file_path

	func play_custom_scene(scene_path: String) -> void:
		playing = true
		last_played_scene = scene_path

	func stop_playing_scene() -> void:
		playing = false


func _init() -> void:
	var scene_root := Node2D.new()
	scene_root.name = "TestScene"
	root.add_child(scene_root)

	var animation_player := AnimationPlayer.new()
	animation_player.name = "Animator"
	scene_root.add_child(animation_player)
	animation_player.owner = scene_root

	var fake_editor := FakeEditorInterface.new(scene_root)
	var bridge := BridgeScript.new()
	bridge.setup(fake_editor, 9876)
	bridge.token = ""

	var ping_result: Dictionary = bridge.handle_request({
		"command": "ping"
	})
	var tree_result: Dictionary = bridge.handle_request({
		"command": "get_scene_tree"
	})
	var project_result: Dictionary = bridge.handle_request({
		"command": "get_project_info"
	})
	var identity_result: Dictionary = bridge.handle_request({
		"command": "get_project_identity"
	})
	var mismatch_result: Dictionary = bridge.handle_request({
		"command": "ping",
		"project_root": "/tmp/not-this-project"
	})
	var context_result: Dictionary = bridge.handle_request({
		"command": "get_editor_context"
	})
	var capabilities_result: Dictionary = bridge.handle_request({
		"command": "list_editor_capabilities"
	})
	var capabilities_v2_result: Dictionary = bridge.handle_request({
		"command": "list_capabilities_v2"
	})
	var command_schema_result: Dictionary = bridge.handle_request({
		"command": "get_command_schema"
	})
	var raw_status_result: Dictionary = bridge.handle_request({
		"command": "get_raw_mode_status"
	})
	var raw_disabled_result: Dictionary = bridge.handle_request({
		"command": "raw_classdb_query",
		"query": "class_exists",
		"class": "Node2D"
	})
	var inspector_result: Dictionary = bridge.handle_request({
		"command": "get_inspector_properties",
		"node_path": ".",
		"max_count": 80
	})
	var inspector_set_result: Dictionary = bridge.handle_request({
		"command": "set_inspector_property",
		"node_path": ".",
		"property": "position",
		"value": {
			"type": "Vector2",
			"x": 4,
			"y": 5
		}
	})
	var project_setting_result: Dictionary = bridge.handle_request({
		"command": "get_project_setting",
		"setting": "application/config/name"
	})
	var project_setting_set_result: Dictionary = bridge.handle_request({
		"command": "set_project_setting",
		"setting": "codex_bridge/smoke_temp",
		"value": true,
		"save": false
	})
	var project_settings_list_result: Dictionary = bridge.handle_request({
		"command": "get_project_settings",
		"prefix": "codex_bridge/",
		"max_count": 20
	})
	var common_project_settings_result: Dictionary = bridge.handle_request({
		"command": "get_common_project_settings"
	})
	var common_project_settings_set_result: Dictionary = bridge.handle_request({
		"command": "set_common_project_settings",
		"save": false,
		"settings": {
			"main_scene": "res://tests/fixtures/fixture_scene.tscn",
			"window_width": 960,
			"window_height": 540,
			"physics_ticks_per_second": 60
		}
	})
	var autoload_path := "res://tests/fixtures/fixture_scene.tscn"
	var autoloads_before_result: Dictionary = bridge.handle_request({
		"command": "get_autoloads"
	})
	var add_autoload_result: Dictionary = bridge.handle_request({
		"command": "add_autoload",
		"name": "CodexSmokeAutoload",
		"path": autoload_path,
		"save": false
	})
	var autoloads_after_add_result: Dictionary = bridge.handle_request({
		"command": "get_autoloads"
	})
	var remove_autoload_result: Dictionary = bridge.handle_request({
		"command": "remove_autoload",
		"name": "CodexSmokeAutoload",
		"save": false
	})
	var layer_names_result: Dictionary = bridge.handle_request({
		"command": "get_layer_names",
		"family": "2d_physics",
		"max_count": 3
	})
	var set_layer_name_result: Dictionary = bridge.handle_request({
		"command": "set_layer_name",
		"family": "2d_physics",
		"layer": 3,
		"name": "codex_smoke_layer",
		"save": false
	})
	var input_add_result: Dictionary = bridge.handle_request({
		"command": "add_input_action",
		"action": "codex_smoke_action",
		"replace_events": true,
		"save": false,
		"events": [
			{
				"type": "key",
				"key": "T"
			}
		]
	})
	var input_list_result: Dictionary = bridge.handle_request({
		"command": "get_input_actions",
		"prefix": "codex_smoke"
	})
	var input_remove_result: Dictionary = bridge.handle_request({
		"command": "remove_input_action",
		"action": "codex_smoke_action",
		"save": false
	})
	var editor_command_result: Dictionary = bridge.handle_request({
		"command": "execute_editor_command",
		"editor_command": "refresh_filesystem"
	})
	var resource_files_result: Dictionary = bridge.handle_request({
		"command": "get_resource_files",
		"root": "res://tests/fixtures",
		"extensions": ["tscn"],
		"max_count": 20
	})
	var resource_info_result: Dictionary = bridge.handle_request({
		"command": "get_resource_info",
		"path": "res://tests/fixtures/fixture_scene.tscn",
		"include_loaded": true
	})
	var resource_import_result: Dictionary = bridge.handle_request({
		"command": "get_resource_import_info",
		"path": "res://tests/fixtures/fixture_scene.tscn"
	})
	var scan_resources_result: Dictionary = bridge.handle_request({
		"command": "scan_resource_filesystem",
		"scan_sources": true
	})
	var reimport_resources_result: Dictionary = bridge.handle_request({
		"command": "reimport_resources",
		"paths": ["res://tests/fixtures/fixture_scene.tscn"]
	})
	var reimported_paths_after_resource_smoke := fake_editor.filesystem.reimported_paths.duplicate()
	var animation_players_result: Dictionary = bridge.handle_request({
		"command": "get_animation_players"
	})
	var create_animation_result: Dictionary = bridge.handle_request({
		"command": "create_animation",
		"node_path": "Animator",
		"animation_name": "bridge_smoke",
		"length": 1.0
	})
	var set_animation_properties_result: Dictionary = bridge.handle_request({
		"command": "set_animation_properties",
		"node_path": "Animator",
		"animation_name": "bridge_smoke",
		"length": 2.5,
		"loop_mode": "linear"
	})
	var add_animation_key_result: Dictionary = bridge.handle_request({
		"command": "add_animation_value_key",
		"node_path": "Animator",
		"animation_name": "bridge_smoke",
		"target_path": "..",
		"property": "position",
		"time": 1.0,
		"value": {
			"type": "Vector2",
			"x": 40,
			"y": 50
		}
	})
	var animation_info_result: Dictionary = bridge.handle_request({
		"command": "get_animation_player_info",
		"node_path": "Animator"
	})
	var dry_run_result: Dictionary = bridge.handle_request({
		"command": "apply_actions",
		"dry_run": true,
		"actions": [
			{
				"type": "add_node",
				"parent_path": ".",
				"node_type": "Node2D",
				"name": "DryRunChild"
			}
		]
	})
	var queue_scene_result: Dictionary = bridge.handle_request({
		"command": "queue_actions",
		"summary": "queue scene smoke",
		"actions": [
			{
				"type": "add_node",
				"parent_path": ".",
				"node_type": "Node2D",
				"name": "QueuedChild"
			}
		]
	})
	var queue_scene_data := queue_scene_result.get("data", {}) as Dictionary
	var queued_scene := queue_scene_data.get("queued", {}) as Dictionary
	var queue_scene_id := str(queued_scene.get("queue_id", ""))
	var queued_child_before_apply := scene_root.get_node_or_null("QueuedChild")
	var pending_result: Dictionary = bridge.handle_request({
		"command": "get_pending_actions"
	})
	var queue_summary_result: Dictionary = bridge.handle_request({
		"command": "get_queue_summary"
	})
	var apply_queue_scene_result: Dictionary = bridge.handle_request({
		"command": "apply_queued_actions",
		"queue_id": queue_scene_id
	})
	var queue_node_ops_result: Dictionary = bridge.handle_request({
		"command": "queue_actions",
		"summary": "node operation smoke",
		"actions": [
			{
				"type": "rename_node",
				"node_path": "QueuedChild",
				"name": "RenamedQueuedChild"
			},
			{
				"type": "set_unique_name",
				"node_path": "RenamedQueuedChild",
				"enabled": true
			},
			{
				"type": "add_group",
				"node_path": "RenamedQueuedChild",
				"group": "codex_smoke_group"
			},
			{
				"type": "set_metadata",
				"node_path": "RenamedQueuedChild",
				"key": "codex_smoke",
				"value": "ok"
			},
			{
				"type": "duplicate_node",
				"node_path": "RenamedQueuedChild",
				"name": "DuplicatedQueuedChild"
			},
			{
				"type": "remove_node",
				"node_path": "DuplicatedQueuedChild"
			}
		]
	})
	var queue_node_ops_data := queue_node_ops_result.get("data", {}) as Dictionary
	var queue_node_ops_queued := queue_node_ops_data.get("queued", {}) as Dictionary
	var apply_node_ops_result: Dictionary = bridge.handle_request({
		"command": "apply_queued_actions",
		"queue_id": str(queue_node_ops_queued.get("queue_id", ""))
	})
	var discard_queue_result: Dictionary = bridge.handle_request({
		"command": "queue_actions",
		"summary": "discard smoke",
		"actions": [
			{
				"type": "add_node",
				"parent_path": ".",
				"node_type": "Node2D",
				"name": "DiscardedChild"
			}
		]
	})
	var discard_queue_data := discard_queue_result.get("data", {}) as Dictionary
	var discard_queued := discard_queue_data.get("queued", {}) as Dictionary
	var discard_result: Dictionary = bridge.handle_request({
		"command": "discard_queued_actions",
		"queue_id": str(discard_queued.get("queue_id", ""))
	})
	var file_path := "res://tmp_bridge_queue/queued.txt"
	_remove_file(file_path)
	var queue_file_result: Dictionary = bridge.handle_request({
		"command": "queue_actions",
		"summary": "queue file smoke",
		"actions": [
			{
				"type": "write_file",
				"path": file_path,
				"content": "queued file"
			}
		]
	})
	var queue_file_data := queue_file_result.get("data", {}) as Dictionary
	var queued_file := queue_file_data.get("queued", {}) as Dictionary
	var apply_queue_file_result: Dictionary = bridge.handle_request({
		"command": "apply_queued_actions",
		"queue_id": str(queued_file.get("queue_id", ""))
	})
	var file_exists_after_apply := FileAccess.file_exists(file_path)
	var apply_queue_file_data := apply_queue_file_result.get("data", {}) as Dictionary
	var file_snapshot := apply_queue_file_data.get("snapshot", {}) as Dictionary
	var snapshots_result: Dictionary = bridge.handle_request({
		"command": "get_snapshots"
	})
	var restore_result: Dictionary = bridge.handle_request({
		"command": "restore_snapshot",
		"snapshot_id": str(file_snapshot.get("snapshot_id", ""))
	})
	var action_result: Dictionary = bridge.handle_request({
		"command": "apply_actions",
		"actions": [
			{
				"type": "add_node",
				"parent_path": ".",
				"node_type": "Node2D",
				"name": "BridgeChild",
				"properties": {
					"position": {
						"type": "Vector2",
						"x": 12,
						"y": 34
					}
				}
			}
		]
	})
	var select_result: Dictionary = bridge.handle_request({
		"command": "select_node",
		"node_path": "BridgeChild"
	})
	var selection_result: Dictionary = bridge.handle_request({
		"command": "get_selection"
	})
	var details_result: Dictionary = bridge.handle_request({
		"command": "get_node_details",
		"node_path": "BridgeChild"
	})
	var batch_inspector_result: Dictionary = bridge.handle_request({
		"command": "set_inspector_properties",
		"node_path": "BridgeChild",
		"properties": {
			"position": {
				"type": "Vector2",
				"x": 22,
				"y": 44
			},
			"visible": true
		}
	})
	var resource_path := "res://tmp_bridge_queue/smoke_resource.tres"
	_remove_file(resource_path)
	var create_resource_result: Dictionary = bridge.handle_request({
		"command": "create_resource",
		"path": resource_path,
		"resource_type": "Gradient",
		"replace": true
	})
	var set_resource_result: Dictionary = bridge.handle_request({
		"command": "set_resource_property",
		"path": resource_path,
		"property": "offsets",
		"value": {
			"type": "PackedFloat32Array",
			"values": [0.0, 1.0]
		}
	})
	var save_resource_result: Dictionary = bridge.handle_request({
		"command": "save_resource",
		"path": resource_path
	})
	var material_path := "res://tmp_bridge_queue/smoke_material.tres"
	_remove_file(material_path)
	var create_material_result: Dictionary = bridge.handle_request({
		"command": "create_material",
		"path": material_path,
		"material_type": "CanvasItemMaterial",
		"replace": true,
		"properties": {
			"blend_mode": 1
		}
	})
	var theme_path := "res://tmp_bridge_queue/smoke_theme.tres"
	_remove_file(theme_path)
	var create_theme_result: Dictionary = bridge.handle_request({
		"command": "create_theme",
		"path": theme_path,
		"replace": true,
		"colors": {
			"Label/font_color": {
				"type": "Color",
				"r": 1.0,
				"g": 0.5,
				"b": 0.25,
				"a": 1.0
			}
		},
		"constants": {
			"MarginContainer/margin_left": 8
		},
		"font_sizes": {
			"Label/font_size": 18
		}
	})
	var design_root := "res://tmp_bridge_queue/art"
	_remove_dir_recursive(design_root)
	var design_system_result: Dictionary = bridge.handle_request({
		"command": "create_design_system",
		"root": design_root,
		"name": "Smoke Art",
		"style": "readable arcade UI",
		"replace": true,
		"palette": {
			"background": "#101826",
			"surface": "#22314a",
			"primary": "#4aa3ff",
			"accent": "#62d986",
			"danger": "#ff6060",
			"text": "#edf5ff"
		}
	})
	var get_design_system_result: Dictionary = bridge.handle_request({
		"command": "get_design_system",
		"root": design_root
	})
	var update_design_system_result: Dictionary = bridge.handle_request({
		"command": "update_design_system",
		"root": design_root,
		"style": "readable arcade UI with strong contrast",
		"tokens": {
			"typography": {
				"base_font_size": 20
			}
		}
	})
	var validate_design_system_result: Dictionary = bridge.handle_request({
		"command": "validate_design_system",
		"root": design_root
	})
	var design_tokens_path := design_root.path_join("design_tokens.json")
	var export_design_tokens_result: Dictionary = bridge.handle_request({
		"command": "export_design_tokens",
		"root": design_root,
		"path": design_tokens_path,
		"replace": true
	})
	var palette_path := design_root.path_join("palettes/smoke_palette.json")
	var palette_result: Dictionary = bridge.handle_request({
		"command": "create_palette",
		"path": palette_path,
		"name": "Smoke Palette",
		"replace": true,
		"colors": {
			"background": "#101826",
			"surface": "#22314a",
			"primary": "#4aa3ff",
			"accent": "#62d986",
			"danger": "#ff6060",
			"text": "#edf5ff"
		}
	})
	var ui_theme_path := design_root.path_join("themes/smoke_theme.tres")
	var ui_theme_result: Dictionary = bridge.handle_request({
		"command": "create_ui_theme",
		"path": ui_theme_path,
		"name": "Smoke Theme",
		"palette_path": palette_path,
		"replace": true
	})
	var design_panel := Control.new()
	design_panel.name = "DesignPanel"
	scene_root.add_child(design_panel)
	design_panel.owner = scene_root
	var apply_ui_theme_result: Dictionary = bridge.handle_request({
		"command": "apply_ui_theme",
		"node_path": "DesignPanel",
		"theme_path": ui_theme_path,
		"recursive": true
	})
	var ui_template_path := design_root.path_join("ui/main_menu.tscn")
	var create_ui_template_result: Dictionary = bridge.handle_request({
		"command": "create_ui_template",
		"template": "main_menu",
		"path": ui_template_path,
		"title": "Smoke Game",
		"theme_path": ui_theme_path,
		"replace": true
	})
	var inspect_ui_scene_result: Dictionary = bridge.handle_request({
		"command": "inspect_ui_scene",
		"scene_path": ui_template_path
	})
	var material_pack_result: Dictionary = bridge.handle_request({
		"command": "create_material_pack",
		"root": design_root.path_join("materials"),
		"palette_path": palette_path,
		"replace": true
	})
	var placeholder_sprite_path := design_root.path_join("sprites/smoke_player.png")
	var placeholder_sprite_result: Dictionary = bridge.handle_request({
		"command": "create_placeholder_sprite",
		"path": placeholder_sprite_path,
		"name": "smoke_player",
		"role": "player",
		"width": 32,
		"height": 32,
		"replace": true
	})
	var placeholder_icons_result: Dictionary = bridge.handle_request({
		"command": "create_placeholder_icon_set",
		"root": design_root.path_join("icons"),
		"icons": [
			{
				"name": "heart",
				"role": "health",
				"shape": "heart",
				"color": "#ff6060"
			},
			{
				"name": "coin",
				"role": "coin",
				"shape": "circle",
				"color": "#ffd166"
			}
		],
		"size": 24,
		"replace": true
	})
	var sprite_frames_path := design_root.path_join("sprites/smoke_frames.tres")
	var sprite_frames_result: Dictionary = bridge.handle_request({
		"command": "create_sprite_frames",
		"path": sprite_frames_path,
		"replace": true,
		"animations": [
			{
				"name": "idle",
				"frames": [placeholder_sprite_path],
				"fps": 6.0,
				"loop": true
			}
		]
	})
	var sprite_frames_report_path := design_root.path_join("reports/smoke_frames_animation_report.json")
	var inspect_sprite_frames_result: Dictionary = bridge.handle_request({
		"command": "inspect_sprite_frames",
		"path": sprite_frames_path,
		"expected_animations": ["idle", "run"],
		"write_report": true,
		"report_path": sprite_frames_report_path
	})
	var animated_sprite_result: Dictionary = bridge.handle_request({
		"command": "create_animated_sprite",
		"parent_path": ".",
		"name": "SmokeAnimated",
		"sprite_frames_path": sprite_frames_path,
		"animation": "idle",
		"autoplay": true,
		"position": {
			"type": "Vector2",
			"x": 12,
			"y": 18
		}
	})
	var animation_preview_path := design_root.path_join("reports/smoke_frames_animation_preview.png")
	var animation_preview_report_path := design_root.path_join("reports/smoke_frames_animation_preview.json")
	var animation_preview_result: Dictionary = bridge.handle_request({
		"command": "create_animation_preview",
		"sprite_frames_path": sprite_frames_path,
		"root": design_root,
		"path": animation_preview_path,
		"report_path": animation_preview_report_path,
		"thumb_size": 32,
		"columns": 2,
		"replace": true
	})
	var texture_import_result: Dictionary = bridge.handle_request({
		"command": "set_texture_import_preset",
		"paths": [placeholder_sprite_path],
		"preset": "pixel_art",
		"create_sidecar": true,
		"reimport": true
	})
	var asset_manifest_path := design_root.path_join("asset_manifest.json")
	var asset_manifest_result: Dictionary = bridge.handle_request({
		"command": "create_asset_manifest",
		"root": design_root,
		"path": asset_manifest_path,
		"replace": true
	})
	var asset_contact_sheet_path := design_root.path_join("reports/asset_contact_sheet.png")
	var asset_contact_sheet_report_path := design_root.path_join("reports/asset_contact_sheet.json")
	var asset_contact_sheet_result: Dictionary = bridge.handle_request({
		"command": "create_asset_contact_sheet",
		"root": design_root,
		"path": asset_contact_sheet_path,
		"report_path": asset_contact_sheet_report_path,
		"thumb_size": 32,
		"columns": 2,
		"replace": true
	})
	var scene_preview_path := design_root.path_join("reports/scene_preview.png")
	var scene_preview_report_path := design_root.path_join("reports/scene_preview.json")
	var scene_preview_result: Dictionary = bridge.handle_request({
		"command": "create_scene_preview",
		"root": design_root,
		"path": scene_preview_path,
		"report_path": scene_preview_report_path,
		"scene_path": ui_template_path,
		"width": 360,
		"height": 220,
		"replace": true
	})
	var inspect_art_result: Dictionary = bridge.handle_request({
		"command": "inspect_art_assets",
		"root": design_root,
		"write_report": true,
		"max_count": 200
	})
	var design_status_result: Dictionary = bridge.handle_request({
		"command": "get_design_status",
		"root": design_root
	})
	var design_lint_result: Dictionary = bridge.handle_request({
		"command": "run_design_lint",
		"root": design_root,
		"scene_path": ui_template_path,
		"write_report": true
	})
	ProjectSettings.set_setting("codex_bridge/raw_api_enabled", true)
	var raw_classdb_result: Dictionary = bridge.handle_request({
		"command": "raw_classdb_query",
		"query": "class_exists",
		"class": "Node2D",
		"mode": "raw"
	})
	var raw_object_result: Dictionary = bridge.handle_request({
		"command": "raw_object_call",
		"node_path": "BridgeChild",
		"method": "set",
		"mode": "raw",
		"args": [
			"position",
			{
				"type": "Vector2",
				"x": 33,
				"y": 66
			}
		]
	})
	var raw_project_result: Dictionary = bridge.handle_request({
		"command": "raw_project_call",
		"target": "ProjectSettings",
		"method": "has_setting",
		"mode": "raw",
		"args": ["application/config/name"]
	})
	ProjectSettings.set_setting("codex_bridge/raw_api_enabled", false)
	var play_status_result: Dictionary = bridge.handle_request({
		"command": "get_play_status"
	})
	var play_main_result: Dictionary = bridge.handle_request({
		"command": "play_main_scene"
	})
	var stop_result: Dictionary = bridge.handle_request({
		"command": "stop_playing_scene"
	})
	var last_run_result: Dictionary = bridge.handle_request({
		"command": "get_last_run_report"
	})
	var history_result: Dictionary = bridge.handle_request({
		"command": "get_command_history"
	})
	var timeline_result: Dictionary = bridge.handle_request({
		"command": "get_command_timeline"
	})

	var child := scene_root.get_node_or_null("BridgeChild") as Node2D
	var dry_run_child := scene_root.get_node_or_null("DryRunChild")
	var queued_child := scene_root.get_node_or_null("QueuedChild") as Node2D
	var renamed_queued_child := scene_root.get_node_or_null("RenamedQueuedChild") as Node2D
	var duplicated_queued_child := scene_root.get_node_or_null("DuplicatedQueuedChild")
	var discarded_child := scene_root.get_node_or_null("DiscardedChild")
	var animated_sprite_node := scene_root.get_node_or_null("SmokeAnimated") as AnimatedSprite2D
	var action_data := action_result.get("data", {}) as Dictionary
	var executor_result := action_data.get("action_result", {}) as Dictionary
	var visual_feedback := action_data.get("visual_feedback", {}) as Dictionary
	var visual_node := visual_feedback.get("node", {}) as Dictionary
	var dry_run_data := dry_run_result.get("data", {}) as Dictionary
	var dry_run_preview := dry_run_data.get("preview", {}) as Dictionary
	var capabilities_data := capabilities_result.get("data", {}) as Dictionary
	var capabilities := capabilities_data.get("capabilities", {}) as Dictionary
	var capabilities_v2_data := capabilities_v2_result.get("data", {}) as Dictionary
	var capabilities_v2 := capabilities_v2_data.get("capabilities", {}) as Dictionary
	var command_schema_data := command_schema_result.get("data", {}) as Dictionary
	var command_schema := command_schema_data.get("schema", {}) as Dictionary
	var command_schema_entries := command_schema.get("commands", []) as Array
	var raw_status_data := raw_status_result.get("data", {}) as Dictionary
	var raw_status := raw_status_data.get("raw_mode", {}) as Dictionary
	var inspector_data := inspector_result.get("data", {}) as Dictionary
	var inspector_properties := inspector_data.get("properties", []) as Array
	var project_setting_data := project_setting_result.get("data", {}) as Dictionary
	var common_project_settings_data := common_project_settings_set_result.get("data", {}) as Dictionary
	var common_project_setting_changes := common_project_settings_data.get("changes", []) as Array
	var add_autoload_data := add_autoload_result.get("data", {}) as Dictionary
	var added_autoload := add_autoload_data.get("after", {}) as Dictionary
	var autoloads_after_add_data := autoloads_after_add_result.get("data", {}) as Dictionary
	var autoloads_after_add := autoloads_after_add_data.get("autoloads", []) as Array
	var layer_names_data := layer_names_result.get("data", {}) as Dictionary
	var layer_families := layer_names_data.get("families", []) as Array
	var set_layer_name_data := set_layer_name_result.get("data", {}) as Dictionary
	var input_add_data := input_add_result.get("data", {}) as Dictionary
	var input_action := input_add_data.get("action", {}) as Dictionary
	var input_list_data := input_list_result.get("data", {}) as Dictionary
	var input_actions := input_list_data.get("actions", []) as Array
	var resource_files_data := resource_files_result.get("data", {}) as Dictionary
	var resource_files := resource_files_data.get("files", []) as Array
	var resource_info_data := resource_info_result.get("data", {}) as Dictionary
	var resource_info := resource_info_data.get("resource", {}) as Dictionary
	var resource_import_data := resource_import_result.get("data", {}) as Dictionary
	var resource_import := resource_import_data.get("import", {}) as Dictionary
	var get_design_system_data := get_design_system_result.get("data", {}) as Dictionary
	var design_system_payload := get_design_system_data.get("design_system", {}) as Dictionary
	var validate_design_system_data := validate_design_system_result.get("data", {}) as Dictionary
	var export_design_tokens_data := export_design_tokens_result.get("data", {}) as Dictionary
	var create_ui_template_data := create_ui_template_result.get("data", {}) as Dictionary
	var inspect_ui_scene_data := inspect_ui_scene_result.get("data", {}) as Dictionary
	var material_pack_data := material_pack_result.get("data", {}) as Dictionary
	var material_pack_paths := material_pack_data.get("paths", []) as Array
	var placeholder_sprite_data := placeholder_sprite_result.get("data", {}) as Dictionary
	var placeholder_icons_data := placeholder_icons_result.get("data", {}) as Dictionary
	var placeholder_icon_paths := placeholder_icons_data.get("paths", []) as Array
	var sprite_frames_data := sprite_frames_result.get("data", {}) as Dictionary
	var sprite_frame_animations := sprite_frames_data.get("animations", []) as Array
	var inspect_sprite_frames_data := inspect_sprite_frames_result.get("data", {}) as Dictionary
	var animated_sprite_data := animated_sprite_result.get("data", {}) as Dictionary
	var animation_preview_data := animation_preview_result.get("data", {}) as Dictionary
	var texture_import_data := texture_import_result.get("data", {}) as Dictionary
	var texture_import_updated := texture_import_data.get("updated", []) as Array
	var asset_manifest_data := asset_manifest_result.get("data", {}) as Dictionary
	var asset_contact_sheet_data := asset_contact_sheet_result.get("data", {}) as Dictionary
	var scene_preview_data := scene_preview_result.get("data", {}) as Dictionary
	var inspect_art_data := inspect_art_result.get("data", {}) as Dictionary
	var design_status_data := design_status_result.get("data", {}) as Dictionary
	var design_status := design_status_data.get("design", {}) as Dictionary
	var design_lint_data := design_lint_result.get("data", {}) as Dictionary
	var animation_players_data := animation_players_result.get("data", {}) as Dictionary
	var animation_players := animation_players_data.get("players", []) as Array
	var animation_info_data := animation_info_result.get("data", {}) as Dictionary
	var animation_player_info := animation_info_data.get("player", {}) as Dictionary
	var bridge_animation := animation_player.get_animation("bridge_smoke")
	var pending_data := pending_result.get("data", {}) as Dictionary
	var pending_items := pending_data.get("pending", []) as Array
	var queue_summary_data := queue_summary_result.get("data", {}) as Dictionary
	var snapshots_data := snapshots_result.get("data", {}) as Dictionary
	var snapshot_items := snapshots_data.get("snapshots", []) as Array
	var selection_data := selection_result.get("data", {}) as Dictionary
	var selection_nodes := selection_data.get("selection", []) as Array
	var details_data := details_result.get("data", {}) as Dictionary
	var node_details := details_data.get("node", {}) as Dictionary
	var history_data := history_result.get("data", {}) as Dictionary
	var history_entries := history_data.get("history", []) as Array
	var timeline_data := timeline_result.get("data", {}) as Dictionary
	var timeline_entries := timeline_data.get("timeline", []) as Array
	var play_main_data := play_main_result.get("data", {}) as Dictionary
	var play_main_report := play_main_data.get("report", {}) as Dictionary
	var last_run_data := last_run_result.get("data", {}) as Dictionary
	var last_run_report := last_run_data.get("report", {}) as Dictionary
	var run_reports := last_run_data.get("reports", []) as Array

	var passed: bool = bool(ping_result.get("ok", false))
	passed = passed and int(ping_result.get("schema_version", 0)) == 2
	passed = passed and bool(tree_result.get("ok", false))
	passed = passed and bool(project_result.get("ok", false))
	passed = passed and bool(identity_result.get("ok", false))
	passed = passed and not bool(mismatch_result.get("ok", true))
	passed = passed and bool(context_result.get("ok", false))
	passed = passed and bool(capabilities_result.get("ok", false))
	passed = passed and (capabilities.get("inspector", []) as Array).has("get_inspector_properties")
	passed = passed and (capabilities.get("animation", []) as Array).has("add_animation_value_key")
	passed = passed and (capabilities.get("animation", []) as Array).has("inspect_sprite_frames")
	passed = passed and (capabilities.get("animation", []) as Array).has("create_animated_sprite")
	passed = passed and (capabilities.get("animation", []) as Array).has("create_animation_preview")
	passed = passed and (capabilities.get("design", []) as Array).has("create_ui_theme")
	passed = passed and (capabilities.get("design", []) as Array).has("create_ui_template")
	passed = passed and (capabilities.get("design", []) as Array).has("create_placeholder_sprite")
	passed = passed and (capabilities.get("design", []) as Array).has("create_asset_manifest")
	passed = passed and (capabilities.get("design", []) as Array).has("create_asset_contact_sheet")
	passed = passed and (capabilities.get("design", []) as Array).has("create_scene_preview")
	passed = passed and bool(capabilities_v2_result.get("ok", false))
	passed = passed and int(capabilities_v2.get("schema_version", 0)) == 2
	passed = passed and (capabilities_v2.get("safe_action_types", []) as Array).has("rename_node")
	passed = passed and bool(command_schema_result.get("ok", false))
	passed = passed and str(command_schema.get("bridge_version", "")) == "0.7.0"
	passed = passed and command_schema_entries.size() > 20
	passed = passed and _schema_has_command(command_schema_entries, "create_design_system")
	passed = passed and _schema_has_command(command_schema_entries, "apply_ui_theme")
	passed = passed and _schema_has_command(command_schema_entries, "run_design_lint")
	passed = passed and _schema_has_command(command_schema_entries, "create_placeholder_sprite")
	passed = passed and _schema_has_command(command_schema_entries, "set_texture_import_preset")
	passed = passed and _schema_has_command(command_schema_entries, "inspect_sprite_frames")
	passed = passed and _schema_has_command(command_schema_entries, "create_animated_sprite")
	passed = passed and _schema_has_command(command_schema_entries, "create_animation_preview")
	passed = passed and _schema_has_command(command_schema_entries, "create_asset_contact_sheet")
	passed = passed and _schema_has_command(command_schema_entries, "create_scene_preview")
	passed = passed and bool(raw_status_result.get("ok", false))
	passed = passed and not bool(raw_status.get("enabled", true))
	passed = passed and not bool(raw_disabled_result.get("ok", true))
	passed = passed and bool(inspector_result.get("ok", false))
	passed = passed and inspector_properties.size() > 0
	passed = passed and bool(inspector_set_result.get("ok", false))
	passed = passed and scene_root.position == Vector2(4, 5)
	passed = passed and bool(project_setting_result.get("ok", false))
	passed = passed and str(project_setting_data.get("setting", "")) == "application/config/name"
	passed = passed and bool(project_setting_set_result.get("ok", false))
	passed = passed and bool(ProjectSettings.get_setting("codex_bridge/smoke_temp", false))
	passed = passed and bool(project_settings_list_result.get("ok", false))
	passed = passed and bool(common_project_settings_result.get("ok", false))
	passed = passed and bool(common_project_settings_set_result.get("ok", false))
	passed = passed and common_project_setting_changes.size() == 4
	passed = passed and int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 960
	passed = passed and bool(autoloads_before_result.get("ok", false))
	passed = passed and bool(add_autoload_result.get("ok", false))
	passed = passed and bool(added_autoload.get("exists", false))
	passed = passed and str(added_autoload.get("path", "")) == autoload_path
	passed = passed and bool(autoloads_after_add_result.get("ok", false))
	passed = passed and _autoload_list_has(autoloads_after_add, "CodexSmokeAutoload")
	passed = passed and bool(remove_autoload_result.get("ok", false))
	passed = passed and not ProjectSettings.has_setting("autoload/CodexSmokeAutoload")
	passed = passed and bool(layer_names_result.get("ok", false))
	passed = passed and layer_families.size() == 1
	passed = passed and bool(set_layer_name_result.get("ok", false))
	passed = passed and str(set_layer_name_data.get("after", "")) == "codex_smoke_layer"
	passed = passed and bool(input_add_result.get("ok", false))
	passed = passed and bool(input_action.get("exists", false))
	passed = passed and (input_action.get("events", []) as Array).size() == 1
	passed = passed and bool(input_list_result.get("ok", false))
	passed = passed and input_actions.size() == 1
	passed = passed and bool(input_remove_result.get("ok", false))
	passed = passed and not InputMap.has_action("codex_smoke_action")
	passed = passed and bool(editor_command_result.get("ok", false))
	passed = passed and bool(resource_files_result.get("ok", false))
	passed = passed and resource_files.size() > 0
	passed = passed and bool(resource_info_result.get("ok", false))
	passed = passed and bool(resource_info.get("exists", false))
	passed = passed and str(resource_info.get("resource_type", "")) == "PackedScene"
	passed = passed and bool(resource_import_result.get("ok", false))
	passed = passed and str(resource_import.get("import_file", "")) == "res://tests/fixtures/fixture_scene.tscn.import"
	passed = passed and bool(scan_resources_result.get("ok", false))
	passed = passed and fake_editor.filesystem.scan_sources_count == 1
	passed = passed and bool(reimport_resources_result.get("ok", false))
	passed = passed and reimported_paths_after_resource_smoke.has("res://tests/fixtures/fixture_scene.tscn")
	passed = passed and bool(animation_players_result.get("ok", false))
	passed = passed and animation_players.size() == 1
	passed = passed and bool(create_animation_result.get("ok", false))
	passed = passed and bool(set_animation_properties_result.get("ok", false))
	passed = passed and bool(add_animation_key_result.get("ok", false))
	passed = passed and bool(animation_info_result.get("ok", false))
	passed = passed and str(animation_player_info.get("path", "")) == "Animator"
	passed = passed and bridge_animation != null
	passed = passed and is_equal_approx(bridge_animation.length, 2.5)
	passed = passed and int(bridge_animation.loop_mode) == 1
	passed = passed and bridge_animation.get_track_count() == 1
	passed = passed and str(bridge_animation.track_get_path(0)) == "..:position"
	passed = passed and bridge_animation.track_get_key_count(0) == 1
	passed = passed and bool(dry_run_result.get("ok", false))
	passed = passed and bool(queue_scene_result.get("ok", false))
	passed = passed and queue_scene_id.begins_with("queue_")
	passed = passed and queued_child_before_apply == null
	passed = passed and bool(pending_result.get("ok", false))
	passed = passed and pending_items.size() > 0
	passed = passed and bool(queue_summary_result.get("ok", false))
	passed = passed and int(queue_summary_data.get("pending_count", 0)) > 0
	passed = passed and bool(apply_queue_scene_result.get("ok", false))
	passed = passed and bool(queue_node_ops_result.get("ok", false))
	passed = passed and bool(apply_node_ops_result.get("ok", false))
	passed = passed and bool(discard_queue_result.get("ok", false))
	passed = passed and bool(discard_result.get("ok", false))
	passed = passed and bool(queue_file_result.get("ok", false))
	passed = passed and bool(apply_queue_file_result.get("ok", false))
	passed = passed and file_exists_after_apply
	passed = passed and bool(snapshots_result.get("ok", false))
	passed = passed and snapshot_items.size() > 0
	passed = passed and bool(restore_result.get("ok", false))
	passed = passed and not FileAccess.file_exists(file_path)
	passed = passed and bool(action_result.get("ok", false))
	passed = passed and bool(visual_feedback.get("focused", false))
	passed = passed and str(visual_node.get("path", "")) == "BridgeChild"
	passed = passed and bool(select_result.get("ok", false))
	passed = passed and bool(selection_result.get("ok", false))
	passed = passed and bool(details_result.get("ok", false))
	passed = passed and bool(batch_inspector_result.get("ok", false))
	passed = passed and child.position == Vector2(33, 66)
	passed = passed and bool(create_resource_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(resource_path))
	passed = passed and bool(set_resource_result.get("ok", false))
	passed = passed and bool(save_resource_result.get("ok", false))
	passed = passed and bool(create_material_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(material_path))
	passed = passed and bool(create_theme_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(theme_path))
	passed = passed and bool(design_system_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(design_root.path_join("design_system.json")))
	passed = passed and bool(get_design_system_result.get("ok", false))
	passed = passed and int(design_system_payload.get("schema_version", 0)) == 2
	passed = passed and bool(update_design_system_result.get("ok", false))
	passed = passed and bool(validate_design_system_result.get("ok", false))
	passed = passed and bool(validate_design_system_data.get("valid", false))
	passed = passed and bool(export_design_tokens_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(str(export_design_tokens_data.get("path", ""))))
	passed = passed and bool(palette_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(palette_path))
	passed = passed and bool(ui_theme_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(ui_theme_path))
	passed = passed and bool(apply_ui_theme_result.get("ok", false))
	passed = passed and design_panel.theme != null
	passed = passed and bool(create_ui_template_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(ui_template_path))
	passed = passed and str(create_ui_template_data.get("template", "")) == "main_menu"
	passed = passed and bool(inspect_ui_scene_result.get("ok", false))
	passed = passed and int(inspect_ui_scene_data.get("control_count", 0)) > 0
	passed = passed and bool(material_pack_result.get("ok", false))
	passed = passed and material_pack_paths.size() >= 2
	passed = passed and bool(FileAccess.file_exists(str(material_pack_data.get("shader_path", ""))))
	passed = passed and bool(placeholder_sprite_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(placeholder_sprite_path))
	passed = passed and str(placeholder_sprite_data.get("role", "")) == "player"
	passed = passed and bool(placeholder_icons_result.get("ok", false))
	passed = passed and placeholder_icon_paths.size() == 2
	passed = passed and bool(FileAccess.file_exists(str(placeholder_icon_paths[0])))
	passed = passed and bool(sprite_frames_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(sprite_frames_path))
	passed = passed and sprite_frame_animations.size() == 1
	passed = passed and bool(inspect_sprite_frames_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(sprite_frames_report_path))
	passed = passed and int(inspect_sprite_frames_data.get("animation_count", 0)) == 1
	passed = passed and int(inspect_sprite_frames_data.get("issue_count", 0)) >= 1
	passed = passed and bool(animated_sprite_result.get("ok", false))
	passed = passed and animated_sprite_node != null
	passed = passed and animated_sprite_node.sprite_frames != null
	passed = passed and str(animated_sprite_node.animation) == "idle"
	passed = passed and animated_sprite_node.position == Vector2(12, 18)
	passed = passed and str((animated_sprite_data.get("node", {}) as Dictionary).get("path", "")) == "SmokeAnimated"
	passed = passed and bool(animation_preview_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(animation_preview_path))
	passed = passed and bool(FileAccess.file_exists(animation_preview_report_path))
	passed = passed and int(animation_preview_data.get("animation_count", 0)) == 1
	passed = passed and bool(texture_import_result.get("ok", false))
	passed = passed and texture_import_updated.size() == 1
	passed = passed and bool(FileAccess.file_exists(placeholder_sprite_path + ".import"))
	passed = passed and fake_editor.filesystem.reimported_paths.has(placeholder_sprite_path)
	passed = passed and bool(asset_manifest_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(asset_manifest_path))
	passed = passed and int(asset_manifest_data.get("asset_count", 0)) >= 1
	passed = passed and bool(asset_contact_sheet_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(asset_contact_sheet_path))
	passed = passed and bool(FileAccess.file_exists(asset_contact_sheet_report_path))
	passed = passed and int(asset_contact_sheet_data.get("image_count", 0)) >= 1
	passed = passed and bool(scene_preview_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(scene_preview_path))
	passed = passed and bool(FileAccess.file_exists(scene_preview_report_path))
	passed = passed and str(scene_preview_data.get("scene_path", "")) == ui_template_path
	passed = passed and int(scene_preview_data.get("node_count", 0)) >= 1
	passed = passed and bool(inspect_art_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(str(inspect_art_data.get("report_path", ""))))
	passed = passed and bool(design_status_result.get("ok", false))
	passed = passed and bool(design_status.get("design_system_exists", false))
	passed = passed and int(design_status.get("palette_count", 0)) >= 1
	passed = passed and int(design_status.get("theme_count", 0)) >= 1
	passed = passed and int(design_status.get("material_count", 0)) >= 1
	passed = passed and int(design_status.get("sprite_count", 0)) >= 1
	passed = passed and int(design_status.get("icon_count", 0)) >= 1
	passed = passed and int(design_status.get("asset_manifest_count", 0)) >= 1
	passed = passed and int(design_status.get("preview_count", 0)) >= 3
	passed = passed and int(design_status.get("report_count", 0)) >= 1
	passed = passed and bool(design_lint_result.get("ok", false))
	passed = passed and bool(FileAccess.file_exists(str(design_lint_data.get("report_path", ""))))
	passed = passed and bool(raw_classdb_result.get("ok", false))
	passed = passed and bool((raw_classdb_result.get("data", {}) as Dictionary).get("exists", false))
	passed = passed and bool(raw_object_result.get("ok", false))
	passed = passed and bool(raw_project_result.get("ok", false))
	passed = passed and bool(play_status_result.get("ok", false))
	passed = passed and bool(play_main_result.get("ok", false))
	passed = passed and bool(stop_result.get("ok", false))
	passed = passed and bool(last_run_result.get("ok", false))
	passed = passed and str(play_main_report.get("mode", "")) == "play_main_scene"
	passed = passed and str(last_run_report.get("mode", "")) == "stop_playing_scene"
	passed = passed and run_reports.size() >= 2
	passed = passed and bool(history_result.get("ok", false))
	passed = passed and bool(dry_run_preview.get("dry_run", false))
	passed = passed and int(executor_result.get("applied", 0)) == 1
	passed = passed and child != null
	passed = passed and discarded_child == null
	passed = passed and dry_run_child == null
	passed = passed and child.position == Vector2(33, 66)
	passed = passed and selection_nodes.size() == 1
	passed = passed and str((selection_nodes[0] as Dictionary).get("path", "")) == "BridgeChild"
	passed = passed and str(node_details.get("class", "")) == "Node2D"
	passed = passed and fake_editor.last_edited_node_name == "BridgeChild"
	passed = passed and fake_editor.last_played_scene == ProjectSettings.get_setting("application/run/main_scene", "")
	passed = passed and not fake_editor.playing
	passed = passed and history_entries.size() > 0
	passed = passed and bool(timeline_result.get("ok", false))
	passed = passed and timeline_entries.size() > 0
	passed = passed and fake_editor.dirty_count >= 1
	passed = passed and queued_child == null
	passed = passed and renamed_queued_child != null
	passed = passed and renamed_queued_child.unique_name_in_owner
	passed = passed and renamed_queued_child.is_in_group("codex_smoke_group")
	passed = passed and str(renamed_queued_child.get_meta("codex_smoke", "")) == "ok"
	passed = passed and duplicated_queued_child == null

	bridge.free()
	scene_root.free()
	_remove_file(file_path)
	_remove_file(resource_path)
	_remove_file(material_path)
	_remove_file(theme_path)
	_remove_dir_recursive("res://tmp_bridge_queue")
	ProjectSettings.clear("codex_bridge/smoke_temp")
	ProjectSettings.clear("codex_bridge/raw_api_enabled")
	if ProjectSettings.has_setting("autoload/CodexSmokeAutoload"):
		ProjectSettings.clear("autoload/CodexSmokeAutoload")
	ProjectSettings.clear("layer_names/2d_physics/layer_3")

	if passed:
		print("control_bridge_smoke: OK")
		quit(0)
	else:
		push_error("control_bridge_smoke: FAILED")
		quit(1)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_dir(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child_path := path.path_join(name)
		if dir.current_is_dir():
			_remove_dir_recursive(child_path)
		else:
			_remove_file(child_path)
	dir.list_dir_end()
	_remove_dir(path)


func _autoload_list_has(items: Array, name: String) -> bool:
	for item in items:
		if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("name", "")) == name:
			return true
	return false


func _schema_has_command(items: Array, command: String) -> bool:
	for item in items:
		if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("command", "")) == command:
			return true
	return false
