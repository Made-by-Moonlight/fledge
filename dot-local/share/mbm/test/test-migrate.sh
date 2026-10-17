#!/usr/bin/env bash
# Tests for settings v2: the legacy dispatcher translation table
# (lib/migrate-dispatch.jq), migrating a version-1 user file on load, and the
# check rules for structured {dsp, args} actions.
# Run in the VM:  cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/dot-local/share/mbm/test/test-migrate.sh'
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
MBM="$HERE/../bin/mbm"
LIB="$HERE/../lib"
FIX="$HERE/fixtures"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# --- translation table: one check per row --------------------------------------
row() { # row <legacy dispatch string> <expected compact JSON>
  check "migrate: $1" "$2" "$(jq -c -L "$LIB" 'include "migrate-dispatch"; migrate_dispatch' <<<"$(jq -n --arg s "$1" '$s')" 2>&1)"
}
row "exec kitty -e btop"         '{"exec":"kitty -e btop"}'
row "workspace 3"                '{"dsp":"focus","args":{"workspace":3}}'
row "workspace e+1"              '{"dsp":"focus","args":{"workspace":"e+1"}}'
row "workspace e-1"              '{"dsp":"focus","args":{"workspace":"e-1"}}'
row "workspace previous"         '{"dsp":"focus","args":{"workspace":"previous"}}'
row "workspace name:web"         '{"dsp":"focus","args":{"workspace":"name:web"}}'
row "movetoworkspace 4"          '{"dsp":"window.move","args":{"workspace":4}}'
row "movetoworkspacesilent 5"    '{"dsp":"window.move","args":{"workspace":5,"follow":false}}'
row "movetoworkspacesilent special:scratchpad" '{"dsp":"window.move","args":{"workspace":"special:scratchpad","follow":false}}'
row "togglespecialworkspace scratchpad" '{"dsp":"workspace.toggle_special","args":"scratchpad"}'
row "movefocus l"                '{"dsp":"focus","args":{"direction":"left"}}'
row "movefocus r"                '{"dsp":"focus","args":{"direction":"right"}}'
row "movefocus u"                '{"dsp":"focus","args":{"direction":"up"}}'
row "movefocus d"                '{"dsp":"focus","args":{"direction":"down"}}'
row "focusmonitor +1"            '{"dsp":"focus","args":{"monitor":"+1"}}'
row "swapwindow l"               '{"dsp":"window.swap","args":{"direction":"left"}}'
row "resizeactive -100 0"        '{"dsp":"window.resize","args":{"x":-100,"y":0,"relative":true}}'
row "movecurrentworkspacetomonitor r" '{"dsp":"workspace.move","args":{"monitor":"r"}}'
row "togglefloating"             '{"dsp":"window.float","args":{"action":"toggle"}}'
row "fullscreen 0"               '{"dsp":"window.fullscreen"}'
row "fullscreen 1"               '{"dsp":"window.fullscreen","args":{"mode":"maximized"}}'
row "fullscreenstate 0 2"        '{"dsp":"window.fullscreen_state","args":{"internal":0,"client":2}}'
row "killactive"                 '{"dsp":"window.close"}'
row "pseudo"                     '{"dsp":"window.pseudo"}'
row "bringactivetotop"           '{"dsp":"window.bring_to_top"}'
row "cyclenext"                  '{"dsp":"window.cycle_next"}'
row "cyclenext prev"             '{"dsp":"window.cycle_next","args":false}'
row "togglegroup"                '{"dsp":"group.toggle"}'
row "moveintogroup l"            '{"dsp":"window.move","args":{"into_group":"l"}}'
row "moveoutofgroup"             '{"dsp":"window.move","args":{"out_of_group":true}}'
row "changegroupactive f"        '{"dsp":"group.next"}'
row "changegroupactive b"        '{"dsp":"group.prev"}'
row "changegroupactive 3"        '{"dsp":"group.active","args":{"index":3}}'
row "layoutmsg togglesplit"      '{"dsp":"layout","args":"togglesplit"}'
row "sendshortcut CTRL, Insert, activewindow" '{"dsp":"send_shortcut","args":{"mods":"CTRL","key":"Insert","window":"activewindow"}}'
row "submap reset"               '{"dsp":"submap","args":"reset"}'
row "dpms off"                   '{"dsp":"dpms","args":{"action":"off"}}'
row "dpms on"                    '{"dsp":"dpms","args":{"action":"on"}}'
row "movewindow"                 '{"dsp":"window.drag"}'
row "resizewindow"               '{"dsp":"window.resize"}'
row "exit"                       '{"dsp":"exit"}'
row "forcerendererreload"        '{"dsp":"force_renderer_reload"}'
# Anything outside the table (or a known dispatcher with arguments it can't
# map) is left for the user to rewrite, never guessed.
row "focuswindow class:kitty"    'null'
row "movefocus x"                'null'
row "killactive now"             'null'
row "resizeactive 10% 0"         'null'
row "movetoworkspace 3,address:0x1" 'null'

# Every legacy dispatcher in the old defaults has a translation, and the result
# is exactly the shipped v2 defaults.
check "migrate: old v1 defaults == v2 defaults (binds)" "true" \
  "$(jq -L "$LIB" --slurpfile v2 "$HERE/../defaults/settings.json" \
     'include "migrate-dispatch"; migrate_user.settings.binds == $v2[0].binds' "$FIX/defaults-v1.json" 2>&1)"
check "migrate: v2 defaults have no dispatch left" "0" \
  "$(jq '[.. | objects | select(has("dispatch"))] | length' "$HERE/../defaults/settings.json")"
check "migrate: v2 defaults are version 2" "2" "$(jq .version "$HERE/../defaults/settings.json")"

# --- migrating a user file on load ---------------------------------------------
fresh() {
  rm -rf "${T:?}/home"
  export HOME="$T/home"
  export MBM_DEFAULTS="$FIX/defaults.json"
  export MBM_CONFIG_DIR="$HOME/.config/mbm" MBM_STATE_DIR="$HOME/.local/state/mbm" MBM_HYPR_DIR="$HOME/.local/state/mbm/hypr"
  unset HYPRLAND_INSTANCE_SIGNATURE MBM_NO_RELOAD
  mkdir -p "$MBM_CONFIG_DIR"
}
U() { printf '%s\n' "$1" >"$MBM_CONFIG_DIR/settings.json"; }
v1='{"version":1,"launcher":{"position":"anchored"},"binds":{
  "windows.workspace-1":{"action":{"dispatch":"workspace 2"}},
  "custom.a":{"mods":"SUPER","key":"F1","label":"A","group":"Apps","action":{"dispatch":"togglefloating"}},
  "custom.b":{"mods":"SUPER","key":"F2","label":"B","group":"Apps","action":[{"exec":"x"},{"dispatch":"killactive"}]},
  "custom.c":{"mods":"SUPER","key":"F3","label":"C","group":"Apps","action":{"dispatch":"focuswindow class:kitty"}}}}'

for cmd in check get apply set; do
  fresh; U "$v1"
  case $cmd in
    check) "$MBM" settings check >"$T/out" 2>"$T/err"; rc=$? ;;
    get) "$MBM" settings get .launcher.position >"$T/out" 2>"$T/err"; rc=$? ;;
    apply) MBM_NO_RELOAD=1 "$MBM" settings apply >"$T/out" 2>"$T/err"; rc=$? ;;
    set) "$MBM" settings set .bar.position '"bottom"' >"$T/out" 2>"$T/err"; rc=$? ;;
  esac
  f="$MBM_CONFIG_DIR/settings.json"
  check "migrate on $cmd: file is version 2" "2" "$(jq .version "$f")"
  check "migrate on $cmd: backup kept" "$(jq -c . <<<"$v1")" "$(jq -c . "$f.v1" 2>&1)"
  contains "migrate on $cmd: message" "mbm: migrated 3 binds to settings v2 (backup: $f.v1)" "$(cat "$T/err")"
  check "migrate on $cmd: converted" '{"dsp":"focus","args":{"workspace":2}}|{"dsp":"window.float","args":{"action":"toggle"}}|[{"exec":"x"},{"dsp":"window.close"}]' \
    "$(jq -r '.binds | [.["windows.workspace-1"], .["custom.a"], .["custom.b"]] | map(.action | tojson) | join("|")' "$f")"
  check "migrate on $cmd: unknown kept" '{"dispatch":"focuswindow class:kitty"}' "$(jq -c '.binds["custom.c"].action' "$f")"
  check "migrate on $cmd: other settings kept" '"anchored"' "$(jq '.launcher.position' "$f")"
  case $cmd in
    check) check "migrate on check: unknown reported -> exit 1" "1" "$rc"
           contains "migrate on check: unknown named" "binds.custom.c: can't convert dispatcher \"focuswindow class:kitty\"; rewrite it as {dsp, args}" "$(cat "$T/err")" ;;
    get) check "migrate on get: still reads" '"anchored"' "$(cat "$T/out")" ;;
    apply) check "migrate on apply: refused while one is unconverted" "1" "$rc" ;;
    set) check "migrate on set: refused while one is unconverted" "1" "$rc" ;;
  esac
done

# Fully convertible file: everything works straight after migrating.
fresh; U '{"version":1,"binds":{"windows.workspace-1":{"action":{"dispatch":"workspace 2"}}}}'
"$MBM" settings check 2>"$T/err"; rc=$?
check "migrate: convertible file then checks clean" "0" "$rc"
contains "migrate: one bind counted" "migrated 1 binds" "$(cat "$T/err")"
"$MBM" settings check 2>"$T/err"
check "migrate: second run is silent" "" "$(cat "$T/err")"

# A user file without a version (what `settings set` writes) still migrates.
fresh; U '{"binds":{"windows.workspace-1":{"action":{"dispatch":"workspace 2"}}}}'
"$MBM" settings get .version >/dev/null 2>"$T/err"
check "migrate: unversioned file with dispatch -> version 2" "2" "$(jq .version "$MBM_CONFIG_DIR/settings.json")"
contains "migrate: unversioned file message" "migrated 1 binds" "$(cat "$T/err")"

# Nothing to migrate: the file is left byte for byte.
for v2 in '{"version":2,"binds":{"custom.a":{"mods":"SUPER","key":"F1","label":"A","group":"Apps","action":{"dsp":"window.close"}}}}' \
          '{"launcher":{"position":"anchored"}}'; do
  fresh; U "$v2"
  before="$(cat "$MBM_CONFIG_DIR/settings.json")"
  "$MBM" settings check 2>"$T/err"; rc=$?
  check "no migration: $v2 -> exit 0" "0" "$rc"
  check "no migration: $v2 -> silent" "" "$(cat "$T/err")"
  check "no migration: $v2 -> untouched" "$before" "$(cat "$MBM_CONFIG_DIR/settings.json")"
  check "no migration: $v2 -> no backup" "no" "$([[ -e $MBM_CONFIG_DIR/settings.json.v1 ]] && echo yes || echo no)"
done

# --- check: structured actions ---------------------------------------------------
bad() { # bad <description> <expected message part> <action-json>
  fresh
  U "{\"version\":2,\"binds\":{\"custom.a\":{\"mods\":\"SUPER\",\"key\":\"F1\",\"label\":\"A\",\"group\":\"Apps\",\"action\":$3}}}"
  local out rc
  out="$("$MBM" settings check 2>&1)"; rc=$?
  check "check: $1 -> exit 1" "1" "$rc"
  contains "check: $1 -> message" "$2" "$out"
}
good() { # good <description> <action-json>
  fresh
  U "{\"version\":2,\"binds\":{\"custom.a\":{\"mods\":\"SUPER\",\"key\":\"F1\",\"label\":\"A\",\"group\":\"Apps\",\"action\":$2}}}"
  local out rc
  out="$("$MBM" settings check 2>&1)"; rc=$?
  check "check: $1 -> exit 0" "0" "$rc"
  check "check: $1 -> silent" "" "$out"
}
bad "unknown dispatcher"     'binds.custom.a: unknown dispatcher "window.nope"' '{"dsp":"window.nope"}'
bad "args as a list"         "binds.custom.a: args for focus"                  '{"dsp":"focus","args":[1]}'
bad "nested args"            "binds.custom.a: args for focus"                  '{"dsp":"focus","args":{"a":{"b":1}}}'
bad "null args"              "binds.custom.a: args for focus"                  '{"dsp":"focus","args":null}'
bad "two kinds"              "binds.custom.a: action must be one of"           '{"dsp":"window.close","exec":"x"}'
bad "args without dsp"       "binds.custom.a: action must be one of"           '{"exec":"x","args":"y"}'
bad "leftover dispatch"      "binds.custom.a: can't convert dispatcher \"focuswindow class:x\"; rewrite it as {dsp, args}" '{"dispatch":"focuswindow class:x"}'
bad "leftover dispatch in a list" "binds.custom.a: can't convert dispatcher \"foo\"" '[{"exec":"x"},{"dispatch":"foo"}]'
bad "dsp not a string"       "binds.custom.a: unknown dispatcher 3"            '{"dsp":3}'
good "dsp without args"      '{"dsp":"window.close"}'
good "dsp with object args"  '{"dsp":"window.move","args":{"workspace":3,"follow":false}}'
good "dsp with string args"  '{"dsp":"layout","args":"togglesplit"}'
good "dsp with bool args"    '{"dsp":"window.cycle_next","args":false}'
good "dsp with number args"  '{"dsp":"window.cycle_next","args":1}'
good "list of mixed actions" '[{"exec":"x"},{"shell":"launcher.toggle"},{"dsp":"group.next"}]'

exit $fail
