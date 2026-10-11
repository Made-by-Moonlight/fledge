#!/usr/bin/env bash
# Tests for dev/bind-parity.sh with small hand-written `hyprctl binds -j` dumps.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
PAR="$HERE/../dev/bind-parity.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# bind MODMASK KEY SUBMAP DISPATCHER ARG [DESCRIPTION]: one hyprctl-style entry.
bind() {
  jq -cn --argjson m "$1" --arg k "$2" --arg s "$3" --arg d "$4" --arg a "$5" --arg desc "${6:-}" \
    '{locked:false,mouse:false,release:false,repeat:false,longPress:false,non_consuming:false,
      auto_consuming:false,has_description:($desc != ""),modmask:$m,submap:$s,submap_universal:"false",
      key:$k,keycode:0,catch_all:false,description:$desc,allow_input_capture:false,dispatcher:$d,arg:$a}'
}
dump() { jq -s . ; }
run() { "$PAR" "$T/before.json" "$T/after.json" >/dev/null 2>"$T/err"; echo $?; }

{ bind 64 SPACE "" exec "walker" "Launch"
  bind 64 W "" killactive ""
  bind 8 TAB "" cyclenext ""
  bind 8 TAB "" bringactivetotop ""
  bind 0 XF86AudioMute "" exec "swayosd-client --output-volume mute-toggle"
} | dump >"$T/before.json"

cp "$T/before.json" "$T/after.json"
check "parity: identical dumps -> 0" 0 "$(run)"

# Allowed remap, description text and key case differ cosmetically.
{ bind 64 SPACE "" exec "qs -c mbm ipc call launcher toggle" "Apps"
  bind 64 w "" killactive "" "Close"
  bind 8 TAB "" bringactivetotop ""
  bind 8 TAB "" cyclenext ""
  bind 0 XF86AudioMute "" exec "qs -c mbm ipc call osd volume mute"
  bind 64 A "" exec "qs -c mbm ipc call quicksettings toggle"
  bind 76 Escape mbm-record submap reset
} | dump >"$T/after.json"
check "parity: allowed remaps, listed adds, multiset order -> 0" 0 "$(run)"

# A dropped walker bind (the old regex would have hidden this).
{ bind 64 W "" killactive ""
  bind 8 TAB "" cyclenext ""
  bind 8 TAB "" bringactivetotop ""
  bind 0 XF86AudioMute "" exec "qs -c mbm ipc call osd volume mute"
  bind 64 A "" exec "qs -c mbm ipc call quicksettings toggle"
  bind 76 Escape mbm-record submap reset
} | dump >"$T/after.json"
check "parity: dropped walker bind -> 1" 1 "$(run)"
check "parity: names the dropped combo" "true" "$(grep -q 'mod 64 key space: bind dropped' "$T/err" && echo true || echo false)"

# The remap moved to a different key.
{ bind 64 X "" exec "qs -c mbm ipc call launcher toggle"
  bind 64 W "" killactive ""
  bind 8 TAB "" cyclenext ""
  bind 8 TAB "" bringactivetotop ""
  bind 0 XF86AudioMute "" exec "qs -c mbm ipc call osd volume mute"
  bind 64 A "" exec "qs -c mbm ipc call quicksettings toggle"
  bind 76 Escape mbm-record submap reset
} | dump >"$T/after.json"
check "parity: remap moved to another key -> 1" 1 "$(run)"

# An added combo that is not in the allow list.
{ bind 64 SPACE "" exec "qs -c mbm ipc call launcher toggle"
  bind 64 W "" killactive ""
  bind 8 TAB "" cyclenext ""
  bind 8 TAB "" bringactivetotop ""
  bind 0 XF86AudioMute "" exec "qs -c mbm ipc call osd volume mute"
  bind 64 A "" exec "qs -c mbm ipc call quicksettings toggle"
  bind 76 Escape mbm-record submap reset
  bind 64 Q "" exec "qs -c mbm ipc call lock lock"
} | dump >"$T/after.json"
check "parity: unlisted added combo -> 1" 1 "$(run)"

# The submap exit bind lost.
{ bind 64 SPACE "" exec "qs -c mbm ipc call launcher toggle"
  bind 64 W "" killactive ""
  bind 8 TAB "" cyclenext ""
  bind 8 TAB "" bringactivetotop ""
  bind 0 XF86AudioMute "" exec "qs -c mbm ipc call osd volume mute"
  bind 64 A "" exec "qs -c mbm ipc call quicksettings toggle"
} | dump >"$T/after.json"
# (the listed add is allowed to be absent; losing the submap bind must still be caught when present before)
{ cat "$T/before.json" | jq -c '.[]'; bind 76 Escape mbm-record submap reset; } | dump >"$T/before.json.2"
mv "$T/before.json.2" "$T/before.json"
check "parity: lost submap bind -> 1" 1 "$(run)"

# A non-ipc replacement on a shared combo, and a changed flag.
{ bind 64 SPACE "" exec "walker"
  bind 64 W "" exec "rm -rf ~"
  bind 8 TAB "" cyclenext ""
  bind 8 TAB "" bringactivetotop ""
  bind 0 XF86AudioMute "" exec "swayosd-client --output-volume mute-toggle"
  bind 76 Escape mbm-record submap reset
} | dump >"$T/after.json"
check "parity: arbitrary replacement on a shared combo -> 1" 1 "$(run)"

check "parity: wrong arg count -> 2" 2 "$("$PAR" "$T/before.json" >/dev/null 2>&1; echo $?)"

# The live pre-cutover dump compared with itself.
"$PAR" "$HERE/fixtures/binds-before.json" "$HERE/fixtures/binds-before.json" >/dev/null 2>&1
check "parity: binds-before vs itself -> 0" 0 "$?"
exit $fail
