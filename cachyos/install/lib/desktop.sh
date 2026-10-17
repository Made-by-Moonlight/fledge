# shellcheck shell=bash
# The desktop layer, installed before the first reboot: bootstrap.sh runs as
# the new user inside the target (arch-chroot), so the first boot lands on the
# login screen. If it fails, slievr-firstboot.service (already enabled) runs it
# again on first boot, as it always used to.
# Sourced by install-cachyos.sh. The target is mounted at $FLEDGE_TARGET.

FLEDGE_TARGET="${FLEDGE_TARGET:-/mnt}"

# seed_user_settings <user> <xkb layout> <xkb variant> <uid> <gid>  ->  the
# chosen layout as the user's fledge settings override, so Hyprland and the
# settings window start with it. Nothing for the default (us, no variant).
# Values are validated (valid_xkb_layout/variant) before they get here.
seed_user_settings() {
  local user="$1" layout="$2" variant="$3" uid="$4" gid="$5" dir
  [[ "$layout" == us && -z "$variant" ]] && return 0
  dir="$FLEDGE_TARGET/home/$user/.config/fledge"
  install -d -o "$uid" -g "$gid" "$FLEDGE_TARGET/home/$user/.config" "$dir"
  printf '{ "input": { "kbLayout": "%s", "kbVariant": "%s" } }\n' "$layout" "$variant" > "$dir/settings.json"
  chown "$uid:$gid" "$dir/settings.json"
}

# remove_install_sudoers  ->  drop the temporary passwordless sudo. Called by
# install-cachyos.sh's EXIT trap too, so a cancelled or killed install never
# leaves the installed system with NOPASSWD:ALL.
remove_install_sudoers() {
  rm -f "$FLEDGE_TARGET/etc/sudoers.d/99-mbm-install"
}

# run_desktop_stage <user>  ->  0 once bootstrap.sh completed in the target.
# bootstrap.sh calls sudo throughout: passwordless sudo for this stage only.
# runuser -l starts from a clean login environment, so bootstrap sees no
# Hyprland session and skips its live-session steps (hyprctl, systemctl --user).
run_desktop_stage() {
  local user="$1" sudoers="$FLEDGE_TARGET/etc/sudoers.d/99-mbm-install" attempt ok=0
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" > "$sudoers"
  chmod 440 "$sudoers"
  for attempt in 1 2 3; do
    echo ">>> desktop: bootstrap.sh as $user (attempt $attempt/3)"
    if arch-chroot "$FLEDGE_TARGET" runuser -l "$user" -c 'bash ~/proj/slievr-cachy/cachyos/bootstrap.sh'; then
      ok=1; break
    fi
    # Mirrors are sometimes mid-sync (a listed package 404s); bootstrap.sh is safe to re-run.
    if (( attempt < 3 )); then
      echo ">>> bootstrap failed; refreshing package databases and retrying in 30s"
      sleep 30
      arch-chroot "$FLEDGE_TARGET" pacman -Syy --noconfirm || true
    fi
  done
  remove_install_sudoers
  (( ok )) || return 1
  arch-chroot "$FLEDGE_TARGET" systemctl disable slievr-firstboot.service
  touch "$FLEDGE_TARGET/var/lib/slievr-firstboot-done"
  arch-chroot "$FLEDGE_TARGET" systemctl enable sddm.service
}

# finish_install  ->  keep the install log in the new system, then close it up.
# Always 0: by now the system is complete, and a busy mount or an open LUKS
# mapping is torn down by the reboot anyway. Failing here would make the
# graphical installer offer to erase and start over.
finish_install() {
  if [[ -f /var/log/mbm-install.log ]]; then
    install -Dm600 /var/log/mbm-install.log "$FLEDGE_TARGET/var/log/mbm-install.log" \
      || echo "WARN: couldn't copy the install log into the new system" >&2
  fi
  umount -R "$FLEDGE_TARGET" \
    || echo "WARN: couldn't unmount $FLEDGE_TARGET; the reboot will" >&2
  cryptsetup close "$LUKS_NAME" \
    || echo "WARN: couldn't close $LUKS_NAME; the reboot will" >&2
  return 0
}
