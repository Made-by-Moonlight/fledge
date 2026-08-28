# shellcheck shell=bash
# Limine UKI bootloader setup. Runs INSIDE arch-chroot (sourced by
# chroot-setup.sh). Reproduces the reference desktop's mechanism:
#
#   limine + limine-mkinitcpio-hook  (provides limine-update / limine-install /
#   the mkinitcpio wrapper). Driven entirely by /etc/default/limine:
#     - ENABLE_UKI=yes         -> UKIs built in /boot/EFI/Linux/ by mkinitcpio
#     - KERNEL_CMDLINE[default] -> baked into the UKI + written to limine.conf
#     - limine-update           -> (re)generates UKIs + /boot/limine.conf entries
#     - limine-install          -> deploys Limine EFI binary + efibootmgr NVRAM entry
#
# NOTE (unverified): limine-mkinitcpio-hook is AUR on stock Arch. If it is not
# in the CachyOS repos, pacstrap in Task 7 fails on it -> prebuild it in the
# live env (makepkg) and `pacman --root /mnt -U` the result, or use whatever
# CachyOS ships as the equivalent. This is the expected first roadblock.
#
# Env in (exported by chroot-setup.sh):
#   KERNEL LUKS_NAME LUKS_PARTUUID EXTRA_CMDLINE GPU_CMDLINE SWAP RESUME_OFFSET HOSTNAME

setup_bootloader() {
  local cmdline_core cmdline_extra

  cmdline_core="cryptdevice=PARTUUID=${LUKS_PARTUUID}:${LUKS_NAME} root=/dev/mapper/${LUKS_NAME} rootflags=subvol=@ rw rootfstype=btrfs"
  cmdline_extra="${EXTRA_CMDLINE}"
  [[ -n "${GPU_CMDLINE:-}" ]] && cmdline_extra+=" ${GPU_CMDLINE}"
  if [[ "${SWAP:-zram}" == hibernate && -n "${RESUME_OFFSET:-}" ]]; then
    cmdline_extra+=" resume=/dev/mapper/${LUKS_NAME} resume_offset=${RESUME_OFFSET}"
  fi

  # Fallback for any plain-mkinitcpio UKI path / other tooling.
  printf '%s %s\n' "$cmdline_core" "$cmdline_extra" > /etc/kernel/cmdline

  install -Dm644 /dev/stdin /etc/default/limine <<EOF
TARGET_OS_NAME="CachyOS"
ESP_PATH="/boot"

KERNEL_CMDLINE[default]+="${cmdline_core}"
KERNEL_CMDLINE[default]+="${cmdline_extra}"

ENABLE_UKI=yes
CUSTOM_UKI_NAME="cachyos"

ENABLE_LIMINE_FALLBACK=yes
FIND_BOOTLOADERS=yes

BOOT_ORDER="*, *fallback, Snapshots"
MAX_SNAPSHOT_ENTRIES=5
EOF

  echo ">>> mkinitcpio -P" >&2
  mkinitcpio -P

  echo ">>> limine-update" >&2
  limine-update

  echo ">>> limine-install" >&2
  limine-install
}
