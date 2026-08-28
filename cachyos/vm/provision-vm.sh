#!/usr/bin/env bash
set -euo pipefail

VM_NAME="cachyos-test"
VM_VCPUS=4
VM_RAM_MB=8192
VM_DISK_GB=40
# A second, blank disk. The installer (cachyos/install/install-cachyos.sh) is
# run against the FIRST disk; this one stands in for the real machine's data
# disks so multi-disk selection and the wrong-disk guard get exercised, and it
# doubles as the "staged repo" delivery medium in the test loop.
VM_DATA_DISK_GB=8
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if sudo virsh dominfo "$VM_NAME" &>/dev/null; then
  echo "VM '$VM_NAME' already exists. Run destroy-vm.sh first to recreate it." >&2
  exit 1
fi

iso_path=$("$SCRIPT_DIR/download-iso.sh")

# Grant libvirt-qemu traverse-only (execute) permission on directory chain to ISO
# This allows qemu-system-x86_64 running as libvirt-qemu to open the ISO file
sudo setfacl -m u:libvirt-qemu:x "$HOME"
sudo setfacl -m u:libvirt-qemu:x "$HOME/.cache"
sudo setfacl -m u:libvirt-qemu:x "$(dirname "$iso_path")"

sudo virt-install \
  --name "$VM_NAME" \
  --vcpus "$VM_VCPUS" \
  --memory "$VM_RAM_MB" \
  --disk "size=$VM_DISK_GB,path=/var/lib/libvirt/images/${VM_NAME}.qcow2" \
  --disk "size=$VM_DATA_DISK_GB,path=/var/lib/libvirt/images/${VM_NAME}-data.qcow2" \
  --cdrom "$iso_path" \
  --os-variant archlinux \
  --network network=default \
  --graphics spice \
  --console pty,target_type=serial \
  --boot uefi \
  --events on_reboot=restart \
  --noautoconsole

echo "VM '$VM_NAME' created and booting from ISO."
echo "Serial console: sudo virsh console $VM_NAME"
echo "Graphical display: virt-viewer --connect qemu:///system $VM_NAME"
