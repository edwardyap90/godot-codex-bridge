extends SceneTree

const StatusDockScript = preload("res://addons/godot_codex_bridge/status_dock.gd")


func _init() -> void:
	var dock := StatusDockScript.new()
	dock._build_ui()
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

	dock.free()

	if passed:
		print("status_dock_smoke: OK")
		quit(0)
	else:
		push_error("status_dock_smoke: FAILED")
		quit(1)
