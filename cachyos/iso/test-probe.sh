#!/usr/bin/env bash
# Unit tests for lib/probe.jq (fledge-probe's disk logic) against a fixture.
#   bash cachyos/iso/test-probe.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
FIX="$DIR/test/fixtures/lsblk.json"
defaults='{"ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7":"~/storage1"}'
probe() { jq -c --arg live /dev/sdc --argjson defaults "$defaults" -f "$DIR/lib/probe.jq" "$FIX" | jq -r "$1"; }

check "disks: no live stick, no usb, no zram" "/dev/sda /dev/nvme2n1 /dev/nvme0n1 /dev/vde" "$(probe '[.disks[].path] | join(" ")')"
check "disks: model trimmed"     "PNY CS900 480GB SSD" "$(probe '.disks[0].model')"
check "disks: parts listed"      "2" "$(probe '.disks[1].parts | length')"
check "datafs: data filesystems, usb included, live stick/ESP/LUKS/swap excluded" \
  "ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7 1234-ABCD 55cefb4f-6b27-4dbc-bbf8-5e9120defa26" "$(probe '[.datafs[].uuid] | join(" ")')"
check "datafs: whole-disk filesystem keeps its disk" "/dev/sdd" "$(probe '.datafs[1].disk')"
# shellcheck disable=SC2088  # the literal "~" is the data, expanded later by the UI
check "datafs: default mount from profile" "~/storage1" "$(probe '.datafs[0].mount')"
check "datafs: no default is null"  "null" "$(probe '.datafs[2].mount')"
check "datafs: label kept"          "big"  "$(probe '.datafs[2].label')"
check "no live disk known: stick listed as usb, still hidden" "/dev/sda /dev/nvme2n1 /dev/nvme0n1 /dev/vde" \
  "$(jq -c --arg live '' --argjson defaults '{}' -f "$DIR/lib/probe.jq" "$FIX" | jq -r '[.disks[].path] | join(" ")')"
check "datafs: filesystem without a uuid excluded, output still valid" "3" "$(probe '.datafs | length')"
check "disks: the uuid-less disk is still an install target" "/dev/vde" "$(probe '.disks[-1].path')"
check "disks: a whole-disk filesystem is listed as its content" "/dev/vde vfat" "$(probe '.disks[-1].parts[] | "\(.path) \(.fstype)"')"
check "disks: partitioned disk lists only its partitions" "1" "$(probe '.disks[0].parts | length')"

exit $fail
