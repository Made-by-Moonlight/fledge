# cachyos/install/

Hardware-adaptive CachyOS installer. Runs as root in the **stock official
CachyOS ISO** live environment and installs onto whichever machine it is
booted on.

Design: `../../docs/superpowers/specs/2026-08-28-bare-metal-install-design.md`
Plan:   `../../docs/superpowers/plans/2026-08-28-bare-metal-install.md`

## What it builds

- GPT: 2 GiB FAT32 ESP + LUKS2 partition (rest of the disk)
- btrfs inside LUKS: subvolumes `@ @home @log @pkg @swap` (+ `@/.snapshots`)
- Limine booting a UKI (`/boot/EFI/Linux/*.efi`)
- zram-generator swap always; an encrypted btrfs swapfile for hibernate
- microcode + GPU driver chosen by runtime detection

It does **not** set up the desktop — that is `../bootstrap.sh`, run after
the first reboot.

## Files

| File | Role |
| --- | --- |
| `install-cachyos.sh` | orchestrator — the thing you run |
| `profile.sh` | fixed, hardware-independent choices; reviewed by eye |
| `lib/detect.sh` | hardware detection (pure functions) |
| `lib/disk.sh` | partition + LUKS + btrfs + swapfile |
| `lib/bootloader.sh` | Limine UKI setup (runs in chroot) |
| `lib/chroot-setup.sh` | system config (runs in chroot) |
| `lib/cachyos-repos.sh` | the target's CachyOS repo sections (v3 / v4 / znver4 by CPU), used by chroot-setup |
| `lib/answers.sh` | parse unattended answers file; user name, host name and data-mount checks |
| `lib/desktop.sh` | the Desktop stage (bootstrap.sh in the target before reboot) and Finish |
| `lib/progress.sh` | `@@fledge` progress markers for the graphical installer (`FLEDGE_PROGRESS=1`) |
| `lib/network.sh` | carry the live session's NetworkManager profiles into the target |
| `test-detect.sh` | runs `lib/detect.sh` against fixtures; `bash test-detect.sh` |
| `test-answers.sh` | runs `lib/answers.sh` against fixtures; `bash test-answers.sh` |
| `test-desktop.sh` | `lib/desktop.sh`'s pure parts and the `--desktop-only` guards |
| `test-progress.sh` | `lib/progress.sh`'s markers and pacman output filter |
| `test-network.sh` | `lib/network.sh` against a temporary directory |
| `test-cachyos-repos.sh` | `lib/cachyos-repos.sh` against cpuinfo, ld.so and pacman.conf fixtures |

## Before you run it, per machine

1. Edit `profile.sh`:
   - `HOSTNAME` — set it, or leave `""` to be prompted.
   - `DATA_DISKS` — the data disks to mount permanently (matched by UUID;
     disks not present on the machine are skipped). Set to `()` for none.
     The graphical installer pre-selects these for Mount; wiping a drive is
     only ever chosen by hand.
2. Get this repo onto a partition the install will **not** touch:
   - Desktop: copy `~/proj/fledge` onto one of the data disks.
   - Laptop: copy it onto a USB stick.

## Running

Boot the stock CachyOS ISO on the target, then:

```sh
# mount the partition holding the staged repo, e.g.
sudo mount /dev/disk/by-id/<data-disk-partN> /mnt-repo
sudo /mnt-repo/fledge/cachyos/install/install-cachyos.sh
```

It prints a detection summary, lists candidate disks, and makes you type
the target disk's model string before it touches anything. After it
finishes it has already run `bootstrap.sh` (the desktop layer) inside the
new system as the new user, so after the reboot you unlock the disk and land
on the login screen. If that stage fails the installer exits 3 with the
target still mounted; either reboot (`fledge-firstboot.service`, still
enabled, runs `bootstrap.sh` on first boot as the fallback) or retry it:

```sh
sudo install-cachyos.sh --desktop-only USER   # needs /mnt still mounted
```

`--desktop-only USER` runs just the Desktop and Finish stages (exit 0 done,
3 desktop failed again). The install log is kept in the new system at
`/var/log/fledge-install.log`.

## Unattended (`--answers`)

The ISO's graphical installer (`fledge-install`, not the configurator) writes
`/run/fledge-answers.env` (mode 600) and runs

    install-cachyos.sh --answers /run/fledge-answers.env

Keys: `DISK` (by-id path), `DISK_CONFIRMED=yes`, `HOSTNAME`, `TIMEZONE`,
`USER_PASSWORD`, `LUKS_PASSPHRASE`, optional `ROOT_PASSWORD` (empty → root
locked), `XKB_LAYOUT` / `XKB_VARIANT` (keyboard; default `us`, seeded into the
user's fledge settings), `DATA_MOUNTS` (`uuid:/abs/path,…`, `~` already
expanded, may be empty) and `DATA_WIPES` (`label:/abs/path:disk,…`: each disk
is erased into one ext4 partition named and labelled `label`, mounted at the
path like a data disk; may be empty, and the disk path, a by-id one included,
goes last because it can hold `:`). Before erasing, firmware boot entries on
the target or a wiped drive are noted and removed after the bootloader stage,
and fledge's entry goes first in `BootOrder`. One `KEY=value` per line, unquoted; parsed by `lib/answers.sh`, never
sourced; deleted once read. Without `--answers` everything prompts as before.
Without `--answers`, data-disk fstab entries from `profile.sh` are only
written when their UUID is present on the machine.

## Testing the detection logic (no VM)

```sh
bash cachyos/install/test-detect.sh
```
