#!/usr/bin/env bash
# Runs INSIDE `arch-chroot /mnt`. Invoked as: bash /root/chroot-setup.sh
# All inputs arrive as exported env vars (see install-cachyos.sh Task 7 step 4):
#   TIMEZONE LOCALE KEYMAP USERNAME HOSTNAME KERNEL SWAP
#   LUKS_NAME LUKS_PARTUUID EXTRA_CMDLINE
#   GPU_MODULES GPU_CMDLINE ZRAM_SIZE RESUME_OFFSET
#   USER_PASSWORD ROOT_PASSWORD
set -euo pipefail

HERE="$(dirname "$(realpath "$0")")"

echo ">>> time / locale / keymap" >&2
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc
echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

if [[ -z "${HOSTNAME:-}" ]]; then
  read -rp "Hostname: " HOSTNAME
fi
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

echo ">>> users" >&2
useradd -m -G wheel -s /bin/bash "${USERNAME}"
printf '%s:%s\n' "${USERNAME}" "${USER_PASSWORD}" | chpasswd
printf 'root:%s\n' "${ROOT_PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ">>> zram (${ZRAM_SIZE} MiB)" >&2
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ${ZRAM_SIZE}
compression-algorithm = zstd
EOF

echo ">>> mkinitcpio.conf" >&2
hooks="base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck"
if [[ "${SWAP:-zram}" == hibernate ]]; then
  hooks="${hooks/ fsck/ resume fsck}"
fi
sed -i "s/^HOOKS=.*/HOOKS=(${hooks})/" /etc/mkinitcpio.conf
sed -i "s/^MODULES=.*/MODULES=(${GPU_MODULES:-})/" /etc/mkinitcpio.conf

echo ">>> CachyOS repos" >&2
# pacstrap writes a stock-Arch /etc/pacman.conf into the target (no [cachyos]
# repos, no cachyos-mirrorlist), even though the live ISO used its own config to
# resolve linux-cachyos. Add the repos the same way CachyOS's own installer
# does, so `pacman -Syu` and bootstrap.sh can find cachyos-only packages
# (steam-jupiter-stable, elephant providers, etc.).
if ! grep -q '^\[cachyos\]' /etc/pacman.conf; then
  curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o /tmp/cachyos-repo.tar.xz
  tar xf /tmp/cachyos-repo.tar.xz -C /tmp
  ( cd /tmp/cachyos-repo && ./cachyos-repo.sh )
fi
pacman -Syu --noconfirm

echo ">>> services" >&2
systemctl enable NetworkManager sshd

echo ">>> bootloader" >&2
# shellcheck source=bootloader.sh
source "${HERE}/bootloader.sh"
setup_bootloader

echo ">>> chroot-setup done" >&2
