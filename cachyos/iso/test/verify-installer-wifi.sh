#!/usr/bin/env bash
# The Wi-Fi picker lists networks in the installer's Network step and in quick
# settings, against simulated Wi-Fi (mac80211_hwsim + an NM hotspot, see the VM
# README) in the test VM. Runs on the host, but only drives the VM via vm.sh:
#   bash cachyos/iso/test/verify-installer-wifi.sh
# A fresh installer matters: there the picker is the first to use Net, before
# Networking has listed the adapter (the v2026.10.18 "Searching…" bug).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VM="$REPO/cachyos/vm/vm.sh"
# shellcheck source=SCRIPTDIR/../../install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"

ssid=fledge-test
ipc() { "$VM" run "LC_ALL=C.UTF-8 qs -p /tmp/fledge-installer ipc call installer $(printf '%q ' "$@")"; }
# Tab until the focus reaches the network row (objectName = SSID), up to n presses.
tab_to_ssid() {
  local i f
  for ((i = 0; i < $2; i++)); do
    "$VM" key KEY_TAB; sleep 0.3
    f="$($1)"
    [[ $f == "$ssid" ]] && { echo found; return; }
  done
  echo "not found (last focus: $f)"
}

"$VM" sync >/dev/null
"$VM" sudo "modprobe mac80211_hwsim radios=2 && sleep 2 && pacman -S --needed --noconfirm dnsmasq >/dev/null \
  && nmcli dev wifi hotspot ifname wlan1 con-name test-ap ssid $ssid password hunter2pass >/dev/null \
  && nmcli con modify test-ap ipv4.method shared && nmcli con up test-ap >/dev/null" || { echo "FAIL  simulated Wi-Fi setup"; exit 1; }
trap '"$VM" run "pkill -f \"^qs -p /tmp/fledge-installer\"; qs -c fledge ipc call quicksettings close" >/dev/null 2>&1
      "$VM" sudo "nmcli con delete test-ap >/dev/null; rmmod mac80211_hwsim" || true' EXIT
sleep 3

"$VM" run 'pkill -f "^qs -p /tmp/fledge-installer"; sleep 1; bash ~/proj/fledge/cachyos/iso/installer/dev/run.sh'
sleep 2
ipc go network
check "installer lists the network" found "$(tab_to_ssid "ipc focused" 4)"
"$VM" run 'pkill -f "^qs -p /tmp/fledge-installer"' || true

"$VM" run 'qs -c fledge ipc call quicksettings open wifi' >/dev/null
sleep 3
"$VM" shot verify-wifi-qs >/dev/null
check "quick settings picker open" wifi "$("$VM" run 'qs -c fledge ipc call shell state' | jq -r .picker)"

exit "$fail"
