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

# The installer's own NOPASSWD rule for its Desktop stage. Its EXIT trap
# removes it, but power loss or SIGKILL mid-stage can't be trapped, and that
# is exactly when this service is still enabled: drop it here.
rm -f /etc/sudoers.d/99-fledge-install

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

# Wi-Fi can take a while to associate, and a machine may have no profile at
# all. Wait for the internet; if it never comes, explain how to connect and
# stay enabled (no `systemctl disable`), so the next boot or a manual start
# runs this again.
online() { curl -fsI --max-time 5 https://archlinux.org >/dev/null 2>&1; }
for (( waited = 0; waited < 120; waited += 5 )); do
  online && break
  (( waited == 0 )) && echo ">>> waiting up to 2 minutes for an internet connection..."
  sleep 5
done
if ! online; then
  echo
  echo "##################################################################"
  echo "# No internet connection, so the desktop can't be installed yet."
  echo "#"
  echo "# 1. Log in as $USER_NAME and connect:"
  echo "#        nmtui"
  echo "# 2. Then finish setup (or just reboot):"
  echo "#        sudo systemctl start slievr-firstboot"
  echo "##################################################################"
  exit 1
fi

# CachyOS mirrors are occasionally mid-sync (the database lists a package the
# mirror doesn't have yet -> 404 and bootstrap aborts). Retry a couple of times
# with fresh databases before giving up; bootstrap.sh is safe to re-run.
ok=0
rc=0
for attempt in 1 2 3; do
  echo ">>> running $BOOTSTRAP as $USER_NAME (attempt $attempt/3)"
  runuser -l "$USER_NAME" -c "$BOOTSTRAP" && { ok=1; break; }
  rc=$?
  if (( attempt < 3 )); then
    echo ">>> bootstrap failed (exit $rc) - a mirror may be mid-sync; refreshing databases and retrying in 60s"
    sleep 60
    pacman -Syy --noconfirm || true
  fi
done

if (( ok )); then
  echo
  echo ">>> bootstrap OK — enabling graphical login"
  systemctl disable slievr-firstboot.service || true
  systemctl enable sddm.service
  systemctl start sddm.service
  echo ">>> done. SDDM should be up now."
else
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
