#!/usr/bin/env bash
set -euo pipefail

# Brings an already-installed cachyos-test VM up for a dev/test iteration
# loop: starts it if stopped, waits for SSH, sets up passwordless key auth
# automatically (via expect - no sshpass, no sudo), and opens the graphical
# console.
#
# Does NOT provision from scratch - that still needs one manual step (see
# README.md's "First-time setup" section) because the CachyOS desktop
# live ISO doesn't attach a shell to the serial console, so unlock-console.exp
# can't drive it non-interactively. Once install-cachyos.sh has run once,
# this script is the whole rest of the loop.

VM_NAME="cachyos-test"
VM_USER="slievr"
VM_PASSWORD="${VM_PASSWORD:-TestPass1}"
SSH_KEY="$HOME/.ssh/id_ed25519"
VIRSH="virsh -c qemu:///system"

if ! $VIRSH dominfo "$VM_NAME" &>/dev/null; then
  echo "VM '$VM_NAME' doesn't exist. Run provision-vm.sh + install-cachyos.sh first." >&2
  exit 1
fi

state=$($VIRSH domstate "$VM_NAME")
if [ "$state" != "running" ]; then
  echo "Starting VM..."
  $VIRSH start "$VM_NAME"
fi

echo "Waiting for an IP address with sshd..."
vm_ip=""
for _ in $(seq 1 30); do
  # Two leases after a reinstall (live ISO + installed system): take the one
  # whose sshd answers, else keep waiting.
  for ip in $($VIRSH domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1); do
    timeout 1 bash -c "echo >/dev/tcp/$ip/22" 2>/dev/null && { vm_ip=$ip; break; }
  done
  [ -n "$vm_ip" ] && break
  sleep 2
done
if [ -z "$vm_ip" ]; then
  echo "Timed out waiting for an IP address or sshd (is the disk still locked?)." >&2
  exit 1
fi
echo "VM IP: $vm_ip"

echo "Waiting for sshd..."
for _ in $(seq 1 30); do
  timeout 2 bash -c "echo >/dev/tcp/$vm_ip/22" 2>/dev/null && break
  sleep 2
done

# Key auth that already works (a key authorized before, or an agent such as
# 1Password's) needs no key of our own; only generate one when it's missing.
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
    "$VM_USER@$vm_ip" 'true' 2>/dev/null; then
  if ! [ -f "$SSH_KEY" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
  fi
  echo "Setting up passwordless SSH..."
  ssh-keygen -R "$vm_ip" &>/dev/null || true
  pubkey="$(cat "${SSH_KEY}.pub")"
  expect <<EOF
    set timeout 20
    spawn ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no "$VM_USER@$vm_ip" \
      "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\\n' '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    expect {
      -re {[Pp]assword:} { send "$VM_PASSWORD\r"; exp_continue }
      eof
    }
EOF
fi

echo "SSH ready: ssh $VM_USER@$vm_ip"

# Test-only tools the desktop doesn't ship: wtype types into the session for
# verify-shell.sh's lock and keybind checks. The login shell is fish, so the
# script goes to bash on stdin.
# shellcheck disable=SC2087  # $VM_PASSWORD is the host's: expanded here, on purpose
ssh -o BatchMode=yes "$VM_USER@$vm_ip" bash -s <<EOF || echo "Couldn't install wtype in the VM; verify-shell.sh needs it." >&2
command -v wtype >/dev/null || printf '%s\\n' '$VM_PASSWORD' | sudo -S -p '' pacman -S --needed --noconfirm wtype >/dev/null
EOF
echo "Opening graphical console..."
setsid virt-viewer --connect qemu:///system "$VM_NAME" &>/dev/null &

echo "$vm_ip"
