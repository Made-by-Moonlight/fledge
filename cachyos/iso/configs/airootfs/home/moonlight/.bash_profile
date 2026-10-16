# shellcheck shell=bash
# Live ISO, tty1: start the graphical installer. If Hyprland can't start (or
# exits with an error), say so and leave this shell; Ctrl+Alt+F2 is a root
# console. Leaving the installer normally also lands here.
if [[ "$(tty)" == /dev/tty1 && -z "${WAYLAND_DISPLAY:-}" ]]; then
  export MBM_REPO=/usr/share/slievr-cachy
  if ! Hyprland --config /etc/mbm-installer/hyprland.conf >/tmp/hyprland-installer.log 2>&1; then
    echo
    echo "The graphical installer couldn't start."
    echo "  log: /tmp/hyprland-installer.log"
    echo "  a root console is on Ctrl+Alt+F2 (log in as root, no password)"
    echo "  to try again: Hyprland --config /etc/mbm-installer/hyprland.conf"
  fi
fi
