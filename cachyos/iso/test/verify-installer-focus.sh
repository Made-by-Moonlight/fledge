#!/usr/bin/env bash
# Tab / Shift+Tab focus in the graphical installer, on the dev installer in the
# test VM. Runs on the host, but only drives the VM through vm.sh: real
# keystrokes (virsh send-key) and the installer's IPC (focused(), get, set):
#   bash cachyos/iso/test/verify-installer-focus.sh
# Starts the dev installer over the VM's desktop and stops it at the end.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VM="$REPO/cachyos/vm/vm.sh"
# shellcheck source=SCRIPTDIR/../../install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"

# Over ssh the locale is "C", and qs prints a Qt locale warning on stdout.
ipc() { "$VM" run "LC_ALL=C.UTF-8 qs -p /tmp/fledge-installer ipc call installer $(printf '%q ' "$@")"; }
ipc_get() { ipc get "$1"; }
focused() { ipc focused; }
# One keystroke, then a moment for Qt to move the focus.
key() { "$VM" key "$@"; sleep 0.3; }
# tabs <n> [shift]: press Tab n times, printing the focus after each, joined by |.
tabs() {
  local i out=()
  for ((i = 0; i < $1; i++)); do
    if [[ ${2:-} == shift ]]; then key KEY_LEFTSHIFT KEY_TAB; else key KEY_TAB; fi
    out+=("$(focused)")
  done
  local IFS='|'; printf '%s\n' "${out[*]}"
}

"$VM" sync >/dev/null
"$VM" run 'bash ~/proj/fledge/cachyos/iso/installer/dev/run.sh'
trap '"$VM" run "pkill -f \"^qs -p /tmp/fledge-installer\"" || true' EXIT

toggle="Same password for the disk; log in automatically after unlocking it"
# From another step, so Account loads afresh and focuses its first field.
ipc go welcome; ipc set sameLuks true; ipc go account; sleep 1
check "account opens on username" "Username" "$(focused)"
order="$(tabs 7)"
check "tab order, shared passwords" \
  "Computer name|Password|Password again|$toggle|Back|Next|Username" "$order"
# Shift+Tab from Username goes back to Next
check "shift+tab wraps backwards" "Next" "$(tabs 1 shift)"
key KEY_TAB                                    # back on Username
tabs 3 >/dev/null                              # to Password again
# Space on the focused toggle flips it, and the hidden passphrase row joins the chain
key KEY_TAB; first="$(focused)"
key KEY_SPACE
check "space toggles" false "$(ipc_get sameLuks)"
order2="$first|$(tabs 4)"
check "tab order, separate passphrase" \
  "$toggle|Disk passphrase|Disk passphrase again|Back|Next" "$order2"
# Return on a focused Back goes back one step, not forward
check "back is before next" "Back" "$(tabs 1 shift)"
key KEY_ENTER
check "return on back" region "$(ipc current)"

# An invalid Account after Next was tried disables Next: Tab never lands on it.
ipc go welcome; ipc set username ""; ipc set sameLuks true; ipc go account; sleep 1
ipc next
check "account stays invalid" account "$(ipc current)"
cycle="$(tabs 8)"
contains "tab goes from back to username" "Back|Username" "$cycle"
check "no tab lands on a disabled next" no "$([[ $cycle == *Next* ]] && echo yes || echo no)"

# Disk: the list is in the chain, so Shift+Tab from its button brings the arrow keys back.
ipc go welcome; ipc set disk /dev/vda; ipc go disk; sleep 1
check "disk opens on the list" "Disk list" "$(focused)"
check "tab to the erase button" "Erase this disk" "$(tabs 1)"
check "shift+tab back to the list" "Disk list" "$(tabs 1 shift)"
key KEY_DOWN
check "down picks the next disk" /dev/nvme0n1 "$(ipc_get disk)"
check "passwords not readable over ipc" "refused: secret" "$(ipc_get password)"
key KEY_ENTER
check "return on the list confirms" data "$(ipc current)"

exit "$fail"
