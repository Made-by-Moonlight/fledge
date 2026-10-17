#!/usr/bin/env bash
# Dev loop for the installer UI, in the VM's desktop session (never the host):
#   cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/cachyos/iso/installer/dev/run.sh'
# Copies the config with symlinks resolved (as build-iso.sh does) and starts it
# in dev mode: canned facts, a fake install, no keyboard-layout changes.
# Ctrl+Q quits (or: pkill -f '^qs -p /tmp/fledge-installer'; anchored, so it can't match the
# shell running it). Drive it with: qs -p /tmp/fledge-installer ipc call installer go <step>
set -euo pipefail

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../.." && pwd)"
pkill -f '^qs -p /tmp/fledge-installer' || true
rm -rf /tmp/fledge-installer
cp -rL "$REPO/cachyos/iso/installer" /tmp/fledge-installer
: > /tmp/fledge-installer.log
# Started by Hyprland, not this SSH login, so it lands in the graphical session.
fledge="$REPO/dot-local/share/fledge/bin/fledge"
cmd="env FLEDGE_INSTALLER_DEV=1 FLEDGE_REPO=$REPO qs -p /tmp/fledge-installer >/tmp/fledge-installer.log 2>&1"
"$fledge" hypr dispatch "hl.dsp.exec_cmd($("$fledge" hypr quote "$cmd"))"
sleep 3
# Qt's text-input-v3 logs disableSurface once whenever a layer surface takes the
# keyboard, which the installer must; it is not a QML problem.
grep -E 'WARN|ERROR' /tmp/fledge-installer.log | grep -v 'QWaylandTextInputv3::disableSurface' | tail -n 40 || true
