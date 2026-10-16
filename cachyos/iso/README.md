# cachyos/iso/

The fledge installer ISO (by made by moonlight). It boots into a graphical
installer: tty1 logs the unprivileged live user `moonlight` in, and its
`.bash_profile` starts Hyprland with a hand-written config that runs one
Quickshell client, the installer (`qs -c mbm-installer`). It asks everything
up front, then runs `install-cachyos.sh --answers` through the root helper
`mbm-install` (the only root commands `moonlight` may run are `mbm-probe`,
`mbm-install`, `mbm-cleanup` and `reboot`), shows the stages and package
counts, sets up the desktop before the reboot and boots to SDDM. The other
ttys are root consoles (no password) for rescue work; leaving the installer
drops tty1 to a shell, and `Hyprland --config /etc/mbm-installer/hyprland.conf`
starts it again.

Design: `../../docs/superpowers/specs/2026-10-16-graphical-installer-design.md`
(the ISO itself: `2026-10-01-custom-iso-design.md`)
Plan:   `../../docs/superpowers/plans/2026-10-16-graphical-installer.md`

## Build

    cachyos/vm/host-deps.sh            # once: gum, libvirt, ... (docker must already be running)
    cachyos/iso/bin/slievr-iso-make    # -> release/fledge-*.iso

The ISO contains the repo's **committed HEAD** (uncommitted changes are
listed and left out). It contains `profile.sh`, so treat it as private until
the repo is public.

## Test

Everything runs in the test VM (`cachyos/vm/`), never on the host:

    cachyos/vm/vm.sh sync
    cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy && bash cachyos/iso/test-mbm.sh && bash cachyos/iso/test-probe.sh'
    cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/cachyos/iso/installer/dev/run.sh'   # the UI, canned facts, fake install
    cachyos/vm/vm.sh run 'qs -p /tmp/mbm-installer ipc call installer go review'       # jump to a step
    cachyos/vm/vm.sh run 'qs -p /tmp/mbm-installer ipc call installer set USERNAME ethan'

`installer/dev/run.sh` starts the installer in the VM's desktop session in
dev mode (`installer/dev/facts.json`, `installer/dev/replay.sh` stands in
for the install, keyboard layout left alone). The IPC target `installer` has
`go <step>`, `set <key> <value>`, `setDisk <path>`, `next` and `current`.

Full run: `cachyos/vm/destroy-vm.sh; cachyos/iso/bin/slievr-iso-boot` boots
the newest ISO and, when the install powers the VM off, boots the installed
system. `cachyos/vm/vm.sh type` / `key` drive the console. After the install,
`cachyos/vm/dev-up.sh`, then:

    cachyos/vm/vm.sh sync
    cachyos/vm/vm.sh run 'VERIFY_LAYOUT=gb VERIFY_DATA_MOUNT=~/testdata bash ~/proj/slievr-cachy/cachyos/iso/test/verify-install.sh'

(`VERIFY_*` only when the run chose that layout and data disk: format the
VM's second disk first with `mkfs.ext4 -U 00000000-0000-4000-8000-00000000da7a
/dev/vdb` from a root console, the UUID `profile.sh` maps to `~/testdata`.)

The installed system's root account is locked, so systemd's emergency/rescue
shell won't open (sulogin refuses a locked root); recover by booting this ISO.

## Release (GitHub Actions)

`.github/workflows/iso.yml` runs the unit tests and shellcheck on every push and
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
| `bin/slievr-iso-make` | host: clone HEAD, run the build container |
| `bin/slievr-iso-boot` | host: boot an ISO in the test VM |
| `builder/build-iso.sh` | in container: patch releng, overlay, bake, mkarchiso |
| `installer/` | the graphical installer (Quickshell config `mbm-installer`; `dev/` is the VM dev loop) |
| `lib/probe.jq` | `mbm-probe`'s disk logic: install targets and data filesystems (tested by `test-probe.sh`) |
| `lib/mbm.sh` | helpers for the root helpers: hostname check, answers file, online check (tested by `test-mbm.sh`) |
| `configs/airootfs/` | files overlaid onto the live system |
| `configs/airootfs/usr/local/bin/mbm-probe` | root helper: disk and hardware facts as JSON, online check |
| `configs/airootfs/usr/local/bin/mbm-install` | root helper: runs `install-cachyos.sh --answers` with progress markers, logs to `/var/log/mbm-install.log` |
| `configs/airootfs/usr/local/bin/mbm-cleanup` | root helper: unmount and close the target after a failed install |
| `configs/airootfs/home/moonlight/` | the live user's `.bash_profile` (starts Hyprland on tty1) |
| `configs/airootfs/etc/mbm-installer/hyprland.conf` | the live session's Hyprland config (no binds) |
| `configs/packages.extra` | packages added to releng's list |
| `configs/pacman-cachyos.conf` | the `[cachyos]` repo section |
| `test/verify-install.sh` | post-install checks |
| `test/verify-shell.sh` | desktop shell checks on the installed system |
