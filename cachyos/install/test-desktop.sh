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

export FLEDGE_TARGET="$T/mnt"
mkdir -p "$FLEDGE_TARGET/home/ethan"
seed_user_settings ethan us "" 1000 1000
check "us layout: no settings file" "no" "$([[ -e $FLEDGE_TARGET/home/ethan/.config/fledge/settings.json ]] && echo yes || echo no)"
seed_user_settings ethan gb extd "$(id -u)" "$(id -g)"
check "layout seeded" '{"input":{"kbLayout":"gb","kbVariant":"extd"}}' "$(tr -d ' \n' < "$FLEDGE_TARGET/home/ethan/.config/fledge/settings.json")"

al="$FLEDGE_TARGET/etc/sddm.conf.d/autologin.conf"
write_autologin ethan 'pa=ss word' 'pa=ss word'
check "autologin: same password writes the drop-in" \
  $'[Autologin]\nUser=ethan\nSession=hyprland-uwsm.desktop' "$(cat "$al" 2>/dev/null)"
check "autologin: drop-in is 644" 644 "$(stat -c %a "$al" 2>/dev/null)"
write_autologin ethan 'pa=ss word' 'pa=ss word '
check "autologin: different passwords, no drop-in" no "$([[ -e $al ]] && echo yes || echo no)"
write_autologin ethan '' ''
check "autologin: empty passwords, no drop-in" no "$([[ -e $al ]] && echo yes || echo no)"
out="$(write_autologin ethan 's3cret*' 's3cret*' 2>&1)"
check "autologin: never echoes the password" "" "$(grep -o 's3cret' <<<"$out")"

src="$DIR/install-cachyos.sh"
check "autologin: written before the Desktop stage" yes \
  "$(awk '/^desktop_and_finish\(\)/,/^}/{next} /write_autologin/{w=NR} /^desktop_and_finish$/{d=NR} END{print (w && d && w<d) ? "yes" : "no"}' "$src")"

mkdir -p "$FLEDGE_TARGET/etc/sudoers.d"
echo x > "$FLEDGE_TARGET/etc/sudoers.d/99-fledge-install"
remove_install_sudoers
check "sudoers drop-in removed" "no" "$([[ -e $FLEDGE_TARGET/etc/sudoers.d/99-fledge-install ]] && echo yes || echo no)"
remove_install_sudoers
check "removal is idempotent" 0 "$?"

# The trap must fire on SIGTERM/SIGINT, even while a child is running.
for sig in TERM INT; do
  echo x > "$FLEDGE_TARGET/etc/sudoers.d/99-fledge-install"
  bash -c '
    source "$1/lib/desktop.sh"
    trap "remove_install_sudoers" EXIT
    trap "exit 143" TERM; trap "exit 130" INT
    sleep 30 & wait' _ "$DIR" &
  pid=$!; sleep 1; kill -"$sig" "$pid"; wait "$pid" 2>/dev/null
  check "sudoers drop-in removed on SIG$sig" "no" "$([[ -e $FLEDGE_TARGET/etc/sudoers.d/99-fledge-install ]] && echo yes || echo no)"
done

# A failed unmount or LUKS close after a good install must not fail the
# install (set -e, as in install-cachyos.sh; umount/cryptsetup stubbed to fail).
out="$(bash -c '
  set -euo pipefail
  source "$1/lib/desktop.sh"
  umount() { return 32; }; cryptsetup() { return 5; }
  LUKS_NAME=cryptroot FLEDGE_TARGET="$2"
  finish_install; echo "rc=$?"' _ "$DIR" "$T/nowhere" 2>&1)"
contains "finish: unmount failure tolerated" "rc=0" "$out"
contains "finish: says it couldn't unmount" "couldn't unmount" "$out"
contains "finish: says it couldn't close LUKS" "couldn't close cryptroot" "$out"

out="$(bash "$DIR/install-cachyos.sh" --desktop-only 'Bad Name' 2>&1)"; rc=$?
check "desktop-only: bad user refused" 1 "$rc"
contains "desktop-only: says why" "not a valid user name" "$out"

exit $fail
