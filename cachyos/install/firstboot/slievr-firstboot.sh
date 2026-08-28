#!/usr/bin/env bash
# First real boot after install-cachyos.sh. Runs the desktop layer
# (cachyos/bootstrap.sh) as the user, unattended, with output on TTY1 and in
# /var/log/slievr-firstboot.log, then hands off to the graphical login.
#
# @USERNAME@ is substituted by install-cachyos.sh when this is copied into the
# target. Installed as /usr/local/sbin/slievr-firstboot.sh, run by
# slievr-firstboot.service (oneshot, guarded by /var/lib/slievr-firstboot-done).
set -uo pipefail

USER_NAME="@USERNAME@"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
BOOTSTRAP="${USER_HOME}/proj/slievr-cachy/cachyos/bootstrap.sh"
LOG=/var/log/slievr-firstboot.log
SUDOERS=/etc/sudoers.d/99-slievr-firstboot

exec > >(tee -a "$LOG") 2>&1
echo
echo "=================================================================="
echo " slievr first-boot bootstrap — $(date)"
echo " log: $LOG"
echo "=================================================================="

if [[ ! -x "$BOOTSTRAP" ]]; then
  echo "ERROR: $BOOTSTRAP not found or not executable."
  echo "The staged repo should be at ${USER_HOME}/proj/slievr-cachy — check the install."
  exit 1
fi

# bootstrap.sh runs as the user but calls sudo throughout. Grant passwordless
# sudo for the duration only.
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_NAME" > "$SUDOERS"
chmod 440 "$SUDOERS"
cleanup() { rm -f "$SUDOERS"; }
trap cleanup EXIT

echo ">>> running $BOOTSTRAP as $USER_NAME"
if runuser -l "$USER_NAME" -c "$BOOTSTRAP"; then
  echo
  echo ">>> bootstrap OK — enabling graphical login"
  systemctl disable slievr-firstboot.service || true
  systemctl enable sddm.service
  systemctl start sddm.service
  echo ">>> done. SDDM should be up now."
else
  rc=$?
  echo
  echo "##################################################################"
  echo "# bootstrap FAILED (exit $rc). Full log: $LOG"
  echo "#"
  echo "# The repo is at ${USER_HOME}/proj/slievr-cachy — fix the cause,"
  echo "# then re-run as $USER_NAME:"
  echo "#     ~/proj/slievr-cachy/cachyos/bootstrap.sh"
  echo "# and once it succeeds:  sudo systemctl enable --now sddm.service"
  echo "##################################################################"
  systemctl disable slievr-firstboot.service || true
  exit "$rc"
fi
