# Installer: wipe drives as new storage, folders named by speed — design

**Date:** 2026-10-20
**Status:** approved 2026-10-20
**Branch:** `data-disk-wipe`

## Problem

The user is moving their main PC to fledge, and the drive layout they want
isn't the one they have. Today the OS (CachyOS, LUKS + btrfs) is on the
**WD Blue SN570 1TB**; four plain ext4 storage drives mount as
`~/storage1..4`. They want fledge on the **Predator SSD GM7 4TB** (the
biggest, fastest drive, now `storage4`) as the new system drive, OS and
`/home` together, and the SN570 to become a storage drive.

The installer can already install to the Predator. It can't do anything
with the SN570 afterwards: the Data disks step only mounts filesystems that
already exist, and never offers LUKS, so the old OS drive is a dead end that
needs manual partitioning after the install. The graphical installer's
design listed "Formatting data disks" as a non-goal; this reverses that.

Separately, `~/storageN` says nothing about a drive. The user wants the
folder name in their home to tell fast drives from slow ones.

## Goals

- On the **Data disks** step, any drive except the install target and the
  installer's own stick can be **wiped and made a fresh storage drive**:
  one partition, ext4, unencrypted, mounted permanently like the other data
  disks.
- Works on **any machine and any drives**, not only the user's: drives with
  an old OS, LUKS, an unknown filesystem or nothing at all qualify.
- Default mount folders **say what kind of drive it is**: `~/nvme1`,
  `~/ssd1`, `~/hdd1`, `~/usb1`, numbered per kind.
- The user's own `profile.sh` defaults move to that scheme.
- Wiping a storage drive is as visible on Review as erasing the target.
- **A clean boot**: the firmware boot entries of every drive the installer
  erases (the target and every wiped drive) are removed, and fledge's entry
  is first in the boot order. Drives the person keeps keep their boot
  entries.

## Non-goals

- Encrypting storage drives (the user's call: plain, like their others).
- Choosing a filesystem, partition sizes, or wiping one partition of a
  drive. A wipe takes the whole drive.
- Putting `/home` on a separate drive. (The user's case is solved by
  installing to the big drive.)
- Wiping from a manual or unattended run without the GUI's answers
  (`install-cachyos.sh` without `--answers` never wipes a second drive).
- Moving data. Whatever is on a drive to be wiped (on the user's machine:
  `storage4` on the Predator, `/home` on the SN570) has to be copied off
  beforehand; that's on the person installing.
- Renaming mounts on already-installed systems. No migration.

## Decisions

| Question | Decision | Whose |
|---|---|---|
| Wipe at all | Yes, from the Data disks step | user |
| Default | Never wipe: Wipe is never pre-selected, not even from `profile.sh`; every wipe is chosen by hand | user |
| Confirming a wipe | One "Erase this drive" press per wiped drive, like the target's "Erase this disk" | my call |
| Drives held by LVM / RAID / swap on the live system | Wipe not offered; the card says why | my call |
| Which drives | Any drive the installer sees but the target and the live stick, USB included | user |
| Encryption | None | user |
| Folder names | By kind: `nvme`, `ssd`, `hdd`, `usb` + number | user |
| Rename the user's own defaults | Yes, to the new scheme | user |
| Layout of a wiped drive | GPT, one partition over the whole drive, ext4 | my call |
| Wipe granularity | Whole drive only; partitions you want to keep are mounted as they are | my call |
| Label of a wiped drive | Its own editable field; defaults to the name by kind (the suggested folder's name, e.g. `nvme1`); unique on the machine | user |
| Numbering | Folders already taken by a `profile.sh` default are skipped; the rest are numbered in the order the drives are listed | my call |
| Old firmware boot entries | Removed for every erased drive; kept for drives that are kept (mounted or left alone) | user |
| Kind detection | `TRAN=nvme` → nvme, `TRAN=usb` → usb, else `ROTA=0` → ssd, else hdd | my call |

## User flow: the Data disks step

The step changes from one row per filesystem to **one card per drive**
(every whole disk but the chosen target and the live stick). The card
header shows the model (or the kernel name when there is none), size and
kind (`NVMe`, `SATA SSD`, `Hard disk`, `USB`) and the disk path, muted.

Each card has three choices (a segmented control or radio row):

1. **Leave alone** — nothing mounted, nothing changed. The default unless
   a filesystem on it has a `profile.sh` default.
2. **Mount** — only offered when the drive has at least one mountable
   filesystem (same rules as today's `datafs`: ext4, btrfs, xfs, ntfs,
   exfat, vfat; never ESP, swap or LUKS). Shows today's rows for that
   drive's filesystems: toggle, label/fstype/size, "Mount at". Selected by
   default when one of its filesystems has a `profile.sh` default (those
   rows pre-ticked with that path).
3. **Wipe** — a red line "Everything on *<model>* will be erased", a
   "Mount at" field pre-filled with the next free folder for its kind, a
   **Label** field pre-filled with the name by kind (`nvme1`), and an
   **Erase this drive** button. The step isn't complete until each
   wiped drive's button is pressed; changing the choice away from Wipe and
   back un-confirms it (like `diskConfirmed`). Choosing Wipe un-ticks that
   drive's filesystem rows (they won't exist). Never selected by default.

   Wipe isn't offered on a drive the live system is using: a partition
   that is an active LVM physical volume, an assembled RAID member, or
   active swap (probe: `lsblk` children of `TYPE` `lvm`/`raid*`, or
   `swapon --show`). The card shows "In use as LVM / RAID / swap here,
   can't be wiped" and only Leave alone / Mount. A LUKS container that is
   closed (the live system never opens one) is not "in use".

The step's subtitle loses "Nothing on them is changed" and says instead
that mounted drives are left as they are and wiped drives are erased when
the install starts. The step is skipped only when there is no drive besides
the target and the live stick (today: when there is no mountable
filesystem). Keyboard: the step is reachable with Tab like the others
(the Tab work in PR #3); arrow keys between the three choices.

Validation is today's, applied to wipe folders too: `valid_mount_path`
rules, no two mounts (existing or wiped) on the same folder.

**Review**: each wiped drive gets its own red **Erase** row, below the
target's, worded like it: `<model> · <size> · <path>  →  <folder>`, with
Edit back to Data disks. The Data disks row keeps listing ticked mounts.
Nothing is written before **Erase and install**, as today.

## Default folder names

Every row or wipe without a `profile.sh` default gets the next free
`~/<kind><n>`: `n` starts at 1 per kind and skips any folder already used
by a default or by a ticked row or a wipe. This replaces today's
`~/storageN`.

*My call (from the builder check):* a suggested name is **not** a
reservation. Names are derived from the current state, not handed out once
when the probe arrives: unticked rows and drives on the chosen target never
take a number, and suggestions are recomputed when the target, a tick or a
wipe changes. Only a name the person typed sticks (an `edited` flag per
mount/wipe). So on the user's machine the SN570 wipe gets `~/nvme1`
whatever order `lsblk` lists the drives in. Choices and typed names survive
a probe refresh, as today.

The user's `profile.sh` `DATA_DISKS` becomes:

| UUID | Drive | Was | Now |
|---|---|---|---|
| `77d7988e…` | Sabrent Rocket 4.0 1TB (NVMe) | `~/storage3` | `~/nvme2` |
| `5e62f799…` | Crucial MX500 2TB (SATA SSD) | `~/storage2` | `~/ssd1` |
| `ceb2ac52…` | PNY CS900 480GB (SATA SSD) | `~/storage1` | `~/ssd2` |
| `55cefb4f…` | Predator 4TB | `~/storage4` | removed: it becomes the system drive |

`nvme1` is deliberately left free for the SN570, which on the user's
install is wiped and gets `~/nvme1` by default. The VM's test-disk entry
(`~/testdata`) stays.

## Architecture

### Probe (`lib/probe.jq`, `fledge-probe`)

- `lsblk` gains the `ROTA` column.
- `disks[]` (install targets) gains `kind` (the table above).
- New `drives[]`: every whole disk but the live one, USB included, as
  `{path, size, model, tran, kind, parts}`. This is the Data disks step's
  card list (`disks[]` stays the Disk step's list, which still hides USB).
- each `drives[]` entry gains `busy`: `""`, `"lvm"`, `"raid"` or `"swap"`,
  as above.
- `datafs[]` unchanged except that it can be joined to `drives[]` by
  `disk`.

### State (`services/Installer.qml`)

- `mounts` (uuid → `{on, path}`) stays. New `wipes`: disk path →
  `{on, path}`. A drive's card state is derived: wipe on → Wipe; any
  mount on → Mount; else Leave alone.
- `dataRows` and the new card list drop the target disk, as today. A wipe
  on the drive just chosen as target is dropped with it.
- Default-name assignment (`onFactsChanged`) moves to a pure function in
  `lib/` (testable in `tst_validate.qml`), covering both mounts and wipes.

### Answers (`lib/Answers.js`, `lib/answers.sh`)

New key **`DATA_WIPES`**: `<label>:/abs/path:<disk path>`,
comma-separated, `~` already expanded, may be empty. The disk path is the
probe's (`/dev/nvme0n1`), as the GUI already sends for `DISK`. It goes last
so a path with `:` (a `/dev/disk/by-id/usb-…-0:0` from a hand-written
answers file) still parses; the label and folder can't contain `:`. `parse_data_wipes` in
`answers.sh` mirrors `parse_data_mounts`: rejects a malformed entry, a
label `valid_data_label` refuses, a path `valid_mount_path` refuses, a disk
or path used twice. `install-cachyos.sh` additionally dies when:

- a wipe disk isn't a block device or isn't a whole disk;
- it's the target, or backs the live `/`, or has a mounted partition;
- a `DATA_MOUNTS` UUID lives on it;
- a wipe folder equals a `DATA_MOUNTS` folder;
- it's held by LVM, RAID or swap (the same check as the probe's `busy`).

### Backend (`lib/disk.sh`, `install-cachyos.sh`)

- New `format_data_disk <disk> <label>`: refuses a mounted disk (same check
  as `partition_disk`), then `wipefs -a`, `sgdisk --zap-all`,
  `sgdisk -n1:0:0 -t1:8300 -c1:<label>`, `partprobe`, `udevadm settle`,
  `mkfs.ext4 -F -L <label>`, and prints the new filesystem's UUID.
- Runs in the **disk** stage, right after the target's guards and
  confirmation, before the target is partitioned, one drive at a time,
  logged. Each wiped drive's `uuid<TAB>path` is appended to
  `DATA_MOUNTS_TSV`, so `add_data_mounts` handles fstab and the mountpoint
  exactly as for existing filesystems.
- A fresh ext4 root belongs to root. After `add_data_mounts`, each wiped
  filesystem is mounted briefly and its root chowned to the user (only
  wiped ones: existing filesystems keep their ownership).
- `mkfs.ext4` (e2fsprogs) joins the preflight tool check.

### Firmware boot entries (`install-cachyos.sh`)

The installer adds its own NVRAM entry (`limine-install`) but has never
removed stale ones, so a wiped old OS drive would leave an entry pointing at
nothing, which some firmware still lists or even tries first.

- Before anything is erased, record the GPT partition GUIDs (`PARTUUID`) of
  every partition on the target and on each wipe drive.
- After the bootloader stage, `efibootmgr` lists the entries; each whose
  `HD(…,GPT,<partuuid>,…)` device path names a recorded GUID is deleted
  (`efibootmgr -b <n> -B`). Entries on drives that were kept are never
  touched, nor are entries without a disk path (firmware setup, network
  boot).
- fledge's entry is put first in `BootOrder` (if `limine-install` doesn't
  already).
- The matching is a pure function over `efibootmgr -v` text and a GUID list
  in `lib/`, unit tested against fixtures.

Limine's `FIND_BOOTLOADERS=yes` stays: bootloaders on kept drives still show
in fledge's boot menu, consistent with "kept means kept".

### Labels

The label is its own field (the user's call), so the drive can be called
something other than its folder. Its default is the name by kind: the
suggested folder's last component (`nvme1`). Until the label is typed in,
it follows the folder suggestion as that is recomputed, and it also follows
the folder when the person edits only the folder (my call: one edit renames
both, which is what someone renaming `nvme1` to `games` expects). Once the
label itself is typed in, it sticks (its own `edited` flag).

`valid_data_label` (bash, mirrored in `Validate.js`): 1–16 bytes (ext4's
limit), `[A-Za-z0-9 ._-]`, not starting or ending with a space. Spaces are
allowed because a label is only shown, never a path; `,` and `:` aren't,
because they delimit `DATA_WIPES`. The label is used for both the GPT
partition name and the ext4 label.

**Labels are unique** (the user's call). A wipe label may not match another
wipe's label, nor the label of any filesystem that will still exist after
the install: filesystems on drives that are kept (left alone or mounted),
not those on the target or another wiped drive. The comparison ignores case
(my call: `Games` and `games` look the same in a file manager). The UI shows
"Another drive is already called <label>" under the field; the default
naming never produces a clash (it skips taken names like folders do), and
`install-cachyos.sh` re-checks against `blkid` labels of the drives not
being erased and dies on a clash.

## Failure handling

| Failure | Result |
|---|---|
| A wipe fails (busy, I/O error) | Stage `disk` fails as today; drives already wiped stay wiped; Failed screen, Clean up and start over |
| Install fails after the wipes | Same as a target failure today: the wiped drives are empty; a retry re-wipes them (they're still in the answers) |
| Drive vanishes between Review and Install | `install-cachyos.sh` dies on "not a block device" before anything is written |

## Testing (everything in the VM)

- **Unit**: `test-probe.sh` (`kind` from TRAN/ROTA, `drives[]` keeps USB
  and drops the live disk) with new fixture rows; `test-answers.sh`
  (`parse_data_wipes`: good, malformed, bad label, by-id with `:`, duplicate disk, duplicate path,
  system path); `tst_validate.qml` (default naming: per-kind numbering,
  skipping defaults and used folders, wipes counted; label default and
  follow/stick behaviour; label clashes (wipe vs wipe, wipe vs kept filesystem, case, target's labels ignored); `valid_data_label`; `DATA_WIPES` in the answers
  text, including a by-id path with `:`).
- **Unit**: the boot-entry matcher against `efibootmgr -v` fixtures (an
  entry on the target, one on a wiped drive, one on a kept drive, one
  without a disk path).
- **VM**: `verify-install.sh` checks no NVRAM entry names a PARTUUID that no
  longer exists and fledge is first in `BootOrder` (the VM's OVMF keeps
  NVRAM across reinstalls, so a second install exercises the stale case).
- **VM**: `provision-vm.sh` gains a third, blank virtual disk to wipe
  (the second keeps its test ext4 for the Mount path). `verify-install.sh`
  checks: the third disk has one ext4 partition with the expected label,
  its fstab line is present, it mounts on access at the chosen folder and
  is writable by the user, and the test data disk's contents are untouched.
- **Screens**: `verify-installer-screens.sh` shoots the new Data disks step
  (Leave / Mount / Wipe cards) and Review with two Erase rows;
  `verify-installer-focus.sh` covers Tab and arrows through the cards.
- The README screenshot for Data disks is retaken.

## Left to the builder

- The exact control for the three choices and the card styling, within the
  existing components.
- Whether `drives[]` replaces `disks[]` with a flag or sits beside it.
- Wording beyond what's quoted here, in the style of the existing steps.
