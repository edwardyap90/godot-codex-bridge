#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  tools/godot_bridge_bootstrap_project.sh [options] PROJECT_DIR [PROJECT_NAME]

Options:
  --godot-bin PATH   Godot executable to launch. Defaults to CODEX_GODOT_BIN,
                     /Applications/Godot.app/Contents/MacOS/Godot, or godot.
  --timeout SEC      Seconds to wait for bridge ping after opening Godot. Default: 30.
  --no-open          Install bridge but do not open Godot.
  --no-wait          Do not wait for bridge ping.
  -h, --help         Show this help.

This is the required first step before asking Codex to build a Godot game in a
new or existing project. After this script reports "Bridge ready", game changes
should be sent through tools/godot_bridge_send.sh instead of direct file edits.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
godot_bin="${CODEX_GODOT_BIN:-}"
open_editor=1
wait_for_bridge=1
timeout_sec=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --godot-bin)
      [[ $# -ge 2 ]] || fail "--godot-bin requires a path"
      godot_bin="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || fail "--timeout requires a number"
      timeout_sec="$2"
      shift 2
      ;;
    --no-open)
      open_editor=0
      shift
      ;;
    --no-wait)
      wait_for_bridge=0
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 1 && $# -le 2 ]] || {
  usage
  exit 2
}

project_dir="$1"
project_name="${2:-$(basename "$project_dir")}"

find_godot_bin() {
  if [[ -n "$godot_bin" ]]; then
    printf '%s\n' "$godot_bin"
    return 0
  fi
  if [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    printf '%s\n' "/Applications/Godot.app/Contents/MacOS/Godot"
    return 0
  fi
  if command -v godot >/dev/null 2>&1; then
    command -v godot
    return 0
  fi
  return 1
}

if [[ ! "$timeout_sec" =~ ^[0-9]+$ ]]; then
  fail "--timeout must be an integer number of seconds"
fi

mkdir -p "$project_dir/addons" "$project_dir/tools"
project_dir="$(cd "$project_dir" && pwd)"

[[ -d "$repo_root/addons/godot_codex_bridge" ]] || fail "missing addon source: $repo_root/addons/godot_codex_bridge"
[[ -f "$repo_root/tools/godot_bridge_send.sh" ]] || fail "missing helper: $repo_root/tools/godot_bridge_send.sh"

rm -rf "$project_dir/addons/godot_codex_bridge"
cp -R "$repo_root/addons/godot_codex_bridge" "$project_dir/addons/godot_codex_bridge"
cp "$repo_root/tools/godot_bridge_send.sh" "$project_dir/tools/godot_bridge_send.sh"
cp "$repo_root/tools/godot_bridge_guard.sh" "$project_dir/tools/godot_bridge_guard.sh"
chmod +x "$project_dir/tools/godot_bridge_send.sh" "$project_dir/tools/godot_bridge_guard.sh"

PROJECT_DIR="$project_dir" PROJECT_NAME="$project_name" python3 - <<'PY'
import os
import re
from pathlib import Path

project_dir = Path(os.environ["PROJECT_DIR"])
project_name = os.environ["PROJECT_NAME"]
project_file = project_dir / "project.godot"
plugin_path = "res://addons/godot_codex_bridge/plugin.cfg"

if project_file.exists():
    text = project_file.read_text(encoding="utf-8")
else:
    text = """; Engine configuration file.
; Created by Godot Codex Bridge bootstrap.

config_version=5
"""

def find_section(lines, section):
    header = f"[{section}]"
    start = None
    end = len(lines)
    for index, line in enumerate(lines):
        if line.strip() == header:
            start = index
            continue
        if start is not None and index > start and line.startswith("[") and line.rstrip().endswith("]"):
            end = index
            break
    return start, end

def ensure_section(lines, section):
    start, end = find_section(lines, section)
    if start is not None:
        return start, end
    if lines and lines[-1].strip():
        lines.append("")
    lines.append(f"[{section}]")
    lines.append("")
    return len(lines) - 2, len(lines)

def set_key(lines, section, key, value, only_if_missing=False):
    start, end = ensure_section(lines, section)
    prefix = key + "="
    for index in range(start + 1, end):
        if lines[index].startswith(prefix):
            if not only_if_missing:
                lines[index] = prefix + value
            return
    lines.insert(end, prefix + value)

def ensure_plugin(lines):
    start, end = ensure_section(lines, "editor_plugins")
    prefix = "enabled="
    for index in range(start + 1, end):
        if not lines[index].startswith(prefix):
            continue
        plugins = re.findall(r'"([^"]+)"', lines[index])
        if plugin_path not in plugins:
            plugins.append(plugin_path)
        quoted = ", ".join(f'"{item}"' for item in plugins)
        lines[index] = f"enabled=PackedStringArray({quoted})"
        return
    lines.insert(end, f'enabled=PackedStringArray("{plugin_path}")')

lines = text.splitlines()
if not any(line.startswith("config_version=") for line in lines):
    lines.insert(0, "config_version=5")

set_key(lines, "application", "config/name", '"' + project_name.replace('"', '\\"') + '"', only_if_missing=True)
set_key(lines, "application", "config/features", 'PackedStringArray("4.6")', only_if_missing=True)
ensure_plugin(lines)
set_key(lines, "codex_bridge", "tcp_bridge_enabled", "false")
set_key(lines, "codex_bridge", "file_bridge_enabled", "true")
set_key(lines, "codex_bridge", "file_bridge_root", '"res://.godot/godot_codex_bridge"')
set_key(lines, "codex_bridge", "file_bridge_poll_interval_sec", "0.2")

project_file.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

echo "Installed Godot Codex Bridge into: $project_dir"

if (( open_editor == 1 )); then
  if resolved_godot_bin="$(find_godot_bin)"; then
    if [[ ! -x "$resolved_godot_bin" ]]; then
      fail "Godot executable is not executable: $resolved_godot_bin"
    fi
    log_path="${TMPDIR:-/tmp}/godot_codex_bridge_bootstrap_$(date +%s).log"
    nohup "$resolved_godot_bin" --editor --path "$project_dir" >"$log_path" 2>&1 &
    echo "Opened Godot editor with: $resolved_godot_bin"
    echo "Godot log: $log_path"
  else
    fail "Godot executable not found. Set CODEX_GODOT_BIN or use --no-open."
  fi
fi

if (( wait_for_bridge == 1 )); then
  deadline=$((SECONDS + timeout_sec))
  while (( SECONDS < deadline )); do
    if CODEX_GODOT_BRIDGE_TIMEOUT=2 "$project_dir/tools/godot_bridge_send.sh" ping >/tmp/godot_codex_bridge_ping.$$ 2>/tmp/godot_codex_bridge_ping_err.$$; then
      cat /tmp/godot_codex_bridge_ping.$$
      rm -f /tmp/godot_codex_bridge_ping.$$ /tmp/godot_codex_bridge_ping_err.$$
      echo
      echo "Bridge ready: $project_dir"
      exit 0
    fi
    sleep 1
  done
  echo "Bridge installed, but ping did not respond within ${timeout_sec}s." >&2
  echo "Open the project in Godot, enable the plugin if prompted, then run:" >&2
  echo "  cd \"$project_dir\" && tools/godot_bridge_guard.sh" >&2
  rm -f /tmp/godot_codex_bridge_ping.$$ /tmp/godot_codex_bridge_ping_err.$$
  exit 1
fi

echo "Bridge installed. Run this before Godot game work:"
echo "  cd \"$project_dir\" && tools/godot_bridge_guard.sh"
