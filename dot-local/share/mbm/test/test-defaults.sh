#!/usr/bin/env bash
# The shipped defaults/settings.json must pass `mbm settings check`, and (while
# today's Hyprland configs still exist) must be what build-defaults.sh makes.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
DEF="$HERE/../defaults/settings.json"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

out="$(HOME="$T" XDG_CONFIG_HOME="$T/.config" MBM_DEFAULTS="$DEF" "$HERE/../bin/mbm" settings check 2>&1)"
check "defaults: settings check rc 0" 0 "$?"
check "defaults: settings check prints nothing" "" "$out"

# Task 18 deletes the sources; after that the JSON is the source of truth.
if [[ -f "$REPO/dot-config/hypr/bindings.conf" && -f "$REPO/dot-config/hypr/hypr-defaults/hypr/bindings/media.conf" ]]; then
  MBM_DEFAULTS_OUT="$T/rebuilt.json" "$HERE/../dev/build-defaults.sh"
  check "defaults: build-defaults.sh reproduces the committed file" "" "$(diff "$DEF" "$T/rebuilt.json")"
else
  echo "PASS  defaults: rebuild check skipped (today's Hyprland sources are gone)"
fi
# Task 18 deletes workspaces.conf; the generator must reproduce it until then.
WS="$REPO/dot-config/hypr/workspaces.conf"
if [[ -f $WS ]]; then
  check "defaults: generated workspaces match today's workspaces.conf" \
    "$(grep '^workspace = ' "$WS")" \
    "$(jq -r -f "$HERE/../lib/gen-workspaces.jq" "$DEF" | tail -n +2)"
else
  echo "PASS  defaults: workspaces.conf comparison skipped (the hand-written file is gone)"
fi
exit $fail
