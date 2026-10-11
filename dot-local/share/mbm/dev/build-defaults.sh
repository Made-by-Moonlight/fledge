#!/usr/bin/env bash
# One-off: today's Hyprland bind files + defaults-base.json + remaps.jq ->
# defaults/settings.json. Order matches hyprland.conf's source order.
# The inputs are deleted at cutover (Task 18); after that the JSON is the source.
set -euo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
D="$REPO/dot-config/hypr/hypr-defaults/hypr/bindings"
binds="$("$HERE/conf-to-binds.sh" \
  "Media=$D/media.conf" "Clipboard=$D/clipboard.conf" "Windows=$D/tiling-v2.conf" \
  "Utilities=$D/utilities.conf" "Apps=$REPO/dot-config/hypr/bindings.conf")"
out="${MBM_DEFAULTS_OUT:-$HERE/../defaults/settings.json}"
jq -n --slurpfile base "$HERE/defaults-base.json" --argjson b "$binds" '$base[0] + {binds: $b}' \
  | jq -f "$HERE/remaps.jq" >"$out.new"
mv "$out.new" "$out"
