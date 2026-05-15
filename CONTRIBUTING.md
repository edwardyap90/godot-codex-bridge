# Contributing

This project is early-stage. Keep changes small, testable, and focused.

## Development Rules

- Keep the plugin self-contained under `addons/godot_codex_bridge`.
- Do not add model API calls or API-key storage to the plugin.
- Prefer project-local file queues over network transport.
- Preserve project isolation and snapshot behavior.
- Add or update smoke tests for behavior changes.

## Test Commands

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --check-only --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/action_executor_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/scene_action_executor_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/control_bridge_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/file_bridge_smoke.gd
```
