#!/usr/bin/env bash
set -euo pipefail

# Packages needed to create/run/manage the CachyOS test VM, plus tooling
# used by the other scripts in this plan (expect, shellcheck) and the ISO
# configurator dry run (gum).
PACKAGES=(qemu-full libvirt virt-manager virt-viewer dnsmasq edk2-ovmf swtpm expect shellcheck gum)

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

# qemu (running as libvirt-qemu) needs traverse permission down the directory
# chain to the cached ISO, which lives under $HOME. Grant it once here so
# provision-vm.sh needs no privileges. ACLs persist on disk.
ISO_CACHE_DIR="${ISO_CACHE_DIR:-$HOME/.cache/cachyos-iso}"
mkdir -p "$ISO_CACHE_DIR"
for d in "$HOME" "$HOME/.cache" "$ISO_CACHE_DIR"; do
  sudo setfacl -m u:libvirt-qemu:x "$d"
done

if ! sudo virsh net-info default &>/dev/null; then
  echo "Default libvirt network not found" >&2
  exit 1
fi

if [ "$(sudo virsh net-info default | awk '/^Active/{print $2}')" != "yes" ]; then
  sudo virsh net-start default
fi
sudo virsh net-autostart default

echo "Host is ready for VM provisioning."
