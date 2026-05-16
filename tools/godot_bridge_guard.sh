#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  tools/godot_bridge_guard.sh [PROJECT_DIR]

Run this at the start of any Codex-driven Godot game task. It fails unless the
project has Godot Codex Bridge installed, enabled, and responding to ping.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

find_project_root() {
  local start_dir="$1"
  local current="$start_dir"
  while [[ "$current" != "/" && ! -f "$current/project.godot" ]]; do
    current="$(dirname "$current")"
  done
  [[ -f "$current/project.godot" ]] || return 1
  printf '%s\n' "$current"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

start_dir="${1:-$(pwd)}"
[[ -d "$start_dir" ]] || fail "not a directory: $start_dir"
project_root="$(find_project_root "$(cd "$start_dir" && pwd)")" || fail "could not find project.godot. Run godot_bridge_bootstrap_project.sh first."

missing=0
if [[ ! -f "$project_root/addons/godot_codex_bridge/plugin.cfg" || ! -f "$project_root/addons/godot_codex_bridge/plugin.gd" ]]; then
  echo "FAIL addon files are missing from $project_root/addons/godot_codex_bridge" >&2
  missing=1
fi

if [[ ! -x "$project_root/tools/godot_bridge_send.sh" ]]; then
  echo "FAIL helper is missing or not executable: $project_root/tools/godot_bridge_send.sh" >&2
  missing=1
fi

if ! grep -q 'res://addons/godot_codex_bridge/plugin.cfg' "$project_root/project.godot"; then
  echo "FAIL plugin is not enabled in project.godot" >&2
  missing=1
fi

if (( missing != 0 )); then
  echo >&2
  echo "Install the bridge first, for example:" >&2
  echo "  /path/to/godot-codex-bridge/tools/godot_bridge_bootstrap_project.sh \"$project_root\"" >&2
  exit 1
fi

echo "Bridge files: OK"
echo "Plugin setting: OK"

if CODEX_GODOT_BRIDGE_TIMEOUT="${CODEX_GODOT_BRIDGE_TIMEOUT:-3}" "$project_root/tools/godot_bridge_send.sh" ping >/tmp/godot_codex_bridge_guard_ping.$$ 2>/tmp/godot_codex_bridge_guard_ping_err.$$; then
  cat /tmp/godot_codex_bridge_guard_ping.$$
  rm -f /tmp/godot_codex_bridge_guard_ping.$$ /tmp/godot_codex_bridge_guard_ping_err.$$
  echo
  echo "Bridge guard: OK"
  exit 0
fi

cat /tmp/godot_codex_bridge_guard_ping_err.$$ >&2 || true
rm -f /tmp/godot_codex_bridge_guard_ping.$$ /tmp/godot_codex_bridge_guard_ping_err.$$
echo >&2
echo "Bridge guard: FAILED" >&2
echo "Open this project in Godot and wait for the Codex Bridge dock, then retry:" >&2
echo "  cd \"$project_root\" && tools/godot_bridge_guard.sh" >&2
exit 1
