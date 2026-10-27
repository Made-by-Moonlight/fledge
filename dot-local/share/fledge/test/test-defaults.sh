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

out="$(HOME="$T" XDG_CONFIG_HOME="$T/.config" FLEDGE_DEFAULTS="$DEF" "$HERE/../bin/fledge" settings check 2>&1)"
check "defaults: settings check rc 0" 0 "$?"
check "defaults: settings check prints nothing" "" "$out"

# What apply generates from the shipped defaults must be Lua Hyprland can load:
# it parses, it runs against the hl stub (only known hl.* calls), and every bind
# becomes one hl.bind (the submaps have their own).
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/luacheck.sh
source "$REPO/cachyos/install/test/luacheck.sh"
LUA="$(command -v lua || command -v lua5.5 || command -v lua5.4)"
gen="$T/.local/state/fledge/hypr"
env -u HYPRLAND_INSTANCE_SIGNATURE HOME="$T" XDG_CONFIG_HOME="$T/.config" FLEDGE_DEFAULTS="$DEF" \
  "$HERE/../bin/fledge" settings apply
check "defaults: apply rc 0" 0 "$?"
for f in binds monitors workspaces input; do
  lua_syntax_ok "$gen/$f.lua"; check "defaults: $f.lua parses" 0 "$?"
  "$LUA" "$HERE/hl-stub.lua" "$gen/$f.lua" >"$T/$f.out" 2>&1; check "defaults: $f.lua runs against the hl stub" 0 "$?"
done
check "defaults: one hl.bind per bind" "$(jq '.binds | length' "$DEF")" "$(grep -c $'^bind\t' "$T/binds.out")"
check "defaults: the fledge-record submap's way out" 1 "$(grep -c '^bind@fledge-record' "$T/binds.out")"
# The window switcher's: Alt+Tab and Alt+Shift+Tab again, arrows, Return and Escape.
check "defaults: the fledge-switcher submap" 6 "$(grep -c '^bind@fledge-switcher' "$T/binds.out")"
check "defaults: Alt+Tab opens the switcher" \
  "bind	ALT + TAB	fn[dsp.event(fledge-switcher next); dsp.submap(fledge-switcher)]	{description=Switch windows}" \
  "$(grep $'^bind\tALT + TAB\t' "$T/binds.out")"
# windows.switcher off: the same keys cycle focus, and there is no switcher submap.
jq '.windows.switcher = false' "$DEF" > "$T/off.json"
env -u HYPRLAND_INSTANCE_SIGNATURE HOME="$T" XDG_CONFIG_HOME="$T/.config" FLEDGE_DEFAULTS="$T/off.json" \
  "$HERE/../bin/fledge" settings apply
check "switcher off: apply rc 0" 0 "$?"
"$LUA" "$HERE/hl-stub.lua" "$gen/binds.lua" >"$T/off.out" 2>&1
check "switcher off: Alt+Tab cycles focus" \
  "bind	ALT + TAB	fn[dsp.window.cycle_next(); dsp.window.bring_to_top()]	{description=Switch windows}" \
  "$(grep $'^bind\tALT + TAB\t' "$T/off.out")"
check "switcher off: Alt+Shift+Tab cycles back" \
  "bind	ALT + SHIFT + TAB	fn[dsp.window.cycle_next(false); dsp.window.bring_to_top()]	{description=Switch windows backwards}" \
  "$(grep $'^bind\tALT + SHIFT + TAB\t' "$T/off.out")"
check "switcher off: no switcher submap" 0 "$(grep -c '^bind@fledge-switcher' "$T/off.out")"
jq '.windows.switcher = "yes"' "$DEF" > "$T/bad.json"
check "switcher: not a boolean is refused" "windows.switcher must be true or false" \
  "$(env -u HYPRLAND_INSTANCE_SIGNATURE HOME="$T" XDG_CONFIG_HOME="$T/.config" FLEDGE_DEFAULTS="$T/bad.json" "$HERE/../bin/fledge" settings check 2>&1)"
exit $fail
