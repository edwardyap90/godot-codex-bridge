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
tools/godot_bridge_send.sh get_editor_context
tools/godot_bridge_send.sh --json '{"command":"open_scene","path":"res://scenes/main.tscn"}'
tools/godot_bridge_send.sh --json '{"command":"apply_actions","actions":[{"type":"add_node","parent_path":".","node_type":"Camera2D","name":"Camera2D"}]}'
```

Use direct filesystem writes only for bootstrap/install work before the bridge
exists. Once `ping` works, keeping changes inside the bridge path makes them
project-scoped, visible in the editor, and reversible through snapshots.

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
