# Security

Godot Codex Bridge is a local editor automation plugin. Treat commands as code execution inside your Godot project.

## Defaults

- The file bridge is enabled by default and stores requests inside the current project.
- TCP is disabled by default.
- If TCP is enabled, it binds to `127.0.0.1`.
- Optional token authentication is available through `CODEX_GODOT_BRIDGE_TOKEN`.
- Requests can include `project_root`; mismatches are rejected.
- The plugin refuses writes under `res://addons/godot_codex_bridge`.

## Recommendations

- Use the file bridge unless you specifically need TCP.
- Do not expose TCP to a network.
- Do not run commands from untrusted agents.
- Do not commit `.godot/godot_codex_bridge/`.
- Review queued actions before applying them.
- Keep project backups or version control enabled.

## Reporting Issues

Open a GitHub issue with:

- Godot version
- Operating system
- Bridge version
- Minimal reproduction steps
- Relevant command payload, with secrets removed
