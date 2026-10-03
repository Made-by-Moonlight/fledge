#!/usr/bin/env bash
# Unit tests for lib/network.sh. No VM, no radio.
#   bash cachyos/install/test-network.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/network.sh
source "$DIR/lib/network.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# iwd's known-network files: <SSID>.psk|.open|.8021x, or ="hex".<ext> when the
# SSID has characters outside [A-Za-z0-9 _-].
mkdir -p "$T/iwd"
printf '[Security]\nPassphrase=hunter2 owl\n' > "$T/iwd/Owl House.psk"
printf '[Security]\nPreSharedKey=%s\n' "$(printf 'ab%.0s' {1..32})" > "$T/iwd/RawKey.psk"
printf '[Settings]\nAutoConnect=true\n' > "$T/iwd/cafe guest.open"
printf '[Settings]\nHidden=true\n[Security]\nPassphrase=secretsecret\n' > "$T/iwd/Hideout.psk"
printf '[Security]\nPassphrase=dotdotdot\n' > "$T/iwd/=4d6f6f6e2e6c69676874.psk"   # "Moon.light"
printf '[Security]\nEAP-Method=PEAP\n' > "$T/iwd/corp.8021x"

check "ssid: plain filename"   "Owl House"  "$(iwd_ssid "$T/iwd/Owl House.psk")"
check "ssid: hex filename"     "Moon.light" "$(iwd_ssid "$T/iwd/=4d6f6f6e2e6c69676874.psk")"
check "ssid bytes: decimal list" "79;119;108;" "$(ssid_bytes "Owl")"

nm="$(iwd_to_nm "$T/iwd/Owl House.psk" 1111-2222)"
contains "psk: id"          $'\nid=Owl House\n'              "$nm"
contains "psk: uuid"        $'\nuuid=1111-2222\n'            "$nm"
contains "psk: wifi type"   $'\ntype=wifi\n'                 "$nm"
contains "psk: ssid bytes"  "ssid=$(ssid_bytes "Owl House")" "$nm"
contains "psk: key-mgmt"    $'\nkey-mgmt=wpa-psk\n'          "$nm"
contains "psk: passphrase"  $'\npsk=hunter2 owl\n'           "$nm"
contains "psk: ipv4 auto"   $'[ipv4]\nmethod=auto'           "$nm"

contains "raw key: hex psk" "psk=$(printf 'ab%.0s' {1..32})" "$(iwd_to_nm "$T/iwd/RawKey.psk" u)"
open="$(iwd_to_nm "$T/iwd/cafe guest.open" u)"
contains "open: id" $'\nid=cafe guest\n' "$open"
check "open: no security section" "" "$(grep -E 'wifi-security|psk=' <<<"$open")"
contains "hidden: flagged" $'\nhidden=true\n' "$(iwd_to_nm "$T/iwd/Hideout.psk" u)"
check "8021x: skipped" "no" "$(iwd_to_nm "$T/iwd/corp.8021x" u >/dev/null 2>&1 && echo yes || echo no)"

install_wifi_profiles "$T/iwd" "$T/nm" >/dev/null
check "install: one keyfile per supported network" \
  $'Hideout.nmconnection\nMoon.light.nmconnection\nOwl House.nmconnection\nRawKey.nmconnection\ncafe guest.nmconnection' \
  "$(ls "$T/nm" | LC_ALL=C sort)"
check "install: keyfiles are root-only (600)" "600" "$(stat -c %a "$T/nm/Owl House.nmconnection")"
check "install: missing iwd dir is fine" "0" "$(install_wifi_profiles "$T/none" "$T/nm2" >/dev/null; echo $?)"

exit $fail
