#!/usr/bin/env bash
set -euo pipefail

# Deletes the test VM and both its qcow2 disks. Uses qemu:///system over
# libvirt-group membership - no sudo.

VM_NAME="cachyos-test"
VIRSH="virsh -c qemu:///system"

if ! $VIRSH dominfo "$VM_NAME" &>/dev/null; then
  echo "VM '$VM_NAME' does not exist, nothing to do."
  exit 0
fi

$VIRSH destroy "$VM_NAME" 2>/dev/null || true
$VIRSH undefine "$VM_NAME" --remove-all-storage --nvram

echo "VM '$VM_NAME' destroyed and disk removed."
