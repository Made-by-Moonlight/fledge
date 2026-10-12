#!/usr/bin/env bash
# End-to-end checks for the mbm shell, run inside the logged-in Hyprland
# session (needs wtype; types the account password for the lock checks):
#   cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/cachyos/iso/test/verify-shell.sh'
# Never suspends: lock-before-sleep can't be exercised in the VM.
set -uo pipefail

PASSWORD="${VM_PASSWORD:-TestPass1}"
# Over ssh the locale is "C", and qs prints a Qt locale warning on stdout.
export LC_ALL=C.UTF-8
bad=0
ok() { printf 'PASS  %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }
is() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }
ipc() { qs -c mbm ipc call "$@" 2>/dev/null; }
state() { ipc shell state | jq -r ".$1"; }
unlock() { wtype "$PASSWORD"; wtype -k Return; sleep 3; }
# The crash-relock flag holds the Hyprland instance signature while locked and
# is emptied (not removed) when unlocked.
lockflag() { tr -d '[:space:]' < ~/.local/state/mbm/locked 2>/dev/null; }

is "mbm-shell active"            active "$(systemctl --user is-active mbm-shell)"
for d in waybar mako swayosd-server hypridle hyprlock walker elephant polkit-gnome-authentication-agent-1; do
  is "$d not running"            no     "$(pgrep -f "$d" >/dev/null && echo yes || echo no)"
done
is "shell answers IPC"           pong   "$(ipc shell ping)"
is "settings valid"              ""     "$(mbm settings check 2>&1)"
is "generated config present"    4      "$(ls ~/.local/state/mbm/hypr/*.conf 2>/dev/null | wc -l)"

ipc launcher toggle;  sleep 0.3; is "launcher opens"       true  "$(state launcher)"
ipc launcher toggle;  sleep 0.3; is "launcher closes"      false "$(state launcher)"
ipc quicksettings open wifi; sleep 0.3; is "quick settings opens a picker" wifi "$(state picker)"
ipc quicksettings close
ipc settings open input; sleep 0.5; is "settings opens a page" input "$(state page)"
ipc settings close

notify-send verify-shell hello; sleep 0.5
is "notification recorded"       yes    "$( (( $(ipc notifications count) > 0 )) && echo yes || echo no)"
ipc notifications dismissAll

mbm settings set '.binds["custom.verify"]' '{"mods":"SUPER CTRL ALT","key":"F12","label":"verify","group":"Custom","action":{"exec":"true"}}' && mbm settings apply
is "custom bind reaches Hyprland" 1     "$(hyprctl binds -j | jq '[.[] | select(.description == "verify")] | length')"
mbm settings reset '.binds["custom.verify"]' && mbm settings apply
is "custom bind removed"         0      "$(hyprctl binds -j | jq '[.[] | select(.description == "verify")] | length')"

(printf 'x\ny\n' | mbm dmenu --select 2 >/tmp/verify-dmenu) & sleep 0.8; wtype -k Return; wait
is "dmenu returns the choice"    y      "$(cat /tmp/verify-dmenu)"

is "relock flag empty while unlocked" "" "$(lockflag)"
ipc lock lock; sleep 1
is "locks"                       locked "$(ipc lock status)"
is "relock flag holds the instance while locked" "${HYPRLAND_INSTANCE_SIGNATURE:-unset}" "$(lockflag)"
wtype not-the-password; wtype -k Return; sleep 3
is "wrong password stays locked" locked "$(ipc lock status)"
systemctl --user kill --signal=SIGKILL mbm-shell; sleep 4
is "shell restarted after crash" active "$(systemctl --user is-active mbm-shell)"
is "still locked after crash"    locked "$(ipc lock status)"
unlock
is "right password unlocks"      unlocked "$(ipc lock status)"
is "relock flag cleared after unlock" "" "$(lockflag)"

exit $bad
