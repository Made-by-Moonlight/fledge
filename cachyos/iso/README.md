# cachyos/iso/

The fledge installer ISO (by made by moonlight). It boots into a graphical
installer: tty1 logs the unprivileged live user `fledge` in, and its
`.bash_profile` starts Hyprland with a hand-written config that runs one
Quickshell client, the installer (`qs -c fledge-installer`). It asks everything
up front, then runs `install-cachyos.sh --answers` through the root helper
`fledge-install` (the only root commands `fledge` may run are `fledge-probe`,
`fledge-install`, `fledge-cleanup` and `reboot`), shows the stages and package
counts, sets up the desktop before the reboot and boots to SDDM. The other
ttys are root consoles (no password) for rescue work; leaving the installer
drops tty1 to a shell, and `Hyprland --config /etc/fledge-installer/hyprland.lua`
starts it again.

Design: `../../docs/superpowers/specs/2026-10-16-graphical-installer-design.md`
(the ISO itself: `2026-10-01-custom-iso-design.md`)
Plan:   `../../docs/superpowers/plans/2026-10-16-graphical-installer.md`

## Build

    cachyos/vm/host-deps.sh            # once: gum, libvirt, ... (docker must already be running)
    cachyos/iso/bin/fledge-iso-make    # -> release/fledge-*.iso

The ISO contains the repo's **committed HEAD** (uncommitted changes are
listed and left out). It contains `profile.sh`, so treat it as private until
the repo is public.

## Test

Everything runs in the test VM (`cachyos/vm/`), never on the host:

    cachyos/vm/vm.sh sync
    cachyos/vm/vm.sh run 'cd ~/proj/fledge && bash cachyos/iso/test-iso-lib.sh && bash cachyos/iso/test-probe.sh'
    cachyos/vm/vm.sh run 'cd ~/proj/fledge && bash cachyos/iso/test-installer-qml.sh'   # the UI's JS (qmltestrunner)
    cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/installer/dev/run.sh'   # the UI, canned facts, fake install
    cachyos/vm/vm.sh run 'qs -p /tmp/fledge-installer ipc call installer go review'       # jump to a step
    cachyos/vm/vm.sh run 'qs -p /tmp/fledge-installer ipc call installer set username ethan'

`installer/dev/run.sh` starts the installer in the VM's desktop session in
dev mode (`installer/dev/facts.json`, `installer/dev/replay.sh` stands in
for the install, keyboard layout left alone). The IPC target `installer` has
`go <step>`, `set <key> <value>` (`key` is an `Installer` property: `username`,
`hostname`, `password`, …), `setDisk <path>`, `setWipe <path>` (wipe a data
drive and confirm it), `choice <path>` (a data drive's leave/mount/wipe),
`get <key>` (objects as JSON), `next` and `current`.

Full run: `cachyos/vm/destroy-vm.sh; cachyos/iso/bin/fledge-iso-boot` boots
the newest ISO and, when the install powers the VM off, boots the installed
system. `cachyos/vm/vm.sh type` / `key` drive the console. After the install,
`cachyos/vm/dev-up.sh`, then run the checks **before any `vm.sh sync`** (sync
rewrites the installed repo, and the checks expect it clean) and **with a tty**
(the script's `sudo` asks for the password; `vm.sh run` has no tty):

    ip="$(cachyos/vm/vm.sh ip)"
    scp cachyos/iso/test/verify-install.sh "slievr@$ip:/tmp/"
    ssh -t "slievr@$ip" 'VERIFY_LAYOUT=gb VERIFY_AUTOLOGIN=1 VERIFY_DATA_MOUNT=~/testdata VERIFY_WIPE=~/hdd1:hdd1 bash /tmp/verify-install.sh'

(`VERIFY_*` only when the run chose that layout, same disk and login password,
and data disks. `VERIFY_DATA_MOUNT`: before starting the installer, format the
VM's second disk from a root console with the UUID `profile.sh` maps to
`~/testdata` and leave a marker on it, which the check expects to survive:

    mkfs.ext4 -F -U 00000000-0000-4000-8000-00000000da7a /dev/vdb
    mount /dev/vdb /mnt
    touch /mnt/fledge-test-marker
    umount /mnt

`VERIFY_WIPE=<folder>:<label>`: Data disks › Wipe on the VM's blank third disk
(`vdc`; virtio reports it rotational with no transport, so it's a Hard disk and
the default is `~/hdd1` / `hdd1`). It checks one ext4 partition with that label
and partition name, the fstab line, the mount on access and that the user can
write there. Every run also checks the firmware boot entries: none names a
partition that no longer exists, and the first in `BootOrder` is on the new
ESP. OVMF keeps NVRAM across reinstalls but `destroy-vm.sh` deletes it, so
the stale-entry case needs a second install into the same VM. The CD drive
is empty after the first install, so put the ISO back and boot it through
Limine's firmware menu:

    virsh -c qemu:///system destroy cachyos-test
    virsh -c qemu:///system change-media cachyos-test sda ~/.cache/cachyos-iso/<iso> --insert --config
    virsh -c qemu:///system start cachyos-test   # then Esc (Limine menu), S, the DVD-ROM

and install again, the same choices.)

The live ISO has no ssh by default. For IPC from the host, start it from a
root console (`systemctl start sshd`, your key in `/root/.ssh/authorized_keys`)
and call the installer as the live user:
`runuser -u fledge -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 qs -c fledge-installer ipc call installer setWipe /dev/vdc`.

Then the desktop checks (no tty needed), including a broken generated
`binds.lua` across a login. verify-shell types keys with `wtype`, a test-only
tool the installed system doesn't ship: install it in the VM first.

    cachyos/vm/vm.sh sudo 'pacman -S --noconfirm --needed wtype'
    cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh'
    cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh break-binds'
    cachyos/vm/vm.sh relogin
    cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh after-relogin'

Monitor arrangement (headless outputs stand in for screens, and a pending
change left by a dead shell is reverted at start):

    cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-displays.sh'

Moving the installer to another screen (Ctrl+M, and the owl screen's button;
run on the host, it drives the dev installer in the VM over a headless output):

    bash cachyos/iso/test/verify-installer-screens.sh

And that every command the desktop runs by name resolves (each `fledge …`,
`"$fledge" …` or `…/bin/fledge …` in the merged settings, libexec, the stowed
config, the shell's QML, bootstrap and the installer is a built-in or a
`fledge help` action, and each word argument left after the action is one the
script's `WORD_ARGS` list knows; each `qs -c fledge ipc call T F` and
`{shell: "T.F"}` names an `Ipc.qml` function):

    cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-commands.sh'

The installed system's root account is locked, so systemd's emergency/rescue
shell won't open (sulogin refuses a locked root); recover by booting this ISO.

## Release (GitHub Actions)

`.github/workflows/iso.yml` runs the unit tests, shellcheck and the repo guards
(`cachyos/check-legacy-ipc.sh`, `cachyos/check-names.sh`,
`cachyos/check-stow-ignore.sh`) on every push and
pull request. Pushing a version tag on `main` builds the ISO on GitHub and
publishes a Release with the ISO and its `.sha256` attached (a tag that isn't
on `main` fails the build):

    git switch main && git tag v2026.10.02 && git push origin v2026.10.02

"Run workflow" on the Actions tab builds the ISO as a check without publishing.
The build fails if the ISO reaches GitHub's 2 GiB release-asset limit.

## Write to a USB stick

    sha256sum -c release/*.sha256
    sudo dd if=release/fledge-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

## Layout

| Path | What |
| --- | --- |
| `bin/fledge-iso-make` | host: clone HEAD, run the build container |
| `bin/fledge-iso-boot` | host: boot an ISO in the test VM |
| `builder/build-iso.sh` | in container: patch releng, overlay, bake, mkarchiso |
| `installer/` | the graphical installer (Quickshell config `fledge-installer`; `dev/` is the VM dev loop) |
| `lib/probe.jq` | `fledge-probe`'s disk logic: install targets and data filesystems (tested by `test-probe.sh`) |
| `lib/fledge.sh` | helpers for the root helpers: answers file, online check (tested by `test-iso-lib.sh`) |
| `configs/airootfs/` | files overlaid onto the live system |
| `configs/airootfs/usr/local/bin/fledge-probe` | root helper: disk and hardware facts as JSON, online check |
| `configs/airootfs/usr/local/bin/fledge-install` | root helper: runs `install-cachyos.sh --answers` with progress markers, logs to `/var/log/fledge-install.log` |
| `configs/airootfs/usr/local/bin/fledge-cleanup` | root helper: unmount and close the target after a failed install |
| `configs/airootfs/home/fledge/` | the live user's `.bash_profile` (starts Hyprland on tty1) |
| `configs/airootfs/etc/fledge-installer/hyprland.lua` | the live session's Hyprland config (no binds) |
| `configs/packages.extra` | packages added to releng's list |
| `configs/pacman-cachyos.conf` | the `[cachyos]` repo section |
| `test/verify-install.sh` | post-install checks |
| `test/verify-shell.sh` | desktop shell checks on the installed system |
| `test/verify-displays.sh` | monitor arrangement reaches Hyprland; a pending change reverts after a crash |
| `test/verify-installer-screens.sh` | the installer moves to another screen (Ctrl+M, the owl screen's button) |
| `test/verify-commands.sh` | every `fledge …` and IPC call the desktop makes resolves |
