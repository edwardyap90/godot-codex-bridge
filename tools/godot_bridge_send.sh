#!/usr/bin/env bash
set -euo pipefail

timeout_sec="${CODEX_GODOT_BRIDGE_TIMEOUT:-10}"

usage() {
  cat <<'USAGE' >&2
Usage:
  tools/godot_bridge_send.sh ping
  tools/godot_bridge_send.sh get_editor_context
  tools/godot_bridge_send.sh status
  tools/godot_bridge_send.sh doctor
  tools/godot_bridge_send.sh --json '{"command":"select_node","node_path":"Player"}'

Environment:
  CODEX_GODOT_BRIDGE_TIMEOUT       Response timeout in seconds. Default: 10.
  CODEX_GODOT_FILE_BRIDGE_ROOT     Queue root. Default: .godot/godot_codex_bridge.
  CODEX_GODOT_REQUEST_ID           Optional request id override.
  CODEX_GODOT_BIN                  Optional Godot executable path for doctor.
USAGE
}

fail() {
  echo "$*" >&2
  exit 2
}

find_project_root() {
  local client_cwd="$1"
  local project_root="$client_cwd"
  while [[ "$project_root" != "/" && ! -f "$project_root/project.godot" ]]; do
    project_root="$(dirname "$project_root")"
  done

  if [[ ! -f "$project_root/project.godot" ]]; then
    fail "Could not find project.godot from $client_cwd. Run this inside a Godot project."
  fi

  printf '%s\n' "$project_root"
}

resolve_bridge_root() {
  local project_root="$1"
  local bridge_root="${CODEX_GODOT_FILE_BRIDGE_ROOT:-.godot/godot_codex_bridge}"
  if [[ "$bridge_root" != /* ]]; then
    bridge_root="$project_root/$bridge_root"
  fi
  printf '%s\n' "$bridge_root"
}

json_file_count() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    printf '0\n'
    return
  fi
  find "$dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '
}

find_godot_bin() {
  if [[ -n "${CODEX_GODOT_BIN:-}" ]]; then
    printf '%s\n' "$CODEX_GODOT_BIN"
    return
  fi
  if [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    printf '%s\n' "/Applications/Godot.app/Contents/MacOS/Godot"
    return
  fi
  if command -v godot >/dev/null 2>&1; then
    command -v godot
    return
  fi
  return 1
}

plugin_enabled() {
  local project_root="$1"
  grep -q 'res://addons/godot_codex_bridge/plugin.cfg' "$project_root/project.godot"
}

print_project_status() {
  local project_root="$1"
  local client_cwd="$2"
  local bridge_root="$3"

  echo "Project root: $project_root"
  echo "Client cwd:   $client_cwd"
  echo "Bridge root:  $bridge_root"
  echo "Inbox:        $bridge_root/inbox ($(json_file_count "$bridge_root/inbox") pending)"
  echo "Outbox:       $bridge_root/outbox ($(json_file_count "$bridge_root/outbox") pending)"

  if plugin_enabled "$project_root"; then
    echo "Plugin:       enabled in project.godot"
  else
    echo "Plugin:       not enabled in project.godot"
  fi
}

write_request() {
  local project_root="$1"
  local client_cwd="$2"
  local request_id="$3"
  local payload_mode="$4"
  local payload_value="$5"
  local inbox_tmp="$6"

  PROJECT_ROOT="$project_root" \
  CLIENT_CWD="$client_cwd" \
  REQUEST_ID="$request_id" \
  PAYLOAD_MODE="$payload_mode" \
  PAYLOAD_VALUE="$payload_value" \
  python3 - <<'PY' > "$inbox_tmp"
import json
import os
import sys

payload_mode = os.environ["PAYLOAD_MODE"]
payload_value = os.environ["PAYLOAD_VALUE"]

if payload_mode == "json":
    try:
        payload = json.loads(payload_value)
    except json.JSONDecodeError as exc:
        print(f"Invalid JSON: {exc}", file=sys.stderr)
        raise SystemExit(2)
else:
    payload = {"command": payload_value}

if not isinstance(payload, dict):
    print("Request must be a JSON object.", file=sys.stderr)
    raise SystemExit(2)

payload["request_id"] = os.environ["REQUEST_ID"]
payload.setdefault("project_root", os.environ["PROJECT_ROOT"])
payload.setdefault("client_cwd", os.environ["CLIENT_CWD"])
print(json.dumps(payload, ensure_ascii=False))
PY
}

send_request() {
  local project_root="$1"
  local client_cwd="$2"
  local bridge_root="$3"
  local payload_mode="$4"
  local payload_value="$5"

  mkdir -p "$bridge_root/inbox" "$bridge_root/outbox"

  local request_id="${CODEX_GODOT_REQUEST_ID:-codex_$(date +%s)_$$}"
  local inbox_tmp="$bridge_root/inbox/$request_id.json.tmp"
  local inbox_file="$bridge_root/inbox/$request_id.json"
  local outbox_file="$bridge_root/outbox/$request_id.json"

  write_request "$project_root" "$client_cwd" "$request_id" "$payload_mode" "$payload_value" "$inbox_tmp"
  mv "$inbox_tmp" "$inbox_file"

  local deadline=$((SECONDS + timeout_sec))
  while [[ ! -f "$outbox_file" ]]; do
    if (( SECONDS >= deadline )); then
      rm -f "$inbox_tmp" "$inbox_file"
      echo "Timed out waiting for Godot file bridge response: $outbox_file" >&2
      return 1
    fi
    sleep 0.1
  done

  cat "$outbox_file"
  rm -f "$outbox_file"
}

run_doctor() {
  local project_root="$1"
  local client_cwd="$2"
  local bridge_root="$3"
  local failures=0

  echo "Godot Codex Bridge doctor"
  echo
  print_project_status "$project_root" "$client_cwd" "$bridge_root"
  echo

  if [[ -f "$project_root/addons/godot_codex_bridge/plugin.cfg" && -f "$project_root/addons/godot_codex_bridge/plugin.gd" ]]; then
    echo "OK   addon files found"
  else
    echo "FAIL missing addons/godot_codex_bridge plugin files"
    failures=$((failures + 1))
  fi

  if plugin_enabled "$project_root"; then
    echo "OK   plugin enabled"
  else
    echo "WARN plugin is not enabled in project.godot"
  fi

  if command -v python3 >/dev/null 2>&1; then
    echo "OK   python3 available"
  else
    echo "FAIL python3 is required by this CLI"
    failures=$((failures + 1))
  fi

  local godot_bin=""
  if godot_bin="$(find_godot_bin)"; then
    if [[ -x "$godot_bin" ]]; then
      echo "OK   Godot executable: $godot_bin"
      "$godot_bin" --version 2>/dev/null | sed 's/^/     version: /' || true
    else
      echo "WARN Godot path is not executable: $godot_bin"
    fi
  else
    echo "WARN Godot executable not found. Set CODEX_GODOT_BIN if needed."
  fi

  mkdir -p "$bridge_root/inbox" "$bridge_root/outbox"
  echo "OK   queue directories are present"

  echo
  echo "Bridge ping:"
  local previous_timeout="$timeout_sec"
  timeout_sec="${CODEX_GODOT_BRIDGE_TIMEOUT:-2}"
  if send_request "$project_root" "$client_cwd" "$bridge_root" "command" "ping"; then
    echo
    echo "OK   bridge responded"
  else
    echo "WARN bridge did not respond. Open Godot with the plugin enabled, then retry."
  fi
  timeout_sec="$previous_timeout"

  if (( failures > 0 )); then
    return 1
  fi
  return 0
}

client_cwd="$(pwd)"
project_root="$(find_project_root "$client_cwd")"
bridge_root="$(resolve_bridge_root "$project_root")"

cd "$project_root"

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

case "${1:-}" in
  -h|--help|help)
    usage
    ;;
  status)
    print_project_status "$project_root" "$client_cwd" "$bridge_root"
    echo
    echo "Bridge status response:"
    send_request "$project_root" "$client_cwd" "$bridge_root" "command" "get_bridge_status"
    ;;
  doctor)
    run_doctor "$project_root" "$client_cwd" "$bridge_root"
    ;;
  --json)
    if [[ $# -ne 2 ]]; then
      usage
      exit 2
    fi
    send_request "$project_root" "$client_cwd" "$bridge_root" "json" "$2"
    ;;
  *)
    if [[ $# -ne 1 ]]; then
      usage
      exit 2
    fi
    send_request "$project_root" "$client_cwd" "$bridge_root" "command" "$1"
    ;;
esac
