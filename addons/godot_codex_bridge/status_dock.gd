@tool
extends VBoxContainer

var control_bridge: Node
var file_bridge: Node

var project_label: Label
var root_label: Label
var queue_label: Label
var history_label: Label
var pending_label: Label
var snapshot_label: Label
var run_label: Label
var command_label: Label
var result_label: Label
var updated_label: Label


func setup(p_control_bridge: Node, p_file_bridge: Node) -> void:
	control_bridge = p_control_bridge
	file_bridge = p_file_bridge
	if control_bridge != null and control_bridge.has_signal("request_handled"):
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
	title.text = "Codex Bridge"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	project_label = _add_row("Project", "")
	root_label = _add_row("Root", "")
	queue_label = _add_row("File queue", "")
	history_label = _add_row("History", "")
	pending_label = _add_row("Pending", "")
	snapshot_label = _add_row("Snapshots", "")
	run_label = _add_row("Last run", "")
	command_label = _add_row("Last command", "Waiting for Codex")
	result_label = _add_row("Result", "")
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
		var project := status.get("project", {}) as Dictionary
		project_label.text = "Project: " + str(project.get("name", ""))
		root_label.text = "Root: " + _shorten_path(str(project.get("root", "")))
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
	_refresh_static_info()
	command_label.text = "Last command: " + command + (" (" + request_id + ")" if not request_id.is_empty() else "")
	result_label.text = "Result: " + ("OK" if ok else "FAILED") + (" - " + message if not message.is_empty() else "")
	updated_label.text = "Updated: " + Time.get_datetime_string_from_system()
	result_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55) if ok else Color(1.0, 0.45, 0.45))


func _shorten_path(path: String) -> String:
	if path.length() <= 56:
		return path
	return "..." + path.substr(path.length() - 53, 53)
