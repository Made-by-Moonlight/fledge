#!/usr/bin/env bash
# Tests for `fledge settings`. Every run uses a temp HOME and env-overridden
# paths; nothing outside the temp dir is read or written (except the repo).
# Run in the VM:  cachyos/vm/vm.sh run 'bash ~/proj/fledge/dot-local/share/fledge/test/test-settings.sh'
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
FLEDGE="$HERE/../bin/fledge"
FIX="$HERE/fixtures"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fresh() { # fresh [defaults.json]: empty temp HOME with all settings paths inside it
  rm -rf "${T:?}/home"
  export HOME="$T/home"
  export FLEDGE_DEFAULTS="${1:-$FIX/defaults.json}"
  export FLEDGE_CONFIG_DIR="$HOME/.config/fledge" FLEDGE_STATE_DIR="$HOME/.local/state/fledge" FLEDGE_HYPR_DIR="$HOME/.local/state/fledge/hypr"
  unset HYPRLAND_INSTANCE_SIGNATURE FLEDGE_NO_RELOAD
  mkdir -p "$HOME"
}
user_file() { cat "$FLEDGE_CONFIG_DIR/settings.json" 2>/dev/null; }

# --- get -------------------------------------------------------------------
fresh
check "get: default value"            '"centre"' "$("$FLEDGE" settings get .launcher.position)"
check "get: no user file is created"  "no"       "$([[ -e $FLEDGE_CONFIG_DIR/settings.json ]] && echo yes || echo no)"
check "get: bind by id"               '"SPACE"'  "$("$FLEDGE" settings get '.binds["shell.launcher"].key')"

# --- set -------------------------------------------------------------------
fresh
"$FLEDGE" settings set .launcher.position '"anchored"'
check "set: merged value"             '"anchored"' "$("$FLEDGE" settings get .launcher.position)"
check "set: user file has only the override" '{"launcher":{"position":"anchored"}}' "$(jq -c . <<<"$(user_file)")"
check "set: merged state refreshed"   '"anchored"' "$(jq .launcher.position "$FLEDGE_STATE_DIR/settings.json")"

fresh
"$FLEDGE" settings set '.binds["shell.launcher"].key' '"D"' .notifications.timeoutMs 8000
check "set: several pairs at once"    '"D" 8000' "$("$FLEDGE" settings get '.binds["shell.launcher"].key') $("$FLEDGE" settings get .notifications.timeoutMs)"
check "set: rest of the bind kept"    '"SUPER"'  "$("$FLEDGE" settings get '.binds["shell.launcher"].mods')"

fresh
"$FLEDGE" settings set .launcher.position '"anchored"'
before="$(user_file)"
"$FLEDGE" settings set '.foo; halt' '1' 2>"$T/err"; rc=$?
check "set: bad path refused"         "1"        "$rc"
contains "set: bad path message"      "bad settings path" "$(cat "$T/err")"
"$FLEDGE" settings set .launcher.position 'not json' 2>"$T/err"; rc=$?
check "set: non-JSON refused"         "1"        "$rc"
check "set: refused writes nothing"   "$before"  "$(user_file)"
"$FLEDGE" settings set .launcher 2>/dev/null; rc=$?
check "set: odd argument count refused" "1"      "$rc"

fresh
"$FLEDGE" settings set '.wallpaper.monitors["DP-"1"]' '"/x/a.png"' 2>"$T/err"; rc=$?
check "set: monitor key with a quote refused" "1" "$rc"
contains "set: monitor key with a quote message" "bad settings path" "$(cat "$T/err")"
check "set: refused monitor key wrote nothing" "" "$(user_file)"

# --- reset -----------------------------------------------------------------
fresh
"$FLEDGE" settings set .launcher.position '"anchored"' .bar.position '"bottom"'
"$FLEDGE" settings reset .launcher.position
check "reset: back to default"        '"centre"' "$("$FLEDGE" settings get .launcher.position)"
check "reset: other override kept"    '"bottom"' "$("$FLEDGE" settings get .bar.position)"

# --- removing a default bind with null --------------------------------------
fresh
"$FLEDGE" settings set '.binds["apps.terminal"]' null
check "null bind: removed from merged" "false"   "$("$FLEDGE" settings get '.binds | has("apps.terminal")')"
"$FLEDGE" settings reset '.binds["apps.terminal"]'
check "null bind: reset restores it"  "true"     "$("$FLEDGE" settings get '.binds | has("apps.terminal")')"

# --- broken user file (Review Focus 1) --------------------------------------
fresh
"$FLEDGE" settings set .launcher.position '"anchored"'
good_state="$(cat "$FLEDGE_STATE_DIR/settings.json")"
printf '{ "launcher": ' >"$FLEDGE_CONFIG_DIR/settings.json"
"$FLEDGE" settings get . >/dev/null 2>"$T/err"; rc=$?
check "broken user file: get fails"   "1"        "$rc"
contains "broken user file: message names the file" "settings.json is not a valid JSON object" "$(cat "$T/err")"
check "broken user file: merged state untouched" "$good_state" "$(cat "$FLEDGE_STATE_DIR/settings.json")"

# --- empty user file: no overrides, not a broken file ---------------------------
fresh
mkdir -p "$FLEDGE_CONFIG_DIR"
: >"$FLEDGE_CONFIG_DIR/settings.json"
check "empty user file: get reads defaults" '"centre"' "$("$FLEDGE" settings get .launcher.position 2>&1)"
"$FLEDGE" settings set .launcher.position '"anchored"' 2>"$T/err"; rc=$?
check "empty user file: set works"    "0"        "$rc"
check "empty user file: set writes only the override" '{"launcher":{"position":"anchored"}}' "$(jq -c . <<<"$(user_file)" 2>&1)"
fresh
mkdir -p "$FLEDGE_CONFIG_DIR"
printf ' \n' >"$FLEDGE_CONFIG_DIR/settings.json"
"$FLEDGE" settings check 2>"$T/err"; rc=$?
check "whitespace-only user file: check passes" "0" "$rc"
"$FLEDGE" settings reset .launcher.position 2>"$T/err"; rc=$?
check "whitespace-only user file: reset works" "0" "$rc"

# --- check -------------------------------------------------------------------
bad() { # bad <description> <expected message part> <user-json>
  fresh
  mkdir -p "$FLEDGE_CONFIG_DIR"; printf '%s\n' "$3" >"$FLEDGE_CONFIG_DIR/settings.json"
  local out rc
  out="$("$FLEDGE" settings check 2>&1)"; rc=$?
  check "check: $1 -> exit 1" "1" "$rc"
  contains "check: $1 -> message" "$2" "$out"
}
fresh
check "check: shipped fixture is valid" "" "$("$FLEDGE" settings check 2>&1)"
bad "unknown top-level key" "unknown setting: foo"            '{"foo": 1}'
bad "wrong version"         "version must be 2"               '{"version": 3}'
bad "duplicate combo"       "use the same keys"               '{"binds":{"custom.1":{"mods":"SUPER","key":"return","label":"Dup","group":"Apps","action":{"exec":"true"}}}}'
bad "modifier order doesn't hide a clash" "use the same keys" '{"binds":{"custom.1":{"mods":"ALT","key":"TAB","label":"Dup","group":"Windows","action":{"dsp":"window.cycle_next"}}}}'
bad "bad modifier"          "bad modifiers"                   '{"binds":{"shell.launcher":{"mods":"SUPR"}}}'
bad "missing key"           "key is required"                 '{"binds":{"shell.launcher":{"key":""}}}'
bad "comma in label"        "without commas"                  '{"binds":{"shell.launcher":{"label":"Launch, now"}}}'
bad "two action kinds"      "action must be one of"           '{"binds":{"shell.launcher":{"action":{"shell":"launcher.toggle","exec":"x"}}}}'
bad "empty action list"     "action must be one of"           '{"binds":{"windows.next":{"action":[]}}}'
bad "bad flags"             "bad flags"                       '{"binds":{"media.volume-up":{"flags":"xd"}}}'
bad "s flag refused"        "flag s (separate keysyms) has no Lua equivalent" '{"binds":{"media.volume-up":{"flags":"els"}}}'
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
"$FLEDGE" settings set '.binds["custom.1"]' '{"mods":"SUPER","key":"SPACE","label":"Dup","group":"Shell","action":{"exec":"true"}}' 2>"$T/err"; rc=$?
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
bad "clock format too big"       "bar.clockFormat must be"              '{"bar":{"clockFormat":4}}'
bad "clock format negative"      "bar.clockFormat must be"              '{"bar":{"clockFormat":-1}}'
bad "clock format fractional"    "bar.clockFormat must be"              '{"bar":{"clockFormat":1.5}}'
bad "clock format text"          "bar.clockFormat must be"              '{"bar":{"clockFormat":"2"}}'
bad "bar height too small"       "bar.height must be a whole number from 20 to 48" '{"bar":{"height":19}}'
bad "bar height too big"         "bar.height must be a whole number from 20 to 48" '{"bar":{"height":49}}'
bad "bar height fractional"      "bar.height must be a whole number from 20 to 48" '{"bar":{"height":32.5}}'
bad "bar height text"            "bar.height must be a whole number from 20 to 48" '{"bar":{"height":"32"}}'
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
bad "kbVariant"                  "input.kbVariant"                      '{"input":{"kbVariant":5}}'
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
bad "wallpaper monitor key with a quote" "wallpaper.monitors: monitor name can't contain a quote or backslash" '{"wallpaper":{"monitors":{"DP-\"1":"/x/a.png"}}}'
bad "wallpaper monitor key with a backslash" "wallpaper.monitors: monitor name can't contain a quote or backslash" '{"wallpaper":{"monitors":{"DP-\\1":"/x/a.png"}}}'
bad "unknown wallpaper field"    "wallpaper: unknown field colour"           '{"wallpaper":{"colour":1}}'
bad "wallpaper image type"       "wallpaper.image must be text"              '{"wallpaper":{"image":5}}'
bad "wallpaper monitors type"    "wallpaper.monitors must be an object"      '{"wallpaper":{"monitors":["a"]}}'
bad "wallpaper monitor empty"    "wallpaper.monitors.DP-1: must be a non-empty path (or moonrise)" '{"wallpaper":{"monitors":{"DP-1":""}}}'
bad "wallpaper monitor not text" "wallpaper.monitors.DP-1: must be a non-empty path (or moonrise)" '{"wallpaper":{"monitors":{"DP-1":3}}}'

good() { # good <description> <user-json>
  fresh
  mkdir -p "$FLEDGE_CONFIG_DIR"; printf '%s\n' "$2" >"$FLEDGE_CONFIG_DIR/settings.json"
  local out rc
  out="$("$FLEDGE" settings check 2>&1)"; rc=$?
  check "check: $1 -> exit 0" "0" "$rc"
  check "check: $1 -> silent" "" "$out"
}
good "wallpaper: image and monitors" '{"wallpaper":{"image":"/home/u/Pictures/Wallpapers/a.png","monitors":{"DP-1":"/x/b.jpg","desc:Acer X34, 1":"/x/c.png"}}}'
good "wallpaper: empty image"  '{"wallpaper":{"image":""}}'
good "wallpaper: moonrise sentinel for a monitor" '{"wallpaper":{"image":"/x/a.png","monitors":{"DP-1":"moonrise"}}}'
good "bar height 20"   '{"bar":{"height":20}}'
good "bar height 48"   '{"bar":{"height":48}}'
fresh "$REPO/dot-local/share/fledge/defaults/settings.json"
check "bar.height: shipped default" 32 "$("$FLEDGE" settings get .bar.height)"
good "clock format 0"  '{"bar":{"clockFormat":0}}'
good "clock format 3"  '{"bar":{"clockFormat":3}}'
good "code: key"       '{"binds":{"custom.1":{"mods":"SUPER","key":"code:11","label":"A","group":"Apps","action":{"exec":"a"}}}}'
good "mouse: key"      '{"binds":{"custom.1":{"mods":"SUPER","key":"mouse:272","flags":"m","label":"A","group":"Apps","action":{"dsp":"window.drag"}}}}'
good "switch: key"     '{"binds":{"custom.1":{"mods":"","key":"switch:on:Lid Switch","flags":"l","label":"A","group":"Apps","action":{"exec":"a"}}}}'
good "empty mods"      '{"binds":{"custom.1":{"mods":"","key":"F12","label":"A","group":"Apps","action":{"exec":"a"}}}}'
good "multi-action"    '{"binds":{"custom.1":{"mods":"SUPER","key":"F11","label":"A","group":"Apps","action":[{"exec":"a"},{"dsp":"window.cycle_next"}]}}}'
good "workspace: desc monitor with spaces" '{"workspaces":{"3":{"monitor":"desc:Some Maker Model 0x1","persistent":false}}}'
good "workspace: connector name"  '{"workspaces":{"3":{"monitor":"HDMI-A-1"}}}'
bad "display key with a comma" "displays: monitor name can't contain a comma" '{"displays":{"desc:Acer X34, 1":{"mode":"preferred"}}}'
bad "empty display key" "displays: monitor name can't be empty" '{"displays":{"":{"mode":"preferred"}}}'
good "display by description" '{"displays":{"desc:Acer Technologies X34 GS 0x1240460A":{"mode":"3440x1440@180","position":"0x0","scale":1}}}'

# --- apply -------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/luacheck.sh
source "$REPO/cachyos/install/test/luacheck.sh"
LUA="$(command -v lua || command -v lua5.5 || command -v lua5.4)"
stub() { "$LUA" "$HERE/hl-stub.lua" "$@" 2>&1; } # what the generated Lua calls (see hl-stub.lua)
# The hl.bind call binding <keys>, out of its try("<keys>", function() … end) guard.
bindline() { grep -F "try(\"$1\"," "$FLEDGE_HYPR_DIR/binds.lua" | sed -E 's/^try\("[^"]*", function\(\) (.*) end\)$/\1/'; }

fresh
"$FLEDGE" settings apply
check "apply: binds.lua"              "$(cat "$FIX/expected-binds.lua")"    "$(cat "$FLEDGE_HYPR_DIR/binds.lua")"
check "apply: monitors.lua"           "$(cat "$FIX/expected-monitors.lua")" "$(cat "$FLEDGE_HYPR_DIR/monitors.lua")"
# Connector rules first, desc: rules after, catch-all last (see gen-monitors.jq).
fresh
mkdir -p "$FLEDGE_CONFIG_DIR"
printf '%s\n' '{"displays":{"desc:Z":{"scale":2},"eDP-1":{"scale":1}}}' >"$FLEDGE_CONFIG_DIR/settings.json"
"$FLEDGE" settings apply
order="$(grep -o 'output = "[^"]*"' "$FLEDGE_HYPR_DIR/monitors.lua" | tr '\n' ' ')"
check "apply: connector rules before desc: rules, catch-all last" 'output = "DP-1" output = "DP-2" output = "eDP-1" output = "desc:Z" output = "" ' "$order"
fresh
"$FLEDGE" settings apply

check "apply: input.lua"              "$(cat "$FIX/expected-input.lua")"    "$(cat "$FLEDGE_HYPR_DIR/input.lua")"
check "apply: merged state written"   '"centre"' "$(jq .launcher.position "$FLEDGE_STATE_DIR/settings.json")"
check "apply: workspaces.lua"         "$(cat "$FIX/expected-workspaces.lua")" "$(cat "$FLEDGE_HYPR_DIR/workspaces.lua")"
check "apply: no .conf written"       ""         "$(find "$FLEDGE_HYPR_DIR" -name '*.conf')"
for f in binds monitors workspaces input; do
  lua_syntax_ok "$FLEDGE_HYPR_DIR/$f.lua"; check "apply: $f.lua parses (luac -p)" 0 "$?"
done
for f in binds monitors workspaces input; do
  stub "$FLEDGE_HYPR_DIR/$f.lua" >/dev/null; check "apply: $f.lua runs against the hl stub" 0 "$?"
done
check "apply: one hl.bind per settings bind, plus the submap's" \
  "$(($(jq '.binds | length' "$FIX/defaults.json") + 1))" "$(stub "$FLEDGE_HYPR_DIR/binds.lua" | grep -c '^bind')"
check "apply: submap bind" "bind@fledge-record	SUPER + CTRL + ALT + Escape	dsp.submap(reset)	nil" \
  "$(stub "$FLEDGE_HYPR_DIR/binds.lua" | grep '^bind@')"
check "apply: action list is one function bind" \
  "bind	ALT + TAB	fn[dsp.window.cycle_next(); dsp.window.bring_to_top()]	{description=Focus on next window}" \
  "$(stub "$FLEDGE_HYPR_DIR/binds.lua" | grep 'ALT + TAB')"
check "apply: no notification when every bind loads" "" "$(stub "$FLEDGE_HYPR_DIR/binds.lua" | grep '^notify')"
# A dispatcher Hyprland doesn't have (renamed in a release, say) costs only its
# own bind: the rest still load, and one notification names what didn't.
out="$(HL_STUB_MISSING=window.resize stub "$FLEDGE_HYPR_DIR/binds.lua")"; rc=$?
check "missing dispatcher: binds.lua still runs to the end" 0 "$rc"
check "missing dispatcher: every other bind registered (all but one, plus the submap's)" \
  "$(jq '.binds | length' "$FIX/defaults.json")" "$(grep -c '^bind' <<<"$out")"
check "missing dispatcher: the submap still defined" 1 "$(grep -c '^bind@fledge-record' <<<"$out")"
check "missing dispatcher: one notification" 1 "$(grep -c '^notify' <<<"$out")"
contains "missing dispatcher: it names the bind" "fledge: binds.lua: these binds didn't load: SUPER + mouse:273 (" "$(grep '^notify' <<<"$out")"
contains "missing dispatcher: shown as an error" "color=rgb(ff5555) icon=error" "$(grep '^notify' <<<"$out")"
check "missing dispatcher: said on stderr too" 1 "$(grep -c "^fledge: binds.lua: these binds didn't load: SUPER + mouse:273 (" <<<"$out")"
check "apply: mouse bind"   'hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { description = "Resize window" })' "$(bindline "SUPER + mouse:273")"
check "apply: empty mods -> just the key" \
  'hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("qs -c fledge ipc call osd volume +5"), { description = "Volume up", locked = true, repeating = true })' \
  "$(bindline XF86AudioRaiseVolume)"

# Stale .conf fragments (from before the Lua config) go; anything else stays.
fresh
mkdir -p "$FLEDGE_HYPR_DIR"
for f in binds monitors workspaces input; do echo old >"$FLEDGE_HYPR_DIR/$f.conf"; done
echo mine >"$FLEDGE_HYPR_DIR/notes.txt"
"$FLEDGE" settings apply
check "apply: old .conf fragments removed" "" "$(find "$FLEDGE_HYPR_DIR" -name '*.conf')"
check "apply: other files kept"        "mine" "$(cat "$FLEDGE_HYPR_DIR/notes.txt")"

# Each flag letter maps to one hl.bind option ('m' has none: see gen-binds.jq; 's' is refused, above).
fresh
u='{"binds":{}}'; n=0
for l in e l r n t i p m; do
  n=$((n + 1))
  u="$(jq --arg l "$l" --arg k "F$n" '.binds["custom.\($l)"] = {mods:"SUPER CTRL ALT", key:$k, flags:$l, label:"Flag \($l)", group:"Apps", action:{exec:"true"}}' <<<"$u")"
done
mkdir -p "$FLEDGE_CONFIG_DIR"; printf '%s\n' "$u" >"$FLEDGE_CONFIG_DIR/settings.json"
"$FLEDGE" settings apply
n=0
for l in e:repeating l:locked r:release n:non_consuming t:transparent i:ignore_mods p:dont_inhibit m:; do
  n=$((n + 1)); opt="${l#*:}"; l="${l%%:*}"
  check "flag $l -> ${opt:-no option}" \
    "hl.bind(\"SUPER + CTRL + ALT + F$n\", hl.dsp.exec_cmd(\"true\"), { description = \"Flag $l\"${opt:+, $opt = true} })" \
    "$(bindline "SUPER + CTRL + ALT + F$n")"
done
lua_syntax_ok "$FLEDGE_HYPR_DIR/binds.lua"; check "flags: binds.lua parses" 0 "$?"

# Strings are Lua literals: \ " and newlines are escaped, '#' and '$' are plain
# characters (the .conf '##' escaping is gone). Running the file must give back
# exactly the command that was set.
fresh
cmd=$'printf "%s\\n" \'a\\b\' "#x" "$HOME"\nnotify-send done\ttab'
"$FLEDGE" settings set '.binds["custom.1"]' "$(jq -n --arg c "$cmd" '{mods:"SUPER ALT", key:"F9", label:"Docs #1 \"q\"", group:"Apps", action:{exec:$c}}')"
"$FLEDGE" settings apply
lua_syntax_ok "$FLEDGE_HYPR_DIR/binds.lua"; check "escaping: binds.lua parses" 0 "$?"
check "escaping: rendered literal" \
  'hl.bind("SUPER + ALT + F9", hl.dsp.exec_cmd("printf \"%s\\n\" '"'"'a\\b'"'"' \"#x\" \"$HOME\"\nnotify-send done\009tab"), { description = "Docs #1 \"q\"" })' \
  "$(bindline "SUPER + ALT + F9")"
check "escaping: the command survives a round trip through Lua" \
  "bind	SUPER + ALT + F9	dsp.exec_cmd($cmd)	{description=Docs #1 \"q\"}" \
  "$(stub "$FLEDGE_HYPR_DIR/binds.lua" | awk '/^bind\tSUPER \+ ALT \+ F9\t/{p=1} p && /^bind/ && !/F9/{p=0} p')"

# dsp args: an object becomes a table (sorted keys; keys that aren't Lua names,
# reserved words included, are bracketed); a plain value is one positional argument.
fresh
"$FLEDGE" settings set \
  '.binds["custom.1"]' '{"mods":"SUPER ALT","key":"F1","label":"A","group":"Apps","action":{"dsp":"layout","args":"togglesplit"}}' \
  '.binds["custom.2"]' '{"mods":"SUPER ALT","key":"F2","label":"B","group":"Apps","action":{"dsp":"window.cycle_next","args":false}}' \
  '.binds["custom.3"]' '{"mods":"SUPER ALT","key":"F3","label":"C","group":"Apps","action":{"dsp":"window.resize","args":{"x":-10,"y":0.5,"relative":true}}}' \
  '.binds["custom.4"]' '{"mods":"SUPER ALT","key":"F4","label":"D","group":"Apps","action":{"dsp":"focus","args":{"end":1,"a-b":"x","_ok":"\"y\""}}}'
"$FLEDGE" settings apply
check "dsp: positional text"  'hl.bind("SUPER + ALT + F1", hl.dsp.layout("togglesplit"), { description = "A" })' "$(bindline "SUPER + ALT + F1")"
check "dsp: positional bool"  'hl.bind("SUPER + ALT + F2", hl.dsp.window.cycle_next(false), { description = "B" })' "$(bindline "SUPER + ALT + F2")"
check "dsp: table args"       'hl.bind("SUPER + ALT + F3", hl.dsp.window.resize({ relative = true, x = -10, y = 0.5 }), { description = "C" })' "$(bindline "SUPER + ALT + F3")"
check "dsp: odd table keys"   'hl.bind("SUPER + ALT + F4", hl.dsp.focus({ _ok = "\"y\"", ["a-b"] = "x", ["end"] = 1 }), { description = "D" })' "$(bindline "SUPER + ALT + F4")"
lua_syntax_ok "$FLEDGE_HYPR_DIR/binds.lua"; check "dsp: binds.lua parses" 0 "$?"
check "dsp: args reach the dispatcher" "dsp.focus({_ok=\"y\" a-b=x end=1})" \
  "$(stub "$FLEDGE_HYPR_DIR/binds.lua" | grep 'SUPER + ALT + F4' | cut -f3)"

fresh
mkdir -p "$FLEDGE_CONFIG_DIR"; printf '{"input":{"kbLayout":"gb","kbVariant":"extd"}}\n' >"$FLEDGE_CONFIG_DIR/settings.json"
FLEDGE_NO_RELOAD=1 "$FLEDGE" settings apply >/dev/null
contains "input: variant rendered" 'kb_variant = "extd"' "$(cat "$FLEDGE_HYPR_DIR/input.lua")"
contains "input: layout rendered"  'kb_layout = "gb"'    "$(cat "$FLEDGE_HYPR_DIR/input.lua")"

fresh
"$FLEDGE" settings set '.workspaces["2"]' null
"$FLEDGE" settings apply
check "workspaces: null removes it from merged" "false" "$("$FLEDGE" settings get '.workspaces | has("2")')"
check "workspaces: null removes it from the file" "0" "$(grep -c 'workspace = "2"' "$FLEDGE_HYPR_DIR/workspaces.lua")"

fresh
"$FLEDGE" settings set '.workspaces["2"]' '{"monitor":"DP-3","persistent":false}'
"$FLEDGE" settings apply
check "workspaces: moved (merge is deep, so persistent:false is explicit), its monitor's default" "1" \
  "$(grep -cxF 'hl.workspace_rule({ default = true, monitor = "DP-3", workspace = "2" })' "$FLEDGE_HYPR_DIR/workspaces.lua")"

fresh
jq 'del(.workspaces)' "$FIX/defaults.json" >"$T/no-ws.json"
FLEDGE_DEFAULTS="$T/no-ws.json" "$FLEDGE" settings apply 2>"$T/err"; rc=$?
check "workspaces: missing section applies" "0" "$rc"
check "workspaces: missing section -> header only" "-- Generated by \`fledge settings apply\`. Do not edit." "$(cat "$FLEDGE_HYPR_DIR/workspaces.lua")"
lua_syntax_ok "$FLEDGE_HYPR_DIR/workspaces.lua"; check "workspaces: header-only file parses" 0 "$?"

fresh
"$FLEDGE" settings set '.displays["DP-2"].enabled' false
"$FLEDGE" settings apply
check "apply: disabled display" 'hl.monitor({ disabled = true, output = "DP-2" })' "$(grep -F '"DP-2"' "$FLEDGE_HYPR_DIR/monitors.lua")"
check "apply: disabled display reaches hl.monitor" "monitor	{disabled=true output=DP-2}" "$(stub "$FLEDGE_HYPR_DIR/monitors.lua" | grep DP-2)"

fresh
"$FLEDGE" settings apply
good="$(cat "$FLEDGE_HYPR_DIR/binds.lua")"
mkdir -p "$FLEDGE_CONFIG_DIR"
printf '{"binds":{"x":{"mods":"SUPER","key":"RETURN","label":"Dup","group":"A","action":{"exec":"y"}}}}\n' >"$FLEDGE_CONFIG_DIR/settings.json"
"$FLEDGE" settings apply 2>"$T/err"; rc=$?
check "apply: invalid -> exit 1"      "1"        "$rc"
check "apply: invalid -> old binds kept" "$good" "$(cat "$FLEDGE_HYPR_DIR/binds.lua")"
check "apply: no temp files left"     ""         "$(find "$FLEDGE_HYPR_DIR" "$FLEDGE_STATE_DIR" -name '*.??????' 2>/dev/null)"

# A writer waits for the settings lock, but not for ever: a hung holder must not
# stall login (env-hyprland runs apply).
fresh
mkdir -p "$FLEDGE_CONFIG_DIR"
flock "$FLEDGE_CONFIG_DIR/.lock" -c "touch '$T/held'; sleep 5" &
holder=$!
for _ in $(seq 50); do [[ -e $T/held ]] && break; sleep 0.1; done
start=$SECONDS
FLEDGE_LOCK_TIMEOUT=1 "$FLEDGE" settings set .launcher.position '"anchored"' 2>"$T/err"; rc=$?
check "lock: busy -> exit 1"          "1"        "$rc"
contains "lock: busy message"         "another fledge settings command holds" "$(cat "$T/err")"
check "lock: gave up within the timeout" "yes"   "$( ((SECONDS - start <= 3)) && echo yes || echo no)"
check "lock: busy -> nothing written" ""         "$(user_file)"
pkill -P "$holder" 2>/dev/null; kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; rm -f "$T/held"

for bad_wait in abc -1 1.5 ""; do
  fresh
  FLEDGE_LOCK_TIMEOUT="$bad_wait" "$FLEDGE" settings set .launcher.position '"anchored"' 2>"$T/err"; rc=$?
  if [[ -z $bad_wait ]]; then
    check "lock: empty FLEDGE_LOCK_TIMEOUT -> default wait" "0" "$rc"
  else
    check "lock: FLEDGE_LOCK_TIMEOUT=$bad_wait -> exit 1" "1" "$rc"
    contains "lock: FLEDGE_LOCK_TIMEOUT=$bad_wait -> message" "FLEDGE_LOCK_TIMEOUT must be a whole number of seconds" "$(cat "$T/err")"
    check "lock: FLEDGE_LOCK_TIMEOUT=$bad_wait -> nothing written" "" "$(user_file)"
  fi
done
FLEDGE_LOCK_TIMEOUT=0 "$FLEDGE" settings set .launcher.position '"anchored"' 2>"$T/err"
check "lock: FLEDGE_LOCK_TIMEOUT=0 accepted" "0" "$?"

# hyprctl is only called inside a Hyprland session
fresh
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "$@" >>"%s/hyprctl.log"\n' "$T" >"$T/bin/hyprctl"; chmod +x "$T/bin/hyprctl"
rm -f "$T/hyprctl.log"
PATH="$T/bin:$PATH" "$FLEDGE" settings apply
check "apply: no reload outside Hyprland" "no" "$([[ -e $T/hyprctl.log ]] && echo yes || echo no)"
HYPRLAND_INSTANCE_SIGNATURE=test PATH="$T/bin:$PATH" "$FLEDGE" settings apply
check "apply: reload inside Hyprland" "reload"   "$(cat "$T/hyprctl.log" 2>/dev/null)"
rm -f "$T/hyprctl.log"
HYPRLAND_INSTANCE_SIGNATURE=test FLEDGE_NO_RELOAD=1 PATH="$T/bin:$PATH" "$FLEDGE" settings apply
check "apply: FLEDGE_NO_RELOAD skips reload" "no" "$([[ -e $T/hyprctl.log ]] && echo yes || echo no)"

exit $fail
