#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
project_dir="$repo_root/examples/bridge-dungeon"
godot_bin="${CODEX_GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
frames_dir="$project_dir/showcase_frames"
media_dir="$repo_root/docs/media"
gif_path="$media_dir/bridge-dungeon-demo.gif"
mp4_path="$media_dir/bridge-dungeon-demo.mp4"

if [[ ! -x "$godot_bin" ]]; then
  echo "Godot executable not found: $godot_bin" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required to build showcase media." >&2
  exit 1
fi

mkdir -p "$media_dir"
rm -rf "$frames_dir"

"$godot_bin" --path "$project_dir" --rendering-method gl_compatibility -s "$script_dir/capture_bridge_dungeon_showcase.gd"

ffmpeg -y -hide_banner -loglevel warning \
  -framerate 12 \
  -i "$frames_dir/frame_%04d.png" \
  -vf "scale=960:-1:flags=lanczos,fps=12,split[s0][s1];[s0]palettegen=max_colors=96[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
  "$gif_path"

ffmpeg -y -hide_banner -loglevel warning \
  -framerate 24 \
  -i "$frames_dir/frame_%04d.png" \
  -vf "scale=960:-2:flags=lanczos" \
  -pix_fmt yuv420p \
  -movflags +faststart \
  "$mp4_path"

rm -rf "$frames_dir"

echo "Wrote $gif_path"
echo "Wrote $mp4_path"
