#!/usr/bin/env bash
set -euo pipefail

# Brings an already-installed cachyos-test VM up for a dev/test iteration
# loop: starts it if stopped, waits for SSH, sets up passwordless key auth
# automatically, and opens the graphical console.
#
# Does NOT provision from scratch — that still needs one manual step (see
# README.md's "First-time setup" section) because the CachyOS desktop
# live ISO doesn't attach a shell to the serial console, so unlock-console.exp
# can't drive it non-interactively. Once install-cachyos.sh has run once,
# this script is the whole rest of the loop.

VM_NAME="cachyos-test"
VM_USER="slievr"
VM_PASSWORD="${VM_PASSWORD:-TestPass1}"
SSH_KEY="$HOME/.ssh/id_ed25519"

if ! sudo virsh dominfo "$VM_NAME" &>/dev/null; then
  echo "VM '$VM_NAME' doesn't exist. Run provision-vm.sh + install-cachyos.sh first." >&2
  exit 1
fi

state=$(sudo virsh domstate "$VM_NAME")
if [ "$state" != "running" ]; then
  echo "Starting VM..."
  sudo virsh start "$VM_NAME"
fi

echo "Waiting for an IP address..."
vm_ip=""
for _ in $(seq 1 30); do
  vm_ip=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1)
  [ -n "$vm_ip" ] && break
  sleep 2
done
if [ -z "$vm_ip" ]; then
  echo "Timed out waiting for an IP address." >&2
  exit 1
fi
echo "VM IP: $vm_ip"

echo "Waiting for sshd..."
for _ in $(seq 1 30); do
  timeout 2 bash -c "echo >/dev/tcp/$vm_ip/22" 2>/dev/null && break
  sleep 2
done

if ! [ -f "$SSH_KEY" ]; then
  echo "Generating SSH key..."
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
    "$VM_USER@$vm_ip" 'true' 2>/dev/null; then
  echo "Setting up passwordless SSH..."
  ssh-keygen -R "$vm_ip" &>/dev/null || true
  if ! command -v sshpass &>/dev/null; then
    echo "Installing sshpass..."
    sudo pacman -S --needed --noconfirm sshpass
  fi
  sshpass -p "$VM_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=accept-new \
    -i "${SSH_KEY}.pub" "$VM_USER@$vm_ip" &>/dev/null
fi

echo "SSH ready: ssh $VM_USER@$vm_ip"
echo "Opening graphical console..."
setsid virt-viewer --connect qemu:///system "$VM_NAME" &>/dev/null &

echo "$vm_ip"
