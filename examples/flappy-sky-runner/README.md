# Flappy Sky Runner

A complete Godot 4 vertical Flappy-style game demo built through Godot Codex
Bridge. It includes a home screen, HUD, pause overlay, game-over flow, score,
best score, generated PNG art, and keyboard/mouse/touch controls.

## Install The Bridge

From the repository root:

```bash
tools/godot_bridge_bootstrap_project.sh examples/flappy-sky-runner "Flappy Sky Runner"
cd examples/flappy-sky-runner
tools/godot_bridge_guard.sh
```

The demo intentionally does not vendor a second copy of the bridge addon.
Bootstrap installs the current repository addon into this project.

## Controls

- Space / left mouse / tap: flap
- Escape or P: pause/resume
- R: restart

## Run

After the guard passes:

```bash
tools/godot_bridge_send.sh play_main_scene
```

## Scenes

- `res://scenes/main.tscn` is the main scene.
- Generated PNG art lives in `res://assets/generated/` after the first run.
