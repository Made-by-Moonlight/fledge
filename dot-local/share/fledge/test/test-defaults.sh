#!/usr/bin/env bash
# The shipped defaults/settings.json must pass `fledge settings check`. Since the
# cutover it is the source of truth for binds, monitors, workspaces and input.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
DEF="$HERE/../defaults/settings.json"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

out="$(HOME="$T" XDG_CONFIG_HOME="$T/.config" MBM_DEFAULTS="$DEF" "$HERE/../bin/fledge" settings check 2>&1)"
check "defaults: settings check rc 0" 0 "$?"
check "defaults: settings check prints nothing" "" "$out"

# What apply generates from the shipped defaults must be Lua Hyprland can load:
# it parses, it runs against the hl stub (only known hl.* calls), and every bind
# becomes one hl.bind (plus the mbm-record submap's).
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/luacheck.sh
source "$REPO/cachyos/install/test/luacheck.sh"
LUA="$(command -v lua || command -v lua5.5 || command -v lua5.4)"
gen="$T/.local/state/mbm/hypr"
env -u HYPRLAND_INSTANCE_SIGNATURE HOME="$T" XDG_CONFIG_HOME="$T/.config" MBM_DEFAULTS="$DEF" \
  "$HERE/../bin/fledge" settings apply
check "defaults: apply rc 0" 0 "$?"
for f in binds monitors workspaces input; do
  lua_syntax_ok "$gen/$f.lua"; check "defaults: $f.lua parses" 0 "$?"
  "$LUA" "$HERE/hl-stub.lua" "$gen/$f.lua" >"$T/$f.out" 2>&1; check "defaults: $f.lua runs against the hl stub" 0 "$?"
done
check "defaults: one hl.bind per bind, plus the submap's" "$(($(jq '.binds | length' "$DEF") + 1))" "$(grep -c '^bind' "$T/binds.out")"
exit $fail
