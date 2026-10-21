#!/usr/bin/env bash
# End-to-end checks for the fledge shell, run inside the logged-in Hyprland
# session (needs wtype; types the account password for the lock checks):
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh'
# Never suspends: lock-before-sleep can't be exercised in the VM.
# The broken-fragment check also runs across a login, in two steps around a relogin:
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh break-binds'
#   cachyos/vm/vm.sh relogin
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh after-relogin'
# (promptly: the loader's notification times out 15 s after Hyprland starts).
set -uo pipefail

PASSWORD="${VM_PASSWORD:-TestPass1}"
# Over ssh the locale is "C", and qs prints a Qt locale warning on stdout.
export LC_ALL=C.UTF-8
bad=0
ok() { printf 'PASS  %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }
is() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }

gen=~/.local/state/fledge/hypr
# Hyprland's own notifications (the ".conf format" notice, fledge's loader
# errors), one per line. hyprctl has no query for them; Lua does. The prefix
# keeps the reply non-empty: repl answers an empty string with "unknown request".
# A reply without the prefix (repl refused or broken) fails, so a negative check
# ("no such notification") can't pass on a reply that lists nothing.
hypr_notes() {
  local reply
  reply="$(hyprctl repl 'local t = {} for _, n in ipairs(hl.notification.get()) do if n:is_alive() then t[#t + 1] = n:get_text() end end return "notes:" .. table.concat(t, "\n")')"
  if [[ $reply != notes:* ]]; then printf 'hypr_notes: no notification list: %s\n' "$reply" >&2; return 1; fi
  printf '%s\n' "${reply#notes:}"
}
# note_has <grep -E pattern>: yes / no, or "repl failed" (which no check expects).
note_has() {
  local notes
  notes="$(hypr_notes)" || { echo "repl failed"; return; }
  grep -qE -- "$1" <<<"$notes" && echo yes || echo no
}
# What a broken binds.lua must not take with it: settings from the files loaded
# before it (look and feel) and after it (input, monitors, workspace rules), as
# they were before the break; and nothing is a config error. Kept in /tmp across
# the relogin. Input is read by values the settings change from Hyprland's own
# defaults (repeat rate 40, not 25; compose:caps), so a lost input.lua shows.
INTACT=/tmp/verify-shell-intact
snapshot() {
  hyprctl getoption general:gaps_out | head -n1
  printf '%s %s\n' "$(hyprctl getoption input:repeat_rate | head -n1)" "$(hyprctl getoption input:kb_options | head -n1)"
  hyprctl monitors -j | jq -c 'map({name, width, height, scale})'
  hyprctl workspacerules -j | jq -c 'map({workspaceString, monitor, default, persistent})'
}
intact() {
  local want got
  want="$(cat "$INTACT" 2>/dev/null)"; got="$(snapshot)"
  is "$1: look and feel still loaded" "$(sed -n 1p <<<"$want")" "$(sed -n 1p <<<"$got")"
  is "$1: input still loaded"         "$(sed -n 2p <<<"$want")" "$(sed -n 2p <<<"$got")"
  is "$1: monitors still loaded"      "$(sed -n 3p <<<"$want")" "$(sed -n 3p <<<"$got")"
  is "$1: workspace rules still loaded" "$(sed -n 4p <<<"$want")" "$(sed -n 4p <<<"$got")"
  is "$1: no config errors"           "" "$(hyprctl configerrors)"
}
# The fledge loader names the file it couldn't load in a notification...
broken_binds_noted() {
  is "$1: fledge notification names binds.lua" yes "$(note_has "^fledge: $gen/binds.lua:")"
}
# ...and the bad file loses its own binds, leaving only hyprland.lua's safety
# net (terminal, launcher, keybind settings, system menu, exit)...
safety_binds() {
  is "$1: only the safety-net binds" "Exit Hyprland,Keybinds,Launch apps,System menu,Terminal" \
    "$(hyprctl binds -j | jq -r '[.[].description] | sort | join(",")')"
}
# ...and apply then writes it back.
binds_restored() {
  fledge settings apply >/dev/null 2>&1
  is "$1: settings apply restores the binds" "$(( $(fledge settings get .binds | jq length) + 1 ))" "$(hyprctl binds -j | jq length)"
}

case "${1:-}" in
  break-binds)
    snapshot > "$INTACT"
    # Newer than the defaults and present, so env-hyprland leaves it alone at login.
    printf 'this is not lua (verify-shell.sh break-binds)\n' > "$gen/binds.lua"
    echo "binds.lua broken; now vm.sh relogin, then run: verify-shell.sh after-relogin"
    exit 0 ;;
  after-relogin)
    is "relogin: binds.lua still broken" yes "$(grep -q 'verify-shell.sh break-binds' "$gen/binds.lua" && echo yes || echo no)"
    safety_binds relogin
    broken_binds_noted relogin
    # The loader also writes to stderr, which uwsm sends to the journal.
    is "relogin: loader error in the journal" yes "$(journalctl --user -b -o cat _PID="$(pgrep -nx Hyprland)" | grep -qF "fledge: $gen/binds.lua:" && echo yes || echo no)"
    intact relogin
    binds_restored relogin
    hyprctl dismissnotify >/dev/null; rm -f "$INTACT"
    exit $bad ;;
  "") ;;
  *) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
ipc() { qs -c fledge ipc call "$@" 2>/dev/null; }
state() { ipc shell state | jq -r ".$1"; }
DMENU_OUT=/tmp/verify-dmenu
unlock() {
  [[ "$(ipc lock status)" == locked ]] || return 0
  wtype "$PASSWORD"; wtype -k Return; sleep 3
}
# The crash-relock flag holds the Hyprland instance signature while locked and
# is emptied (not removed) when unlocked; a fresh account has none until the
# first lock. stderr is redirected first, so a missing file stays quiet.
lockflag() { tr -d '[:space:]' 2>/dev/null < ~/.local/state/fledge/locked; }

nl_temp() { hyprctl hyprsunset temperature 2>/dev/null | grep -xE '[0-9]+'; }

# Leave the session as found however the run ends: unlocked, no test bind, no
# open popup. Passwords are only typed while the shell reports "locked", so a
# failed lock never types into whatever window has focus.
cleanup() {
  trap - EXIT INT TERM
  [[ "$(ipc lock status)" == locked ]] && unlock
  # apply also rewrites a binds.lua the broken-fragment check left behind.
  fledge settings reset '.binds["custom.verify"]' >/dev/null 2>&1; fledge settings apply >/dev/null 2>&1
  [[ -n "${ws0:-}" ]] && fledge hypr dispatch "hl.dsp.focus({workspace = $ws0})" >/dev/null 2>&1
  [[ -n "${zoom0:-}" ]] && fledge hypr set "cursor = { zoom_factor = $zoom0 }" >/dev/null 2>&1
  ipc launcher close >/dev/null; ipc quicksettings close >/dev/null; ipc settings close >/dev/null
  ipc notifications dismissAll >/dev/null
  rm -f "$DMENU_OUT"
  # Night light is left off (6000 = hyprsunset's identity), even if a check died mid-toggle.
  [[ "$(nl_temp)" == 4000 ]] && hyprctl hyprsunset temperature 6000 >/dev/null 2>&1
  fledge settings reset .bar.main .bar.hidden >/dev/null 2>&1
  [[ -n "${headless:-}" ]] && hyprctl output remove "$headless" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM
trap 'exit 130' INT TERM

is "fledge-shell active"            active "$(systemctl --user is-active fledge-shell)"
for d in waybar mako swayosd-server hypridle hyprlock walker elephant; do
  is "$d not running"            no     "$(pgrep -x "$d" >/dev/null && echo yes || echo no)"
done
# The comm name is truncated to 15 chars, so match polkit-gnome by path.
is "polkit-gnome not running"    no     "$(pgrep -f '^/usr/lib/polkit-gnome/' >/dev/null && echo yes || echo no)"
is "shell answers IPC"           pong   "$(ipc shell ping)"
is "settings valid"              ""     "$(fledge settings check 2>&1)"
is "generated config present"    4      "$(ls "$gen"/{binds,monitors,workspaces,input}.lua 2>/dev/null | wc -l)"
is "no generated .conf left"     0      "$(ls "$gen"/*.conf 2>/dev/null | wc -l)"

# Hyprland runs the Lua config: the session's log says so, nothing failed to
# parse, and no notification is up (0.56 posts one on every .conf login).
is "Hyprland uses the Lua config" yes  "$(grep -q 'Using lua config' "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" && echo yes || echo no)"
is "no Hyprland config errors"   ""     "$(hyprctl configerrors)"
is "no .conf notification"       no     "$(note_has '\.conf')"
is "no fledge loader notification" no   "$(note_has '^fledge: ')"
# Every settings bind is one Hyprland bind, plus the fledge-record submap's way out.
is "every settings bind loaded"  "$(( $(fledge settings get .binds | jq length) + 1 ))" "$(hyprctl binds -j | jq length)"
is "bind descriptions are the settings labels" "$(fledge settings get .binds | jq -c '[.[].label] | sort')" "$(hyprctl binds -j | jq -c '[.[] | select(.submap == "") | .description] | sort')"
is "fledge-record submap has its reset bind" 1 "$(hyprctl binds -j | jq '[.[] | select(.submap == "fledge-record" and .key == "Escape")] | length')"
fledge hypr dispatch 'hl.dsp.submap("fledge-record")' >/dev/null
is "fledge hypr enters the fledge-record submap" fledge-record "$(hyprctl submap)"
fledge hypr dispatch 'hl.dsp.submap("reset")' >/dev/null
is "fledge hypr leaves the submap" default "$(hyprctl submap)"
ws0="$(hyprctl activeworkspace -j | jq .id)"
ws1=$((ws0 == 2 ? 3 : 2))   # somewhere else, or the check proves nothing
fledge hypr dispatch "hl.dsp.focus({workspace = $ws1})" >/dev/null
is "fledge hypr dispatch moves to workspace $ws1" "$ws1" "$(hyprctl activeworkspace -j | jq .id)"
fledge hypr dispatch "hl.dsp.focus({workspace = $ws0})" >/dev/null
is "fledge hypr dispatch moves back"  "$ws0" "$(hyprctl activeworkspace -j | jq .id)"
is "fledge hypr fails on a bad dispatcher" 1 "$(fledge hypr dispatch 'hl.dsp.no_such_thing()' >/dev/null 2>&1; echo $?)"
zoom0="$(hyprctl getoption cursor:zoom_factor | sed -n 's/^float: //p')"
# 1.5, not the default 1, or the check proves nothing; cleanup restores zoom0.
is "fledge hypr set succeeds"    0      "$(fledge hypr set 'cursor = { zoom_factor = 1.5 }' >/dev/null 2>&1; echo $?)"
is "fledge hypr set applies"     "float: 1.500000" "$(hyprctl getoption cursor:zoom_factor | head -n1)"
# The zoom binds' commands (they ran `hyprctl keyword`, refused under Lua).
zoom_cmd() { fledge settings get ".binds[\"$1\"].action.exec" | jq -r .; }
sh -c "$(zoom_cmd utilities.reset-zoom)"
is "reset-zoom bind command resets the zoom" "float: 1.000000" "$(hyprctl getoption cursor:zoom_factor | head -n1)"
sh -c "$(zoom_cmd utilities.zoom-in)"
is "zoom-in bind command zooms in"         "float: 2.000000" "$(hyprctl getoption cursor:zoom_factor | head -n1)"
sh -c "$(zoom_cmd utilities.reset-zoom)"

# A broken generated fragment costs only its own settings, with a fledge
# notification rather than emergency mode. (Across a login: see the top.)
hyprctl dismissnotify >/dev/null
snapshot > "$INTACT"
printf 'this is not lua (verify-shell.sh)\n' > "$gen/binds.lua"
hyprctl reload >/dev/null; sleep 1
safety_binds reload
broken_binds_noted reload
intact reload
binds_restored reload
hyprctl dismissnotify >/dev/null; rm -f "$INTACT"

# Login shell is fish: abbreviations and the starship prompt load, zsh is gone.
is "login shell is fish"         /usr/bin/fish "$(getent passwd "$USER" | cut -d: -f7)"
# Apps launched through uwsm inherit SHELL from the user systemd manager, which
# outlives the login-shell switch; a stale value launches a removed zsh.
is "session SHELL is the login shell" "$(getent passwd "$USER" | cut -d: -f7)" "$(systemctl --user show-environment | sed -n 's/^SHELL=//p')"
# Keybind execs run with Hyprland's own environment, a second copy of SHELL.
rm -f /tmp/verify-bind-shell
fledge hypr dispatch "hl.dsp.exec_cmd($(fledge hypr quote "sh -c 'echo \$SHELL > /tmp/verify-bind-shell'"))" >/dev/null 2>&1
for _ in $(seq 20); do [[ -s /tmp/verify-bind-shell ]] && break; sleep 0.25; done
is "bind-launched apps see the login shell" "$(getent passwd "$USER" | cut -d: -f7)" "$(cat /tmp/verify-bind-shell 2>/dev/null)"
rm -f /tmp/verify-bind-shell
is "gst abbreviation defined"    yes "$(fish -ic 'abbr --show' 2>/dev/null | grep -c ' gst ' >/dev/null && echo yes || echo no)"
is "starship on PATH"            yes "$(fish -c 'type -q starship' 2>/dev/null && echo yes || echo no)"
is "starship prompt initialised" yes "$(fish -ic 'functions fish_prompt' 2>/dev/null | grep -q starship && echo yes || echo no)"
# The full oh-my-zsh git/kubectl sets, as abbreviations that expand to the same commands.
abbr_of() { fish -ic "abbr --show" 2>/dev/null | grep -a -- " $1 " | head -n1; }
for pair in "gcam|git commit --all --message" "gcmsg|git commit --message" "gcb|git checkout -b" \
            "glola|--all" "gsta|git stash push" "kgp|kubectl get pods" "kdp|kubectl describe pods" \
            "gpsup|\$(git_current_branch)"; do
  is "abbr ${pair%%|*} expands" yes "$(abbr_of "${pair%%|*}" | grep -cF -- "${pair#*|}" >/dev/null && echo yes || echo no)"
done
is "git_main_branch finds main"  main "$(cd ~/proj/fledge && fish -c git_main_branch 2>/dev/null)"
is "zsh not installed"           no  "$(pacman -Qi zsh >/dev/null 2>&1 && echo yes || echo no)"

ipc launcher open apps; sleep 0.3; is "launcher opens"     true  "$(state launcher)"
ipc launcher close;   sleep 0.3; is "launcher closes"      false "$(state launcher)"
ipc quicksettings open wifi; sleep 0.3; is "quick settings opens a picker" wifi "$(state picker)"
ipc quicksettings close
ipc settings open input; sleep 0.5; is "settings opens a page" input "$(state page)"
# Its window rule (fledge/rules.lua) matches the title: a centred floating dialog.
is "settings window floats at 960x680" "true [960,680]" \
  "$(hyprctl clients -j | jq -r '.[] | select(.title == "fledge · settings") | "\(.floating) \(.size | tojson)"')"
ipc settings close

before="$(ipc notifications count)"
notify-send verify-shell hello; sleep 0.5
is "notification recorded"       yes    "$( (( $(ipc notifications count) > before )) && echo yes || echo no)"
ipc notifications dismissAll

fledge settings set '.binds["custom.verify"]' '{"mods":"SUPER CTRL ALT","key":"F12","label":"verify","group":"Custom","action":{"exec":"true"}}' && fledge settings apply
is "custom bind reaches Hyprland" 1     "$(hyprctl binds -j | jq '[.[] | select(.description == "verify")] | length')"
# Key recording: the settings window puts Hyprland in the fledge-record submap, takes
# one key (a bare F-key: wtype's -M modifiers don't reach Qt as modifiers) and
# saves it to the bind.
ipc settings record custom.verify; sleep 1.5
is "recording enters the fledge-record submap" fledge-record "$(hyprctl submap)"
wtype -k F9; sleep 2
is "recording leaves the submap"  default "$(hyprctl submap)"
is "the recorded key is saved"    "+F9"  "$(fledge settings get '.binds["custom.verify"] | .mods + "+" + .key' | jq -r .)"
is "and reaches Hyprland"         1      "$(hyprctl binds -j | jq '[.[] | select(.description == "verify" and .key == "F9")] | length')"
ipc settings close
fledge settings reset '.binds["custom.verify"]' && fledge settings apply
is "custom bind removed"         0      "$(hyprctl binds -j | jq '[.[] | select(.description == "verify")] | length')"

(printf 'x\ny\n' | timeout 10 fledge dmenu --select 2 >"$DMENU_OUT") & sleep 0.8; wtype -k Return; wait
is "dmenu returns the choice"    y      "$(cat "$DMENU_OUT")"

# Night light: the tile runs fledge toggle nightlight and reads hyprsunset's temperature.
nl0="$(nl_temp)"
fledge toggle nightlight >/dev/null 2>&1; sleep 1; nl1="$(nl_temp)"
fledge toggle nightlight >/dev/null 2>&1; sleep 1; nl2="$(nl_temp)"
is "night light toggles on"      4000   "$nl1"
is "night light toggles back"    "${nl0:-6000}" "$nl2"
is "night light ends off"        6000   "$nl2"

is "relock flag empty while unlocked" "" "$(lockflag)"
ipc lock lock; sleep 1
is "locks"                       locked "$(ipc lock status)"
is "relock flag holds the instance while locked" "${HYPRLAND_INSTANCE_SIGNATURE:-unset}" "$(lockflag)"
# A manual lock turns the screens off after 3 s (Lock.qml, hl.dsp.dpms); unlock wakes them.
sleep 4
is "screens off while locked (dpms)" false "$(hyprctl monitors -j | jq '.[0].dpmsStatus')"
# The wrong password costs one faillock strike; the successful unlock below
# resets the count. Only typed when actually locked.
if [[ "$(ipc lock status)" == locked ]]; then wtype not-the-password; wtype -k Return; sleep 3; fi
is "wrong password stays locked" locked "$(ipc lock status)"
systemctl --user kill --signal=SIGKILL fledge-shell; sleep 4
is "shell restarted after crash" active "$(systemctl --user is-active fledge-shell)"
is "still locked after crash"    locked "$(ipc lock status)"
unlock
is "right password unlocks"      unlocked "$(ipc lock status)"
is "relock flag cleared after unlock" "" "$(lockflag)"
is "screens on after unlock (dpms)" true "$(hyprctl monitors -j | jq 'all(.dpmsStatus)')"

# Main monitor and per-monitor bars. layers_on <output> <namespace>: how many of that
# layer the output has. The two-monitor checks get a headless second output when the
# VM has one screen (removed again by cleanup).
layers_on() { hyprctl layers -j | jq --arg o "$1" --arg n "$2" '[.[$o].levels[]?[]? | select(.namespace == $n)] | length'; }
mons() { hyprctl monitors -j | jq -r 'sort_by(.y, .x) | .[].name'; }
fledge settings reset .bar.main .bar.hidden >/dev/null 2>&1; sleep 1
first="$(mons | head -n1)"
is "main monitor has a bar"             1 "$(layers_on "$first" fledge-bar)"
is "only the bar edge is reserved"      1 "$(layers_on "$first" fledge-frame-reserve)"
if [[ "$(mons | wc -l)" -lt 2 ]]; then
  headless=FLEDGE-TEST; hyprctl output create headless "$headless" >/dev/null; sleep 2
fi
second="$(mons | sed -n 2p)"
if [[ -n "$second" ]]; then
  # A monitor with no description is keyed by its connector (Layout.js keyFor).
  key2="$(hyprctl monitors -j | jq -r --arg n "$second" '.[] | select(.name == $n) | if .description == "" then .name else "desc:" + .description end')"
  is "second monitor has a bar by default" 1 "$(layers_on "$second" fledge-bar)"
  fledge settings set .bar.hidden "$(jq -cn --arg k "$key2" '[$k]')" >/dev/null; sleep 2
  is "hidden: no bar on it"             0 "$(layers_on "$second" fledge-bar)"
  is "hidden: no reserved edge on it"   0 "$(layers_on "$second" fledge-frame-reserve)"
  fledge settings set .bar.main "$(jq -cn --arg k "$key2" '$k')" >/dev/null; sleep 2
  is "main beats hidden"                1 "$(layers_on "$second" fledge-bar)"
  notify-send "fledge verify" "main monitor"; sleep 1
  is "notification on the main monitor" 1 "$(layers_on "$second" fledge-notifications)"
  ipc notifications dismissAll >/dev/null
  fledge settings reset .bar.main .bar.hidden >/dev/null; sleep 2
else
  echo "SKIP  two-monitor checks (no second output)"
fi

# GTK dark is seeded once: with the marker present, bootstrap's seeding must leave a
# user's light choice alone. Runs the function exactly as bootstrap.sh defines it.
GTK_KEY="gsettings get org.gnome.desktop.interface color-scheme"
gtk_prev="$($GTK_KEY)"
[[ -e ~/.local/state/fledge/gtk-dark-seeded ]] || { mkdir -p ~/.local/state/fledge; : > ~/.local/state/fledge/gtk-dark-seeded; }
gsettings set org.gnome.desktop.interface color-scheme default
bash -c "$(sed -n '/^seed_gtk_dark() {/,/^}/p' "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../bootstrap.sh"); seed_gtk_dark"
is "gtk dark not re-applied once seeded" "'default'" "$($GTK_KEY)"
gsettings set org.gnome.desktop.interface color-scheme "${gtk_prev//\'/}"

exit $bad
