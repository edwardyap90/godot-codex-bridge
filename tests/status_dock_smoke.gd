extends SceneTree

const StatusDockScript = preload("res://addons/godot_codex_bridge/status_dock.gd")


class FakeBridge:
	extends Node

	signal request_observed(entry: Dictionary)

	var applied_queue_id := ""
	var discarded_queue_id := ""
	var restored_snapshot_id := ""
	var stopped := false
	var pending := [
		{
			"queue_id": "queue_smoke",
			"created_at": "2026-01-01T00:00:00",
			"summary": "Add smoke node",
			"action_count": 1,
			"preview": {
				"invalid": 0,
				"actions": [
					{
						"target": "./SmokeNode"
					}
				]
			}
		}
	]
	var snapshots := [
		{
			"snapshot_id": "snapshot_smoke",
			"reason": "before smoke",
			"scene_path": "res://tests/fixtures/fixture_scene.tscn"
		}
	]

	func console_state() -> Dictionary:
		return {
			"status": {
				"bridge_version": "0.6.1",
				"control_plane": {
					"schema_version": 2,
					"bridge_version": "0.6.1",
					"godot_version": {
						"string": "4.6.2"
					}
				},
				"project": {
					"name": "Smoke",
					"root": "/tmp/smoke"
				},
				"play": {
					"is_playing": true,
					"can_stop": true
				},
				"file": {
					"root": "res://.godot/godot_codex_bridge"
				},
				"history_count": 1,
				"history_path": "res://.godot/godot_codex_bridge/history.jsonl",
				"pending_actions_path": "res://.godot/godot_codex_bridge/pending_actions.json",
				"last_snapshot": snapshots[0],
				"design": {
					"root": "res://art",
					"design_system_exists": true,
					"palette_count": 1,
					"theme_count": 1,
					"material_count": 2,
					"image_count": 3,
					"sprite_count": 1,
					"icon_count": 1,
					"audio_count": 0,
					"font_count": 0,
					"asset_manifest_count": 1,
					"preview_count": 2,
					"report_count": 1,
					"palettes": [
						{
							"path": "res://art/palettes/smoke_palette.json"
						}
					],
					"themes": [
						{
							"path": "res://art/themes/smoke_theme.tres"
						}
					],
					"sprites": [
						{
							"path": "res://art/sprites/smoke_player.png"
						}
					],
					"asset_manifests": [
						{
							"path": "res://art/asset_manifest.json"
						}
					],
					"previews": [
						{
							"path": "res://art/reports/asset_contact_sheet.png"
						},
						{
							"path": "res://art/reports/scene_preview.png"
						}
					],
					"reports": [
						{
							"path": "res://art/reports/design_lint_report.json"
						}
					]
				}
			},
			"pending": pending,
			"snapshots": snapshots,
			"play": {
				"is_playing": true,
				"can_stop": true
			},
			"last_run_report": {
				"mode": "check_only",
				"ok": true,
				"exit_code": 0,
				"duration_ms": 10,
				"errors": [],
				"warnings": []
			},
			"design": {
				"root": "res://art",
				"design_system_exists": true,
				"palette_count": 1,
				"theme_count": 1,
				"material_count": 2,
				"image_count": 3,
				"sprite_count": 1,
				"icon_count": 1,
				"audio_count": 0,
				"font_count": 0,
				"asset_manifest_count": 1,
				"preview_count": 2,
				"report_count": 1,
				"palettes": [
					{
						"path": "res://art/palettes/smoke_palette.json"
					}
				],
				"themes": [
					{
						"path": "res://art/themes/smoke_theme.tres"
					}
				],
				"sprites": [
					{
						"path": "res://art/sprites/smoke_player.png"
					}
				],
				"asset_manifests": [
					{
						"path": "res://art/asset_manifest.json"
					}
				],
				"previews": [
					{
						"path": "res://art/reports/asset_contact_sheet.png"
					},
					{
						"path": "res://art/reports/scene_preview.png"
					}
				],
				"reports": [
					{
						"path": "res://art/reports/design_lint_report.json"
					}
				]
			},
			"raw_mode": {
				"enabled": false,
				"executes_arbitrary_code": false,
				"audit_path": "res://.godot/godot_codex_bridge/raw_audit.jsonl"
			},
			"raw_audit": []
		}

	func handle_request(request: Dictionary) -> Dictionary:
		var command := str(request.get("command", ""))
		match command:
			"apply_queued_actions":
				applied_queue_id = str(request.get("queue_id", ""))
				pending.clear()
			"discard_queued_actions":
				discarded_queue_id = str(request.get("queue_id", ""))
				pending.clear()
			"restore_snapshot":
				restored_snapshot_id = str(request.get("snapshot_id", ""))
			"stop_playing_scene":
				stopped = true
		var entry := {
			"command": command,
			"ok": true,
			"message": "ok",
			"request_id": str(request.get("request_id", "")),
			"updated_at": "2026-01-01T00:00:00",
			"summary": command,
			"visual_feedback": {}
		}
		request_observed.emit(entry)
		return {
			"ok": true,
			"message": "ok",
			"data": {}
		}


func _init() -> void:
	var bridge := FakeBridge.new()
	root.add_child(bridge)
	var dock := StatusDockScript.new()
	dock._build_ui()
	dock.setup(bridge, null)
	dock._refresh_static_info()
	dock._on_request_observed({
		"command": "apply_actions",
		"ok": true,
		"message": "ok",
		"request_id": "smoke",
		"updated_at": "2026-01-01T00:00:00",
		"summary": "Applied 1 / 1 actions",
		"visual_feedback": {
			"focused": true,
			"node": {
				"path": "BridgeChild",
				"class": "Node2D"
			}
		}
	})

	var passed := dock.command_label.text.contains("apply_actions")
	passed = passed and dock.result_label.text.contains("Applied 1 / 1 actions")
	passed = passed and dock.visual_label.text.contains("selected BridgeChild")
	passed = passed and dock.recent_label.text.contains("OK apply_actions")
	passed = passed and dock.pending_list.item_count == 1
	passed = passed and dock.snapshot_list.item_count == 1
	passed = passed and not dock.apply_button.disabled
	passed = passed and not dock.restore_button.disabled
	passed = passed and dock.play_label.text.contains("running")
	passed = passed and not dock.stop_button.disabled
	passed = passed and dock.design_label.text.contains("1 palettes")
	passed = passed and dock.design_label.text.contains("1 sprites")
	passed = passed and dock.design_label.text.contains("2 previews")
	passed = passed and dock.design_detail_label.text.contains("smoke_palette")
	passed = passed and dock.design_detail_label.text.contains("smoke_player")
	passed = passed and dock.design_detail_label.text.contains("asset_manifest")
	passed = passed and dock.design_detail_label.text.contains("asset_contact_sheet")
	passed = passed and dock.design_detail_label.text.contains("scene_preview")
	passed = passed and dock.design_detail_label.text.contains("design_lint_report")
	dock._on_apply_pressed()
	passed = passed and bridge.applied_queue_id == "queue_smoke"
	passed = passed and dock.pending_list.item_count == 0
	dock._on_restore_pressed()
	passed = passed and bridge.restored_snapshot_id == "snapshot_smoke"
	dock._on_stop_pressed()
	passed = passed and bridge.stopped

	dock.free()
	bridge.free()

	if passed:
		print("status_dock_smoke: OK")
		quit(0)
	else:
		push_error("status_dock_smoke: FAILED")
		quit(1)
