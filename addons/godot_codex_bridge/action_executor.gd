@tool
extends RefCounted

const PLUGIN_ROOT := "res://addons/godot_codex_bridge"

var editor_interface = null


func setup(p_editor_interface) -> void:
	editor_interface = p_editor_interface


func apply_actions(actions: Array) -> Dictionary:
	var results: Array = []
	var applied_count := 0

	for index in actions.size():
		var action = actions[index]
		if typeof(action) != TYPE_DICTIONARY:
			results.append(_result("unknown", "", false, "Action #" + str(index + 1) + " is not a Dictionary."))
			continue

		var action_dict := action as Dictionary
		var action_type := str(action_dict.get("type", "")).strip_edges()
		var result := _apply_action(action_type, action_dict)
		results.append(result)
		if bool(result.get("ok", false)):
			applied_count += 1

	_refresh_filesystem()
	return {
		"applied": applied_count,
		"total": actions.size(),
		"results": results
	}


func _apply_action(action_type: String, action: Dictionary) -> Dictionary:
	match action_type:
		"write_file":
			return _write_file(action, false)
		"append_file":
			return _write_file(action, true)
		"make_dir":
			return _make_dir(action)
		"create_scene":
			return _create_scene(action)
		"add_node":
			return _add_node(action)
		"set_property":
			return _set_property(action)
		"attach_script":
			return _attach_script(action)
		"connect_signal":
			return _connect_signal(action)
		"remove_node":
			return _remove_node(action)
		"rename_node":
			return _rename_node(action)
		"duplicate_node":
			return _duplicate_node(action)
		"reparent_node":
			return _reparent_node(action)
		"move_node":
			return _move_node(action)
		"set_owner":
			return _set_owner(action)
		"set_unique_name":
			return _set_unique_name(action)
		"add_group":
			return _set_group(action, true)
		"remove_group":
			return _set_group(action, false)
		"set_metadata":
			return _set_metadata(action)
		"remove_metadata":
			return _remove_metadata(action)
		"open_scene":
			return _open_scene(action)
		"refresh_filesystem":
			_refresh_filesystem()
			return _result(action_type, "", true, "Filesystem refreshed.")
		_:
			return _result(action_type, str(action.get("path", "")), false, "Unsupported action type: " + action_type)


func _write_file(action: Dictionary, append: bool) -> Dictionary:
	var action_type := "append_file" if append else "write_file"
	var path := _normalize_project_path(str(action.get("path", "")))
	if path.is_empty():
		return _result(action_type, str(action.get("path", "")), false, "Path is invalid or not allowed.")
	if not action.has("content"):
		return _result(action_type, path, false, "Missing content.")

	var dir_error := _ensure_parent_dir(path)
	if dir_error != OK:
		return _result(action_type, path, false, "Failed to create parent directory: " + error_string(dir_error))

	var mode := FileAccess.WRITE
	if append and FileAccess.file_exists(path):
		mode = FileAccess.READ_WRITE

	var file := FileAccess.open(path, mode)
	if file == null:
		return _result(action_type, path, false, "Failed to open file: " + error_string(FileAccess.get_open_error()))

	if append:
		file.seek_end()
	file.store_string(str(action.get("content", "")))
	return _result(action_type, path, true, "File written.")


func _make_dir(action: Dictionary) -> Dictionary:
	var path := _normalize_project_path(str(action.get("path", "")), true)
	if path.is_empty():
		return _result("make_dir", str(action.get("path", "")), false, "Directory path is invalid or not allowed.")

	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if error != OK and error != ERR_ALREADY_EXISTS:
		return _result("make_dir", path, false, "Failed to create directory: " + error_string(error))

	return _result("make_dir", path, true, "Directory created.")


func _create_scene(action: Dictionary) -> Dictionary:
	var path := _normalize_project_path(str(action.get("path", "")))
	if path.is_empty():
		return _result("create_scene", str(action.get("path", "")), false, "Scene path is invalid or not allowed.")
	if path.get_extension() != "tscn":
		return _result("create_scene", path, false, "Scene path must end with .tscn.")

	var root_type := str(action.get("root_type", "Node2D")).strip_edges()
	if root_type.is_empty():
		root_type = "Node2D"
	if not ClassDB.class_exists(root_type) or not ClassDB.can_instantiate(root_type):
		return _result("create_scene", path, false, "Cannot instantiate node type: " + root_type)

	var root_object := ClassDB.instantiate(root_type)
	if not root_object is Node:
		if root_object != null and root_object.has_method("free"):
			root_object.free()
		return _result("create_scene", path, false, "root_type is not a Node: " + root_type)

	var root := root_object as Node
	root.name = str(action.get("root_name", root_type)).strip_edges()
	if root.name.is_empty():
		root.name = root_type

	var script_path := str(action.get("script_path", "")).strip_edges()
	if not script_path.is_empty():
		var normalized_script_path := _normalize_project_path(script_path)
		if normalized_script_path.is_empty():
			root.free()
			return _result("create_scene", path, false, "Script path is invalid or not allowed: " + script_path)
		var script := load(normalized_script_path)
		if script == null:
			root.free()
			return _result("create_scene", path, false, "Cannot load script: " + normalized_script_path)
		root.set_script(script)

	var dir_error := _ensure_parent_dir(path)
	if dir_error != OK:
		root.free()
		return _result("create_scene", path, false, "Failed to create parent directory: " + error_string(dir_error))

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(root)
	root.free()
	if pack_error != OK:
		return _result("create_scene", path, false, "Failed to pack scene: " + error_string(pack_error))

	var save_error := ResourceSaver.save(packed_scene, path)
	if save_error != OK:
		return _result("create_scene", path, false, "Failed to save scene: " + error_string(save_error))

	return _result("create_scene", path, true, "Scene created.")


func _add_node(action: Dictionary) -> Dictionary:
	var parent_path := str(action.get("parent_path", ".")).strip_edges()
	var node_type := str(action.get("node_type", "Node2D")).strip_edges()
	var node_name := str(action.get("name", node_type)).strip_edges()
	if node_name.is_empty():
		node_name = node_type

	var root := _edited_scene_root()
	if root == null:
		return _result("add_node", parent_path, false, "No editable scene is currently open.")

	var parent := _find_scene_node(parent_path)
	if parent == null:
		return _result("add_node", parent_path, false, "Parent node not found.")
	if not ClassDB.class_exists(node_type) or not ClassDB.can_instantiate(node_type):
		return _result("add_node", parent_path, false, "Cannot instantiate node type: " + node_type)

	var node_object := ClassDB.instantiate(node_type)
	if not node_object is Node:
		if node_object != null and node_object.has_method("free"):
			node_object.free()
		return _result("add_node", parent_path, false, "node_type is not a Node: " + node_type)

	var node := node_object as Node
	node.name = node_name
	parent.add_child(node)
	node.owner = root

	var script_path := str(action.get("script_path", "")).strip_edges()
	if not script_path.is_empty():
		var script_result := _set_node_script(node, script_path)
		if not bool(script_result.get("ok", false)):
			node.queue_free()
			return _result("add_node", parent_path, false, str(script_result.get("message", "")))

	if typeof(action.get("properties")) == TYPE_DICTIONARY:
		var property_error := _apply_properties(node, action.get("properties") as Dictionary)
		if not property_error.is_empty():
			node.queue_free()
			return _result("add_node", parent_path, false, property_error)

	_set_scene_dirty()
	return _result("add_node", _scene_node_path(node), true, "Node added.")


func _set_property(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var property_name := str(action.get("property", "")).strip_edges()
	if property_name.is_empty():
		return _result("set_property", node_path, false, "Missing property.")

	var node := _find_scene_node(node_path)
	if node == null:
		return _result("set_property", node_path, false, "Node not found.")
	if not _has_property(node, property_name):
		return _result("set_property", node_path, false, "Node does not have property: " + property_name)

	node.set(property_name, _decode_value(action.get("value")))
	_set_scene_dirty()
	return _result("set_property", node_path + "." + property_name, true, "Property set.")


func _attach_script(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var script_path := str(action.get("script_path", "")).strip_edges()
	var node := _find_scene_node(node_path)
	if node == null:
		return _result("attach_script", node_path, false, "Node not found.")

	var script_result := _set_node_script(node, script_path)
	if not bool(script_result.get("ok", false)):
		return _result("attach_script", node_path, false, str(script_result.get("message", "")))

	_set_scene_dirty()
	return _result("attach_script", node_path, true, "Script attached.")


func _connect_signal(action: Dictionary) -> Dictionary:
	var source_path := str(action.get("source_path", "")).strip_edges()
	var signal_name := str(action.get("signal", "")).strip_edges()
	var target_path := str(action.get("target_path", "")).strip_edges()
	var method_name := str(action.get("method", "")).strip_edges()
	if signal_name.is_empty() or method_name.is_empty():
		return _result("connect_signal", source_path, false, "Missing signal or method.")

	var source := _find_scene_node(source_path)
	var target := _find_scene_node(target_path)
	if source == null:
		return _result("connect_signal", source_path, false, "Signal source node not found.")
	if target == null:
		return _result("connect_signal", target_path, false, "Target node not found.")
	if not source.has_signal(signal_name):
		return _result("connect_signal", source_path, false, "Signal source does not have signal: " + signal_name)
	if not target.has_method(method_name):
		return _result("connect_signal", target_path, false, "Target node does not have method: " + method_name)

	var callable := Callable(target, method_name)
	if source.is_connected(signal_name, callable):
		return _result("connect_signal", source_path, true, "Signal already connected.")

	var error := source.connect(signal_name, callable)
	if error != OK:
		return _result("connect_signal", source_path, false, "Failed to connect signal: " + error_string(error))

	_set_scene_dirty()
	return _result("connect_signal", source_path, true, "Signal connected.")


func _remove_node(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var node := _find_scene_node(node_path)
	var root := _edited_scene_root()
	if node == null:
		return _result("remove_node", node_path, false, "Node not found.")
	if node == root:
		return _result("remove_node", node_path, false, "Cannot remove the scene root.")

	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
	_set_scene_dirty()
	return _result("remove_node", node_path, true, "Node removed.")


func _rename_node(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var node := _find_scene_node(node_path)
	var new_name := str(action.get("name", "")).strip_edges()
	if node == null:
		return _result("rename_node", node_path, false, "Node not found.")
	if new_name.is_empty() or new_name.contains("/") or new_name.contains(":"):
		return _result("rename_node", node_path, false, "Node name is invalid.")

	node.name = new_name
	_set_scene_dirty()
	return _result("rename_node", _scene_node_path(node), true, "Node renamed.")


func _duplicate_node(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var node := _find_scene_node(node_path)
	var root := _edited_scene_root()
	if node == null:
		return _result("duplicate_node", node_path, false, "Node not found.")
	if node == root:
		return _result("duplicate_node", node_path, false, "Cannot duplicate the scene root.")

	var parent := node.get_parent()
	if parent == null:
		return _result("duplicate_node", node_path, false, "Node has no parent.")

	var duplicate := node.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	if not duplicate is Node:
		return _result("duplicate_node", node_path, false, "Duplicate failed.")
	var duplicate_node := duplicate as Node
	var new_name := str(action.get("name", "")).strip_edges()
	if not new_name.is_empty():
		duplicate_node.name = new_name
	parent.add_child(duplicate_node)
	parent.move_child(duplicate_node, node.get_index() + 1)
	_assign_owner_recursive(duplicate_node, root)
	_set_scene_dirty()
	return _result("duplicate_node", _scene_node_path(duplicate_node), true, "Node duplicated.")


func _reparent_node(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var new_parent_path := str(action.get("new_parent_path", action.get("parent_path", ""))).strip_edges()
	var node := _find_scene_node(node_path)
	var root := _edited_scene_root()
	var new_parent := _find_scene_node(new_parent_path)
	if node == null:
		return _result("reparent_node", node_path, false, "Node not found.")
	if node == root:
		return _result("reparent_node", node_path, false, "Cannot reparent the scene root.")
	if new_parent == null:
		return _result("reparent_node", new_parent_path, false, "New parent not found.")
	if node == new_parent or node.is_ancestor_of(new_parent):
		return _result("reparent_node", node_path, false, "Cannot reparent a node under itself.")

	var global_position := Vector2.ZERO
	var had_node2d_position := false
	if bool(action.get("keep_global_transform", true)) and node is Node2D:
		global_position = (node as Node2D).global_position
		had_node2d_position = true

	var old_parent := node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	new_parent.add_child(node)
	if had_node2d_position:
		(node as Node2D).global_position = global_position
	_assign_owner_recursive(node, root)
	_set_scene_dirty()
	return _result("reparent_node", _scene_node_path(node), true, "Node reparented.")


func _move_node(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var node := _find_scene_node(node_path)
	if node == null:
		return _result("move_node", node_path, false, "Node not found.")
	var parent := node.get_parent()
	if parent == null:
		return _result("move_node", node_path, false, "Node has no parent.")
	var index := int(action.get("index", node.get_index()))
	index = mini(maxi(index, 0), parent.get_child_count() - 1)
	parent.move_child(node, index)
	_set_scene_dirty()
	return _result("move_node", _scene_node_path(node), true, "Node moved.")


func _set_owner(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var owner_path := str(action.get("owner_path", ".")).strip_edges()
	var node := _find_scene_node(node_path)
	var owner := _find_scene_node(owner_path)
	if node == null:
		return _result("set_owner", node_path, false, "Node not found.")
	if owner == null:
		return _result("set_owner", owner_path, false, "Owner node not found.")
	node.owner = owner
	_set_scene_dirty()
	return _result("set_owner", _scene_node_path(node), true, "Owner set.")


func _set_unique_name(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var node := _find_scene_node(node_path)
	if node == null:
		return _result("set_unique_name", node_path, false, "Node not found.")
	node.unique_name_in_owner = bool(action.get("enabled", true))
	_set_scene_dirty()
	return _result("set_unique_name", _scene_node_path(node), true, "Unique name flag updated.")


func _set_group(action: Dictionary, enabled: bool) -> Dictionary:
	var action_type := "add_group" if enabled else "remove_group"
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var group_name := str(action.get("group", "")).strip_edges()
	var node := _find_scene_node(node_path)
	if node == null:
		return _result(action_type, node_path, false, "Node not found.")
	if group_name.is_empty() or group_name.contains("/") or group_name.contains(":"):
		return _result(action_type, node_path, false, "Group name is invalid.")
	if enabled:
		node.add_to_group(group_name, bool(action.get("persistent", true)))
	else:
		node.remove_from_group(group_name)
	_set_scene_dirty()
	return _result(action_type, _scene_node_path(node), true, "Group updated.")


func _set_metadata(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var key := str(action.get("key", "")).strip_edges()
	var node := _find_scene_node(node_path)
	if node == null:
		return _result("set_metadata", node_path, false, "Node not found.")
	if key.is_empty():
		return _result("set_metadata", node_path, false, "Metadata key is invalid.")
	node.set_meta(key, _decode_value(action.get("value")))
	_set_scene_dirty()
	return _result("set_metadata", _scene_node_path(node), true, "Metadata set.")


func _remove_metadata(action: Dictionary) -> Dictionary:
	var node_path := str(action.get("node_path", action.get("path", ""))).strip_edges()
	var key := str(action.get("key", "")).strip_edges()
	var node := _find_scene_node(node_path)
	if node == null:
		return _result("remove_metadata", node_path, false, "Node not found.")
	if key.is_empty():
		return _result("remove_metadata", node_path, false, "Metadata key is invalid.")
	if node.has_meta(key):
		node.remove_meta(key)
	_set_scene_dirty()
	return _result("remove_metadata", _scene_node_path(node), true, "Metadata removed.")


func _open_scene(action: Dictionary) -> Dictionary:
	var path := _normalize_project_path(str(action.get("path", "")))
	if path.is_empty():
		return _result("open_scene", str(action.get("path", "")), false, "Scene path is invalid or not allowed.")
	if editor_interface == null or not editor_interface.has_method("open_scene_from_path"):
		return _result("open_scene", path, false, "EditorInterface is not available in this environment.")

	editor_interface.open_scene_from_path(path)
	return _result("open_scene", path, true, "Scene opened.")


func _refresh_filesystem() -> void:
	if editor_interface == null or not editor_interface.has_method("get_resource_filesystem"):
		return
	var filesystem = editor_interface.get_resource_filesystem()
	if filesystem != null and filesystem.has_method("scan"):
		filesystem.scan()


func _normalize_project_path(raw_path: String, allow_directory: bool = false) -> String:
	var path := raw_path.strip_edges().replace("\\", "/")
	if path.is_empty():
		return ""
	if not path.begins_with("res://"):
		if path.begins_with("/") or path.begins_with("user://"):
			return ""
		path = "res://" + path
	while path.contains("//") and not path.begins_with("res://"):
		path = path.replace("//", "/")
	if path.contains(".."):
		return ""
	if path == "res://" and not allow_directory:
		return ""
	if path.begins_with(PLUGIN_ROOT):
		return ""
	return path


func _ensure_parent_dir(path: String) -> int:
	var base_dir := path.get_base_dir()
	if base_dir.is_empty() or base_dir == "." or base_dir == "res://":
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))


func _edited_scene_root() -> Node:
	if editor_interface == null or not editor_interface.has_method("get_edited_scene_root"):
		return null
	var root = editor_interface.get_edited_scene_root()
	if root is Node:
		return root as Node
	return null


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


func _scene_node_path(node: Node) -> String:
	var root := _edited_scene_root()
	if root == null or node == root:
		return "."
	return str(root.get_path_to(node))


func _assign_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		if child is Node:
			_assign_owner_recursive(child as Node, owner)


func _set_node_script(node: Node, raw_script_path: String) -> Dictionary:
	var script_path := _normalize_project_path(raw_script_path)
	if script_path.is_empty():
		return {
			"ok": false,
			"message": "Script path is invalid or not allowed: " + raw_script_path
		}

	var script := load(script_path)
	if script == null:
		return {
			"ok": false,
			"message": "Cannot load script: " + script_path
		}

	node.set_script(script)
	return {
		"ok": true,
		"message": "Script attached."
	}


func _apply_properties(node: Node, properties: Dictionary) -> String:
	for property_name in properties.keys():
		var name := str(property_name)
		if not _has_property(node, name):
			return "Node does not have property: " + name
		node.set(name, _decode_value(properties[property_name]))
	return ""


func _has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return true
	return false


func _decode_value(value):
	if typeof(value) != TYPE_DICTIONARY:
		return value

	var value_dict := value as Dictionary
	if value_dict.has("resource_path"):
		var resource_path := _normalize_project_path(str(value_dict.get("resource_path", "")))
		return load(resource_path) if not resource_path.is_empty() else null

	if value_dict.has("resource_type"):
		return _build_resource(value_dict)

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
		"PackedVector2Array":
			var points: Array = []
			for point in value_dict.get("points", []):
				points.append(_decode_value(point))
			return PackedVector2Array(points)
		_:
			return value


func _build_resource(resource_spec: Dictionary):
	var resource_type := str(resource_spec.get("resource_type", "")).strip_edges()
	if resource_type.is_empty() or not ClassDB.class_exists(resource_type) or not ClassDB.can_instantiate(resource_type):
		return null

	var object = ClassDB.instantiate(resource_type)
	if not object is Resource:
		if object != null and object.has_method("free"):
			object.free()
		return null

	var resource := object as Resource
	if typeof(resource_spec.get("properties")) == TYPE_DICTIONARY:
		var properties := resource_spec.get("properties") as Dictionary
		for property_name in properties.keys():
			var name := str(property_name)
			if _has_property(resource, name):
				resource.set(name, _decode_value(properties[property_name]))
	return resource


func _set_scene_dirty() -> void:
	if editor_interface != null and editor_interface.has_method("mark_scene_as_unsaved"):
		editor_interface.mark_scene_as_unsaved()


func _result(action_type: String, path: String, ok: bool, message: String) -> Dictionary:
	return {
		"type": action_type,
		"path": path,
		"ok": ok,
		"message": message
	}
