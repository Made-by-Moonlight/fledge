#!/usr/bin/env bash
set -euo pipefail

# Creates the disposable CachyOS test VM. Talks to the system libvirt over
# qemu:///system, which only needs libvirt-group membership - NO sudo. The
# one-time privileged host setup (packages, group, ISO-dir ACLs) lives in
# host-deps.sh; run that once if this script complains about access.

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
VIRSH="virsh -c qemu:///system"

if $VIRSH dominfo "$VM_NAME" &>/dev/null; then
  echo "VM '$VM_NAME' already exists. Run destroy-vm.sh first to recreate it." >&2
  exit 1
fi

# ISO_PATH: boot a specific ISO (e.g. our own, via cachyos/iso/bin/slievr-iso-boot);
# default is the latest stock CachyOS ISO.
iso_path="${ISO_PATH:-$("$SCRIPT_DIR/download-iso.sh")}"

# qemu (running as libvirt-qemu) must be able to traverse the directory chain
# to the ISO. host-deps.sh sets these ACLs once; verify rather than re-apply so
# this script needs no privileges.
iso_dir="$(dirname "$iso_path")"
for d in "$HOME" "$HOME/.cache" "$iso_dir"; do
  perms="$(stat -c '%A' "$d")"
  # world-executable, or an explicit libvirt-qemu ACL, is enough to traverse
  if [[ "${perms:9:1}" != "x" ]] \
     && ! getfacl -p "$d" 2>/dev/null | grep -q '^user:libvirt-qemu:..x'; then
    echo "libvirt-qemu can't traverse '$d' - run ./host-deps.sh once to fix ISO access." >&2
    exit 1
  fi
done

virt-install \
  --connect qemu:///system \
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
  --tpm emulator \
  --events on_reboot=restart \
  --noautoconsole

echo "VM '$VM_NAME' created and booting from ISO."
echo "Serial console: virsh -c qemu:///system console $VM_NAME"
echo "Graphical display: virt-viewer --connect qemu:///system $VM_NAME"
