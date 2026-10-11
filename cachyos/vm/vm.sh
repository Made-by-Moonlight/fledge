#!/usr/bin/env bash
# Drive the cachyos-test VM from the host: sync the working tree in, run
# commands inside the logged-in Hyprland session, take screenshots. All
# project code runs in the VM, never on the host (AGENTS.md rule 1).
#   vm.sh ip | sync | restow | shell | run CMD... | sudo CMD... | shot NAME | type TEXT | relogin
set -euo pipefail

VM_NAME="cachyos-test"
VM_USER="${VM_USER:-slievr}"
VM_PASSWORD="${VM_PASSWORD:-TestPass1}"
VIRSH="virsh -c qemu:///system"
REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
VM_REPO="proj/slievr-cachy"

vm_ip() {
  local ip
  ip="$($VIRSH domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -n1)"
  [[ -n $ip ]] || { echo "vm.sh: no IP for $VM_NAME (run cachyos/vm/dev-up.sh first)" >&2; exit 1; }
  printf '%s\n' "$ip"
}

ssh_vm() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$VM_USER@$(vm_ip)" "$@"; }

# Session env for commands run over SSH: the Wayland socket and Hyprland
# instance of the user's graphical login, plus the project bin dirs.
# shellcheck disable=SC2016  # expanded by the VM shell, on purpose
SESSION_ENV='export XDG_RUNTIME_DIR=/run/user/$(id -u)
w=$(ls -1 "$XDG_RUNTIME_DIR" 2>/dev/null | grep -E "^wayland-[0-9]+$" | head -n1); [ -n "$w" ] && export WAYLAND_DISPLAY=$w
h=$(ls -1t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1); [ -n "$h" ] && export HYPRLAND_INSTANCE_SIGNATURE=$h
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
export PATH=$HOME/.local/share/mbm/bin:$HOME/.local/share/slievr-cachy/bin:$PATH'

cmd_sync() {
  cd "$REPO"
  local list
  list="$(git ls-files -co --exclude-standard)"
  # Delete files the VM copy has that the host no longer does (renames, cutover deletions).
  ssh_vm "mkdir -p ~/$VM_REPO && cd ~/$VM_REPO && comm -23 <(git ls-files -co --exclude-standard 2>/dev/null | sort) <(sort) | xargs -r -d '\n' rm -f --" <<<"$list"
  printf '%s\n' "$list" | tar -czf - -T - | ssh_vm "tar -xzf - -C ~/$VM_REPO"
}

case "${1:-}" in
  ip) vm_ip ;;
  sync) cmd_sync ;;
  restow) cmd_sync; ssh_vm "cd ~/$VM_REPO && stow --dotfiles -R -v -t ~ . 2>&1 | grep -v '^LINK\|^UNLINK' || true" ;;
  run) shift; ssh_vm "$SESSION_ENV"$'\n'"$*" ;;
  sudo) shift; printf '%s\n' "$VM_PASSWORD" | ssh_vm "$SESSION_ENV"$'\n'"sudo -S -p '' sh -c $(printf '%q' "$*")" ;;
  shell)
    # Dev loop before Task 18 installs the service: stop the old UI daemons
    # (mako owns the notification bus name, waybar overlaps the bar), restart qs.
    ssh_vm "$SESSION_ENV"$'\n''pkill -x waybar; pkill -x mako; pkill -x swayosd-server; pkill -x hypridle
      if systemctl --user is-active -q mbm-shell 2>/dev/null; then systemctl --user restart mbm-shell; sleep 3; journalctl --user -u mbm-shell -b --no-pager | grep -E "WARN|ERROR" | tail -n 40
      else qs -c mbm kill >/dev/null 2>&1; sleep 0.5; setsid -f qs -c mbm >/tmp/mbm.log 2>&1 </dev/null; sleep 3; grep -E "WARN|ERROR" /tmp/mbm.log | tail -n 40; fi; true' ;;
  shot)
    name="${2:?vm.sh shot NAME}"; mkdir -p "$REPO/.superpowers/shots"
    ssh_vm "$SESSION_ENV"$'\n'"grim /tmp/$name.png" && scp -q "$VM_USER@$(vm_ip):/tmp/$name.png" "$REPO/.superpowers/shots/$name.png"
    echo "$REPO/.superpowers/shots/$name.png" ;;
  type)
    # Type into the VM's console (LUKS prompt, SDDM) with virsh send-key, then Enter.
    shift; text="$*"
    for ((i = 0; i < ${#text}; i++)); do
      c="${text:i:1}"
      case "$c" in
        [a-z]) $VIRSH send-key "$VM_NAME" --holdtime 40 "KEY_${c^^}" >/dev/null ;;
        [A-Z]) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_LEFTSHIFT "KEY_$c" >/dev/null ;;
        [0-9]) $VIRSH send-key "$VM_NAME" --holdtime 40 "KEY_$c" >/dev/null ;;
        ' ') $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_SPACE >/dev/null ;;
        *) echo "vm.sh type: can't type '$c'" >&2; exit 1 ;;
      esac
      sleep 0.15   # back-to-back send-keys get dropped by the guest
    done
    $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_ENTER >/dev/null ;;
  relogin)
    # End the session and log back in at SDDM by typing the password.
    ssh_vm "$SESSION_ENV"$'\n''(uwsm stop >/dev/null 2>&1 &)' || true
    sleep 10; "$0" type "$VM_PASSWORD"; sleep 12
    ssh_vm "$SESSION_ENV"$'\n''hyprctl version >/dev/null && echo "logged in"' ;;
  *) sed -n '2,6p' "$0" >&2; exit 2 ;;
esac
