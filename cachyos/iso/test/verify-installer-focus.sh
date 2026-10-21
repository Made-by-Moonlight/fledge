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
ipc go welcome; ipc set disk /dev/nvme0n1; ipc go disk; sleep 1
check "disk opens on the list" "Disk list" "$(focused)"
check "tab to the erase button" "Erase this disk" "$(tabs 1)"
check "shift+tab back to the list" "Disk list" "$(tabs 1 shift)"
key KEY_DOWN
check "down picks the next disk" /dev/nvme1n1 "$(ipc_get disk)"
check "passwords not readable over ipc" "refused: secret" "$(ipc_get password)"
check "passwords not writable over ipc" "refused: password" "$(ipc set password x)"
check "internals not writable over ipc" "refused: terminal" "$(ipc set terminal true)"
check "answers writable over ipc" "ok|ethan" "$(ipc set username ethan)|$(ipc_get username)"
key KEY_ENTER
check "return on the list confirms" data "$(ipc current)"

# Data disks: a card per drive besides the target (the Predator), each with its
# choice in the Tab chain. tab_to <name>: Tab until <name> has the focus, at most
# 30 presses; prints the names passed on the way, joined by |.
tab_to() {
  local i f out=()
  for ((i = 0; i < 30; i++)); do
    key KEY_TAB; f="$(focused)"; out+=("$f")
    [[ $f == "$1" ]] && break
  done
  local IFS='|'; printf '%s\n' "${out[*]}"
}
picked() { ipc choice "$1"; }
confirmed() { ipc_get wipes | jq -r --arg d "$1" '.[$d].confirmed'; }
sn570="WD Blue SN570 1TB choice"; usb="SanDisk Ultra choice"
check "tab reaches the first card" "$sn570" "$(tab_to "$sn570")"
chain="$(tab_to "$usb")"
for c in "Sabrent Rocket 4.0 1TB choice" "PNY CS900 480GB SSD choice" "CT2000MX500SSD1 choice" "$usb"; do
  contains "tab reaches $c" "$c" "$chain"
done
# The stick has a filesystem and no profile default: Leave alone, then Mount, then Wipe.
check "the stick starts on leave alone" leave "$(picked /dev/sdd)"
key KEY_RIGHT
check "right picks mount" mount "$(picked /dev/sdd)"
key KEY_RIGHT
check "right again picks wipe" wipe "$(picked /dev/sdd)"
check "tab from a wipe card" "Mount at|Label|Erase this drive" "$(tabs 3)"
ipc next
check "an unconfirmed wipe holds the step" data "$(ipc current)"
key KEY_SPACE
check "space on the button confirms" true "$(confirmed /dev/sdd)"
# The SN570 (only an ESP and LUKS: no Mount) goes Leave alone -> Wipe, and Return confirms.
tab_to "$sn570" >/dev/null
key KEY_RIGHT
check "no mount on the sn570: right picks wipe" wipe "$(picked /dev/nvme0n1)"
check "tab to its button" "Erase this drive" "$(tabs 3 | cut -d'|' -f3)"
key KEY_ENTER
check "return on the button confirms" true "$(confirmed /dev/nvme0n1)"
check "return on the button stays on the step" data "$(ipc current)"
ipc next
check "confirmed wipes complete the step" review "$(ipc current)"

exit "$fail"
