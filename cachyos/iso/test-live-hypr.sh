#!/usr/bin/env bash
# The live session's Hyprland config (configs/airootfs/etc/fledge-installer/hyprland.lua),
# run with plain `lua` and a stand-in `hl`: whatever its settings do, the hook that
# starts the installer and ends the session must be registered.
#   bash cachyos/iso/test-live-hypr.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
LIVE="$DIR/configs/airootfs/etc/fledge-installer/hyprland.lua"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# driver <what throws: none|config|monitor|all>: prints what the config did
cat > "$T/driver.lua" <<'EOL'
local throws = arg[2]
local hooks, cmds, notes = {}, {}, 0
local function maybe(name) return function()
  if throws == name or throws == "all" then error(name .. " refused") end
end end
hl = {
  on = function(ev, fn) hooks[ev] = fn end,
  exec_cmd = function(c) cmds[#cmds + 1] = c end,
  config = maybe("config"),
  monitor = maybe("monitor"),
  notification = { create = function() notes = notes + 1 end },
}
dofile(arg[1])
print("hook=" .. tostring(hooks["hyprland.start"] ~= nil))
if hooks["hyprland.start"] then hooks["hyprland.start"]() end
print("cmd=" .. table.concat(cmds, " | "))
print("notes=" .. notes)
EOL
run() { out="$(lua "$T/driver.lua" "$LIVE" "$1" 2>"$T/err")"; rc=$?; }
field() { sed -n "s/^$1=//p" <<<"$out"; }
want_cmd="qs -c fledge-installer; hyprctl dispatch 'hl.dsp.exit()'"

run none
check "settings accepted: runs" 0 "$rc"
check "settings accepted: start hook registered" "true" "$(field hook)"
check "settings accepted: it starts the installer, then ends the session" "$want_cmd" "$(field cmd)"
check "settings accepted: no notification" 0 "$(field notes)"

for t in config monitor all; do
  run "$t"
  check "$t throws: no error escapes" 0 "$rc"
  check "$t throws: start hook still registered" "true" "$(field hook)"
  check "$t throws: the installer still starts" "$want_cmd" "$(field cmd)"
  contains "$t throws: said on stderr (the log)" "fledge-installer: " "$(cat "$T/err")"
done
check "both throw: one notification each" 2 "$(run all; field notes)"

# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
