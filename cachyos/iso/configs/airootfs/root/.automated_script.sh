#!/usr/bin/env bash
# Live ISO entry point. releng's ~/.zlogin runs this on each root login; it
# only acts on tty1: load the brand console palette, then run the
# configurator. Leaving the configurator lands you in this root shell.
[[ "$(tty)" == /dev/tty1 ]] || exit 0

MBM_REPO=/usr/share/slievr-cachy
# shellcheck source=SCRIPTDIR/../../../../branding/palette.sh
source "$MBM_REPO/cachyos/branding/palette.sh"
mbm_vt_palette
clear

if ! mbm-configurator; then
  echo
  echo "Installer closed. Run 'mbm-configurator' to start again."
fi
