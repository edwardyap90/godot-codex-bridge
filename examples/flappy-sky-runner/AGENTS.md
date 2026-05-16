# Codex Instructions For This Demo

This project is a Godot Codex Bridge demo. Codex-driven Godot changes must use
the bridge so changes are project-scoped, visible in the Godot editor, and
reviewable before they are applied.

Before modifying gameplay, scenes, resources, project settings, or editor state:

1. Run `tools/godot_bridge_guard.sh` from this directory.
2. If `tools/godot_bridge_guard.sh` is missing or the bridge addon is not
   installed, run this from the repository root:
   `tools/godot_bridge_bootstrap_project.sh examples/flappy-sky-runner "Flappy Sky Runner"`
3. After the guard passes, use `tools/godot_bridge_send.sh` for Godot project
   changes instead of editing scenes, scripts, resources, or settings directly.
4. If the bridge is not responding, fix the Godot editor or bridge connection
   before continuing Godot work.

Direct filesystem edits are only acceptable for the initial bridge bootstrap or
for non-Godot repository documentation.
