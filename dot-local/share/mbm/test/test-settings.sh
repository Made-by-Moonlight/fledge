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
  export MBM_CONFIG_DIR="$HOME/.config/mbm" MBM_STATE_DIR="$HOME/.local/state/mbm" MBM_HYPR_DIR="$HOME/.local/state/mbm/hypr"
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

# --- empty user file: no overrides, not a broken file ---------------------------
fresh
mkdir -p "$MBM_CONFIG_DIR"
: >"$MBM_CONFIG_DIR/settings.json"
check "empty user file: get reads defaults" '"centre"' "$("$MBM" settings get .launcher.position 2>&1)"
"$MBM" settings set .launcher.position '"anchored"' 2>"$T/err"; rc=$?
check "empty user file: set works"    "0"        "$rc"
check "empty user file: set writes only the override" '{"launcher":{"position":"anchored"}}' "$(jq -c . <<<"$(user_file)" 2>&1)"
fresh
mkdir -p "$MBM_CONFIG_DIR"
printf ' \n' >"$MBM_CONFIG_DIR/settings.json"
"$MBM" settings check 2>"$T/err"; rc=$?
check "whitespace-only user file: check passes" "0" "$rc"
"$MBM" settings reset .launcher.position 2>"$T/err"; rc=$?
check "whitespace-only user file: reset works" "0" "$rc"

# --- check -------------------------------------------------------------------
bad() { # bad <description> <expected message part> <user-json>
  fresh
  mkdir -p "$MBM_CONFIG_DIR"; printf '%s\n' "$3" >"$MBM_CONFIG_DIR/settings.json"
  local out rc
  out="$("$MBM" settings check 2>&1)"; rc=$?
  check "check: $1 -> exit 1" "1" "$rc"
  contains "check: $1 -> message" "$2" "$out"
}
fresh
check "check: shipped fixture is valid" "" "$("$MBM" settings check 2>&1)"
bad "unknown top-level key" "unknown setting: foo"            '{"foo": 1}'
bad "wrong version"         "version must be 1"               '{"version": 2}'
bad "duplicate combo"       "use the same keys"               '{"binds":{"custom.1":{"mods":"SUPER","key":"return","label":"Dup","group":"Apps","action":{"exec":"true"}}}}'
bad "modifier order doesn't hide a clash" "use the same keys" '{"binds":{"custom.1":{"mods":"ALT","key":"TAB","label":"Dup","group":"Windows","action":{"dispatch":"cyclenext"}}}}'
bad "bad modifier"          "bad modifiers"                   '{"binds":{"shell.launcher":{"mods":"SUPR"}}}'
bad "missing key"           "key is required"                 '{"binds":{"shell.launcher":{"key":""}}}'
bad "comma in label"        "without commas"                  '{"binds":{"shell.launcher":{"label":"Launch, now"}}}'
bad "two action kinds"      "action must be one of"           '{"binds":{"shell.launcher":{"action":{"shell":"launcher.toggle","exec":"x"}}}}'
bad "empty action list"     "action must be one of"           '{"binds":{"windows.next":{"action":[]}}}'
bad "bad flags"             "bad flags"                       '{"binds":{"media.volume-up":{"flags":"xd"}}}'
bad "unknown bind field"    "unknown field colour"            '{"binds":{"shell.launcher":{"colour":"red"}}}'
bad "bad display mode"      "bad mode"                        '{"displays":{"DP-1":{"mode":"huge"}}}'
bad "bad display transform" "bad transform"                   '{"displays":{"DP-1":{"transform":9}}}'
bad "bad bar module"        "unknown module"                  '{"bar":{"left":["workspaces","weather"]}}'
bad "bad launcher position" "launcher.position"               '{"launcher":{"position":"sideways"}}'
bad "bad notification corner" "notifications.corner"          '{"notifications":{"corner":"middle"}}'
bad "lock sooner than dim"  "lockSec must be >= dimSec"       '{"idle":{"dimSec":300,"lockSec":60}}'
bad "negative timeout"      "idle.suspendSec"                 '{"idle":{"suspendSec":-1}}'
bad "repeat rate range"     "input.repeatRate"                '{"input":{"repeatRate":0}}'
bad "touchpad type"         "input.touchpad.naturalScroll"    '{"input":{"touchpad":{"naturalScroll":"yes"}}}'

fresh
"$MBM" settings set '.binds["custom.1"]' '{"mods":"SUPER","key":"SPACE","label":"Dup","group":"Shell","action":{"exec":"true"}}' 2>"$T/err"; rc=$?
check "set: refuses a clash"          "1"        "$rc"
contains "set: clash message"         "use the same keys" "$(cat "$T/err")"
check "set: clash wrote nothing"      ""         "$(user_file)"


# --- check: coverage of every rule ------------------------------------------
bad "mod order doesn't hide a clash" "use the same keys" \
  '{"binds":{"custom.1":{"mods":"SUPER SHIFT","key":"X","label":"A","group":"Apps","action":{"exec":"a"}},"custom.2":{"mods":"SHIFT SUPER","key":"x","label":"B","group":"Apps","action":{"exec":"b"}}}}'
bad "unknown display field"      "displays.DP-1: unknown field colour"  '{"displays":{"DP-1":{"colour":1}}}'
bad "unknown bar field"          "bar: unknown field colour"            '{"bar":{"colour":1}}'
bad "unknown launcher field"     "launcher: unknown field colour"       '{"launcher":{"colour":1}}'
bad "unknown notifications field" "notifications: unknown field colour" '{"notifications":{"colour":1}}'
bad "unknown idle field"         "idle: unknown field colour"           '{"idle":{"colour":1}}'
bad "unknown input field"        "input: unknown field colour"          '{"input":{"colour":1}}'
bad "unknown touchpad field"     "input.touchpad: unknown field colour" '{"input":{"touchpad":{"colour":1}}}'
bad "group required"             "group is required"                    '{"binds":{"shell.launcher":{"group":null}}}'
bad "display position"           "displays.DP-1: bad position"          '{"displays":{"DP-1":{"position":"left"}}}'
bad "display scale"              "displays.DP-1: bad scale"             '{"displays":{"DP-1":{"scale":0}}}'
bad "display enabled"            "displays.DP-1: enabled must be"       '{"displays":{"DP-1":{"enabled":"yes"}}}'
bad "bar position"               "bar.position must be"                 '{"bar":{"position":"left"}}'
bad "bar glyph"                  "bar.glyphs: unknown glyph"            '{"bar":{"glyphs":["wifi"]}}'
bad "bar centre module"          "bar.centre: unknown module"           '{"bar":{"centre":["weather"]}}'
bad "bar right module"           "bar.right: unknown module"            '{"bar":{"right":["weather"]}}'
bad "notification timeout"       "notifications.timeoutMs"              '{"notifications":{"timeoutMs":-5}}'
bad "idle lockOnSleep"           "idle.lockOnSleep"                     '{"idle":{"lockOnSleep":"yes"}}'
bad "repeat delay"               "input.repeatDelay"                    '{"input":{"repeatDelay":5}}'
bad "numlock"                    "input.numlock"                        '{"input":{"numlock":"on"}}'
bad "sensitivity"                "input.sensitivity"                    '{"input":{"sensitivity":2}}'
bad "kbLayout"                   "input.kbLayout"                       '{"input":{"kbLayout":""}}'
bad "kbOptions"                  "input.kbOptions"                      '{"input":{"kbOptions":5}}'
bad "tapToClick"                 "input.touchpad.tapToClick"            '{"input":{"touchpad":{"tapToClick":"yes"}}}'
bad "scrollFactor"               "input.touchpad.scrollFactor"          '{"input":{"touchpad":{"scrollFactor":0}}}'
bad "workspace key 0"            "workspaces: 0 is not a workspace number"   '{"workspaces":{"0":{"monitor":"DP-1"}}}'
bad "workspace key abc"          "workspaces: abc is not a workspace number" '{"workspaces":{"abc":{"monitor":"DP-1"}}}'
bad "workspace key -1"           "workspaces: -1 is not a workspace number"  '{"workspaces":{"-1":{"monitor":"DP-1"}}}'
bad "workspace monitor missing"  "workspaces.5: monitor is required"         '{"workspaces":{"5":{"persistent":true}}}'
bad "workspace monitor empty"    "workspaces.2: monitor is required"         '{"workspaces":{"2":{"monitor":""}}}'
bad "workspace monitor comma"    "workspaces.2: monitor can't contain a comma" '{"workspaces":{"2":{"monitor":"desc:Maker, Model"}}}'
bad "workspace persistent type"  "workspaces.2: persistent must be true or false" '{"workspaces":{"2":{"persistent":"yes"}}}'
bad "workspace unknown field"    "workspaces.2: unknown field default"       '{"workspaces":{"2":{"default":true}}}'
bad "workspace not an object"    "workspaces.7: must be an object"           '{"workspaces":{"7":"DP-1"}}'
bad "unknown wallpaper field"    "wallpaper: unknown field colour"           '{"wallpaper":{"colour":1}}'
bad "wallpaper image type"       "wallpaper.image must be text"              '{"wallpaper":{"image":5}}'
bad "wallpaper monitors type"    "wallpaper.monitors must be an object"      '{"wallpaper":{"monitors":["a"]}}'
bad "wallpaper monitor empty"    "wallpaper.monitors.DP-1: must be a non-empty path" '{"wallpaper":{"monitors":{"DP-1":""}}}'
bad "wallpaper monitor not text" "wallpaper.monitors.DP-1: must be a non-empty path" '{"wallpaper":{"monitors":{"DP-1":3}}}'

good() { # good <description> <user-json>
  fresh
  mkdir -p "$MBM_CONFIG_DIR"; printf '%s\n' "$2" >"$MBM_CONFIG_DIR/settings.json"
  local out rc
  out="$("$MBM" settings check 2>&1)"; rc=$?
  check "check: $1 -> exit 0" "0" "$rc"
  check "check: $1 -> silent" "" "$out"
}
good "wallpaper: image and monitors" '{"wallpaper":{"image":"/home/u/Pictures/Wallpapers/a.png","monitors":{"DP-1":"/x/b.jpg","desc:Acer X34, 1":"/x/c.png"}}}'
good "wallpaper: empty image"  '{"wallpaper":{"image":""}}'
good "code: key"       '{"binds":{"custom.1":{"mods":"SUPER","key":"code:11","label":"A","group":"Apps","action":{"exec":"a"}}}}'
good "mouse: key"      '{"binds":{"custom.1":{"mods":"SUPER","key":"mouse:272","flags":"m","label":"A","group":"Apps","action":{"dispatch":"movewindow"}}}}'
good "switch: key"     '{"binds":{"custom.1":{"mods":"","key":"switch:on:Lid Switch","flags":"l","label":"A","group":"Apps","action":{"exec":"a"}}}}'
good "empty mods"      '{"binds":{"custom.1":{"mods":"","key":"F12","label":"A","group":"Apps","action":{"exec":"a"}}}}'
good "multi-action"    '{"binds":{"custom.1":{"mods":"SUPER","key":"F11","label":"A","group":"Apps","action":[{"exec":"a"},{"dispatch":"cyclenext"}]}}}'
good "workspace: desc monitor with spaces" '{"workspaces":{"3":{"monitor":"desc:Some Maker Model 0x1","persistent":false}}}'
good "workspace: connector name"  '{"workspaces":{"3":{"monitor":"HDMI-A-1"}}}'

# --- apply -------------------------------------------------------------------
fresh
"$MBM" settings apply
check "apply: binds.conf"             "$(cat "$FIX/expected-binds.conf")"    "$(cat "$MBM_HYPR_DIR/binds.conf")"
check "apply: monitors.conf"          "$(cat "$FIX/expected-monitors.conf")" "$(cat "$MBM_HYPR_DIR/monitors.conf")"
check "apply: input.conf"             "$(cat "$FIX/expected-input.conf")"    "$(cat "$MBM_HYPR_DIR/input.conf")"
check "apply: merged state written"   '"centre"' "$(jq .launcher.position "$MBM_STATE_DIR/settings.json")"
check "apply: workspaces.conf"        "$(cat "$FIX/expected-workspaces.conf")" "$(cat "$MBM_HYPR_DIR/workspaces.conf")"

fresh
"$MBM" settings set '.workspaces["2"]' null
"$MBM" settings apply
check "workspaces: null removes it from merged" "false" "$("$MBM" settings get '.workspaces | has("2")')"
check "workspaces: null removes it from the file" "" "$(grep -c 'workspace = 2,' "$MBM_HYPR_DIR/workspaces.conf" | grep -v '^0$')"

fresh
"$MBM" settings set '.workspaces["2"]' '{"monitor":"DP-3","persistent":false}'
"$MBM" settings apply
contains "workspaces: moved (merge is deep, so persistent:false is explicit), its monitor's default" "workspace = 2, monitor:DP-3, default:true" "$(cat "$MBM_HYPR_DIR/workspaces.conf")"
check "workspaces: moved line is exact" "1" "$(grep -cx 'workspace = 2, monitor:DP-3, default:true' "$MBM_HYPR_DIR/workspaces.conf")"

fresh
jq 'del(.workspaces)' "$FIX/defaults.json" >"$T/no-ws.json"
MBM_DEFAULTS="$T/no-ws.json" "$MBM" settings apply 2>"$T/err"; rc=$?
check "workspaces: missing section applies" "0" "$rc"
check "workspaces: missing section -> header only" "# Generated by \`mbm settings apply\`. Do not edit." "$(cat "$MBM_HYPR_DIR/workspaces.conf")"

fresh
"$MBM" settings set '.displays["DP-2"].enabled' false
"$MBM" settings apply
contains "apply: disabled display"    "monitor = DP-2, disable" "$(cat "$MBM_HYPR_DIR/monitors.conf")"

fresh
"$MBM" settings apply
good="$(cat "$MBM_HYPR_DIR/binds.conf")"
mkdir -p "$MBM_CONFIG_DIR"
printf '{"binds":{"x":{"mods":"SUPER","key":"RETURN","label":"Dup","group":"A","action":{"exec":"y"}}}}\n' >"$MBM_CONFIG_DIR/settings.json"
"$MBM" settings apply 2>"$T/err"; rc=$?
check "apply: invalid -> exit 1"      "1"        "$rc"
check "apply: invalid -> old binds kept" "$good" "$(cat "$MBM_HYPR_DIR/binds.conf")"
check "apply: no temp files left"     ""         "$(find "$MBM_HYPR_DIR" "$MBM_STATE_DIR" -name '*.??????' 2>/dev/null)"

# '#' starts a comment in Hyprland config: generated values double it, so a label or
# command keeps its '#' (e.g. a URL fragment) instead of losing the rest of the line.
fresh
"$MBM" settings set '.binds["custom.1"]' '{"mods":"SUPER ALT","key":"F9","label":"Docs #1","group":"Apps","action":{"exec":"xdg-open https://example.com/#x"}}'
"$MBM" settings apply
check "apply: '#' escaped in label and command" "bindd = SUPER ALT, F9, Docs ##1, exec, xdg-open https://example.com/##x" "$(grep ', F9,' "$MBM_HYPR_DIR/binds.conf")"

# hyprctl is only called inside a Hyprland session
fresh
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "$@" >>"%s/hyprctl.log"\n' "$T" >"$T/bin/hyprctl"; chmod +x "$T/bin/hyprctl"
rm -f "$T/hyprctl.log"
PATH="$T/bin:$PATH" "$MBM" settings apply
check "apply: no reload outside Hyprland" "no" "$([[ -e $T/hyprctl.log ]] && echo yes || echo no)"
HYPRLAND_INSTANCE_SIGNATURE=test PATH="$T/bin:$PATH" "$MBM" settings apply
check "apply: reload inside Hyprland" "reload"   "$(cat "$T/hyprctl.log" 2>/dev/null)"
rm -f "$T/hyprctl.log"
HYPRLAND_INSTANCE_SIGNATURE=test MBM_NO_RELOAD=1 PATH="$T/bin:$PATH" "$MBM" settings apply
check "apply: MBM_NO_RELOAD skips reload" "no" "$([[ -e $T/hyprctl.log ]] && echo yes || echo no)"

exit $fail
