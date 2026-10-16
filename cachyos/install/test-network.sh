#!/usr/bin/env bash
# Unit tests for lib/network.sh. No VM state touched.
#   bash cachyos/install/test-network.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/network.sh
source "$DIR/lib/network.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkdir -p "$T/src"
printf '[connection]\nid=Owl House\n' > "$T/src/Owl House.nmconnection"
printf '[connection]\nid=cafe\n'      > "$T/src/cafe.nmconnection"
printf 'not a profile\n'              > "$T/src/README"
out="$(copy_nm_profiles "$T/src" "$T/dst")"
check "copies every profile, reports names" $'network: Owl House\nnetwork: cafe' "$out"
check "profiles are root-only"   "600" "$(stat -c '%a' "$T/dst/cafe.nmconnection")"
check "dir is root-only"         "700" "$(stat -c '%a' "$T/dst")"
check "only .nmconnection files" "no"  "$([[ -e $T/dst/README ]] && echo yes || echo no)"
check "nothing to copy is fine"  ""    "$(copy_nm_profiles "$T/none" "$T/dst2")"
check "nothing to copy makes no dir" "no" "$([[ -e $T/dst2 ]] && echo yes || echo no)"

exit $fail
