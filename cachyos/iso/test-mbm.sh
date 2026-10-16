#!/usr/bin/env bash
# Unit tests for cachyos/iso/lib/mbm.sh. No ISO, no network.
#   bash cachyos/iso/test-mbm.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/mbm.sh
source "$DIR/lib/mbm.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

ok()  { "$@" && echo yes || echo no; }
check "hostname: simple"            yes "$(ok valid_hostname glaux)"
check "hostname: digits and dash"   yes "$(ok valid_hostname ninox-2)"
check "hostname: uppercase rejected" no "$(ok valid_hostname Glaux)"
check "hostname: leading dash"       no "$(ok valid_hostname -glaux)"
check "hostname: trailing dash"      no "$(ok valid_hostname glaux-)"
check "hostname: dot rejected"       no "$(ok valid_hostname glaux.local)"
check "hostname: empty rejected"     no "$(ok valid_hostname '')"
check "hostname: 63 chars ok"       yes "$(ok valid_hostname "$(printf 'a%.0s' {1..63})")"
check "hostname: 64 chars rejected"  no "$(ok valid_hostname "$(printf 'a%.0s' {1..64})")"

write_answers "$T/a.env" "DISK=/dev/disk/by-id/nvme-X" "USER_PASSWORD=s3cret pass" "LUKS_PASSPHRASE=luks=pw"
check "answers: mode 600" "600" "$(stat -c '%a' "$T/a.env")"
check "answers: one KEY=value per line" \
  $'DISK=/dev/disk/by-id/nvme-X\nUSER_PASSWORD=s3cret pass\nLUKS_PASSPHRASE=luks=pw' "$(cat "$T/a.env")"

check "answers: newline refused" "1" "$(write_answers "$T/b.env" $'USER_PASSWORD=a\nDISK=/dev/sda' 2>/dev/null; echo $?)"
check "answers: refused file removed" "gone" "$([[ -e "$T/b.env" ]] && echo present || echo gone)"

exit $fail
