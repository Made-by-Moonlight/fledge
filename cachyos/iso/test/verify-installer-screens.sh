#!/usr/bin/env bash
# Moving the installer to another screen, on the dev installer in the test VM.
# Runs on the host, but only drives the VM through vm.sh: a headless output
# stands in for a second screen, real keystrokes (virsh send-key) and the
# installer's IPC (screen, useScreen, current):
#   bash cachyos/iso/test/verify-installer-screens.sh
# Starts the dev installer over the VM's desktop; stops it and removes the
# headless output at the end.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VM="$REPO/cachyos/vm/vm.sh"
# shellcheck source=SCRIPTDIR/../../install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"

# Over ssh the locale is "C", and qs prints a Qt locale warning on stdout.
ipc() { "$VM" run "LC_ALL=C.UTF-8 qs -p /tmp/fledge-installer ipc call installer $(printf '%q ' "$@")"; }
names() { "$VM" run 'hyprctl monitors -j | jq -r ".[].name"'; }

"$VM" sync >/dev/null
before="$(names)"
"$VM" run 'hyprctl output create headless >/dev/null'
sleep 1
extra="$(names | grep -vxF -- "$before" | head -n1)"
cleanup() {
  "$VM" run "pkill -f '^qs -p /tmp/fledge-installer'" || true
  [[ -n $extra ]] && "$VM" run "hyprctl output remove $extra >/dev/null" || true
}
trap cleanup EXIT
check "a headless output stands in for a second screen" yes "$([[ -n $extra ]] && echo yes)"
[[ -n $extra ]] || exit 1

# The installer latches the monitor Hyprland has focused, so start it there.
"$VM" run 'fledge hypr dispatch "hl.dsp.focus({ monitor = \"Virtual-1\" })"'
"$VM" run 'bash ~/proj/fledge/cachyos/iso/installer/dev/run.sh'
sleep 1
check "starts on the focused screen" Virtual-1 "$(ipc screen)"

ipc go account >/dev/null; sleep 0.5
# Ctrl+M, a real keystroke: the main screen has the keyboard.
"$VM" key KEY_LEFTCTRL KEY_M; sleep 1
check "ctrl+m moves to the next screen" "$extra" "$(ipc screen)"
check "the step survives the move" account "$(ipc current)"
"$VM" key KEY_LEFTCTRL KEY_M; sleep 1
check "ctrl+m wraps round" Virtual-1 "$(ipc screen)"

# The owl screen's button calls useScreen with its own screen.
check "useScreen moves it" "$extra" "$(ipc useScreen "$extra")"
check "useScreen ignores an unknown screen" "$extra" "$(ipc useScreen NOPE-9)"
ipc useScreen Virtual-1 >/dev/null; sleep 1

# The other screen still answers keys after moving back: Escape goes back a step.
"$VM" key KEY_ESC; sleep 0.5
check "keyboard follows the installer back" region "$(ipc current)"

exit "$fail"
