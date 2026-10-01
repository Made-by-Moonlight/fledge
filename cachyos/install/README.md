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
| `lib/answers.sh` | parse unattended answers file |
| `test-detect.sh` | runs `lib/detect.sh` against fixtures; `bash test-detect.sh` |
| `test-answers.sh` | runs `lib/answers.sh` against fixtures; `bash test-answers.sh` |

## Before you run it, per machine

1. Edit `profile.sh`:
   - `HOSTNAME` — set it, or leave `""` to be prompted.
   - `EXTRA_FSTAB_ENTRIES` — set to `()` on any machine without the
     desktop's four extra data disks.
2. Get this repo onto a partition the install will **not** touch:
   - Desktop: copy `~/proj/slievr-cachy` onto one of the data disks.
   - Laptop: copy it onto a USB stick.

## Running

Boot the stock CachyOS ISO on the target, then:

```sh
# mount the partition holding the staged repo, e.g.
sudo mount /dev/disk/by-id/<data-disk-partN> /mnt-repo
sudo /mnt-repo/slievr-cachy/cachyos/install/install-cachyos.sh
```

It prints a detection summary, lists candidate disks, and makes you type
the target disk's model string before it touches anything. After it
finishes and reboots:

```sh
# log in as the user, then from the staged repo:
~/proj/slievr-cachy/cachyos/bootstrap.sh
```

## Unattended (`--answers`)

The ISO's configurator writes `/run/mbm-answers.env` (mode 600) and runs

    install-cachyos.sh --answers /run/mbm-answers.env

Keys: `DISK` (by-id path), `DISK_CONFIRMED=yes`, `HOSTNAME`, `TIMEZONE`,
`USER_PASSWORD`, `LUKS_PASSPHRASE`, optional `ROOT_PASSWORD` (empty → root
locked). One `KEY=value` per line, unquoted; parsed by `lib/answers.sh`, never
sourced; deleted once read. Without `--answers` everything prompts as before.
Data-disk fstab entries from `profile.sh` are only written when their UUID is
present on the machine.

## Testing the detection logic (no VM)

```sh
bash cachyos/install/test-detect.sh
```
