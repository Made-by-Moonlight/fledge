#!/usr/bin/env bash
# End-to-end check for going back after a failed `fledge update`, in three steps around two
# reboots (run inside the logged-in session; types the account password into sudo):
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-recovery.sh fail'
#   cachyos/vm/vm.sh reboot snapshot     # boots the newest Limine › Snapshots entry
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-recovery.sh snapshot'
#   (the restore reboots the VM; then unlock it: cachyos/vm/vm.sh type <password>)
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-recovery.sh after'
# fail: an update whose AUR step changes / and then fails; the guide's "go back" names the
#   snapshot as the boot menu does. Needs bootstrap's snapper setup (verify-update.sh fresh).
# snapshot: booted into it, the change is gone, the shell's dialog says which snapshot and how
#   that update ended, and `fledge update recover` restores it (answering limine-snapper-restore
#   through a pty, as a person would in the terminal).
# after: back on the normal boot entry, on the restored system: the change is still gone.
set -uo pipefail

PASSWORD="${VM_PASSWORD:-TestPass1}"
export LC_ALL=C.UTF-8
bad=0
ok() { printf 'PASS  %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }
is() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }
has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else no "$1 (no \"$2\" in: $3)"; fi; }

FLEDGE=~/proj/fledge/dot-local/share/fledge/bin/fledge
MARKER=/etc/fledge-recovery-marker
SAVED=~/.cache/fledge-verify-recovery   # the snapshot number, between the steps
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# sudo through askpass: no terminal over ssh, and stdin is the command's own (see verify-update.sh).
printf '#!/bin/bash\nprintf "%%s\\n" %q\n' "$PASSWORD" >"$T/askpass"
printf '#!/bin/bash\nexec /usr/bin/sudo -A "$@"\n' >"$T/bin/sudo"
chmod +x "$T/askpass" "$T/bin/sudo"
export SUDO_ASKPASS="$T/askpass" PATH="$T/bin:$PATH"

case ${1:-} in
  fail)
    sudo rm -f "$MARKER"
    # Nothing from the repos; one AUR package, whose upgrade changes / and fails.
    printf '#!/bin/bash\nexit 2\n' >"$T/bin/checkupdates"
    printf '#!/bin/bash\n[[ $1 == -Qua ]] && { echo "fledge-test 1 -> 2"; exit 0; }\n[[ $1 == -Sua ]] && { sudo touch %q; echo "error: failed to build fledge-test" >&2; exit 1; }\nexec /usr/bin/paru "$@"\n' "$MARKER" >"$T/bin/paru"
    chmod +x "$T/bin/checkupdates" "$T/bin/paru"
    # A dev checkout: fledge's own step stays out of this.
    git init -q -b dev "$T/repo"; export FLEDGE_REPO="$T/repo"
    # Yes to the update; at the guide, go back; don't reboot (vm.sh reboot does that).
    out="$(printf 'y\n2\nn\n' | "$FLEDGE" update 2>&1)"; rc=$?
    is "the failed update exits 1" 1 "$rc"
    has "it names the step" "AUR packages failed" "$out"
    n="$(jq -r '.runs[-1].snapshot' ~/.local/state/fledge/update.json)"
    date="$(jq -r '.runs[-1].date' ~/.local/state/fledge/update.json)"
    is "the run is recorded as failed" "failed: AUR packages" "$(jq -r '.runs[-1].result' ~/.local/state/fledge/update.json)"
    has "the guide names the boot entry" "boot  $n │ $date" "$out"
    is "the change is on the system" yes "$([[ -e $MARKER ]] && echo yes || echo no)"
    sleep 3
    is "the snapshot is in the boot menu" yes "$(sudo grep -q "^ *///$n │" /boot/limine.conf && echo yes || echo no)"
    posts="$(sudo snapper -c root --jsonout list | jq -r '.root[] | select(.type == "post") | .number')"
    listed=""; for p in $posts; do sudo grep -q "^ *///$p │" /boot/limine.conf && listed+="$p "; done
    is "post snapshots aren't in the boot menu" "" "$listed"
    mkdir -p "$(dirname "$SAVED")"; echo "$n" >"$SAVED"
    ;;
  snapshot)
    n="$(cat "$SAVED")"
    has "booted into the snapshot" "subvol=/@/.snapshots/$n/snapshot" "$(cat /proc/cmdline)"
    is "the change isn't there" no "$([[ -e $MARKER ]] && echo yes || echo no)"
    for _ in $(seq 20); do s="$(qs -c fledge ipc call recovery state)"; [[ $(jq .open <<<"$s") == true ]] && break; sleep 1; done
    is "the dialog is open" true "$(jq .open <<<"$s")"
    is "it knows which snapshot" "$n" "$(jq .snapshot <<<"$s")"
    is "and how that update ended" '"failed: AUR packages"' "$(jq -c .run.result <<<"$s")"
    qs -c fledge ipc call recovery close
    # Through a pty, answering each prompt when it shows: ours, then limine-snapper-restore's
    # [r/l/c], the backup's description (Enter, as the guide says), then its reboot question
    # (no: the test reboots on its own terms).
    mkfifo "$T/in"; log="$T/restore.log"
    script -qfec "$FLEDGE update recover" "$log" <"$T/in" >/dev/null 2>&1 &
    exec 3>"$T/in"
    answered=""
    for _ in $(seq 240); do
      sleep 1
      text="$(sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$log" 2>/dev/null | tr '\r' '\n')"
      if [[ $answered != *y* && $text == *"Restore it now? [y/N]"* ]]; then echo y >&3; answered+=y
      elif [[ $answered != *r* && $text == *"Choice [r/l/c]"* ]]; then echo r >&3; answered+=r
      elif [[ $answered != *d* && $text == *"Description for backup"* ]]; then echo >&3; answered+=d
      elif [[ $answered != *n* && $text == *"Reboot now? [Y/n]"* ]]; then echo n >&3; answered+=n; break
      fi
    done
    exec 3>&-
    # Unanswered (a prompt this doesn't know): don't hang, show the log below.
    sleep 2; pkill -f '^script -qfec .*fledge update recover' || true; wait
    text="$(sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$log" | tr '\r' '\n')"
    is "recover walked through the restore" yrdn "$answered"
    has "the restore finished" "Restore complete" "$text"
    ((bad)) && sed 's/^/    /' <<<"$text" | tail -40
    echo "Now: sudo reboot, unlock, then run this with 'after'."
    ;;
  after)
    has "booted normally" "rootflags=subvol=@ " "$(cat /proc/cmdline) "
    is "the restored system doesn't have the change" no "$([[ -e $MARKER ]] && echo yes || echo no)"
    is "the dialog stays shut" '-1 false' "$(qs -c fledge ipc call recovery state | jq -r '"\(.snapshot) \(.open)"')"
    is "no failed units" 0 "$(systemctl --failed --no-legend | wc -l)"
    rm -f "$SAVED"
    ;;
  *) echo "usage: verify-recovery.sh fail | snapshot | after" >&2; exit 2 ;;
esac
exit $bad
