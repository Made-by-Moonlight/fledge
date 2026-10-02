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

# iwctl get-networks as it reaches a pipe: ANSI colour, rows padded with
# trailing spaces, '>' on the connected network, dim stars for missing signal.
E=$'\e'
printf '%s\n' \
  "                               Available networks                             " \
  "--------------------------------------------------------------------------------" \
  "${E}[1;90m      Network name                      Security            Signal         ${E}[0m" \
  "--------------------------------------------------------------------------------" \
  "  ${E}[1;90m> ${E}[0m  Owl House                         psk                 ****           " \
  "      Moonlight-5G                      psk                 ***${E}[1;90m*${E}[0m           " \
  "      cafe guest wifi                   open                **${E}[1;90m**${E}[0m           " \
  "      corp                              8021x               *${E}[1;90m***${E}[0m           " \
  "" > "$T/nets.txt"
check "wifi: names only, no security or signal" \
  $'Owl House\nMoonlight-5G\ncafe guest wifi\ncorp' "$(parse_networks < "$T/nets.txt")"
check "wifi: empty table gives nothing" "" "$(head -4 "$T/nets.txt" | parse_networks)"

write_answers "$T/a.env" "DISK=/dev/disk/by-id/nvme-X" "USER_PASSWORD=s3cret pass" "LUKS_PASSPHRASE=luks=pw"
check "answers: mode 600" "600" "$(stat -c '%a' "$T/a.env")"
check "answers: one KEY=value per line" \
  $'DISK=/dev/disk/by-id/nvme-X\nUSER_PASSWORD=s3cret pass\nLUKS_PASSPHRASE=luks=pw' "$(cat "$T/a.env")"
check "answers: masked for display" \
  $'DISK=/dev/disk/by-id/nvme-X\nUSER_PASSWORD=********\nLUKS_PASSPHRASE=********' "$(mask_answers "$T/a.env")"

check "answers: newline refused" "1" "$(write_answers "$T/b.env" $'USER_PASSWORD=a\nDISK=/dev/sda' 2>/dev/null; echo $?)"
check "answers: refused file removed" "gone" "$([[ -e "$T/b.env" ]] && echo present || echo gone)"

exit $fail
