#!/usr/bin/env bash
# Unit tests for lib/desktop.sh's pure parts and install-cachyos.sh's
# --desktop-only guards. No chroot, no disks.
#   bash cachyos/install/test-desktop.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/desktop.sh
source "$DIR/lib/desktop.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

export MBM_TARGET="$T/mnt"
mkdir -p "$MBM_TARGET/home/ethan"
seed_user_settings ethan us "" 1000 1000
check "us layout: no settings file" "no" "$([[ -e $MBM_TARGET/home/ethan/.config/mbm/settings.json ]] && echo yes || echo no)"
seed_user_settings ethan gb extd "$(id -u)" "$(id -g)"
check "layout seeded" '{"input":{"kbLayout":"gb","kbVariant":"extd"}}' "$(tr -d ' \n' < "$MBM_TARGET/home/ethan/.config/mbm/settings.json")"

mkdir -p "$MBM_TARGET/etc/sudoers.d"
echo x > "$MBM_TARGET/etc/sudoers.d/99-mbm-install"
remove_install_sudoers
check "sudoers drop-in removed" "no" "$([[ -e $MBM_TARGET/etc/sudoers.d/99-mbm-install ]] && echo yes || echo no)"
remove_install_sudoers
check "removal is idempotent" 0 "$?"

# The trap must fire on SIGTERM/SIGINT, even while a child is running.
for sig in TERM INT; do
  echo x > "$MBM_TARGET/etc/sudoers.d/99-mbm-install"
  bash -c '
    source "$1/lib/desktop.sh"
    trap "remove_install_sudoers" EXIT
    trap "exit 143" TERM; trap "exit 130" INT
    sleep 30 & wait' _ "$DIR" &
  pid=$!; sleep 1; kill -"$sig" "$pid"; wait "$pid" 2>/dev/null
  check "sudoers drop-in removed on SIG$sig" "no" "$([[ -e $MBM_TARGET/etc/sudoers.d/99-mbm-install ]] && echo yes || echo no)"
done

out="$(bash "$DIR/install-cachyos.sh" --desktop-only 'Bad Name' 2>&1)"; rc=$?
check "desktop-only: bad user refused" 1 "$rc"
contains "desktop-only: says why" "not a valid user name" "$out"

exit $fail
