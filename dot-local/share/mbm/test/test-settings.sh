#!/usr/bin/env bash
# Tests for `mbm settings`. Every run uses a temp HOME and env-overridden
# paths; nothing outside the temp dir is read or written (except the repo).
# Run in the VM:  cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/dot-local/share/mbm/test/test-settings.sh'
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
MBM="$HERE/../bin/mbm"
FIX="$HERE/fixtures"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fresh() { # fresh [defaults.json]: empty temp HOME with all mbm paths inside it
  rm -rf "${T:?}/home"
  export HOME="$T/home"
  export MBM_DEFAULTS="${1:-$FIX/defaults.json}"
  export MBM_CONFIG_DIR="$HOME/.config/mbm" MBM_STATE_DIR="$HOME/.local/state/mbm" MBM_HYPR_DIR="$HOME/.config/hypr/mbm"
  unset HYPRLAND_INSTANCE_SIGNATURE MBM_NO_RELOAD
  mkdir -p "$HOME"
}
user_file() { cat "$MBM_CONFIG_DIR/settings.json" 2>/dev/null; }

# --- get -------------------------------------------------------------------
fresh
check "get: default value"            '"centre"' "$("$MBM" settings get .launcher.position)"
check "get: no user file is created"  "no"       "$([[ -e $MBM_CONFIG_DIR/settings.json ]] && echo yes || echo no)"
check "get: bind by id"               '"SPACE"'  "$("$MBM" settings get '.binds["shell.launcher"].key')"

# --- set -------------------------------------------------------------------
fresh
"$MBM" settings set .launcher.position '"anchored"'
check "set: merged value"             '"anchored"' "$("$MBM" settings get .launcher.position)"
check "set: user file has only the override" '{"launcher":{"position":"anchored"}}' "$(jq -c . <<<"$(user_file)")"
check "set: merged state refreshed"   '"anchored"' "$(jq .launcher.position "$MBM_STATE_DIR/settings.json")"

fresh
"$MBM" settings set '.binds["shell.launcher"].key' '"D"' .notifications.timeoutMs 8000
check "set: several pairs at once"    '"D" 8000' "$("$MBM" settings get '.binds["shell.launcher"].key') $("$MBM" settings get .notifications.timeoutMs)"
check "set: rest of the bind kept"    '"SUPER"'  "$("$MBM" settings get '.binds["shell.launcher"].mods')"

fresh
"$MBM" settings set .launcher.position '"anchored"'
before="$(user_file)"
"$MBM" settings set '.foo; halt' '1' 2>"$T/err"; rc=$?
check "set: bad path refused"         "1"        "$rc"
contains "set: bad path message"      "bad settings path" "$(cat "$T/err")"
"$MBM" settings set .launcher.position 'not json' 2>"$T/err"; rc=$?
check "set: non-JSON refused"         "1"        "$rc"
check "set: refused writes nothing"   "$before"  "$(user_file)"
"$MBM" settings set .launcher 2>/dev/null; rc=$?
check "set: odd argument count refused" "1"      "$rc"

# --- reset -----------------------------------------------------------------
fresh
"$MBM" settings set .launcher.position '"anchored"' .bar.position '"bottom"'
"$MBM" settings reset .launcher.position
check "reset: back to default"        '"centre"' "$("$MBM" settings get .launcher.position)"
check "reset: other override kept"    '"bottom"' "$("$MBM" settings get .bar.position)"

# --- removing a default bind with null --------------------------------------
fresh
"$MBM" settings set '.binds["apps.terminal"]' null
check "null bind: removed from merged" "false"   "$("$MBM" settings get '.binds | has("apps.terminal")')"
"$MBM" settings reset '.binds["apps.terminal"]'
check "null bind: reset restores it"  "true"     "$("$MBM" settings get '.binds | has("apps.terminal")')"

# --- broken user file (Review Focus 1) --------------------------------------
fresh
"$MBM" settings set .launcher.position '"anchored"'
good_state="$(cat "$MBM_STATE_DIR/settings.json")"
printf '{ "launcher": ' >"$MBM_CONFIG_DIR/settings.json"
"$MBM" settings get . >/dev/null 2>"$T/err"; rc=$?
check "broken user file: get fails"   "1"        "$rc"
contains "broken user file: message names the file" "settings.json is not a valid JSON object" "$(cat "$T/err")"
check "broken user file: merged state untouched" "$good_state" "$(cat "$MBM_STATE_DIR/settings.json")"

exit $fail
