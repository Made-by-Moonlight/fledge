#!/usr/bin/env bash
# Runs INSIDE `arch-chroot /mnt`. Invoked as: bash /root/chroot-setup.sh
# All inputs arrive as exported env vars (see install-cachyos.sh Task 7 step 4):
#   TIMEZONE LOCALE KEYMAP XKB_LAYOUT XKB_VARIANT MBM_PROGRESS USERNAME HOSTNAME KERNEL SWAP
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
# KEYMAP for the console and the LUKS prompt (sd-vconsole in the initramfs);
# XKB* so localectl and anything reading vconsole.conf see the real layout.
{
  echo "KEYMAP=${KEYMAP}"
  echo "XKBLAYOUT=${XKB_LAYOUT}"
  if [[ -n "${XKB_VARIANT:-}" ]]; then echo "XKBVARIANT=${XKB_VARIANT}"; fi
} > /etc/vconsole.conf

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
if [[ -n "${ROOT_PASSWORD:-}" ]]; then
  printf 'root:%s\n' "${ROOT_PASSWORD}" | chpasswd
else
  passwd -l root            # unattended (ISO) install: no root login, sudo via wheel
fi
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ">>> zram (${ZRAM_SIZE} MiB)" >&2
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ${ZRAM_SIZE}
compression-algorithm = zstd
EOF

echo ">>> plymouth theme" >&2
# Graphical boot splash + LUKS password prompt. Theme was copied to
# /usr/share/plymouth/themes/slievr-cachy by install-cachyos.sh. 'splash' is
# already in the kernel cmdline (profile.sh EXTRA_CMDLINE).
plymouth-set-default-theme slievr-cachy

echo ">>> mkinitcpio.conf" >&2
# plymouth hook goes after kms, before encrypt, so the splash is up before the
# LUKS prompt and 'encrypt' routes the prompt through plymouth.
hooks="base udev autodetect microcode modconf kms plymouth keyboard keymap consolefont block encrypt filesystems fsck"
if [[ "${SWAP:-zram}" == hibernate ]]; then
  hooks="${hooks/ fsck/ resume fsck}"
fi
sed -i "s/^HOOKS=.*/HOOKS=(${hooks})/" /etc/mkinitcpio.conf
sed -i "s/^MODULES=.*/MODULES=(${GPU_MODULES:-})/" /etc/mkinitcpio.conf

echo ">>> CachyOS repos" >&2
# pacstrap writes a stock /etc/pacman.conf into the target (no [cachyos]
# repos), even though the live ISO used its own config to resolve
# linux-cachyos. Add them, at the most specific level this CPU runs, so
# `pacman -Syu` and bootstrap.sh find cachyos-only packages (steam-jupiter-
# stable, elephant providers, etc.). pacstrap installed cachyos-keyring and the
# mirrorlists; the keyring's own populate is skipped when it is installed
# before pacman, so populate here (idempotent).
pacman-key --populate cachyos
# shellcheck source=cachyos-repos.sh
source "${HERE}/cachyos-repos.sh"
add_cachyos_repos /etc/pacman.conf \
  "$(cachyos_repo_level "$(/lib/ld-linux-x86-64.so.2 --help)" /proc/cpuinfo)"
# A single slow file fails the whole transaction (as with pacstrap): retry
# with fresh databases.
for attempt in 1 2 3; do
  pacman -Syu --noconfirm && break
  if (( attempt == 3 )); then
    echo "ERROR: pacman -Syu failed 3 times - check the network and the log above" >&2
    exit 1
  fi
  echo "WARN: pacman -Syu failed (attempt $attempt/3); refreshing package databases and retrying in 10s" >&2
  sleep 10
  pacman -Syy --noconfirm || true
done

echo ">>> services" >&2
systemctl enable NetworkManager sshd

if [[ "${MBM_PROGRESS:-}" == 1 ]]; then echo "@@mbm stage boot Bootloader"; fi
echo ">>> bootloader" >&2
# shellcheck source=bootloader.sh
source "${HERE}/bootloader.sh"
setup_bootloader

echo ">>> chroot-setup done" >&2
