# cachyos/iso/

The made by moonlight installer ISO: boots to a branded configurator on tty1,
asks everything up front, then installs unattended (`install-cachyos.sh
--answers`) and reboots into firstboot → `bootstrap.sh`.

Design: `../../docs/superpowers/specs/2026-10-01-custom-iso-design.md`
Plan:   `../../docs/superpowers/plans/2026-10-01-custom-iso.md`

## Build

    cachyos/vm/host-deps.sh            # once: gum, libvirt, ... (docker must already be running)
    cachyos/iso/bin/slievr-iso-make    # -> release/made-by-moonlight-*.iso

The ISO contains the repo's **committed HEAD** (uncommitted changes are
listed and left out). It contains `profile.sh`, so treat it as private until
the repo is public.

## Test

    bash cachyos/iso/test-mbm.sh                                  # unit tests
    MBM_REPO=$PWD cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator --dry-run
    cachyos/vm/destroy-vm.sh; cachyos/iso/bin/slievr-iso-boot     # full run in the VM
    scp cachyos/iso/test/verify-install.sh slievr@<vm-ip>:/tmp/ && ssh -t slievr@<vm-ip> bash /tmp/verify-install.sh

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
    sudo dd if=release/made-by-moonlight-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

## Layout

| Path | What |
| --- | --- |
| `bin/slievr-iso-make` | host: clone HEAD, run the build container |
| `bin/slievr-iso-boot` | host: boot an ISO in the test VM |
| `builder/build-iso.sh` | in container: patch releng, overlay, bake, mkarchiso |
| `configs/airootfs/` | files overlaid onto the live system |
| `configs/packages.extra` | packages added to releng's list |
| `configs/pacman-cachyos.conf` | the `[cachyos]` repo section |
| `lib/mbm.sh` | configurator helpers (tested by `test-mbm.sh`) |
| `test/verify-install.sh` | post-install checks |
