#!/usr/bin/env bash
set -euo pipefail

# Runs INSIDE the CachyOS live ISO environment (pushed via scp, run via ssh).
DISK=/dev/vda
HOSTNAME=cachyos-test
USERNAME=slievr
USER_PASSWORD="${1:?Usage: install-cachyos.sh <user-password>}"

parted -s "$DISK" mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB set 1 esp on \
  mkpart primary ext4 513MiB 100%

mkfs.fat -F32 "${DISK}1"
mkfs.ext4 -F "${DISK}2"

mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

pacstrap -K /mnt base linux linux-firmware networkmanager sudo vim git openssh

genfstab -U /mnt >> /mnt/etc/fstab

root_partuuid=$(blkid -s PARTUUID -o value "${DISK}2")

arch-chroot /mnt /bin/bash -e <<CHROOT
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "root:$USER_PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager sshd

curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o /tmp/cachyos-repo.tar.xz
tar xf /tmp/cachyos-repo.tar.xz -C /tmp
(cd /tmp/cachyos-repo && ./cachyos-repo.sh)

pacman -Syu --noconfirm
pacman -S --needed --noconfirm linux-cachyos linux-cachyos-headers

bootctl install

cat > /boot/loader/loader.conf <<LOADER
default cachyos.conf
timeout 3
console-mode max
LOADER

cat > /boot/loader/entries/cachyos.conf <<ENTRY
title   CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=PARTUUID=$root_partuuid rw
ENTRY
CHROOT

umount -R /mnt
echo "Install complete, rebooting."
reboot
