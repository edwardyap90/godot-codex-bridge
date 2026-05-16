# Command Reference

Requests are JSON objects with a `command` field. The shell helper adds `request_id`, `project_root`, and `client_cwd` automatically.

## Examples

```json
{"command":"ping"}
{"command":"get_project_identity"}
{"command":"get_bridge_status"}
{"command":"get_scene_tree"}
{"command":"get_selection"}
{"command":"select_node","node_path":"Player"}
{"command":"get_inspector_properties","node_path":"Player"}
{"command":"set_inspector_property","node_path":"Player","property":"position","value":{"type":"Vector2","x":120,"y":80}}
{"command":"get_resource_files","root":"res://scenes","extensions":["tscn"]}
{"command":"get_animation_players"}
{"command":"create_animation","node_path":"AnimationPlayer","animation_name":"idle","length":1.0}
{"command":"add_animation_value_key","node_path":"AnimationPlayer","animation_name":"idle","target_path":"..","property":"position","time":0.5,"value":{"type":"Vector2","x":20,"y":0}}
{"command":"run_check_only"}
```

## Safe Change Flow

```json
{"command":"preview_actions","actions":[{"type":"add_node","parent_path":".","node_type":"Camera2D","name":"Camera2D"}]}
{"command":"queue_actions","summary":"Add Camera2D","actions":[{"type":"add_node","parent_path":".","node_type":"Camera2D","name":"Camera2D"}]}
{"command":"get_pending_actions"}
{"command":"apply_queued_actions","queue_id":"queue_..."}
{"command":"get_snapshots"}
{"command":"restore_snapshot","snapshot_id":"snapshot_..."}
```

`apply_actions` and `apply_queued_actions` responses include `visual_feedback` when the bridge can focus a changed scene node in the editor. The dock also keeps the latest visual feedback and recent command list visible.

## Supported Actions

- `write_file`
- `append_file`
- `make_dir`
- `create_scene`
- `open_scene`
- `refresh_filesystem`
- `add_node`
- `set_property`
- `attach_script`
- `connect_signal`
