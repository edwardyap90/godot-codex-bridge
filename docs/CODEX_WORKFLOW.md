# Codex Workflow

This workflow is the recommended way to let Codex create or modify Godot games
with visible editor feedback.

## New Game Bootstrap

From this repository:

```bash
tools/godot_bridge_bootstrap_project.sh ~/GodotGames/my-game "My Game"
```

The bootstrap script:

- creates the project folder if needed,
- copies `addons/godot_codex_bridge/` into the project,
- copies `tools/godot_bridge_send.sh` and `tools/godot_bridge_guard.sh`,
- updates `project.godot` to enable the plugin and file queue,
- opens the Godot editor,
- waits for `ping` to succeed.

When it prints `Bridge ready`, Codex can start game work.

## Required Guard

Run this inside the target Godot project before any Codex-driven game task:

```bash
tools/godot_bridge_guard.sh
```

If the guard fails, do not continue by editing files directly. Open the project
in Godot, enable the plugin if needed, and rerun the guard.

## After Bootstrap

All gameplay files, scenes, resources, art direction assets, project settings,
input actions, and editor actions should be sent through the bridge:

```bash
tools/godot_bridge_send.sh ping
tools/godot_bridge_send.sh capabilities
tools/godot_bridge_send.sh get_editor_context
tools/godot_bridge_send.sh --json '{"command":"create_design_system","root":"res://art","name":"My Game Art","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"open_scene","path":"res://scenes/main.tscn"}'
tools/godot_bridge_send.sh --json '{"command":"apply_actions","actions":[{"type":"add_node","parent_path":".","node_type":"Camera2D","name":"Camera2D"}]}'
```

Use direct filesystem writes only for bootstrap/install work before the bridge
exists. Once `ping` works, keeping changes inside the bridge path makes them
project-scoped, visible in the editor, and reversible through snapshots.

## Control Plane v2

Use these helper commands when starting a task:

```bash
tools/godot_bridge_send.sh doctor --deep
tools/godot_bridge_send.sh doctor --project
tools/godot_bridge_send.sh doctor --queue
tools/godot_bridge_send.sh capabilities
tools/godot_bridge_send.sh schema
tools/godot_bridge_send.sh timeline
tools/godot_bridge_send.sh queue-summary
tools/godot_bridge_send.sh play-status
tools/godot_bridge_send.sh raw-status
```

Codex should prefer safe commands and queued action batches. Each response now
includes `schema_version`, `ui_feedback`, `warnings`, and `changed_paths` so
the agent can explain what happened and the Godot dock can show the same state.

For multi-project work, run `doctor --project` before editing. It prints the
detected project root, helper path, queue status, project identity, and raw mode
state so a copied helper or wrong working directory is visible before any
changes are applied.

If a request times out, run `doctor --queue` and `last-response` before sending
another edit. If stale inbox/outbox files are blocking a project-local queue,
use `clean-queue` after reviewing the diagnostics.

## Visible Review in Godot

The Dock Console has tabs for Overview, Pending, Snapshots, Run, Design, and Raw Mode.
Codex should queue visible editor changes when practical:

```bash
tools/godot_bridge_send.sh --json '{"command":"queue_actions","summary":"Add Camera2D","actions":[{"type":"add_node","parent_path":".","node_type":"Camera2D","name":"Camera2D"}]}'
tools/godot_bridge_send.sh queue-summary
```

The user can then apply or discard the batch in the Godot dock. Snapshot
restore is also available from the dock.

## Art Direction Workflow

For UI and art-heavy tasks, start by creating or reading the design workspace:

```bash
tools/godot_bridge_send.sh --json '{"command":"get_design_status","root":"res://art"}'
tools/godot_bridge_send.sh --json '{"command":"create_palette","path":"res://art/palettes/game_palette.json","colors":{"background":"#101826","surface":"#22314a","primary":"#4aa3ff","accent":"#62d986","danger":"#ff6060","text":"#edf5ff"},"replace":true}'
tools/godot_bridge_send.sh --json '{"command":"create_ui_theme","path":"res://art/themes/game_theme.tres","palette_path":"res://art/palettes/game_palette.json","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"create_ui_template","template":"main_menu","path":"res://ui/main_menu.tscn","theme_path":"res://art/themes/game_theme.tres","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"inspect_ui_scene","scene_path":"res://ui/main_menu.tscn"}'
tools/godot_bridge_send.sh --json '{"command":"create_material_pack","root":"res://art/materials","palette_path":"res://art/palettes/game_palette.json","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"create_placeholder_sprite","path":"res://art/sprites/player.png","role":"player","width":64,"height":64,"replace":true}'
tools/godot_bridge_send.sh --json '{"command":"create_placeholder_icon_set","root":"res://art/icons","icons":["health","coin","key"],"size":32,"replace":true}'
tools/godot_bridge_send.sh --json '{"command":"create_sprite_frames","path":"res://art/sprites/player_frames.tres","animations":[{"name":"idle","frames":["res://art/sprites/player.png"],"fps":6,"loop":true}],"replace":true}'
tools/godot_bridge_send.sh --json '{"command":"inspect_sprite_frames","path":"res://art/sprites/player_frames.tres","expected_animations":["idle","run"],"write_report":true}'
tools/godot_bridge_send.sh --json '{"command":"create_animated_sprite","parent_path":".","name":"PlayerAnimator","sprite_frames_path":"res://art/sprites/player_frames.tres","animation":"idle","autoplay":true}'
tools/godot_bridge_send.sh --json '{"command":"create_animation_preview","sprite_frames_path":"res://art/sprites/player_frames.tres","path":"res://art/reports/player_animation_preview.png","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"set_texture_import_preset","paths":["res://art/sprites/player.png"],"preset":"pixel_art","create_sidecar":true,"reimport":true}'
tools/godot_bridge_send.sh --json '{"command":"create_asset_manifest","root":"res://art","path":"res://art/asset_manifest.json","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"create_asset_contact_sheet","root":"res://art","path":"res://art/reports/asset_contact_sheet.png","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"create_scene_preview","root":"res://art","path":"res://art/reports/scene_preview.png","scene_path":"res://ui/main_menu.tscn","replace":true}'
tools/godot_bridge_send.sh --json '{"command":"inspect_art_assets","root":"res://art","write_report":true}'
tools/godot_bridge_send.sh --json '{"command":"run_design_lint","root":"res://art","scene_path":"res://ui/main_menu.tscn","write_report":true}'
```

The Design tab shows palette/theme/material counts and recent art-direction
resources and reports, so the user can see visual-system work from inside
Godot. For v0.7-style UI, asset, and animation work, Codex should generate or
refresh the asset manifest, create a contact sheet, animation preview, or scene
preview when useful, then run `validate_design_system`, `inspect_ui_scene`,
`inspect_sprite_frames`, `inspect_art_assets`, or `run_design_lint` before
claiming visual changes are complete.

## Controlled Raw API

Raw mode is for trusted local workflows that need an allowlisted Editor API
escape hatch. It is disabled by default.

Enable it only when needed:

```bash
CODEX_GODOT_RAW_API_ENABLED=1 godot --editor --path .
```

or set `codex_bridge/raw_api_enabled=true` in project settings.

Raw commands are audited in `.godot/godot_codex_bridge/raw_audit.jsonl` and do
not execute arbitrary scripts. If a safe command exists, use the safe command
instead of raw mode.

## Demo Projects

The repository includes two complete small games created through this workflow:

- `examples/flappy-sky-runner`
- `examples/bridge-dungeon`

To try them:

```bash
tools/godot_bridge_bootstrap_project.sh examples/flappy-sky-runner "Flappy Sky Runner"
cd examples/flappy-sky-runner
tools/godot_bridge_guard.sh
tools/godot_bridge_send.sh play_main_scene
```

```bash
tools/godot_bridge_bootstrap_project.sh examples/bridge-dungeon "Bridge Dungeon"
cd examples/bridge-dungeon
tools/godot_bridge_guard.sh
tools/godot_bridge_send.sh play_main_scene
```
