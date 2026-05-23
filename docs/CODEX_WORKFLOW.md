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

All gameplay files, scenes, resources, project settings, input actions, and
editor actions should be sent through the bridge:

```bash
tools/godot_bridge_send.sh ping
tools/godot_bridge_send.sh capabilities
tools/godot_bridge_send.sh get_editor_context
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
tools/godot_bridge_send.sh capabilities
tools/godot_bridge_send.sh schema
tools/godot_bridge_send.sh timeline
tools/godot_bridge_send.sh queue-summary
tools/godot_bridge_send.sh raw-status
```

Codex should prefer safe commands and queued action batches. Each response now
includes `schema_version`, `ui_feedback`, `warnings`, and `changed_paths` so
the agent can explain what happened and the Godot dock can show the same state.

For multi-project work, run `doctor --project` before editing. It prints the
detected project root, helper path, queue status, project identity, and raw mode
state so a copied helper or wrong working directory is visible before any
changes are applied.

## Visible Review in Godot

The Dock Console has tabs for Overview, Pending, Snapshots, Run, and Raw Mode.
Codex should queue visible editor changes when practical:

```bash
tools/godot_bridge_send.sh --json '{"command":"queue_actions","summary":"Add Camera2D","actions":[{"type":"add_node","parent_path":".","node_type":"Camera2D","name":"Camera2D"}]}'
tools/godot_bridge_send.sh queue-summary
```

The user can then apply or discard the batch in the Godot dock. Snapshot
restore is also available from the dock.

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
