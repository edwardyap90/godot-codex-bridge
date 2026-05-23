@tool
extends VBoxContainer

const RECENT_LIMIT := 5

var control_bridge: Node
var file_bridge: Node
var recent_events: Array = []

var plane_label: Label
var project_label: Label
var root_label: Label
var security_label: Label
var raw_label: Label
var queue_label: Label
var history_label: Label
var pending_label: Label
var snapshot_label: Label
var run_label: Label
var command_label: Label
var result_label: Label
var visual_label: Label
var path_label: Label
var warning_label: Label
var recent_label: Label
var updated_label: Label


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
	custom_minimum_size = Vector2(360, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Codex Bridge Console"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	plane_label = _add_row("Control plane", "")
	project_label = _add_row("Project", "")
	root_label = _add_row("Root", "")
	security_label = _add_row("Safety", "")
	raw_label = _add_row("Raw mode", "")
	queue_label = _add_row("File queue", "")
	history_label = _add_row("History", "")
	pending_label = _add_row("Pending", "")
	snapshot_label = _add_row("Snapshots", "")
	run_label = _add_row("Last run", "")
	command_label = _add_row("Last command", "Waiting for Codex")
	result_label = _add_row("Result", "")
	visual_label = _add_row("Visual feedback", "No recent editor focus")
	path_label = _add_row("Changed paths", "")
	warning_label = _add_row("Warnings", "")
	recent_label = _add_row("Recent", "No commands yet")
	updated_label = _add_row("Updated", "")


func _add_row(name: String, value: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = name + ": " + value
	add_child(label)
	return label


func _refresh_static_info() -> void:
	if project_label == null:
		return

	if control_bridge != null and control_bridge.has_method("bridge_status"):
		var status: Dictionary = control_bridge.bridge_status()
		var control_plane := status.get("control_plane", {}) as Dictionary
		var raw_mode := status.get("raw_mode", {}) as Dictionary
		var project := status.get("project", {}) as Dictionary
		var godot_version := control_plane.get("godot_version", {}) as Dictionary
		plane_label.text = "Control plane: v" + str(control_plane.get("schema_version", "")) + " / Godot " + str(godot_version.get("string", ""))
		project_label.text = "Project: " + str(project.get("name", ""))
		root_label.text = "Root: " + _shorten_path(str(project.get("root", "")))
		security_label.text = "Safety: project-scoped, snapshots, no model API keys"
		raw_label.text = "Raw mode: " + ("ENABLED" if bool(raw_mode.get("enabled", false)) else "disabled") + " -> " + str(raw_mode.get("audit_path", ""))
		var file_status := status.get("file", {}) as Dictionary
		queue_label.text = "File queue: " + str(file_status.get("root", ""))
		history_label.text = "History: " + str(status.get("history_count", 0)) + " entries -> " + str(status.get("history_path", ""))
		pending_label.text = "Pending: " + str(status.get("pending_action_count", 0)) + " batches -> " + str(status.get("pending_actions_path", ""))
		var last_snapshot := status.get("last_snapshot", {}) as Dictionary
		if last_snapshot.is_empty():
			snapshot_label.text = "Snapshots: " + str(status.get("snapshot_count", 0))
		else:
			snapshot_label.text = "Snapshots: " + str(status.get("snapshot_count", 0)) + ", latest " + str(last_snapshot.get("snapshot_id", ""))
		var run_report := status.get("last_run_report", {}) as Dictionary
		if run_report.is_empty():
			run_label.text = "Last run: none"
		else:
			run_label.text = "Last run: " + str(run_report.get("mode", "")) + " " + ("OK" if bool(run_report.get("ok", false)) else "FAILED") + " / errors " + str(run_report.get("error_count", 0)) + " / warnings " + str(run_report.get("warning_count", 0))


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
