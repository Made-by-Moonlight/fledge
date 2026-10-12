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
DMENU_OUT=/tmp/verify-dmenu
unlock() {
  [[ "$(ipc lock status)" == locked ]] || return 0
  wtype "$PASSWORD"; wtype -k Return; sleep 3
}
# The crash-relock flag holds the Hyprland instance signature while locked and
# is emptied (not removed) when unlocked.
lockflag() { tr -d '[:space:]' < ~/.local/state/mbm/locked 2>/dev/null; }

nl_temp() { hyprctl hyprsunset temperature 2>/dev/null | grep -xE '[0-9]+'; }

# Leave the session as found however the run ends: unlocked, no test bind, no
# open popup. Passwords are only typed while the shell reports "locked", so a
# failed lock never types into whatever window has focus.
cleanup() {
  trap - EXIT INT TERM
  [[ "$(ipc lock status)" == locked ]] && unlock
  mbm settings reset '.binds["custom.verify"]' >/dev/null 2>&1 && mbm settings apply >/dev/null 2>&1
  ipc launcher close >/dev/null; ipc quicksettings close >/dev/null; ipc settings close >/dev/null
  ipc notifications dismissAll >/dev/null
  rm -f "$DMENU_OUT"
  # Night light is left off (6000 = hyprsunset's identity), even if a check died mid-toggle.
  [[ "$(nl_temp)" == 4000 ]] && hyprctl hyprsunset temperature 6000 >/dev/null 2>&1
}
trap cleanup EXIT INT TERM
trap 'exit 130' INT TERM

is "mbm-shell active"            active "$(systemctl --user is-active mbm-shell)"
for d in waybar mako swayosd-server hypridle hyprlock walker elephant; do
  is "$d not running"            no     "$(pgrep -x "$d" >/dev/null && echo yes || echo no)"
done
# The comm name is truncated to 15 chars, so match polkit-gnome by path.
is "polkit-gnome not running"    no     "$(pgrep -f '^/usr/lib/polkit-gnome/' >/dev/null && echo yes || echo no)"
is "shell answers IPC"           pong   "$(ipc shell ping)"
is "settings valid"              ""     "$(mbm settings check 2>&1)"
is "generated config present"    4      "$(ls ~/.local/state/mbm/hypr/*.conf 2>/dev/null | wc -l)"

ipc launcher open apps; sleep 0.3; is "launcher opens"     true  "$(state launcher)"
ipc launcher close;   sleep 0.3; is "launcher closes"      false "$(state launcher)"
ipc quicksettings open wifi; sleep 0.3; is "quick settings opens a picker" wifi "$(state picker)"
ipc quicksettings close
ipc settings open input; sleep 0.5; is "settings opens a page" input "$(state page)"
ipc settings close

before="$(ipc notifications count)"
notify-send verify-shell hello; sleep 0.5
is "notification recorded"       yes    "$( (( $(ipc notifications count) > before )) && echo yes || echo no)"
ipc notifications dismissAll

mbm settings set '.binds["custom.verify"]' '{"mods":"SUPER CTRL ALT","key":"F12","label":"verify","group":"Custom","action":{"exec":"true"}}' && mbm settings apply
is "custom bind reaches Hyprland" 1     "$(hyprctl binds -j | jq '[.[] | select(.description == "verify")] | length')"
mbm settings reset '.binds["custom.verify"]' && mbm settings apply
is "custom bind removed"         0      "$(hyprctl binds -j | jq '[.[] | select(.description == "verify")] | length')"

(printf 'x\ny\n' | timeout 10 mbm dmenu --select 2 >"$DMENU_OUT") & sleep 0.8; wtype -k Return; wait
is "dmenu returns the choice"    y      "$(cat "$DMENU_OUT")"

# Night light: the tile runs slievr-toggle-nightlight and reads hyprsunset's temperature.
nl0="$(nl_temp)"
slievr-toggle-nightlight >/dev/null 2>&1; sleep 1; nl1="$(nl_temp)"
slievr-toggle-nightlight >/dev/null 2>&1; sleep 1; nl2="$(nl_temp)"
is "night light toggles on"      4000   "$nl1"
is "night light toggles back"    "${nl0:-6000}" "$nl2"
is "night light ends off"        6000   "$nl2"

is "relock flag empty while unlocked" "" "$(lockflag)"
ipc lock lock; sleep 1
is "locks"                       locked "$(ipc lock status)"
is "relock flag holds the instance while locked" "${HYPRLAND_INSTANCE_SIGNATURE:-unset}" "$(lockflag)"
# The wrong password costs one faillock strike; the successful unlock below
# resets the count. Only typed when actually locked.
if [[ "$(ipc lock status)" == locked ]]; then wtype not-the-password; wtype -k Return; sleep 3; fi
is "wrong password stays locked" locked "$(ipc lock status)"
systemctl --user kill --signal=SIGKILL mbm-shell; sleep 4
is "shell restarted after crash" active "$(systemctl --user is-active mbm-shell)"
is "still locked after crash"    locked "$(ipc lock status)"
unlock
is "right password unlocks"      unlocked "$(ipc lock status)"
is "relock flag cleared after unlock" "" "$(lockflag)"

# GTK dark is seeded once: with the marker present, bootstrap's seeding must leave a
# user's light choice alone. Runs the function exactly as bootstrap.sh defines it.
GTK_KEY="gsettings get org.gnome.desktop.interface color-scheme"
gtk_prev="$($GTK_KEY)"
[[ -e ~/.local/state/mbm/gtk-dark-seeded ]] || { mkdir -p ~/.local/state/mbm; : > ~/.local/state/mbm/gtk-dark-seeded; }
gsettings set org.gnome.desktop.interface color-scheme default
bash -c "$(sed -n '/^seed_gtk_dark() {/,/^}/p' "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../bootstrap.sh"); seed_gtk_dark"
is "gtk dark not re-applied once seeded" "'default'" "$($GTK_KEY)"
gsettings set org.gnome.desktop.interface color-scheme "${gtk_prev//\'/}"

exit $bad
