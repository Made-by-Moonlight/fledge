#!/usr/bin/env bash
# Drive the cachyos-test VM from the host: sync the working tree in, run
# commands inside the logged-in Hyprland session, take screenshots. All
# project code runs in the VM, never on the host (AGENTS.md rule 1).
#   vm.sh ip | sync | restow | shell | run CMD... | sudo CMD... | shot NAME | type TEXT | key KEY... | relogin
set -euo pipefail

VM_NAME="cachyos-test"
VM_USER="${VM_USER:-slievr}"
VM_PASSWORD="${VM_PASSWORD:-TestPass1}"
VIRSH="virsh -c qemu:///system"
REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
VM_REPO="proj/fledge"

# After a reinstall from the ISO the same MAC holds two leases (the live
# system's and the installed one's): prefer the address where sshd answers.
vm_ip() {
  local ips ip
  ips="$($VIRSH domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1)"
  [[ -n $ips ]] || { echo "vm.sh: no IP for $VM_NAME (run cachyos/vm/dev-up.sh first)" >&2; exit 1; }
  for ip in $ips; do
    if timeout 1 bash -c "echo >/dev/tcp/$ip/22" 2>/dev/null; then printf '%s\n' "$ip"; return; fi
  done
  printf '%s\n' "${ips%%$'\n'*}"
}

# The login shell is fish, which can't parse the POSIX commands below, so the
# command travels base64-encoded into an explicit bash (stdin stays free for
# the tar and sudo-password pipes). "$(...)" works in both fish and bash.
ssh_vm() {
  local enc
  enc="$(printf '%s' "$*" | base64 -w0)"
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$VM_USER@$(vm_ip)" "exec bash -c \"\$(printf %s $enc | base64 -d)\""
}

# Session env for commands run over SSH: the Wayland socket and Hyprland
# instance of the user's graphical login, plus the fledge command.
# shellcheck disable=SC2016  # expanded by the VM shell, on purpose
SESSION_ENV='export XDG_RUNTIME_DIR=/run/user/$(id -u)
w=$(ls -1 "$XDG_RUNTIME_DIR" 2>/dev/null | grep -E "^wayland-[0-9]+$" | head -n1); [ -n "$w" ] && export WAYLAND_DISPLAY=$w
h=$(ls -1t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1); [ -n "$h" ] && export HYPRLAND_INSTANCE_SIGNATURE=$h
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
export PATH=$HOME/.local/share/fledge/bin:$PATH'

cmd_sync() {
  cd "$REPO"
  # NUL-separated, and only paths that still exist: a tracked file deleted in
  # the working tree is still listed by git until the deletion is committed.
  local list f
  list="$(mktemp)"
  trap 'rm -f "$list"' RETURN
  while IFS= read -r -d '' f; do
    [[ -e $f || -L $f ]] && printf '%s\0' "$f"
  done < <(git ls-files -z -co --exclude-standard) >"$list"
  # Delete files the VM copy has that the host no longer does (renames, cutover deletions).
  ssh_vm "mkdir -p ~/$VM_REPO && cd ~/$VM_REPO && comm -z -23 <(git ls-files -z -co --exclude-standard 2>/dev/null | sort -z) <(sort -z) | xargs -r -0 rm -f --" <"$list"
  tar --null -czf - -T "$list" | ssh_vm "tar -xzf - -C ~/$VM_REPO"
  # And the directories those deletions emptied, as a git checkout would: a stowed
  # link to an empty dir (e.g. ~/.config/waybar after the cutover) never dangles.
  ssh_vm "find ~/$VM_REPO -mindepth 1 -depth -type d -empty -not -path '*/.git/*' -delete"
  reload_hypr
}

# Hyprland doesn't reload on file changes (misc.disable_autoreload; a .conf
# session still does, and can catch tar or stow mid-write), so reload once they're
# done. A query command, the same on both config managers; no session, no-op.
reload_hypr() {
  ssh_vm "$SESSION_ENV"$'\n''if hyprctl version >/dev/null 2>&1; then hyprctl reload >/dev/null || echo "vm.sh: hyprctl reload failed" >&2; fi'
}

case "${1:-}" in
  ip) vm_ip ;;
  sync) cmd_sync ;;
  restow) cmd_sync; ssh_vm "cd ~/$VM_REPO && stow --dotfiles -R -v -t ~ . 2>&1 | grep -v '^LINK\|^UNLINK' || true"; reload_hypr ;;
  run) shift; ssh_vm "$SESSION_ENV"$'\n'"$*" ;;
  sudo) shift; printf '%s\n' "$VM_PASSWORD" | ssh_vm "$SESSION_ENV"$'\n'"sudo -S -p '' sh -c $(printf '%q' "$*")" ;;
  shell)
    # Dev loop: restart the shell, through fledge-shell.service once the cutover has
    # installed it. On an older install, first stop the old UI daemons (mako owns
    # the notification bus name, waybar overlaps the bar), then restart qs.
    # Every running instance is stopped first, not just one: a stale duplicate
    # holds the notification bus name and doubles the reserved space.
    # polkit allows one agent per session, so polkit-gnome goes before qs registers its own
    # (anchored: an unanchored -f would match this very command line).
    # shellcheck disable=SC2016  # expanded by the VM shell, on purpose
    ssh_vm "$SESSION_ENV"$'\n''pkill -x waybar; pkill -x mako; pkill -x swayosd-server; pkill -x hypridle
      pk="^/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
      pkill -f "$pk"; for _ in $(seq 20); do pgrep -f "$pk" >/dev/null || break; sleep 0.25; done
      if systemctl --user is-active -q fledge-shell 2>/dev/null; then systemctl --user restart fledge-shell; sleep 3; journalctl --user -u fledge-shell -b --no-pager | grep -E "WARN|ERROR" | tail -n 40
      else
        # After a crash, the Quickshell crash guard restarts the shell as a bare /usr/bin/quickshell.
        inst="^((qs|quickshell) -c fledge( |\$)|/usr/bin/quickshell\$)"
        pkill -f "$inst"
        for _ in $(seq 20); do pgrep -f "$inst" >/dev/null || break; sleep 0.25; done
        pkill -9 -f "$inst" && sleep 0.5
        if pgrep -f "$inst" >/dev/null; then echo "vm.sh: qs -c fledge still running" >&2; exit 1; fi
        # Started by Hyprland, not from this SSH login: polkit binds an agent to the logind
        # session of its process, and one started here would serve the SSH session, not the desktop.
        : >/tmp/fledge.log   # so the grep below shows only this run
        fledge hypr dispatch "hl.dsp.exec_cmd(\"qs -c fledge >/tmp/fledge.log 2>&1 </dev/null\")"
        sleep 3; grep -E "WARN|ERROR" /tmp/fledge.log | tail -n 40
      fi; true' ;;
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
        -) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_MINUS >/dev/null ;;
        /) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_SLASH >/dev/null ;;
        .) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_DOT >/dev/null ;;
        :) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_LEFTSHIFT KEY_SEMICOLON >/dev/null ;;
        =) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_EQUAL >/dev/null ;;
        _) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_LEFTSHIFT KEY_MINUS >/dev/null ;;
        '>') $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_LEFTSHIFT KEY_DOT >/dev/null ;;
        '|') $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_LEFTSHIFT KEY_BACKSLASH >/dev/null ;;
        *) echo "vm.sh type: can't type '$c'" >&2; exit 1 ;;
      esac
      sleep 0.15   # back-to-back send-keys get dropped by the guest
    done
    $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_ENTER >/dev/null ;;
  key)
    # Send keys without typing text, e.g. vm.sh key KEY_DOWN, vm.sh key KEY_LEFTCTRL KEY_LEFTALT KEY_F2
    shift; $VIRSH send-key "$VM_NAME" --holdtime 40 "$@" >/dev/null ;;
  relogin)
    # End the session and log back in at SDDM by typing the password.
    ssh_vm "$SESSION_ENV"$'\n''(uwsm stop >/dev/null 2>&1 &)' || true
    sleep 10; "$0" type "$VM_PASSWORD"; sleep 12
    ssh_vm "$SESSION_ENV"$'\n''hyprctl version >/dev/null && echo "logged in"' ;;
  *) sed -n '2,6p' "$0" >&2; exit 2 ;;
esac
