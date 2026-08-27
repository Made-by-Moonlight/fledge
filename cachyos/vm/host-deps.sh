#!/usr/bin/env bash
set -euo pipefail

# Packages needed to create/run/manage the CachyOS test VM, plus tooling
# used by the other scripts in this plan (expect, shellcheck).
PACKAGES=(qemu-full libvirt virt-manager virt-viewer dnsmasq edk2-ovmf swtpm expect shellcheck)

missing=()
for pkg in "${PACKAGES[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Installing missing packages: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
else
  echo "All required packages already installed."
fi

if ! id -nG "$USER" | grep -qw libvirt; then
  echo "Adding $USER to libvirt group (log out/in required to take effect)"
  sudo usermod -aG libvirt "$USER"
fi

sudo systemctl enable --now libvirtd.service
sudo systemctl enable --now libvirtd.socket

if ! sudo virsh net-info default &>/dev/null; then
  echo "Default libvirt network not found" >&2
  exit 1
fi

if [ "$(sudo virsh net-info default | awk '/^Active/{print $2}')" != "yes" ]; then
  sudo virsh net-start default
fi
sudo virsh net-autostart default

echo "Host is ready for VM provisioning."
