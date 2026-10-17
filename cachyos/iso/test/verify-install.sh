#!/usr/bin/env bash
# Post-install checks for a VM installed from the made by moonlight ISO.
# Run as slievr on the installed system, before any `vm.sh sync` (it rewrites
# ~/proj/slievr-cachy, which must still be clean), e.g.
#   ip="$(cachyos/vm/vm.sh ip)"
#   scp cachyos/iso/test/verify-install.sh "slievr@$ip:/tmp/"
#   ssh -t "slievr@$ip" 'VERIFY_LAYOUT=gb VERIFY_DATA_MOUNT=~/testdata bash /tmp/verify-install.sh'
# (needs a tty for sudo, so not `vm.sh run` and don't pipe it into ssh)
set -uo pipefail

bad=0
ok()  { printf 'PASS  %s\n' "$1"; }
no()  { printf 'FAIL  %s\n' "$1"; bad=1; }
is()  { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }

is "exactly one boot (no hang/retry)"  1      "$(journalctl --list-boots --no-pager | tail -n +2 | grep -c .)"
is "desktop installed before reboot"   1      "$(sudo grep -c 'Bootstrap complete.' /var/log/mbm-install.log 2>/dev/null)"
is "firstboot done-guard present"      yes    "$([[ -e /var/lib/slievr-firstboot-done ]] && echo yes || echo no)"
is "console layout in vconsole.conf"   yes    "$(grep -q '^XKBLAYOUT=' /etc/vconsole.conf && echo yes || echo no)"
# systemd 262's TPM measurement units (systemd-pcr*, systemd-tpm2-setup*) fail
# with "Could not extend NvPCR" on swtpm; nothing here uses measured boot.
is "no failed units (TPM measurement excluded)" 0 "$(systemctl --failed --no-legend --plain | grep -vE '^(systemd-pcr|systemd-tpm2-setup)' | grep -c .)"
is "quickshell installed"              yes    "$(command -v qs >/dev/null && echo yes || echo no)"
is "fledge shell enabled"                 enabled "$(systemctl --user is-enabled fledge-shell 2>/dev/null)"
is "fledge shell running"                 active "$(systemctl --user is-active fledge-shell 2>/dev/null)"
is "no retired desktop daemons"        ""     "$(pgrep -x 'waybar|mako|swayosd-server|hypridle|hyprlock|walker|elephant' 2>/dev/null; pgrep -f '^/usr/lib/polkit-gnome/' 2>/dev/null)"
# Holds the Hyprland instance only while locked; this runs in an unlocked session.
is "relock flag clear"                 ""     "$(cat "$HOME/.local/state/fledge/locked" 2>/dev/null)"
is "fledge settings valid"             ""     "$("$HOME/.local/share/fledge/bin/fledge" settings check 2>&1)"
gen="$HOME/.local/state/fledge/hypr"
is "generated Hyprland config"         yes    "$( [[ -s $gen/binds.lua && -s $gen/monitors.lua && -s $gen/workspaces.lua && -s $gen/input.lua ]] && echo yes || echo no )"
# Hyprland reads ~/.config/hypr/hyprland.lua (stowed); a .conf beside it would be
# the stub a .conf session writes, which lands in the repo through the stow fold.
is "Hyprland config is Lua"            yes    "$( [[ -e $HOME/.config/hypr/hyprland.lua && ! -e $HOME/.config/hypr/hyprland.conf ]] && echo yes || echo no )"
is "btop uses the theme"               yes    "$( [[ -L "$HOME/.config/btop/themes/current.theme" ]] && grep -q '^color_theme = "current"' "$HOME/.config/btop/btop.conf" && echo yes || echo no )"
is "sddm active"                       active "$(systemctl is-active sddm)"
is "firstboot disabled"                disabled "$(systemctl is-enabled slievr-firstboot.service 2>/dev/null)"
is "root account locked"               L      "$(sudo passwd -S root | awk '{print $2}')"
bloat="$(pacman -Qq | grep -E '^(plasma|kde|kwin|gnome-shell|xfce|lxqt|cinnamon|mate-|cachyos-.+-settings$)' || true)"
is "no desktop bloat"                  ""     "$bloat"
is "linux-cachyos kernel"              yes    "$(pacman -Q linux-cachyos >/dev/null 2>&1 && echo yes || echo no)"
# The CachyOS repos chroot-setup.sh wrote, for this CPU's level, above [core].
# shellcheck source=../../install/lib/cachyos-repos.sh
source ~/proj/slievr-cachy/cachyos/install/lib/cachyos-repos.sh
want="$(cachyos_repo_sections "$(cachyos_repo_level "$(/lib/ld-linux-x86-64.so.2 --help)" /proc/cpuinfo)" | grep '^\[' | tr '\n' ' ')[core] "
is "cachyos repos for this CPU"        "$want" "$(grep -E '^\[(cachyos.*|core)\]' /etc/pacman.conf | tr '\n' ' ')"
is "cachyos keyring + mirrorlists"     4      "$(pacman -Qq cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist 2>/dev/null | grep -c .)"
is "cachyos key trusted"               yes    "$(sudo pacman-key --list-keys F3B607488DB35A47 2>/dev/null | grep -q '\[ *full *\]\|\[ultimate\]' && echo yes || echo no)"
is "running kernel >= 7.2"            yes    "$( (( $(vercmp "$(uname -r | sed 's/-.*//')" 7.2) >= 0 )) && echo yes || echo no)"
is "repo origin is GitHub"             yes    "$(git -C ~/proj/slievr-cachy remote get-url origin | grep -q '^https://github.com/' && echo yes || echo no)"
is "bootstrap.sh is executable"        yes    "$([[ -x ~/proj/slievr-cachy/cachyos/bootstrap.sh ]] && echo yes || echo no)"
is "$HOME/.config is a real directory"     yes    "$( [[ -d $HOME/.config && ! -L $HOME/.config ]] && echo yes || echo no )"
is "repo has no local changes"         ""     "$(git -C ~/proj/slievr-cachy status --porcelain)"

# VERIFY_LAYOUT=gb: the installer's keyboard choice reached the user's settings.
if [[ -n "${VERIFY_LAYOUT:-}" ]]; then
  is "settings kbLayout"               "$VERIFY_LAYOUT" "$(jq -r '.input.kbLayout' "$HOME/.config/fledge/settings.json" 2>/dev/null)"
  is "vconsole XKBLAYOUT"              "XKBLAYOUT=$VERIFY_LAYOUT" "$(grep '^XKBLAYOUT=' /etc/vconsole.conf)"
fi
# VERIFY_DATA_MOUNT=~/testdata: the data disk is in fstab and mounts on access.
if [[ -n "${VERIFY_DATA_MOUNT:-}" ]]; then
  d="${VERIFY_DATA_MOUNT/#\~/$HOME}"
  is "data disk in fstab (nofail, automount)" 1 "$(grep -c " $d ext4 defaults,nofail,x-systemd.automount" /etc/fstab)"
  ls "$d" >/dev/null 2>&1
  is "data disk mounts on access"       yes   "$(findmnt -n "$d" -t ext4 >/dev/null && echo yes || echo no)"
fi

exit $bad
