# Bare-metal CachyOS Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hardware-adaptive CachyOS installer that runs as root in the stock CachyOS live ISO and installs the desktop's LUKS2 + btrfs-subvol + Limine-UKI + zram layout onto any target machine.

**Architecture:** Runtime hardware detection (`lib/detect.sh`, pure functions) picks microcode / GPU driver / target disk / swap sizing. A hand-reviewed `profile.sh` holds the hardware-independent choices. `install-cachyos.sh` orchestrates: preflight -> detect -> disk guard -> partition/LUKS/btrfs (`lib/disk.sh`) -> pacstrap -> `arch-chroot` into `lib/chroot-setup.sh` (users, mkinitcpio, `lib/bootloader.sh` for Limine UKI) -> reboot. `bootstrap.sh` (unchanged role) does the desktop layer post-reboot.

**Tech Stack:** bash, sgdisk/parted, cryptsetup (LUKS2), btrfs-progs, arch-install-scripts (pacstrap/genfstab), mkinitcpio, Limine, zram-generator. Tests: plain bash assertion script for detection; QEMU/libvirt VM for integration.

**Spec:** `docs/superpowers/specs/2026-08-28-bare-metal-install-design.md`

## Global Constraints

- Target ISO: **stock official CachyOS ISO** — CachyOS repos already in its `pacman.conf`; do NOT run the `cachyos-repo.sh` bootstrap.
- UEFI only. Bootloader: **Limine booting a UKI** (`/boot/EFI/Linux/*.efi`), not systemd-boot.
- Root: **LUKS2** (`--type luks2`), mapper name from `profile.sh` `LUKS_NAME` (`root`). Unlock via kernel cmdline `cryptdevice=PARTUUID=<p2>:<LUKS_NAME>` + busybox `encrypt` hook — NOT `sd-encrypt`, NOT `/etc/crypttab`.
- Filesystem: btrfs, subvols `@ @home @log @pkg @swap` (+ `@/.snapshots`), mount opts `compress=zstd:3,ssd,space_cache=v2,relatime` (`@swap`: `nodatacow`, no compress).
- mkinitcpio HOOKS baseline: `base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck`; insert `resume` before `fsck` when `SWAP=hibernate`.
- Swap: zram-generator always on (`zram-size = min(RAM/2, 8192)` MiB); hibernate adds an encrypted btrfs swapfile at `/swap/swapfile`, size = round(RAM up to GiB) + 2 GiB, with `resume=/dev/mapper/<LUKS_NAME> resume_offset=<N>` on the cmdline.
- Never write to any disk except the user-confirmed target. Never touch a mounted disk, the disk backing `/` or `/run/archiso`, or a USB disk (unless `--allow-usb`).
- Partition device names always via `lsblk`/`sgdisk` output + `part_suffix`, never string concatenation.
- `set -euo pipefail` in every script. All `lib/*.sh` sourced relative to `install-cachyos.sh`'s own dir.
- Exact CachyOS package names for the Limine mkinitcpio/UKI hook, the prebuilt NVIDIA kernel module, and `arch-install-scripts` / recent `btrfs-progs` presence in the ISO are UNVERIFIED — confirm in Task 2 / Task 7 and adjust; do not block the plan on them.

---

### Task 1: Scaffold + profile.sh

**Files:**
- Create: `cachyos/install/profile.sh`
- Create: `cachyos/install/lib/.gitkeep` (placeholder until Task 2)
- Create: `cachyos/install/README.md`
- Delete: `cachyos/vm/install-cachyos.sh` (replaced; do this in Task 8 once the new one works — for now leave it)

**Interfaces:**
- Produces: `profile.sh` sets these vars when sourced: `TIMEZONE LOCALE KEYMAP USERNAME HOSTNAME ESP_SIZE LUKS_NAME BTRFS_SUBVOLS BTRFS_OPTS CREATE_SNAPSHOTS_SUBVOL KERNEL SWAP HIBERNATE_SWAP_SIZE EXTRA_CMDLINE EXTRA_FSTAB_ENTRIES`.
  - `BTRFS_SUBVOLS` is a bash array of `subvol:mountpoint` strings.
  - `EXTRA_FSTAB_ENTRIES` is a bash array of full fstab lines.

- [ ] **Step 1: Write `profile.sh`** — verbatim from the spec's "profile.sh — the fixed choices (complete)" section, including the four `EXTRA_FSTAB_ENTRIES` desktop data-disk lines and header comments explaining each var and which are per-machine.

- [ ] **Step 2: Write `README.md`** — how the installer is invoked (staged repo on an untouched partition, `sudo cachyos/install/install-cachyos.sh` in the live ISO), what `profile.sh` is for, that `lib/detect.sh` is unit-tested via `test-detect.sh`, and a "per-machine before you run it" checklist (edit `HOSTNAME` or leave blank to be prompted; set `EXTRA_FSTAB_ENTRIES=()` on machines without extra data disks).

- [ ] **Step 3: Verify** — `bash -n cachyos/install/profile.sh` and `bash -c 'source cachyos/install/profile.sh && declare -p BTRFS_SUBVOLS EXTRA_FSTAB_ENTRIES SWAP'`. Expected: arrays print, `SWAP=hibernate`.

- [ ] **Step 4: Commit** — `git add cachyos/install && git commit -m "Add install/ scaffold and profile.sh"`

---

### Task 2: lib/detect.sh + test-detect.sh (TDD)

**Files:**
- Create: `cachyos/install/lib/detect.sh`
- Create: `cachyos/install/test-detect.sh`
- Create: `cachyos/install/test/fixtures/` (canned `cpuinfo-*`, `lspci-*` files)

**Interfaces:**
- Produces (all print to stdout, take input path/text as `$1` where noted):
  - `detect_ucode <cpuinfo_path>` -> `amd-ucode` | `intel-ucode`
  - `detect_gpu_pkgs <lspci_text>` -> space-separated pkg list (may be empty)
  - `detect_gpu_cmdline <lspci_text>` -> `nvidia_drm.modeset=1` | empty
  - `detect_gpu_modules <lspci_text>` -> `nvidia nvidia_modeset nvidia_uvm nvidia_drm` | empty
  - `part_suffix <disk_name>` -> `p` | empty
  - `zram_size <memtotal_kb>` -> integer MiB
  - `hibernate_swap_size <memtotal_kb>` -> integer MiB
  - `list_disks` -> lines `NAME<TAB>SIZE<TAB>MODEL<TAB>TRAN` (live-uses `lsblk`; excludes live media + usb; not fixture-tested, exercised in VM)

- [ ] **Step 1: Write fixtures** — `cpuinfo-amd` (has `vendor_id : AuthenticAMD`), `cpuinfo-intel` (`GenuineIntel`); `lspci-desktop` (NVIDIA GA102 + AMD Raphael rows, real `lspci -nn` format from the spec), `lspci-laptop-intel` (one Intel VGA row), `lspci-vm` (one `Red Hat` / QXL VGA row).

- [ ] **Step 2: Write `test-detect.sh`** — sources `lib/detect.sh`, runs each function against fixtures, asserts:
  - `detect_ucode cpuinfo-amd` == `amd-ucode`; `...-intel` == `intel-ucode`
  - `detect_gpu_pkgs lspci-desktop` contains `linux-cachyos-nvidia` AND `vulkan-radeon`
  - `detect_gpu_pkgs lspci-laptop-intel` == `vulkan-intel`
  - `detect_gpu_pkgs lspci-vm` == `` (empty)
  - `detect_gpu_cmdline lspci-desktop` == `nvidia_drm.modeset=1`; `lspci-vm` == ``
  - `detect_gpu_modules lspci-desktop` == `nvidia nvidia_modeset nvidia_uvm nvidia_drm`
  - `part_suffix nvme1n1` == `p`; `part_suffix sda` == ``; `part_suffix vda` == ``; `part_suffix mmcblk0` == `p`
  - `zram_size 64000000` (~61 GiB) == `8192` (capped); `zram_size 8000000` (~7.6 GiB) == `3906`
  - `hibernate_swap_size 64000000` == `63488` (62 GiB rounded up) ... compute exact expected in-script from the formula and assert equality
  Script exits non-zero on any failed assertion, prints `PASS`/`FAIL` per case.

- [ ] **Step 3: Run — expect FAIL** — `bash cachyos/install/test-detect.sh`. Expected: fails, `detect.sh` functions undefined.

- [ ] **Step 4: Implement `lib/detect.sh`** — each function per the spec's detection table. `detect_gpu_*` grep the lspci text for `VGA compatible controller|3D controller|Display controller` lines, then match vendor (`NVIDIA`, `Advanced Micro Devices|AMD|ATI`, `Intel`). `zram_size`: `kb/1024/2`, min with `8192`. `hibernate_swap_size`: `ceil(kb/1024/1024)` GiB `* 1024 + 2048`. `part_suffix`: regex `^(nvme|mmcblk|loop)`.

- [ ] **Step 5: Run — expect PASS** — `bash cachyos/install/test-detect.sh`. Expected: all PASS.

- [ ] **Step 6: Confirm ISO tooling assumption** — add a comment block in `detect.sh` noting `list_disks` needs `lsblk` with `-T/--tree`? no — plain `lsblk -dpno`. No action, just note the live-only functions.

- [ ] **Step 7: Commit** — `git add cachyos/install && git commit -m "Add hardware detection with fixture tests"`

---

### Task 3: lib/disk.sh — partition + LUKS + btrfs + swapfile

**Files:**
- Create: `cachyos/install/lib/disk.sh`

**Interfaces:**
- Consumes: `profile.sh` vars; `part_suffix` from `detect.sh`.
- Produces:
  - `partition_disk <disk_by_id_path>` — zaps, creates p1 ESP (`ef00`, `$ESP_SIZE`) + p2 (`8309`, rest). Echoes nothing; sets globals `ESP_PART` `LUKS_PART` (resolved device paths via `lsblk -rno NAME` on the disk).
  - `luks_format_open <luks_part>` — prompts passphrase x2 (`cryptsetup luksFormat --type luks2 --batch-mode` fed via here-string is NOT safe for a real passphrase; use `cryptsetup` interactive twice or read -s then pipe). Opens as `$LUKS_NAME`. Sets global `LUKS_PARTUUID` (`blkid -s PARTUUID -o value`).
  - `make_filesystems` — `mkfs.fat -F32 "$ESP_PART"`; `mkfs.btrfs -f /dev/mapper/$LUKS_NAME`; mounts `/dev/mapper/$LUKS_NAME` at `/mnt`, creates subvols from `BTRFS_SUBVOLS` (+ `@/.snapshots` if `CREATE_SNAPSHOTS_SUBVOL`), unmounts, re-mounts each subvol at `/mnt<mountpoint>` with `-o subvol=<name>,$BTRFS_OPTS` (swap subvol: `-o subvol=@swap,nodatacow`), `mkdir -p /mnt/boot` + mount `$ESP_PART`.
  - `make_swapfile` — only when `SWAP=hibernate`. `btrfs filesystem mkswapfile --size ${SIZE}M /mnt/swap/swapfile` (fallback: `truncate -s 0` + `chattr +C` + `fallocate` + `chmod 600` + `mkswap`). Sets global `RESUME_OFFSET` from `btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile`.

- [ ] **Step 1: Write `lib/disk.sh`** with the four functions above. `set -euo pipefail`. Each function `echo`s a `>>> partitioning <disk>` style progress line to stderr. Guard: `partition_disk` refuses if `findmnt --source` finds any mount on the disk or its partitions.

- [ ] **Step 2: Syntax + shellcheck** — `bash -n` and `shellcheck cachyos/install/lib/disk.sh` (fix warnings or disable with justification comment).

- [ ] **Step 3: Dry integration in VM deferred to Task 8.** No unit test — this only works against real block devices.

- [ ] **Step 4: Commit** — `git commit -m "Add disk.sh: partition, LUKS2, btrfs subvols, swapfile"`

---

### Task 4: lib/bootloader.sh — Limine UKI

**Files:**
- Create: `cachyos/install/lib/bootloader.sh`

**Interfaces:**
- Consumes: runs INSIDE `arch-chroot` (called from `chroot-setup.sh`). Env: `LUKS_NAME`, `LUKS_PARTUUID`, `EXTRA_CMDLINE`, `GPU_CMDLINE`, `SWAP`, `RESUME_OFFSET`.
- Produces: `setup_bootloader` — writes `/etc/kernel/cmdline`, ensures UKI is generated, installs Limine EFI binary + `limine.conf`, registers efibootmgr entry.

- [ ] **Step 1: Confirm packages in a scratch VM / pacman -Ss** — determine the real CachyOS package(s) providing the Limine mkinitcpio UKI hook and the `limine.conf` entry generator (candidates: `limine`, `limine-mkinitcpio-hook`, `limine-entry-tool`, `limine-dracut` — verify). Record findings as a comment header in `bootloader.sh` and update Task 7's pacstrap list.

- [ ] **Step 2: Write `/etc/kernel/cmdline`** content:
  `cryptdevice=PARTUUID=${LUKS_PARTUUID}:${LUKS_NAME} root=/dev/mapper/${LUKS_NAME} rootflags=subvol=@ rw rootfstype=btrfs ${EXTRA_CMDLINE} ${GPU_CMDLINE}` and, when `SWAP=hibernate`, append ` resume=/dev/mapper/${LUKS_NAME} resume_offset=${RESUME_OFFSET}`.

- [ ] **Step 3: Write `setup_bootloader`** — enable the mkinitcpio UKI preset (edit `/etc/mkinitcpio.d/${KERNEL}.preset` to emit `_uki=` / disable the plain image, per the hook's docs found in Step 1); `mkinitcpio -P`; `mkdir -p /boot/EFI/BOOT`; `cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI`; write minimal `/boot/limine.conf` pointing at the generated UKI (Tokyo Night colors from the current host's `limine.conf` are a nice-to-have, not required for v1 — plain config is fine); `efibootmgr --create --disk <esp disk> --part 1 --label "CachyOS (Limine)" --loader '\EFI\BOOT\BOOTX64.EFI'` guarded by an existing-entry check.

- [ ] **Step 4: Syntax + shellcheck.**

- [ ] **Step 5: Commit** — `git commit -m "Add bootloader.sh: Limine UKI setup"`

---

### Task 5: lib/chroot-setup.sh

**Files:**
- Create: `cachyos/install/lib/chroot-setup.sh`

**Interfaces:**
- Consumes: runs INSIDE `arch-chroot /mnt`. Env passed by orchestrator: all `profile.sh` vars + `LUKS_NAME LUKS_PARTUUID GPU_MODULES GPU_CMDLINE ZRAM_SIZE RESUME_OFFSET USER_PASSWORD ROOT_PASSWORD`.
- Produces: fully configured system short of unmount/reboot. Sources and calls `setup_bootloader` from `bootloader.sh`.

- [ ] **Step 1: Write `chroot-setup.sh`:**
  - `ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime`; `hwclock --systohc`
  - locale: append `$LOCALE UTF-8` to `/etc/locale.gen`, `locale-gen`, `echo "LANG=$LOCALE" > /etc/locale.conf`
  - `echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf`
  - hostname: if empty, `read -rp` prompt; write `/etc/hostname`
  - `useradd -m -G wheel -s /bin/bash "$USERNAME"`; `chpasswd` for user + root from env; uncomment `%wheel ALL=(ALL:ALL) ALL` in `/etc/sudoers`
  - `/etc/systemd/zram-generator.conf`: `[zram0]\nzram-size = $ZRAM_SIZE\ncompression-algorithm = zstd`
  - `/etc/mkinitcpio.conf`: set `HOOKS=(...)` per Global Constraints (`resume` inserted iff `SWAP=hibernate`); set `MODULES=($GPU_MODULES)`
  - `systemctl enable NetworkManager sshd`
  - `source "$(dirname "$0")/bootloader.sh"; setup_bootloader`
- [ ] **Step 2: Syntax + shellcheck.**
- [ ] **Step 3: Commit** — `git commit -m "Add chroot-setup.sh"`

---

### Task 6: install-cachyos.sh orchestrator — preflight + detect + disk guard

**Files:**
- Create: `cachyos/install/install-cachyos.sh`

**Interfaces:**
- Consumes: `profile.sh`, `lib/detect.sh`, `lib/disk.sh`.
- Produces: interactive selection; sets `DISK` (by-id path), `UCODE GPU_PKGS GPU_CMDLINE GPU_MODULES ZRAM_SIZE` for later phases.

- [ ] **Step 1: Write preflight** — `[[ $EUID -eq 0 ]]`; `[[ -d /sys/firmware/efi ]]`; `[[ -f /run/archiso/... || -f /etc/cachyos-release || grep -q archiso /proc/cmdline ]]` (best-effort live-env check, warn-not-fail); `command -v pacstrap genfstab cryptsetup sgdisk mkfs.btrfs efibootmgr` — hard fail listing any missing; `ping -c1` a mirror (warn-not-fail).
- [ ] **Step 2: Source profile + libs; run detection; print summary table** — CPU ucode, GPU pkgs/cmdline/modules, `MemTotal` -> zram + swapfile sizes, then `list_disks` as a numbered menu.
- [ ] **Step 3: Disk selection + guard** — `read` a menu number; resolve to `/dev/disk/by-id/` (prefer a `nvme-`/`ata-` id, not `wwn-`); print model+size+`sgdisk -p`; refuse if mounted / backs `/` / live media / `TRAN=usb` w/o `--allow-usb`; require the user to type the exact MODEL string; final `type YES to destroy` confirm.
- [ ] **Step 4: Syntax + shellcheck.**
- [ ] **Step 5: Commit** — `git commit -m "Add orchestrator: preflight, detection summary, disk guard"`

---

### Task 7: install-cachyos.sh — install phases

**Files:**
- Modify: `cachyos/install/install-cachyos.sh`

- [ ] **Step 1: Wire the disk phase** — call `partition_disk "$DISK"`, `luks_format_open "$LUKS_PART"`, `make_filesystems`, `make_swapfile`.
- [ ] **Step 2: pacstrap** — build the package array: base set from Global Constraints + `$UCODE` + `$GPU_PKGS` + verified Limine packages (from Task 4 Step 1) + `zram-generator`. `pacstrap -K /mnt "${pkgs[@]}"`.
- [ ] **Step 3: fstab** — `genfstab -U /mnt >> /mnt/etc/fstab`; append each `EXTRA_FSTAB_ENTRIES` line; append `/swap/swapfile none swap defaults 0 0` iff hibernate. `sed`-dedupe any accidental duplicate of the swapfile line.
- [ ] **Step 4: chroot** — copy `lib/bootloader.sh` into `/mnt/root/` alongside a generated env file; `arch-chroot /mnt bash /root/chroot-setup.sh` with all needed vars exported (prompt for user + root passwords in the orchestrator with `read -s`, pass via env, not argv).
- [ ] **Step 5: Teardown** — `umount -R /mnt`; `cryptsetup close "$LUKS_NAME"`; print "done, reboot then run bootstrap.sh"; `read -rp` before `reboot`.
- [ ] **Step 6: Syntax + shellcheck.**
- [ ] **Step 7: Commit** — `git commit -m "Add orchestrator install phases: disk, pacstrap, fstab, chroot"`

---

### Task 8: VM integration + cutover

**Files:**
- Modify: `cachyos/vm/provision-vm.sh` (add second blank disk)
- Modify: `cachyos/vm/dev-up.sh` / `cachyos/vm/README.md` (doc the new flow)
- Delete: `cachyos/vm/install-cachyos.sh`
- Modify: `cachyos/NEXT-SESSION.md` (or the handoff doc) to reference `cachyos/install/`

- [ ] **Step 1: `provision-vm.sh`** — add `--disk size=8,path=/var/lib/libvirt/images/${VM_NAME}-data.qcow2` as a second disk so disk selection + the wrong-disk guard are exercised.
- [ ] **Step 2: Full VM run** — recreate VM (`destroy-vm.sh` + `provision-vm.sh`), boot ISO, in the live env: partition+format the data disk, copy the repo onto it (mimics staged delivery), mount it, run `cachyos/install/install-cachyos.sh`, pick the *main* disk, complete install, reboot.
- [ ] **Step 3: Verify booted system** — LUKS passphrase prompt appears; boots to a login; `lsblk` shows the subvol layout; `swapon --show` lists zram0 (+ `/swap/swapfile` — note VM has less RAM, hibernate not truly testable but the swapfile + resume cmdline should be present); `bootctl status` shows Limine; the data disk is untouched.
- [ ] **Step 4: Run `bootstrap.sh`** — from the staged repo; verify the desktop still comes up (waybar, walker, sddm) as in the prior working state.
- [ ] **Step 5: Cutover** — delete `cachyos/vm/install-cachyos.sh`, update docs.
- [ ] **Step 6: Commit** — `git commit -m "VM integration: second disk, docs, remove old vm installer"`

---

## Self-Review

**Spec coverage:**
- Delivery (staged repo) — Task 1 README, Task 8 Step 2. ✓
- profile.sh complete — Task 1. ✓
- Detection table (all 8 rows) — Task 2. ✓
- Install flow steps 1-11 — Tasks 6 (1-3), 7 (4-10), reboot/bootstrap (11) Task 8. ✓
- Limine UKI — Task 4. ✓ (package names flagged unverified, Task 4 Step 1 resolves)
- Hibernate swapfile + resume — Task 3 `make_swapfile`, Task 5 HOOKS/cmdline, Task 4 cmdline. ✓
- zram always — Task 5. ✓
- Data-disk preservation — Task 1 `EXTRA_FSTAB_ENTRIES`, Task 7 Step 3, Task 8 Step 3 verify. ✓
- Disk guard — Task 6 Step 3. ✓
- Testing (fixtures + VM second disk) — Task 2, Task 8. ✓
- Snapshots out of scope, `.snapshots` subvol created — Task 3 `make_filesystems`. ✓

**Placeholder scan:** Task 4 carries genuine unknowns (Limine package/preset mechanics) resolved by its own Step 1 against a live system — acceptable as an investigate-then-implement step, not a plan placeholder. No other TBDs.

**Type consistency:** `LUKS_NAME`, `LUKS_PART`, `LUKS_PARTUUID`, `ESP_PART`, `GPU_PKGS/GPU_CMDLINE/GPU_MODULES`, `ZRAM_SIZE`, `RESUME_OFFSET` used consistently across Tasks 3-7. `detect_gpu_*` take lspci *text*; orchestrator passes `"$(lspci -nn)"`. `part_suffix` returns `p`/empty, consumed in `disk.sh`.
