@tool
extends EditorPlugin

const ControlBridge = preload("res://addons/godot_codex_bridge/control_bridge.gd")
const FileBridge = preload("res://addons/godot_codex_bridge/file_bridge.gd")
const StatusDock = preload("res://addons/godot_codex_bridge/status_dock.gd")

var _bridge: Node
var _file_bridge: Node
var _status_dock: Control


func _enter_tree() -> void:
	_bridge = ControlBridge.new()
	_bridge.name = "GodotCodexControlBridge"
	_bridge.setup(get_editor_interface())
	add_child(_bridge)

	_file_bridge = FileBridge.new()
	_file_bridge.name = "GodotCodexFileBridge"
	_file_bridge.setup(_bridge)
	add_child(_file_bridge)

	_status_dock = StatusDock.new()
	_status_dock.name = "Codex Bridge"
	_status_dock.setup(_bridge, _file_bridge)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _status_dock)


func _exit_tree() -> void:
	if _status_dock != null:
		remove_control_from_docks(_status_dock)
		_status_dock.queue_free()
		_status_dock = null
	if _file_bridge != null:
		_file_bridge.queue_free()
		_file_bridge = null
	if _bridge != null:
		_bridge.queue_free()
		_bridge = null
