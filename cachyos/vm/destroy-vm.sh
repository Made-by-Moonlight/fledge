#!/usr/bin/env bash
set -euo pipefail

VM_NAME="cachyos-test"

if ! sudo virsh dominfo "$VM_NAME" &>/dev/null; then
  echo "VM '$VM_NAME' does not exist, nothing to do."
  exit 0
fi

sudo virsh destroy "$VM_NAME" 2>/dev/null || true
sudo virsh undefine "$VM_NAME" --remove-all-storage

echo "VM '$VM_NAME' destroyed and disk removed."
