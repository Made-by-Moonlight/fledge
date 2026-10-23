#!/usr/bin/env bash
# End-to-end checks for `fledge update`, run inside the logged-in session (types the
# account password into sudo):
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-update.sh [fresh] [packages]'
# fresh: first put / back as the installer leaves it (no snapper config, an empty
#   @/.snapshots) and run bootstrap.sh, checking it sets snapshots up.
# packages: let the run update the VM's real packages too (slow); otherwise
#   checkupdates and `paru -Qua` are stubbed to report nothing.
# fledge's own step runs against a scratch checkout (FLEDGE_REPO) at an old tag
# whose local origin carries a newer one, with a stub bootstrap: the real
# bootstrap would restow ~ from the scratch checkout.
set -uo pipefail

PASSWORD="${VM_PASSWORD:-TestPass1}"
export LC_ALL=C.UTF-8
bad=0
ok() { printf 'PASS  %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }
is() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }

fresh=false packages=false
for a in "$@"; do
  case $a in
    fresh) fresh=true ;;
    packages) packages=true ;;
    *) echo "usage: verify-update.sh [fresh] [packages]" >&2; exit 2 ;;
  esac
done

REPO=~/proj/fledge
FLEDGE="$REPO/dot-local/share/fledge/bin/fledge"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
# sudo through an askpass helper: there's no terminal over ssh, and the password
# must not go in on stdin, which is the command's own (bootstrap's `sudo tee <<EOF`
# would write it, or nothing, into /etc).
printf '#!/bin/bash\nprintf "%%s\\n" %q\n' "$PASSWORD" >"$T/askpass"
printf '#!/bin/bash\nexec /usr/bin/sudo -A "$@"\n' >"$T/bin/sudo"
chmod +x "$T/askpass" "$T/bin/sudo"
export SUDO_ASKPASS="$T/askpass"
export PATH="$T/bin:$PATH"

if $fresh; then
  echo "== bootstrap sets snapshots up"
  sudo snapper -c root delete-config 2>/dev/null
  [[ -d /.snapshots ]] || sudo btrfs subvolume create /.snapshots >/dev/null
  sudo systemctl disable --quiet limine-snapper-sync.service snapper-cleanup.timer 2>/dev/null
  bash "$REPO/cachyos/bootstrap.sh" >"$T/bootstrap.log" 2>&1
  is "bootstrap ran" 0 "$?"
  for p in snapper limine-snapper-sync pacman-contrib fwupd; do
    pacman -Q "$p" >/dev/null 2>&1 && ok "$p installed" || no "$p installed"
  done
  cfg="$(sudo snapper -c root get-config 2>&1)"
  is "a root snapper config" yes "$(grep -q '^SUBVOLUME *│ /$' <<<"$cfg" && echo yes || echo no)"
  is "keeps 5" 5 "$(awk -F'│' '$1 ~ /^NUMBER_LIMIT +$/ {gsub(/ /, "", $2); print $2}' <<<"$cfg")"
  is "no timeline" no "$(awk -F'│' '$1 ~ /^TIMELINE_CREATE +$/ {gsub(/ /, "", $2); print $2}' <<<"$cfg")"
  is "limine-snapper-sync enabled" enabled "$(systemctl is-enabled limine-snapper-sync.service 2>&1)"
  is "snapper cleanup enabled" enabled "$(systemctl is-enabled snapper-cleanup.timer 2>&1)"
  is "the lock's PAM service is written" yes "$([[ -s /etc/pam.d/fledge-lock ]] && echo yes || echo no)"
  bash "$REPO/cachyos/bootstrap.sh" >"$T/bootstrap2.log" 2>&1
  is "bootstrap again: still fine" 0 "$?"
fi

echo "== fledge update"
if ! $packages; then
  printf '#!/bin/bash\nexit 2\n' >"$T/bin/checkupdates"
  printf '#!/bin/bash\n[[ $1 == -Qua ]] && exit 1\nexec /usr/bin/paru "$@"\n' >"$T/bin/paru"
  chmod +x "$T/bin/checkupdates" "$T/bin/paru"
fi
# The scratch release history: v2026.01.01, then v2026.01.02 whose bootstrap logs.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q -b main "$T/src"
( cd "$T/src" && mkdir cachyos && echo 'exit 0' >cachyos/bootstrap.sh && git add . && git commit -qm one && git tag v2026.01.01 \
  && printf 'echo "bootstrap ran at $(git -C "$(dirname "$0")/.." describe --tags)" >>%q\ngit -C "$(dirname "$0")/.." describe --tags --always --dirty >%q\n' "$T/log" "$T/state/bootstrapped" >cachyos/bootstrap.sh \
  && git commit -qam two && git tag v2026.01.02 )
git clone -q --bare "$T/src" "$T/origin.git"
git clone -q "$T/origin.git" "$T/checkout"
git -C "$T/checkout" reset -q --hard v2026.01.01
# Its own state too: the real ~/.local/state/fledge (what bootstrap finished, the runs) stays
# the VM's own.
export FLEDGE_REPO="$T/checkout" FLEDGE_STATE="$T/state"

is "check offers the newer tag" '{"from":"v2026.01.01","to":"v2026.01.02"}' "$("$FLEDGE" update check --json | jq -c .fledge)"
before="$(sudo snapper -c root --jsonout list | jq '.root | map(.number) | max')"
"$FLEDGE" update --yes >"$T/run.log" 2>&1
rc=$?
is "update --yes exits 0" 0 "$rc"
((rc == 0)) || sed 's/^/    /' "$T/run.log"
is "fledge is at the new tag, on main" "main v2026.01.02" "$(git -C "$T/checkout" branch --show-current) $(git -C "$T/checkout" describe --tags)"
is "the new release's bootstrap ran" "bootstrap ran at v2026.01.02" "$(cat "$T/log" 2>/dev/null)"
snaps="$(sudo snapper -c root --jsonout list | jq -c --argjson b "$before" '[.root[] | select(.number > $b) | {type, description, pre: (."pre-number" // null)}]')"
pre="$(sudo snapper -c root --jsonout list | jq --argjson b "$before" '[.root[] | select(.number > $b and .type == "pre")][0].number')"
is "a pre and a post snapshot" "[{\"type\":\"pre\",\"description\":\"fledge update\",\"pre\":null},{\"type\":\"post\",\"description\":\"fledge update\",\"pre\":$pre}]" "$snaps"
sleep 3
is "the snapshot is in the boot menu" yes "$(sudo grep -q "^ *///$pre │" /boot/limine.conf && echo yes || echo no)"
is "nothing left to do" '{"fledge":null,"packages":0,"aur":0}' "$("$FLEDGE" update check --json | jq -c '{fledge, packages, aur}')"
out="$("$FLEDGE" update --yes 2>&1)"
is "a second run has nothing to do" yes "$([[ $out == *"Everything is up to date."* ]] && echo yes || echo no)"

if $packages; then
  # The run asks the shell to recheck; the check takes a few seconds.
  for _ in $(seq 60); do
    sleep 2; u="$(qs -c fledge ipc call shell updates)"
    [[ $(jq .checking <<<"$u") == false ]] && break
  done
  is "the bar's module is hidden after" 0 "$(jq .count <<<"$u")"
fi

exit $bad
