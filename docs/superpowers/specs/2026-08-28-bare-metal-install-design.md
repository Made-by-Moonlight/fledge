# Bare-metal CachyOS install — design

**Date:** 2026-08-28
**Status:** approved, pending implementation plan

## Problem

`cachyos/vm/install-cachyos.sh` installs CachyOS into the test VM only. It
hardcodes `DISK=/dev/vda`, does a whole-disk GPT wipe to a single ext4
partition, installs systemd-boot, and has no encryption, no microcode, no
GPU driver, and no data-disk preservation. It cannot install onto real
hardware.

Real targets:

- **Desktop** (the machine this repo is developed on, migrating from
  Arch/Omarchy): AMD Ryzen 9 7900X, RTX 3080 + Raphael iGPU, UEFI, 61 GiB
  RAM. Root disk `nvme1n1` (WD Blue SN570 1TB). Four other data disks
  (`sda1`, `sdb1`, `nvme2n1p1`, `nvme0n1p3`) mounted as `~/storage1..4`
  that must survive untouched.
- **Laptop** (future): different CPU (likely Intel), different/no discrete
  GPU, different disks.

The current desktop install is Omarchy-style: Limine booting a UKI
(`/EFI/Linux/omarchy_linux.efi`) via `limine-entry-tool`, LUKS2 on
`nvme1n1p2` (mapper name `root`) → btrfs subvolumes `@ @home @log @pkg` +
snapper `.snapshots`, `compress=zstd:3`. Root cmdline:

```
cryptdevice=PARTUUID=<p2>:root root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs
```

ESP is `nvme1n1p1`, 2 GiB, FAT32. amd-ucode. mkinitcpio HOOKS use the
busybox `encrypt` hook (not `sd-encrypt`); `/etc/crypttab` is empty (root
unlock is via the kernel cmdline).

## Goals

- One installer, run as root in the **stock official CachyOS ISO** live
  environment, that adapts to whichever machine it is booted on.
- Reproduce the desktop's opinionated layout (LUKS2 + btrfs subvolumes +
  Limine UKI + zram) on any target.
- Hardware specifics (microcode, GPU driver + kernel params, target disk,
  partition-name suffix, swap sizing) **detected at install time**, never
  baked into config.
- Safe disk selection: never touch a disk the user did not explicitly
  confirm; never touch the live media or a mounted disk.
- Hibernate-capable.
- Testable in the VM (with a second blank disk) and — for the detection
  logic — on the host with fixtures, no VM.

## Non-goals (v1)

- snapper + `limine-snapper-sync` snapshot boot entries. The `@/.snapshots`
  subvol is created so this can be added later with no reformat, but
  configuring snapper is out of scope.
- Secure Boot / TPM auto-unlock.
- Dual-boot / preserving an existing OS partition on the target disk. The
  target root disk is wiped whole; only *other* disks are preserved.
- Making the repo public / git-clone-based delivery as the primary path.

## Delivery

Before rebooting a machine into the live ISO, copy `~/proj/slievr-cachy`
onto a partition the install will not touch — a data disk on the desktop,
a USB stick on the laptop. The live ISO mounts it and runs
`cachyos/install/install-cachyos.sh` from there. The repo stays private.

`bootstrap.sh` keeps its `git clone` fallback for the case where the repo
was not staged but there is network + auth.

## File layout

```
cachyos/
  install/
    install-cachyos.sh    # orchestrator — run as root in the live ISO on the target
    profile.sh            # fixed, hardware-independent choices (sourced); reviewed by eye
    lib/
      detect.sh           # hardware detection (pure functions, unit-testable)
      disk.sh             # partition + LUKS + btrfs + swapfile
      bootloader.sh       # Limine UKI setup
      chroot-setup.sh     # everything that runs inside arch-chroot
    test-detect.sh        # runs detect.sh against fixture inputs, asserts package sets
  bootstrap.sh            # unchanged role — desktop layer, runs post-reboot as the user
  vm/                     # existing VM scripts, lightly updated (see Testing)
```

The old `cachyos/vm/install-cachyos.sh` is replaced by
`cachyos/install/install-cachyos.sh`. The VM uses the same script — the VM
is just another target the detection handles.

## profile.sh — the fixed choices (complete)

```sh
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
KEYMAP="us"
USERNAME="slievr"
HOSTNAME=""                       # empty -> prompt at install time

ESP_SIZE="2GiB"
LUKS_NAME="root"
BTRFS_SUBVOLS=( "@:/" "@home:/home" "@log:/var/log" "@pkg:/var/cache/pacman/pkg" "@swap:/swap" )
BTRFS_OPTS="compress=zstd:3,ssd,space_cache=v2,relatime"
CREATE_SNAPSHOTS_SUBVOL=true      # make @/.snapshots now so snapper can be added later, no reformat

KERNEL="linux-cachyos"
SWAP="hibernate"                  # "hibernate" = zram + btrfs swapfile.  "zram" = zram only.
HIBERNATE_SWAP_SIZE=""            # empty -> auto: round(RAM up to GiB) + 2 GiB
EXTRA_CMDLINE="quiet splash zswap.enabled=0"

# Per-machine, optional. Empty on the laptop. On the desktop: the 4 data disks,
# copied verbatim from the current /etc/fstab.
EXTRA_FSTAB_ENTRIES=(
  "UUID=ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7 /home/slievr/storage1 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
  "UUID=5e62f799-8df9-4ee3-b4d7-4da62c8c65ff /home/slievr/storage2 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
  "UUID=77d7988e-2e64-4654-bda2-481d321eecdd /home/slievr/storage3 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
  "UUID=55cefb4f-6b27-4dbc-bbf8-5e9120defa26 /home/slievr/storage4 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
)
```

Everything hardware-specific is detected, never in the profile.

## Hardware detection (lib/detect.sh)

Pure functions, each taking its input source as an argument (so fixtures
can be substituted in tests) and printing its result to stdout.

| Function | Logic | Output |
|---|---|---|
| `detect_ucode` | `/proc/cpuinfo` `vendor_id` | `amd-ucode` or `intel-ucode` |
| `detect_gpu_pkgs` | `lspci -nn` VGA/3D/Display class rows | NVIDIA present -> `linux-cachyos-nvidia nvidia-utils lib32-nvidia-utils`; AMD -> `vulkan-radeon lib32-vulkan-radeon`; Intel -> `vulkan-intel`. Multiple GPUs -> union. |
| `detect_gpu_cmdline` | same rows | NVIDIA present -> `nvidia_drm.modeset=1`; else empty |
| `detect_gpu_modules` | same rows | NVIDIA present -> `nvidia nvidia_modeset nvidia_uvm nvidia_drm`; else empty |
| `list_disks` | `lsblk -dpno NAME,SIZE,MODEL,TRAN`; exclude the disk backing `/run/archiso` (live media) and `TRAN=usb` unless `--allow-usb` | candidate disk list |
| `part_suffix` | target name matches `nvme`/`mmcblk`/`loop` -> `p`; else -> `` | partition-name suffix |
| `zram_size` | `min(MemTotal/2, 8192)` MiB | zram-generator conf value |
| `hibernate_swap_size` | `MemTotal` rounded up to GiB, + 2 GiB | swapfile size (61 GiB RAM -> 64 GiB) |

`test-detect.sh` feeds each function canned `cpuinfo` / `lspci` text for
three profiles (desktop, Intel laptop, VM) and asserts the package list,
cmdline fragment, and module list. Runs on the host, no VM.

## Install flow (install-cachyos.sh)

1. **Preflight** — must be root; `/sys/firmware/efi` exists; running in a
   live env; `profile.sh` present; a configured mirror is reachable. The
   CachyOS ISO already ships the CachyOS repos in `pacman.conf`, so the
   `cachyos-repo.sh` bootstrap step from the old VM script is dropped.
2. Source `profile.sh` + `lib/*`; run detection; print a summary table
   (ucode, GPU pkgs, RAM/zram/swapfile sizes, candidate disks).
3. **Disk selection & guard** — user picks the target from `list_disks`
   output. Script prints its model, size, and current partition table and
   requires the user to **type the disk's model string** to proceed. Hard
   refuse if the target: is mounted anywhere, backs `/` or `/run/archiso`,
   or is USB (unless `--allow-usb`). Resolve the choice to a
   `/dev/disk/by-id/` path and use that for the rest of the run.
4. **Partition** (`lib/disk.sh`) — `sgdisk --zap-all`; p1 type `ef00`
   size `$ESP_SIZE`; p2 type `8309` (Linux root, LUKS) using the rest.
   Partition device names via `lsblk`, never string concat, using
   `part_suffix`.
5. **LUKS** — passphrase prompt x2; `cryptsetup luksFormat --type luks2`;
   `cryptsetup open` as `$LUKS_NAME`.
6. **Filesystems** — `mkfs.fat -F32` on p1; `mkfs.btrfs` on the mapper;
   mount top-level, create subvols from `BTRFS_SUBVOLS` (plus
   `@/.snapshots` if `CREATE_SNAPSHOTS_SUBVOL`), unmount, remount each at
   its target with `subvol=` + `BTRFS_OPTS` (`@swap` mounted `nodatacow`,
   no compression); mount ESP at `/mnt/boot`. If `SWAP=hibernate`:
   `btrfs filesystem mkswapfile --size $(hibernate_swap_size) /mnt/swap/swapfile`
   and capture `resume_offset` from
   `btrfs inspect-internal map-swapfile -r`.
7. **pacstrap -K /mnt** — `base linux-cachyos linux-cachyos-headers
   linux-firmware btrfs-progs cryptsetup mkinitcpio $(detect_ucode)
   networkmanager sudo git openssh zram-generator limine` + Limine
   mkinitcpio/entry hook packages (exact names TBD, see Open questions) +
   `$(detect_gpu_pkgs)`.
8. **fstab** — `genfstab -U /mnt >> /mnt/etc/fstab`; append each
   `EXTRA_FSTAB_ENTRIES` line verbatim; if `SWAP=hibernate` append
   `/swap/swapfile none swap defaults 0 0`.
9. **arch-chroot -> chroot-setup.sh** —
   - timezone / locale / keymap / hostname (prompt if `HOSTNAME` empty)
   - `useradd -m -G wheel`, set user + root passwords, enable `%wheel`
     sudo
   - `/etc/systemd/zram-generator.conf` with `zram-size = $(zram_size)`
   - `/etc/mkinitcpio.conf`:
     `HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems resume fsck)`
     (`resume` only when `SWAP=hibernate`); `MODULES=($(detect_gpu_modules))`
   - `/etc/kernel/cmdline`:
     `cryptdevice=PARTUUID=<p2>:$LUKS_NAME root=/dev/mapper/$LUKS_NAME rootflags=subvol=@ rw rootfstype=btrfs $EXTRA_CMDLINE $(detect_gpu_cmdline)`
     plus `resume=/dev/mapper/$LUKS_NAME resume_offset=<N>` when hibernate
   - **Limine UKI setup** (`lib/bootloader.sh`, see below)
   - `mkinitcpio -P`
   - `systemctl enable NetworkManager sshd`
10. Unmount `-R`; `cryptsetup close`; reboot.
11. **Post-reboot** — log in as the user; the staged
    `~/proj/slievr-cachy` is already on a data disk / USB; run
    `cachyos/bootstrap.sh` for the desktop layer.

## Limine UKI (lib/bootloader.sh)

Reproduces the desktop: kernel + microcode + initramfs + cmdline built
into `/boot/EFI/Linux/*.efi`; Limine is the EFI payload that reads
`limine.conf`.

- `limine` package + the CachyOS Limine mkinitcpio hook package (builds
  the UKI on every `mkinitcpio -P`) + `limine-entry-tool` (writes
  `limine.conf` entries). **Exact package names to be confirmed against
  the live CachyOS repos during implementation** — this is the step
  expected to need VM iteration.
- Copy `/usr/share/limine/BOOTX64.EFI` -> `/boot/EFI/BOOT/BOOTX64.EFI`;
  register an `efibootmgr` entry pointing at it.
- Snapshot boot entries (`limine-snapper-sync`) are out of scope for v1.

## Testing

- **test-detect.sh** — fixtures for desktop / Intel laptop / VM; asserts
  package + cmdline + module output. Runs on the host, no VM.
- **VM** — `cachyos/vm/provision-vm.sh` gains a **second blank disk** so
  multi-disk selection and the wrong-disk guard are exercised. Full loop:
  boot ISO -> mount the second disk holding a staged repo copy (mimics the
  real "repo on a data disk" delivery) -> run `install/install-cachyos.sh`
  -> reboot -> `bootstrap.sh` -> verify the desktop comes up.
- VM hardware differences are covered by the detection design: virtio
  `/dev/vda` (no `p` suffix), single virtio/QXL GPU (no driver package),
  `part_suffix` handles all three naming schemes.

## Open questions / risks

1. **Limine hook package names** on CachyOS — confirm during
   implementation (`limine`, plus whatever provides the mkinitcpio UKI
   hook and `limine-entry-tool` equivalent). Highest-risk step.
2. `btrfs filesystem mkswapfile` requires a recent `btrfs-progs`; confirm
   it is present in the CachyOS ISO, else fall back to the manual
   `truncate` + `chattr +C` + `fallocate` + `mkswap` sequence.
3. `linux-cachyos-nvidia` vs building the module another way — confirm the
   CachyOS prebuilt NVIDIA kernel package name and that it coexists with
   the UKI hook.
4. Whether the CachyOS ISO's live env has `arch-install-scripts`
   (`pacstrap`, `genfstab`) — it should, confirm in preflight.
