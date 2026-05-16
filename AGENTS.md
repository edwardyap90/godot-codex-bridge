# Codex Instructions

When doing Godot game work in this repository or in a project created from it,
use Godot Codex Bridge as the editor automation path.

Before creating or modifying a Godot game project:

1. Run `tools/godot_bridge_guard.sh` from the target Godot project.
2. If the guard fails because the bridge is missing, run
   `tools/godot_bridge_bootstrap_project.sh <project-dir> "<Project Name>"`
   from this repository first.
3. Do not write gameplay files, scenes, resources, or project settings directly
   after the bridge is installed. Send those changes through
   `tools/godot_bridge_send.sh` so Godot validates the project target and the
   editor shows the change.
4. If the bridge stops responding, fix the bridge/editor connection before
   continuing game work.

The only acceptable direct filesystem work for a new game is bootstrap work:
creating the initial project folder, installing this addon, copying the helper
scripts, and enabling the plugin. All actual game content should go through the
bridge after `ping` succeeds.
