@tool
extends VBoxContainer

const RECENT_LIMIT := 8

var control_bridge: Node
var file_bridge: Node
var recent_events: Array = []
var pending_batches: Array = []
var snapshot_items: Array = []

var tab_container: TabContainer
var plane_label: Label
var project_label: Label
var root_label: Label
var security_label: Label
var raw_label: Label
var queue_label: Label
var history_label: Label
var pending_label: Label
var snapshot_label: Label
var play_label: Label
var run_label: Label
var design_label: Label
var command_label: Label
var result_label: Label
var visual_label: Label
var path_label: Label
var warning_label: Label
var recent_label: Label
var updated_label: Label
var pending_list: ItemList
var pending_detail_label: Label
var apply_button: Button
var discard_button: Button
var snapshot_list: ItemList
var snapshot_detail_label: Label
var restore_button: Button
var stop_button: Button
var run_play_label: Label
var run_report_label: Label
var design_detail_label: Label
var raw_detail_label: Label


func setup(p_control_bridge: Node, p_file_bridge: Node) -> void:
	control_bridge = p_control_bridge
	file_bridge = p_file_bridge
	if control_bridge != null:
		if control_bridge.has_signal("request_observed"):
			var observed_callback := Callable(self, "_on_request_observed")
			if not control_bridge.is_connected("request_observed", observed_callback):
				control_bridge.connect("request_observed", observed_callback)
		elif control_bridge.has_signal("request_handled"):
			var callback := Callable(self, "_on_request_handled")
			if not control_bridge.is_connected("request_handled", callback):
				control_bridge.connect("request_handled", callback)
	if is_node_ready():
		_refresh_static_info()


func _ready() -> void:
	_build_ui()
	_refresh_static_info()


func _build_ui() -> void:
	if tab_container != null:
		return

	custom_minimum_size = Vector2(380, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(title_row)

	var title := Label.new()
	title.text = "Codex Bridge Console"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title_row.add_child(title)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.tooltip_text = "Refresh bridge console state"
	refresh_button.pressed.connect(Callable(self, "_on_refresh_pressed"))
	title_row.add_child(refresh_button)

	tab_container = TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tab_container)

	_build_overview_tab()
	_build_pending_tab()
	_build_snapshots_tab()
	_build_run_tab()
	_build_design_tab()
	_build_raw_tab()


func _build_overview_tab() -> void:
	var overview := ScrollContainer.new()
	overview.name = "Overview"
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(overview)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overview.add_child(body)

	plane_label = _add_row(body, "Control plane", "")
	project_label = _add_row(body, "Project", "")
	root_label = _add_row(body, "Root", "")
	security_label = _add_row(body, "Safety", "")
	raw_label = _add_row(body, "Raw mode", "")
	queue_label = _add_row(body, "File queue", "")
	history_label = _add_row(body, "History", "")
	pending_label = _add_row(body, "Pending", "")
	snapshot_label = _add_row(body, "Snapshots", "")
	play_label = _add_row(body, "Play", "")
	run_label = _add_row(body, "Last run", "")
	design_label = _add_row(body, "Design", "")
	command_label = _add_row(body, "Last command", "Waiting for Codex")
	result_label = _add_row(body, "Result", "")
	visual_label = _add_row(body, "Visual feedback", "No recent editor focus")
	path_label = _add_row(body, "Changed paths", "")
	warning_label = _add_row(body, "Warnings", "")
	recent_label = _add_row(body, "Recent", "No commands yet")
	updated_label = _add_row(body, "Updated", "")


func _build_pending_tab() -> void:
	var pending_tab := VBoxContainer.new()
	pending_tab.name = "Pending"
	pending_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pending_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(pending_tab)

	pending_detail_label = _add_row(pending_tab, "Queue", "No pending batches")
	pending_list = ItemList.new()
	pending_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pending_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pending_list.custom_minimum_size = Vector2(0, 160)
	pending_tab.add_child(pending_list)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pending_tab.add_child(row)

	apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.tooltip_text = "Apply the selected pending action batch"
	apply_button.pressed.connect(Callable(self, "_on_apply_pressed"))
	row.add_child(apply_button)

	discard_button = Button.new()
	discard_button.text = "Discard"
	discard_button.tooltip_text = "Discard the selected pending action batch"
	discard_button.pressed.connect(Callable(self, "_on_discard_pressed"))
	row.add_child(discard_button)


func _build_snapshots_tab() -> void:
	var snapshots_tab := VBoxContainer.new()
	snapshots_tab.name = "Snapshots"
	snapshots_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snapshots_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(snapshots_tab)

	snapshot_detail_label = _add_row(snapshots_tab, "Snapshots", "No snapshots")
	snapshot_list = ItemList.new()
	snapshot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snapshot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	snapshot_list.custom_minimum_size = Vector2(0, 160)
	snapshots_tab.add_child(snapshot_list)

	restore_button = Button.new()
	restore_button.text = "Restore"
	restore_button.tooltip_text = "Restore the selected snapshot"
	restore_button.pressed.connect(Callable(self, "_on_restore_pressed"))
	snapshots_tab.add_child(restore_button)


func _build_run_tab() -> void:
	var run_tab := ScrollContainer.new()
	run_tab.name = "Run"
	run_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(run_tab)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	run_tab.add_child(body)

	run_play_label = _add_row(body, "Play", "not running")

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	stop_button = Button.new()
	stop_button.text = "Stop Game"
	stop_button.tooltip_text = "Stop the running Godot play session"
	stop_button.pressed.connect(Callable(self, "_on_stop_pressed"))
	row.add_child(stop_button)

	run_report_label = Label.new()
	run_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run_report_label.text = "No run reports yet"
	run_report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(run_report_label)


func _build_design_tab() -> void:
	var design_tab := ScrollContainer.new()
	design_tab.name = "Design"
	design_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	design_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(design_tab)

	design_detail_label = Label.new()
	design_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	design_detail_label.text = "No art direction data yet"
	design_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	design_tab.add_child(design_detail_label)


func _build_raw_tab() -> void:
	var raw_tab := ScrollContainer.new()
	raw_tab.name = "Raw Mode"
	raw_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raw_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(raw_tab)

	raw_detail_label = Label.new()
	raw_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	raw_detail_label.text = "Raw mode is disabled by default"
	raw_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raw_tab.add_child(raw_detail_label)


func _add_row(parent: Control, name: String, value: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = name + ": " + value
	parent.add_child(label)
	return label


func _refresh_static_info() -> void:
	if project_label == null:
		return

	var state := _console_state()
	var status := state.get("status", {}) as Dictionary
	var control_plane := status.get("control_plane", {}) as Dictionary
	var raw_mode := status.get("raw_mode", state.get("raw_mode", {})) as Dictionary
	var project := status.get("project", {}) as Dictionary
	var godot_version := control_plane.get("godot_version", {}) as Dictionary
	plane_label.text = "Control plane: v" + str(control_plane.get("schema_version", "")) + " / bridge " + str(status.get("bridge_version", control_plane.get("bridge_version", ""))) + " / Godot " + str(godot_version.get("string", ""))
	project_label.text = "Project: " + str(project.get("name", ""))
	root_label.text = "Root: " + _shorten_path(str(project.get("root", "")))
	security_label.text = "Safety: project-scoped, snapshots, visible queue, no model API keys"
	raw_label.text = "Raw mode: " + ("ENABLED" if bool(raw_mode.get("enabled", false)) else "disabled") + " -> " + str(raw_mode.get("audit_path", ""))
	var file_status := status.get("file", {}) as Dictionary
	queue_label.text = "File queue: " + str(file_status.get("root", ""))
	history_label.text = "History: " + str(status.get("history_count", 0)) + " entries -> " + str(status.get("history_path", ""))

	pending_batches = (state.get("pending", []) as Array).duplicate(true)
	snapshot_items = (state.get("snapshots", []) as Array).duplicate(true)
	var play := state.get("play", status.get("play", {})) as Dictionary
	var is_playing := bool(play.get("is_playing", false))
	play_label.text = "Play: " + ("running" if is_playing else "stopped") + " / stop " + ("available" if bool(play.get("can_stop", false)) else "unavailable")
	_populate_pending_list()
	_populate_snapshot_list()
	_populate_run_report(state)
	_populate_design_panel(state)
	_populate_raw_panel(state)

	pending_label.text = "Pending: " + str(pending_batches.size()) + " batches -> " + str(status.get("pending_actions_path", ""))
	var last_snapshot := status.get("last_snapshot", {}) as Dictionary
	if last_snapshot.is_empty():
		snapshot_label.text = "Snapshots: " + str(snapshot_items.size())
	else:
		snapshot_label.text = "Snapshots: " + str(snapshot_items.size()) + ", latest " + str(last_snapshot.get("snapshot_id", ""))
	var run_report := state.get("last_run_report", status.get("last_run_report", {})) as Dictionary
	if run_report.is_empty():
		run_label.text = "Last run: none"
	else:
		run_label.text = "Last run: " + str(run_report.get("mode", "")) + " " + ("OK" if bool(run_report.get("ok", false)) else "FAILED") + " / errors " + str(run_report.get("error_count", 0)) + " / warnings " + str(run_report.get("warning_count", 0))


func _console_state() -> Dictionary:
	if control_bridge != null and control_bridge.has_method("console_state"):
		var state = control_bridge.console_state()
		if typeof(state) == TYPE_DICTIONARY:
			return state as Dictionary
	if control_bridge != null and control_bridge.has_method("bridge_status"):
		var status = control_bridge.bridge_status()
		if typeof(status) == TYPE_DICTIONARY:
			return {
				"status": status
			}
	return {
		"status": {}
	}


func _populate_pending_list() -> void:
	if pending_list == null:
		return
	pending_list.clear()
	for queued in pending_batches:
		if typeof(queued) != TYPE_DICTIONARY:
			continue
		var item := queued as Dictionary
		var index := pending_list.add_item(_format_pending_item(item))
		pending_list.set_item_metadata(index, str(item.get("queue_id", "")))
	var has_pending := pending_list.item_count > 0
	apply_button.disabled = not has_pending
	discard_button.disabled = not has_pending
	pending_detail_label.text = "Queue: " + str(pending_list.item_count) + " pending batches"


func _populate_snapshot_list() -> void:
	if snapshot_list == null:
		return
	snapshot_list.clear()
	for snapshot in snapshot_items:
		if typeof(snapshot) != TYPE_DICTIONARY:
			continue
		var item := snapshot as Dictionary
		var index := snapshot_list.add_item(_format_snapshot_item(item))
		snapshot_list.set_item_metadata(index, str(item.get("snapshot_id", "")))
	restore_button.disabled = snapshot_list.item_count == 0
	snapshot_detail_label.text = "Snapshots: " + str(snapshot_list.item_count) + " available"


func _populate_run_report(state: Dictionary) -> void:
	if run_report_label == null:
		return
	var status := state.get("status", {}) as Dictionary
	var play := state.get("play", status.get("play", {})) as Dictionary
	var is_playing := bool(play.get("is_playing", false))
	if run_play_label != null:
		run_play_label.text = "Play: " + ("running" if is_playing else "stopped")
	if stop_button != null:
		stop_button.disabled = not bool(play.get("can_stop", false))
	var report := state.get("last_run_report", {}) as Dictionary
	if report.is_empty():
		run_report_label.text = "No run reports yet"
		return
	var errors := report.get("errors", []) as Array
	var warnings := report.get("warnings", []) as Array
	var lines: Array[String] = [
		"Mode: " + str(report.get("mode", "")),
		"Result: " + ("OK" if bool(report.get("ok", false)) else "FAILED"),
		"Exit code: " + str(report.get("exit_code", "")),
		"Duration: " + str(report.get("duration_ms", 0)) + " ms",
		"Errors: " + str(errors.size()),
		"Warnings: " + str(warnings.size())
	]
	if not errors.is_empty():
		lines.append("")
		lines.append("Errors:")
		for item in errors:
			lines.append("- " + str(item))
	if not warnings.is_empty():
		lines.append("")
		lines.append("Warnings:")
		for item in warnings:
			lines.append("- " + str(item))
	run_report_label.text = "\n".join(lines)


func _populate_design_panel(state: Dictionary) -> void:
	var status := state.get("status", {}) as Dictionary
	var design := state.get("design", status.get("design", {})) as Dictionary
	if design_label != null:
		design_label.text = "Design: " + str(design.get("palette_count", 0)) + " palettes / " + str(design.get("theme_count", 0)) + " themes / " + str(design.get("material_count", 0)) + " materials"
	if design_detail_label == null:
		return
	if design.is_empty():
		design_detail_label.text = "No art direction data yet"
		return
	var lines: Array[String] = [
		"Root: " + str(design.get("root", "")),
		"Design system: " + ("present" if bool(design.get("design_system_exists", false)) else "missing"),
		"Palettes: " + str(design.get("palette_count", 0)),
		"Themes: " + str(design.get("theme_count", 0)),
		"Materials: " + str(design.get("material_count", 0)),
		"Images: " + str(design.get("image_count", 0)),
		"Audio: " + str(design.get("audio_count", 0)),
		"Fonts: " + str(design.get("font_count", 0))
	]
	var palettes := design.get("palettes", []) as Array
	if not palettes.is_empty():
		lines.append("")
		lines.append("Recent palettes:")
		for item in palettes.slice(0, mini(palettes.size(), 4)):
			if typeof(item) == TYPE_DICTIONARY:
				lines.append("- " + str((item as Dictionary).get("path", "")))
	var themes := design.get("themes", []) as Array
	if not themes.is_empty():
		lines.append("")
		lines.append("Recent themes:")
		for item in themes.slice(0, mini(themes.size(), 4)):
			if typeof(item) == TYPE_DICTIONARY:
				lines.append("- " + str((item as Dictionary).get("path", "")))
	design_detail_label.text = "\n".join(lines)


func _populate_raw_panel(state: Dictionary) -> void:
	if raw_detail_label == null:
		return
	var raw_mode := state.get("raw_mode", {}) as Dictionary
	var audit := state.get("raw_audit", []) as Array
	var lines: Array[String] = [
		"State: " + ("ENABLED" if bool(raw_mode.get("enabled", false)) else "disabled"),
		"Arbitrary scripts: " + ("yes" if bool(raw_mode.get("executes_arbitrary_code", false)) else "no"),
		"Audit path: " + str(raw_mode.get("audit_path", "")),
		"Audit entries: " + str(audit.size())
	]
	if bool(raw_mode.get("enabled", false)):
		lines.append("Warning: raw mode should only be used for trusted local workflows.")
	raw_detail_label.text = "\n".join(lines)


func _on_request_handled(command: String, ok: bool, message: String, request_id: String) -> void:
	_on_request_observed({
		"command": command,
		"ok": ok,
		"message": message,
		"request_id": request_id,
		"updated_at": Time.get_datetime_string_from_system(),
		"summary": "",
		"visual_feedback": {}
	})


func _on_request_observed(entry: Dictionary) -> void:
	_refresh_static_info()
	_record_recent_event(entry)

	var command := str(entry.get("command", ""))
	var request_id := str(entry.get("request_id", ""))
	var ok := bool(entry.get("ok", false))
	var message := str(entry.get("message", ""))
	var summary := str(entry.get("summary", ""))
	var mode := str(entry.get("mode", "safe"))
	var changed_paths := entry.get("changed_paths", []) as Array
	var warnings := entry.get("warnings", []) as Array

	command_label.text = "Last command: " + command + " [" + mode + "]" + (" (" + request_id + ")" if not request_id.is_empty() else "")
	result_label.text = "Result: " + ("OK" if ok else "FAILED") + (" - " + message if not message.is_empty() else "") + (" / " + summary if not summary.is_empty() else "")
	visual_label.text = "Visual feedback: " + _format_ui_feedback(entry)
	path_label.text = "Changed paths: " + _format_path_list(changed_paths)
	warning_label.text = "Warnings: " + _format_path_list(warnings)
	recent_label.text = "Recent:\n" + _format_recent_events()
	updated_label.text = "Updated: " + str(entry.get("updated_at", Time.get_datetime_string_from_system()))
	result_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55) if ok else Color(1.0, 0.45, 0.45))
	raw_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35) if mode == "raw" or command.begins_with("raw_") else Color(0.75, 0.82, 0.9))


func _on_refresh_pressed() -> void:
	_refresh_static_info()


func _on_apply_pressed() -> void:
	var queue_id := _selected_item_metadata(pending_list)
	if queue_id.is_empty():
		_set_console_message(false, "Select a pending batch first.")
		return
	_send_dock_command({
		"command": "apply_queued_actions",
		"queue_id": queue_id
	})


func _on_discard_pressed() -> void:
	var queue_id := _selected_item_metadata(pending_list)
	if queue_id.is_empty():
		_set_console_message(false, "Select a pending batch first.")
		return
	_send_dock_command({
		"command": "discard_queued_actions",
		"queue_id": queue_id
	})


func _on_restore_pressed() -> void:
	var snapshot_id := _selected_item_metadata(snapshot_list)
	if snapshot_id.is_empty():
		_set_console_message(false, "Select a snapshot first.")
		return
	_send_dock_command({
		"command": "restore_snapshot",
		"snapshot_id": snapshot_id
	})


func _on_stop_pressed() -> void:
	_send_dock_command({
		"command": "stop_playing_scene"
	})


func _send_dock_command(request: Dictionary) -> void:
	if control_bridge == null or not control_bridge.has_method("handle_request"):
		_set_console_message(false, "Control bridge is not available.")
		return
	var payload := request.duplicate(true)
	payload["request_id"] = "dock_" + str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec())
	payload["mode"] = "safe"
	var emits_observed := control_bridge.has_signal("request_observed")
	var response = control_bridge.handle_request(payload)
	if typeof(response) == TYPE_DICTIONARY and not emits_observed:
		var response_dict := response as Dictionary
		_set_console_message(bool(response_dict.get("ok", false)), str(response_dict.get("message", "")))
	_refresh_static_info()


func _selected_item_metadata(list: ItemList) -> String:
	if list == null or list.item_count == 0:
		return ""
	var selected := list.get_selected_items()
	var index := int(selected[0]) if selected.size() > 0 else 0
	return str(list.get_item_metadata(index))


func _set_console_message(ok: bool, message: String) -> void:
	if result_label == null:
		return
	result_label.text = "Result: " + ("OK" if ok else "FAILED") + (" - " + message if not message.is_empty() else "")
	result_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55) if ok else Color(1.0, 0.45, 0.45))


func _format_pending_item(queued: Dictionary) -> String:
	var queue_id := str(queued.get("queue_id", ""))
	var summary := str(queued.get("summary", ""))
	var preview := queued.get("preview", {}) as Dictionary
	var invalid := int(preview.get("invalid", 0))
	var first_target := ""
	var actions := preview.get("actions", []) as Array
	if not actions.is_empty() and typeof(actions[0]) == TYPE_DICTIONARY:
		first_target = str((actions[0] as Dictionary).get("target", ""))
	var text := queue_id + " - " + str(queued.get("action_count", 0)) + " actions"
	if not summary.is_empty():
		text += " - " + summary
	if not first_target.is_empty():
		text += " -> " + first_target
	if invalid > 0:
		text += " / invalid " + str(invalid)
	return text


func _format_snapshot_item(snapshot: Dictionary) -> String:
	var text := str(snapshot.get("snapshot_id", ""))
	var reason := str(snapshot.get("reason", ""))
	if not reason.is_empty():
		text += " - " + reason
	var scene_path := str(snapshot.get("scene_path", ""))
	if not scene_path.is_empty():
		text += " -> " + scene_path
	return text


func _shorten_path(path: String) -> String:
	if path.length() <= 56:
		return path
	return "..." + path.substr(path.length() - 53, 53)


func _record_recent_event(entry: Dictionary) -> void:
	recent_events.push_front(entry.duplicate(true))
	while recent_events.size() > RECENT_LIMIT:
		recent_events.pop_back()


func _format_recent_events() -> String:
	if recent_events.is_empty():
		return "No commands yet"

	var lines: Array[String] = []
	for event in recent_events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var entry := event as Dictionary
		var command := str(entry.get("command", ""))
		var ok := bool(entry.get("ok", false))
		var summary := str(entry.get("summary", ""))
		var mode := str(entry.get("mode", "safe"))
		var line := ("OK" if ok else "FAIL") + " " + command + " [" + mode + "]"
		if not summary.is_empty():
			line += " - " + summary
		lines.append(line)
	return "\n".join(lines)


func _format_ui_feedback(entry: Dictionary) -> String:
	var ui_feedback = entry.get("ui_feedback", {})
	if typeof(ui_feedback) == TYPE_DICTIONARY:
		var feedback := ui_feedback as Dictionary
		var feedback_type := str(feedback.get("type", ""))
		if feedback_type == "raw_editor_call" or feedback_type == "raw_object_call" or feedback_type == "raw_project_call":
			return feedback_type + " " + str(feedback.get("target", "")) + "." + str(feedback.get("method", ""))
		if feedback_type == "run_report":
			return "run report errors " + str(feedback.get("errors", 0)) + ", warnings " + str(feedback.get("warnings", 0))
		if feedback_type == "inspector_target":
			var target := feedback.get("target", feedback.get("details", {})) as Dictionary
			return "inspector " + str(target.get("kind", "")) + " " + str(target.get("path", ""))
	return _format_visual_feedback(entry.get("visual_feedback", {}))


func _format_path_list(values: Array) -> String:
	if values.is_empty():
		return "none"
	var lines: Array[String] = []
	for item in values:
		lines.append(str(item))
	return ", ".join(lines)


func _format_visual_feedback(raw_feedback) -> String:
	if typeof(raw_feedback) != TYPE_DICTIONARY:
		return "No editor focus reported"

	var feedback := raw_feedback as Dictionary
	if feedback.is_empty():
		return "No editor focus reported"
	if not bool(feedback.get("focused", false)):
		return str(feedback.get("reason", "No focusable scene node"))

	var node := feedback.get("node", {}) as Dictionary
	var path := str(node.get("path", ""))
	var node_class := str(node.get("class", ""))
	return "selected " + (path if not path.is_empty() else ".") + (" (" + node_class + ")" if not node_class.is_empty() else "")
