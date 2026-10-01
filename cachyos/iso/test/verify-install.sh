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

is "exactly one boot (no hang/retry)"  1      "$(journalctl --list-boots --no-pager --no-legend | grep -c .)"
is "firstboot finished bootstrap"      1      "$(grep -c 'Bootstrap complete.' /var/log/slievr-firstboot.log)"
is "no failed units"                   0      "$(systemctl --failed --no-legend | grep -c .)"
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
