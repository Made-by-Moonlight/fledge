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
row "exec [float] kitty"         'null'
row "exec [workspace 2 silent; float] foot -e x" 'null'
row "movefocus x"                'null'
row "killactive now"             'null'
row "resizeactive 10% 0"         'null'
row "movetoworkspace 3,address:0x1" 'null'
row "workspace 1 extra"          'null'
row "movetoworkspacesilent 2 x"  'null'
row "sendshortcut CTRL, X,"      'null'
row "sendshortcut , F5"          '{"dsp":"send_shortcut","args":{"mods":"","key":"F5"}}'

# The fixture is the v1 defaults exactly as they shipped (git show
# b970944:dot-local/share/mbm/defaults/settings.json): never edit it to make a
# test pass, or it stops standing for what users really have.
check "fixture: defaults-v1.json is the shipped v1 defaults, byte for byte" \
  "e95bda97ebe56b3281332119d485685377346ecb6afb1bf075afe971d06f3f95" "$(sha256sum <"$FIX/defaults-v1.json" | cut -d' ' -f1)"

# The v1 zoom binds' `hyprctl keyword` commands (refused by the Lua config) get
# fledge's forms; only those exact strings.
zoom_in="$(jq -r '.binds["utilities.zoom-in"].action.exec' "$FIX/defaults-v1.json")"
zoom_reset="$(jq -r '.binds["utilities.reset-zoom"].action.exec' "$FIX/defaults-v1.json")"
mig_exec() { jq -c -L "$LIB" --arg c "$1" -n 'include "migrate-dispatch"; {binds: {z: {action: {exec: $c}}}} | migrate_user | [.settings.binds.z.action, .count]'; }
check "migrate: v1 zoom-in command -> fledge hypr eval" \
  "[$(jq -c '.binds["utilities.zoom-in"].action' "$HERE/../defaults/settings.json"),1]" "$(mig_exec "$zoom_in")"
check "migrate: v1 reset-zoom command -> fledge hypr set" \
  '[{"exec":"fledge hypr set '"'"'cursor = { zoom_factor = 1 }'"'"'"},1]' "$(mig_exec "$zoom_reset")"
check "migrate: other legacy IPC in a command is left alone (check names it)" \
  '[{"exec":"hyprctl keyword cursor:zoom_factor 2"},0]' "$(mig_exec "hyprctl keyword cursor:zoom_factor 2")"
check "migrate: a version-less file holding a v1 zoom command needs migrating" "true" \
  "$(jq -L "$LIB" --arg c "$zoom_reset" -n 'include "migrate-dispatch"; {binds: {z: {action: {exec: $c}}}} | needs_migration')"

# Every legacy dispatcher in the old defaults has a translation, and the result
# is exactly the shipped v2 defaults, give or take the binds changed since on
# purpose: the YouTube web app bind went (no web apps) and YouTube Music runs limusic.
check "migrate: old v1 defaults == v2 defaults (binds)" "true" \
  "$(jq -L "$LIB" --slurpfile v2 "$HERE/../defaults/settings.json" \
     'include "migrate-dispatch"; migrate_user.settings.binds
      | del(.["apps.youtube"]) | .["apps.youtube-music"].action.exec = "slievr-launch-or-focus limusic-app"
      | . == $v2[0].binds' "$FIX/defaults-v1.json" 2>&1)"
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

# get and check migrate in memory only: they never write (a read-only command
# must not race a concurrent `set`, and must work when the config dir isn't writable).
for cmd in check get; do
  fresh; U "$v1"
  before="$(cat "$MBM_CONFIG_DIR/settings.json")"
  case $cmd in
    check) "$MBM" settings check >"$T/out" 2>"$T/err"; rc=$? ;;
    get) "$MBM" settings get '.launcher.position, .binds["custom.a"].action' >"$T/out" 2>"$T/err"; rc=$? ;;
  esac
  check "in-memory on $cmd: file untouched" "$before" "$(cat "$MBM_CONFIG_DIR/settings.json")"
  check "in-memory on $cmd: no backup" "no" "$([[ -e $MBM_CONFIG_DIR/settings.json.v1 ]] && echo yes || echo no)"
  case $cmd in
    check) check "in-memory on check: unknown reported -> exit 1" "1" "$rc"
           contains "in-memory on check: unknown named" "binds.custom.c: can't convert dispatcher \"focuswindow class:kitty\"; rewrite it as {dsp, args}" "$(cat "$T/err")"
           check "in-memory on check: converted ones pass" "1" "$(grep -c '^binds\.' "$T/err")" ;;
    get) check "in-memory on get: migrated values" '"anchored"|{"dsp":"window.float","args":{"action":"toggle"}}' "$(jq -c . "$T/out" | paste -sd'|')"
         check "in-memory on get: rc 0" "0" "$rc" ;;
  esac
done

fresh; U '{"version":1,"binds":{"windows.workspace-1":{"action":{"dispatch":"workspace 2"}}}}'
"$MBM" settings check 2>"$T/err"; rc=$?
check "in-memory: convertible file checks clean" "0" "$rc"

fresh; U "$v1"
chmod 555 "$MBM_CONFIG_DIR"
out="$("$MBM" settings get '.binds["windows.workspace-1"].action' 2>"$T/err")"; rc=$?
chmod 755 "$MBM_CONFIG_DIR"
check "read-only config dir: get rc 0" "0" "$rc"
check "read-only config dir: get migrated value" '{"dsp":"focus","args":{"workspace":2}}' "$(jq -c . <<<"$out")"

# set, reset and apply write the migrated file back, with a backup of what was read.
for cmd in apply set reset; do
  fresh; U "$v1"; chmod 644 "$MBM_CONFIG_DIR/settings.json"
  case $cmd in
    apply) MBM_NO_RELOAD=1 "$MBM" settings apply >"$T/out" 2>"$T/err"; rc=$? ;;
    set) "$MBM" settings set .bar.position '"bottom"' >"$T/out" 2>"$T/err"; rc=$? ;;
    reset) "$MBM" settings reset .bar.position >"$T/out" 2>"$T/err"; rc=$? ;;
  esac
  f="$MBM_CONFIG_DIR/settings.json"
  check "migrate on $cmd: file is version 2" "2" "$(jq .version "$f")"
  check "migrate on $cmd: backup is the original" "$v1" "$(cat "$f.v1" 2>&1)"
  check "migrate on $cmd: file mode kept" "644" "$(stat -c %a "$f")"
  check "migrate on $cmd: backup mode kept" "644" "$(stat -c %a "$f.v1" 2>&1)"
  contains "migrate on $cmd: message" "mbm: migrated 3 binds to settings v2, 1 could not be converted (backup: $f.v1)" "$(cat "$T/err")"
  check "migrate on $cmd: converted" '{"dsp":"focus","args":{"workspace":2}}|{"dsp":"window.float","args":{"action":"toggle"}}|[{"exec":"x"},{"dsp":"window.close"}]' \
    "$(jq -r '.binds | [.["windows.workspace-1"], .["custom.a"], .["custom.b"]] | map(.action | tojson) | join("|")' "$f")"
  check "migrate on $cmd: unknown kept" '{"dispatch":"focuswindow class:kitty"}' "$(jq -c '.binds["custom.c"].action' "$f")"
  check "migrate on $cmd: other settings kept" '"anchored"' "$(jq '.launcher.position' "$f")"
  check "migrate on $cmd: refused while one is unconverted" "1" "$rc"
  check "migrate on $cmd: no temp files left" "" "$(find "$MBM_CONFIG_DIR" -name 'settings.json.??????')"
done

# A second migration (the leftover {dispatch} with the version reset away) never
# overwrites the first backup: that one holds the user's real original.
fresh; U "$v1"
MBM_NO_RELOAD=1 "$MBM" settings apply >/dev/null 2>&1
jq 'del(.version)' "$MBM_CONFIG_DIR/settings.json" >"$T/nov.json" && cp "$T/nov.json" "$MBM_CONFIG_DIR/settings.json"
MBM_NO_RELOAD=1 "$MBM" settings apply >/dev/null 2>"$T/err"
check "second migration: file is version 2 again" "2" "$(jq .version "$MBM_CONFIG_DIR/settings.json")"
check "second migration: first backup kept" "$v1" "$(cat "$MBM_CONFIG_DIR/settings.json.v1")"
contains "second migration: message names the kept backup" "migrated 0 binds to settings v2, 1 could not be converted (earlier backup kept: $MBM_CONFIG_DIR/settings.json.v1)" "$(cat "$T/err")"

# Concurrent writers on a v1 file: the migration and every change survive.
v1ok="$(jq -c 'del(.binds["custom.c"])' <<<"$v1")"
fresh; U "$v1ok"
for i in 1 2 3 4 5 6; do
  "$MBM" settings set ".binds[\"custom.p$i\"]" "{\"mods\":\"SUPER ALT\",\"key\":\"F$i\",\"label\":\"P\",\"group\":\"Apps\",\"action\":{\"exec\":\"p\"}}" 2>/dev/null &
done
wait
check "concurrent set: every change kept" "6" "$(jq '[.binds | keys[] | select(startswith("custom.p"))] | length' "$MBM_CONFIG_DIR/settings.json")"
check "concurrent set: backup is the original" "$v1ok" "$(cat "$MBM_CONFIG_DIR/settings.json.v1")"

fresh; U '{"version":1,"binds":{"windows.workspace-1":{"action":{"dispatch":"workspace 2"}}}}'
MBM_NO_RELOAD=1 "$MBM" settings apply 2>"$T/err"; rc=$?
check "migrate: convertible file applies" "0" "$rc"
contains "migrate: one bind counted" "migrated 1 binds to settings v2, 0 could not be converted" "$(cat "$T/err")"
MBM_NO_RELOAD=1 "$MBM" settings apply 2>"$T/err"
check "migrate: second run is silent" "" "$(cat "$T/err")"

# A v1 bind with the 's' flag has no Lua equivalent: counted as unconverted,
# kept as it was, and check names it.
fresh; U '{"version":1,"binds":{"windows.workspace-1":{"flags":"s","action":{"dispatch":"workspace 2"}}}}'
MBM_NO_RELOAD=1 "$MBM" settings apply 2>"$T/err"; rc=$?
check "migrate: s flag -> apply refused" "1" "$rc"
contains "migrate: s flag counted as unconverted" "migrated 1 binds to settings v2, 1 could not be converted" "$(cat "$T/err")"
check "migrate: s flag kept" '"s"' "$(jq '.binds["windows.workspace-1"].flags' "$MBM_CONFIG_DIR/settings.json")"
contains "migrate: check names the s flag" "binds.windows.workspace-1: flag s (separate keysyms)" "$("$MBM" settings check 2>&1)"

# A user file without a version (what `settings set` writes) still migrates.
fresh; U '{"binds":{"windows.workspace-1":{"action":{"dispatch":"workspace 2"}}}}'
MBM_NO_RELOAD=1 "$MBM" settings apply >/dev/null 2>"$T/err"
check "migrate: unversioned file with dispatch -> version 2" "2" "$(jq .version "$MBM_CONFIG_DIR/settings.json")"
contains "migrate: unversioned file message" "migrated 1 binds" "$(cat "$T/err")"

# --- merge: a user action replaces the default's, it never deep-merges -----------
# (windows.workspace-1's default is {"dsp":"focus","args":{"workspace":1}}.)
fresh; U '{"version":2,"binds":{"windows.workspace-1":{"action":{"dsp":"focus","args":{"direction":"left"}}}}}'
check "merge: same dsp, other args -> user's args only" '{"dsp":"focus","args":{"direction":"left"}}' "$("$MBM" settings get '.binds["windows.workspace-1"].action' | jq -c .)"
fresh; U '{"version":2,"binds":{"windows.workspace-1":{"action":{"dsp":"window.close"}}}}'
check "merge: other dsp -> no default args left" '{"dsp":"window.close"}' "$("$MBM" settings get '.binds["windows.workspace-1"].action' | jq -c .)"
fresh; U '{"version":1,"binds":{"windows.workspace-1":{"action":{"dispatch":"movefocus l"}}}}'
check "merge: migrated override -> user's action only" '{"dsp":"focus","args":{"direction":"left"}}' "$("$MBM" settings get '.binds["windows.workspace-1"].action' | jq -c .)"
fresh; U '{"version":2,"binds":{"windows.workspace-1":{"key":"F5"}}}'
check "merge: override without action keeps the default action" '{"dsp":"focus","args":{"workspace":1}}' "$("$MBM" settings get '.binds["windows.workspace-1"].action' | jq -c .)"
check "merge: ...and its other fields merge" '"F5"' "$("$MBM" settings get '.binds["windows.workspace-1"].key')"

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
# Legacy IPC inside a command: refused by the Lua config (mostly with exit 0),
# so the bind would silently do nothing.
legacy="binds.custom.a: runs Hyprland's legacy IPC (hyprctl keyword, --batch or a dispatch string), which the Lua config refuses: use fledge hypr set|dispatch|eval"
bad "exec: hyprctl keyword"   "$legacy" '{"exec":"hyprctl keyword cursor:zoom_factor 2"}'
bad "exec: hyprctl -j keyword" "$legacy" '{"exec":"x && hyprctl -j keyword general:gaps_in 0"}'
bad "exec: hyprctl --batch"   "$legacy" '{"exec":"hyprctl --batch \"dispatch exec a ; dispatch exec b\""}'
bad "exec: hyprctl -b"        "$legacy" '{"exec":"hyprctl -b \"keyword a b\""}'
bad "exec: legacy dispatch"   "$legacy" '{"exec":"hyprctl dispatch workspace 2"}'
bad "shell: legacy dispatch"  "$legacy" '{"shell":"x.y $(hyprctl dispatch exec kitty)"}'
bad "legacy IPC in a list"    "$legacy" '[{"exec":"x"},{"exec":"hyprctl keyword a b"}]'
good "exec: Lua dispatch"     '{"exec":"hyprctl dispatch '"'"'hl.dsp.focus({ workspace = 2 })'"'"'"}'
good "exec: unquoted Lua dispatch" '{"exec":"hyprctl dispatch hl.dsp.exit()"}'
good "exec: hyprctl queries"  '{"exec":"hyprctl -j getoption cursor:zoom_factor; hyprctl reload"}'
good "exec: fledge hypr"      '{"exec":"fledge hypr set '"'"'cursor = { zoom_factor = 1 }'"'"'"}'
good "exec: the word keyword" '{"exec":"notify-send keyword"}'
good "dsp without args"      '{"dsp":"window.close"}'
good "dsp with object args"  '{"dsp":"window.move","args":{"workspace":3,"follow":false}}'
good "dsp with string args"  '{"dsp":"layout","args":"togglesplit"}'
good "dsp with bool args"    '{"dsp":"window.cycle_next","args":false}'
good "dsp with number args"  '{"dsp":"window.cycle_next","args":1}'
good "list of mixed actions" '[{"exec":"x"},{"shell":"launcher.toggle"},{"dsp":"group.next"}]'

exit $fail
