# Command Reference

Requests are JSON objects with a `command` field. The shell helper adds `request_id`, `project_root`, and `client_cwd` automatically.

## Examples

```json
{"command":"ping"}
{"command":"get_project_identity"}
{"command":"get_bridge_status"}
{"command":"list_capabilities_v2"}
{"command":"get_command_schema"}
{"command":"get_command_history"}
{"command":"get_command_timeline"}
{"command":"get_queue_summary"}
{"command":"get_scene_tree"}
{"command":"get_selection"}
{"command":"select_node","node_path":"Player"}
{"command":"get_inspector_properties","node_path":"Player"}
{"command":"set_inspector_property","node_path":"Player","property":"position","value":{"type":"Vector2","x":120,"y":80}}
{"command":"set_inspector_properties","node_path":"Player","properties":{"position":{"type":"Vector2","x":120,"y":80},"visible":true}}
{"command":"get_resource_files","root":"res://scenes","extensions":["tscn"]}
{"command":"create_resource","path":"res://materials/player_gradient.tres","resource_type":"Gradient","replace":true}
{"command":"set_resource_property","path":"res://materials/player_gradient.tres","property":"offsets","value":{"type":"PackedFloat32Array","values":[0.0,1.0]}}
{"command":"create_material","path":"res://materials/player_material.tres","material_type":"CanvasItemMaterial","properties":{"blend_mode":1},"replace":true}
{"command":"create_theme","path":"res://ui/game_theme.tres","colors":{"Label/font_color":{"type":"Color","r":1,"g":1,"b":1,"a":1}},"font_sizes":{"Label/font_size":18},"replace":true}
{"command":"create_design_system","root":"res://art","name":"My Game Art","style":"bright readable arcade UI","replace":true}
{"command":"get_design_system","root":"res://art"}
{"command":"update_design_system","root":"res://art","tokens":{"typography":{"base_font_size":20}}}
{"command":"validate_design_system","root":"res://art"}
{"command":"export_design_tokens","root":"res://art","path":"res://art/design_tokens.json","replace":true}
{"command":"create_palette","path":"res://art/palettes/game_palette.json","colors":{"background":"#101826","surface":"#22314a","primary":"#4aa3ff","accent":"#62d986","danger":"#ff6060","text":"#edf5ff"},"replace":true}
{"command":"create_ui_theme","path":"res://art/themes/game_theme.tres","palette_path":"res://art/palettes/game_palette.json","replace":true}
{"command":"apply_ui_theme","node_path":"CanvasLayer/HUD","theme_path":"res://art/themes/game_theme.tres","recursive":true}
{"command":"create_ui_template","template":"main_menu","path":"res://ui/main_menu.tscn","theme_path":"res://art/themes/game_theme.tres","replace":true}
{"command":"inspect_ui_scene","scene_path":"res://ui/main_menu.tscn"}
{"command":"create_material_pack","root":"res://art/materials","palette_path":"res://art/palettes/game_palette.json","replace":true}
{"command":"inspect_art_assets","root":"res://art","write_report":true}
{"command":"run_design_lint","root":"res://art","scene_path":"res://ui/main_menu.tscn","write_report":true}
{"command":"get_animation_players"}
{"command":"create_animation","node_path":"AnimationPlayer","animation_name":"idle","length":1.0}
{"command":"add_animation_value_key","node_path":"AnimationPlayer","animation_name":"idle","target_path":"..","property":"position","time":0.5,"value":{"type":"Vector2","x":20,"y":0}}
{"command":"run_check_only"}
{"command":"get_play_status"}
{"command":"get_autoloads"}
{"command":"add_autoload","name":"GameState","path":"res://scripts/game_state.gd","save":true}
{"command":"remove_autoload","name":"GameState","save":true}
{"command":"get_layer_names","family":"2d_physics"}
{"command":"set_layer_name","family":"2d_physics","layer":1,"name":"player"}
{"command":"get_common_project_settings"}
{"command":"set_common_project_settings","settings":{"main_scene":"res://scenes/main.tscn","window_width":1280,"window_height":720}}
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
- `remove_node`
- `rename_node`
- `duplicate_node`
- `reparent_node`
- `move_node`
- `set_owner`
- `set_unique_name`
- `add_group`
- `remove_group`
- `set_metadata`
- `remove_metadata`

## Control Plane v2

New responses include:

- `schema_version`
- `ui_feedback`
- `warnings`
- `changed_paths`

Use `list_capabilities_v2` to discover supported command families, safe action
types, transport state, and raw mode status.

Use `get_command_schema` or `tools/godot_bridge_send.sh schema` to fetch the
machine-readable command catalog. The repository also includes a JSON request
schema at `docs/schema/commands.schema.json`.

## Visible Console Commands

The Godot dock now shows Overview, Pending, Snapshots, Run, Design, and Raw Mode tabs.
The Run tab includes play status and a `Stop Game` button, and play/stop
commands are recorded in the run report timeline.
The pending queue and snapshot lists can be acted on from the editor UI:

```json
{"command":"get_queue_summary"}
{"command":"apply_queued_actions","queue_id":"queue_..."}
{"command":"discard_queued_actions","queue_id":"queue_..."}
{"command":"restore_snapshot","snapshot_id":"snapshot_..."}
{"command":"get_play_status"}
{"command":"stop_playing_scene"}
```

## Queue Diagnostics

When the file queue looks stuck, use the CLI diagnostics before retrying a
large edit:

```bash
tools/godot_bridge_send.sh doctor --queue
tools/godot_bridge_send.sh last-response
tools/godot_bridge_send.sh clean-queue
```

## Project Surface Commands

These commands wrap common `ProjectSettings` tasks so agents do not need raw API
mode for routine setup:

```json
{"command":"get_common_project_settings"}
{"command":"set_common_project_settings","settings":{"project_name":"My Game","main_scene":"res://scenes/main.tscn","window_width":1280,"window_height":720},"save":true}
{"command":"get_autoloads"}
{"command":"add_autoload","name":"GameState","path":"res://scripts/game_state.gd","singleton":true,"save":true}
{"command":"remove_autoload","name":"GameState","save":true}
{"command":"get_layer_names","family":"2d_physics"}
{"command":"set_layer_name","family":"2d_physics","layer":1,"name":"player","save":true}
```

Supported layer families are `2d_physics`, `2d_render`, `3d_physics`,
`3d_render`, `2d_navigation`, and `3d_navigation`.

## Resource Helper Commands

`create_resource` remains the generic path. `create_material` and
`create_theme` are convenience commands for common game UI and art setup.

```json
{"command":"create_material","path":"res://materials/player_material.tres","material_type":"CanvasItemMaterial","properties":{"blend_mode":1},"replace":true}
{"command":"create_theme","path":"res://ui/game_theme.tres","colors":{"Label/font_color":{"type":"Color","r":1,"g":1,"b":1,"a":1}},"constants":{"MarginContainer/margin_left":12},"font_sizes":{"Label/font_size":18},"replace":true}
```

## Art Direction Kit Commands

These commands let Codex set up a project-local art direction workspace without
calling model APIs from the plugin.

```json
{"command":"get_design_status","root":"res://art"}
{"command":"get_design_system","root":"res://art"}
{"command":"create_design_system","root":"res://art","name":"Dungeon Art","style":"clear top-down fantasy UI","replace":true}
{"command":"update_design_system","root":"res://art","tokens":{"spacing":{"hud_gap":12}}}
{"command":"validate_design_system","root":"res://art"}
{"command":"export_design_tokens","root":"res://art","path":"res://art/design_tokens.json","replace":true}
{"command":"create_palette","path":"res://art/palettes/dungeon_palette.json","colors":{"background":"#101826","surface":"#22314a","primary":"#4aa3ff","accent":"#62d986","danger":"#ff6060","text":"#edf5ff"},"replace":true}
{"command":"create_ui_theme","path":"res://art/themes/dungeon_theme.tres","palette_path":"res://art/palettes/dungeon_palette.json","corner_radius":6,"font_size":18,"replace":true}
{"command":"apply_ui_theme","node_path":"HUD","theme_path":"res://art/themes/dungeon_theme.tres","recursive":true}
{"command":"create_ui_template","template":"hud","path":"res://ui/hud.tscn","theme_path":"res://art/themes/dungeon_theme.tres","replace":true}
{"command":"inspect_ui_scene","scene_path":"res://ui/hud.tscn","min_touch_size":44}
{"command":"create_material_pack","root":"res://art/materials","palette_path":"res://art/palettes/dungeon_palette.json","replace":true}
{"command":"create_placeholder_sprite","path":"res://art/sprites/player.png","role":"player","width":64,"height":64,"replace":true}
{"command":"create_placeholder_icon_set","root":"res://art/icons","icons":["health","coin","key"],"size":32,"replace":true}
{"command":"create_sprite_frames","path":"res://art/sprites/player_frames.tres","animations":[{"name":"idle","frames":["res://art/sprites/player.png"],"fps":6,"loop":true}],"replace":true}
{"command":"set_texture_import_preset","paths":["res://art/sprites/player.png"],"preset":"pixel_art","create_sidecar":true,"reimport":true}
{"command":"create_asset_manifest","root":"res://art","path":"res://art/asset_manifest.json","replace":true}
{"command":"inspect_art_assets","root":"res://art","max_texture_size":2048,"write_report":true}
{"command":"run_design_lint","root":"res://art","scene_path":"res://ui/hud.tscn","write_report":true}
```

`create_material_pack` creates a reusable canvas-item tint shader plus
`ShaderMaterial` resources from the palette. `inspect_art_assets` reports asset
counts, import-sidecar gaps, naming issues, and oversized textures.
`create_placeholder_sprite` and `create_placeholder_icon_set` generate simple
transparent PNGs for early gameplay prototypes. `create_sprite_frames` builds a
Godot `SpriteFrames` resource from existing image paths. `set_texture_import_preset`
updates `.import` sidecars for common 2D art workflows, and
`create_asset_manifest` writes a machine-readable asset index for Codex.
`run_design_lint` combines Design System v2 validation, UI scene checks, and
asset checks into one project-local report.

## Controlled Raw API

Raw API commands are disabled by default. Enable them only for trusted local
workflows with `codex_bridge/raw_api_enabled=true` or
`CODEX_GODOT_RAW_API_ENABLED=1`.

```json
{"command":"get_raw_mode_status"}
{"command":"raw_classdb_query","query":"class_exists","class":"Node2D","mode":"raw"}
{"command":"raw_object_call","node_path":"Player","method":"set","mode":"raw","args":["visible",true]}
{"command":"raw_editor_call","target":"resource_filesystem","method":"scan","mode":"raw"}
{"command":"raw_project_call","target":"ProjectSettings","method":"has_setting","mode":"raw","args":["application/config/name"]}
```

Raw calls are allowlisted and audited to
`.godot/godot_codex_bridge/raw_audit.jsonl`. The bridge does not execute
arbitrary GDScript macros.
