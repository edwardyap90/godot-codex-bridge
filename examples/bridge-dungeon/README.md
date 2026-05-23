# Bridge Dungeon

A compact Godot 4 top-down action demo for Godot Codex Bridge.

This example is intentionally small but complete: home screen, HUD, pause,
endless run flow, generated art, player movement, mouse/keyboard shooting,
escalating enemy chase behavior, a key pickup, and a depth gate.

## Install The Bridge

From the repository root:

```bash
tools/godot_bridge_bootstrap_project.sh examples/bridge-dungeon "Bridge Dungeon"
cd examples/bridge-dungeon
tools/godot_bridge_guard.sh
```

The demo does not vendor a second copy of the bridge addon. Bootstrap installs
the current repository addon into this project.

## Controls

- WASD / arrow keys: move
- Left mouse / Space: shoot
- Escape or P: pause/resume
- R: restart

## Run

After the guard passes:

```bash
tools/godot_bridge_send.sh play_main_scene
```

## Goal

Find the key, survive the sentries, then reach the open gate to descend into
the next harder depth. Score, time, and depth keep going until the player dies.
