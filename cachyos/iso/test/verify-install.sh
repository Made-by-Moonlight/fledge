#!/usr/bin/env bash
# Post-install checks for a VM installed from the made by moonlight ISO.
# Run as slievr on the installed system, e.g.
#   scp cachyos/iso/test/verify-install.sh slievr@<vm-ip>:/tmp/ && ssh -t slievr@<vm-ip> bash /tmp/verify-install.sh
# (needs a tty for sudo, so don't pipe it into ssh)
set -uo pipefail

bad=0
ok()  { printf 'PASS  %s\n' "$1"; }
no()  { printf 'FAIL  %s\n' "$1"; bad=1; }
is()  { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }

is "exactly one boot (no hang/retry)"  1      "$(journalctl --list-boots --no-pager | tail -n +2 | grep -c .)"
is "firstboot finished bootstrap"      1      "$(grep -c 'Bootstrap complete.' /var/log/slievr-firstboot.log)"
# systemd 262's TPM measurement units (systemd-pcr*, systemd-tpm2-setup*) fail
# with "Could not extend NvPCR" on swtpm; nothing here uses measured boot.
is "no failed units (TPM measurement excluded)" 0 "$(systemctl --failed --no-legend --plain | grep -vE '^(systemd-pcr|systemd-tpm2-setup)' | grep -c .)"
is "quickshell installed"              yes    "$(command -v qs >/dev/null && echo yes || echo no)"
is "mbm shell enabled"                 enabled "$(systemctl --user is-enabled mbm-shell 2>/dev/null)"
is "mbm settings valid"                ""     "$("$HOME/.local/share/mbm/bin/mbm" settings check 2>&1)"
# shellcheck disable=SC2012 # counting plain *.conf names
is "generated Hyprland config"         4      "$(ls "$HOME"/.local/state/mbm/hypr/*.conf 2>/dev/null | wc -l)"
is "btop uses the theme"               yes    "$( [[ -L "$HOME/.config/btop/themes/current.theme" ]] && grep -q '^color_theme = "current"' "$HOME/.config/btop/btop.conf" && echo yes || echo no )"
is "sddm active"                       active "$(systemctl is-active sddm)"
is "firstboot disabled"                disabled "$(systemctl is-enabled slievr-firstboot.service 2>/dev/null)"
is "root account locked"               L      "$(sudo passwd -S root | awk '{print $2}')"
bloat="$(pacman -Qq | grep -E '^(plasma|kde|kwin|gnome-shell|xfce|lxqt|cinnamon|mate-|cachyos-.+-settings$)' || true)"
is "no desktop bloat"                  ""     "$bloat"
is "linux-cachyos kernel"              yes    "$(pacman -Q linux-cachyos >/dev/null 2>&1 && echo yes || echo no)"
is "running kernel >= 7.2"             yes    "$( (( $(vercmp "$(uname -r | sed 's/-.*//')" 7.2) >= 0 )) && echo yes || echo no)"
is "repo origin is GitHub"             yes    "$(git -C ~/proj/slievr-cachy remote get-url origin | grep -q '^https://github.com/' && echo yes || echo no)"
is "bootstrap.sh is executable"        yes    "$([[ -x ~/proj/slievr-cachy/cachyos/bootstrap.sh ]] && echo yes || echo no)"
is "$HOME/.config is a real directory"     yes    "$( [[ -d $HOME/.config && ! -L $HOME/.config ]] && echo yes || echo no )"
is "repo has no local changes"         ""     "$(git -C ~/proj/slievr-cachy status --porcelain)"

exit $bad
