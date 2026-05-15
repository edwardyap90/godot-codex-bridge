#!/usr/bin/env bash
set -euo pipefail

timeout_sec="${CODEX_GODOT_BRIDGE_TIMEOUT:-10}"

client_cwd="$(pwd)"
project_root="$client_cwd"
while [[ "$project_root" != "/" && ! -f "$project_root/project.godot" ]]; do
  project_root="$(dirname "$project_root")"
done

if [[ ! -f "$project_root/project.godot" ]]; then
  echo "Could not find project.godot from $client_cwd. Run this inside a Godot project." >&2
  exit 2
fi

cd "$project_root"

bridge_root="${CODEX_GODOT_FILE_BRIDGE_ROOT:-.godot/godot_codex_bridge}"
if [[ "$bridge_root" != /* ]]; then
  bridge_root="$project_root/$bridge_root"
fi

usage() {
  cat <<'USAGE' >&2
Usage:
  tools/godot_bridge_send.sh ping
  tools/godot_bridge_send.sh get_editor_context
  tools/godot_bridge_send.sh --json '{"command":"select_node","node_path":"Player"}'
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

if [[ "${1:-}" == "--json" ]]; then
  if [[ $# -ne 2 ]]; then
    usage
    exit 2
  fi
  raw_payload="$2"
else
  if [[ $# -ne 1 ]]; then
    usage
    exit 2
  fi
  raw_payload="{\"command\":\"$1\"}"
fi

mkdir -p "$bridge_root/inbox" "$bridge_root/outbox"

request_id="${CODEX_GODOT_REQUEST_ID:-codex_$(date +%s)_$$}"
inbox_tmp="$bridge_root/inbox/$request_id.json.tmp"
inbox_file="$bridge_root/inbox/$request_id.json"
outbox_file="$bridge_root/outbox/$request_id.json"

PROJECT_ROOT="$project_root" CLIENT_CWD="$client_cwd" REQUEST_ID="$request_id" RAW_PAYLOAD="$raw_payload" python3 - <<'PY' > "$inbox_tmp"
import json
import os
import sys

try:
    payload = json.loads(os.environ["RAW_PAYLOAD"])
except json.JSONDecodeError as exc:
    print(f"Invalid JSON: {exc}", file=sys.stderr)
    raise SystemExit(2)

if not isinstance(payload, dict):
    print("Request must be a JSON object.", file=sys.stderr)
    raise SystemExit(2)

payload["request_id"] = os.environ["REQUEST_ID"]
payload.setdefault("project_root", os.environ["PROJECT_ROOT"])
payload.setdefault("client_cwd", os.environ["CLIENT_CWD"])
print(json.dumps(payload, ensure_ascii=False))
PY

mv "$inbox_tmp" "$inbox_file"

deadline=$((SECONDS + timeout_sec))
while [[ ! -f "$outbox_file" ]]; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for Godot file bridge response: $outbox_file" >&2
    exit 1
  fi
  sleep 0.1
done

cat "$outbox_file"
rm -f "$outbox_file"
