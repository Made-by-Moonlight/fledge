# Installer: wipe drives as new storage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The graphical installer's Data disks step can wipe any non-target drive into a fresh ext4 storage drive with an editable unique label, default folders are named by drive kind (`~/nvme1`, `~/ssd1`, `~/hdd1`, `~/usb1`), and firmware boot entries of every erased drive are removed.

**Architecture:** The probe (`lib/probe.jq`) reports every drive with its kind and whether the live system holds it. Pure JS (`lib/Drives.js`, `Validate.js`, `Answers.js`) names, validates and serialises; `Installer.qml` holds per-drive choices; `DataDisks.qml` shows one card per drive. The answers file gains `DATA_WIPES`; `install-cachyos.sh` re-validates, wipes before partitioning the target, feeds the new UUIDs into the existing `DATA_MOUNTS_TSV` path, and prunes stale NVRAM entries after the bootloader stage.

**Tech Stack:** bash (shellcheck-clean, `set -euo pipefail`), jq, QML/Quickshell (Qt 6), `qmltestrunner`, sgdisk/wipefs/mkfs.ext4/efibootmgr.

**Spec:** `docs/superpowers/specs/2026-10-20-installer-wipe-data-disks-design.md`

## Global Constraints

- **Everything that runs project code runs in the test VM** (`cachyos/vm/`, `cachyos-test`), unit tests included: `cachyos/vm/vm.sh sync` then `cachyos/vm/vm.sh run 'bash ~/proj/fledge/<test>'`. Never on the host.
- Shell: bash, `set -euo pipefail` in scripts, shellcheck-clean; comments explain *why*; match surrounding density.
- Tests: `test-*.sh` with `cachyos/install/test/lib.sh` (`check name expected actual`, `contains`, `exit $fail`); QML unit tests in `cachyos/iso/installer/test/tst_validate.qml` via `cachyos/iso/test-installer-qml.sh`.
- Commit messages: `area: what changed and why`, lowercase area (`install:`, `iso:`, `docs:`, `vm:`).
- Names: product is `fledge`; no `mbm`/`slievr`/`made-by-moonlight` component names (`cachyos/check-names.sh`).
- Wipe is **never** pre-selected, not even from `profile.sh`.
- Wiped layout: GPT, one partition over the whole disk, type `8300`, ext4, unencrypted; partition name = ext4 label = the label.
- Kind: `tran == nvme` → `nvme`; `tran == usb` → `usb`; else not rotational → `ssd`; else `hdd`. UI names: `NVMe`, `SATA SSD`, `Hard disk`, `USB`.
- Default folder: `~/<kind><n>`, smallest `n ≥ 1` not used by a `profile.sh` default (off the target), an active mount/wipe, or (for its basename) a label on a kept drive.
- Label: 1–16 bytes, `[A-Za-z0-9 ._-]`, no leading/trailing space; unique ignoring case against other wipes and every filesystem label on drives that are kept; labels on the target or another wiped drive don't count.
- `DATA_WIPES` = comma-separated `<label>:<abs path>:<disk path>`, `~` expanded, may be empty.
- Boot entries: delete every NVRAM entry whose `HD(…,GPT,<guid>,…)` names a partition GUID recorded on the target or a wipe disk **before** erasing; never touch entries for kept drives or without a disk path; fledge's entry first in `BootOrder`.
- Copy: wipe warning "Everything on *<model>* will be erased", button **Erase this drive**, label clash "Another drive is already called <label>", busy "In use as <LVM|RAID|swap|…> here, can't be wiped".

## Review Focus

1. **Target changed after a wipe was set**: picking the wiped drive as the install target drops its wipe from the step, the Review page and the answers; picking another target brings it back unconfirmed. → Task 5 test `test_targetDropsWipe`.
2. **Probe refresh mid-step** (a USB stick plugged in): choices, confirmations and typed folders/labels survive; only new drives get suggestions. → Task 5 test `test_refreshKeepsChoices`.
3. **Mount ↔ Wipe ↔ Leave switching**: leaving Wipe un-confirms; switching to Wipe un-ticks the drive's filesystem rows so they never reach `DATA_MOUNTS`. → Task 5 test `test_choiceSwitching`.
4. **Model-less drives (virtio, some USB)**: card, Erase row and warning use the kernel name (`vdc`). → Task 4 test in `test_drivesNames`.
5. **"Clean up and start over" after a failed install**: the wiped drive now has a fresh ext4; the retry still sends the wipe once (no duplicate mount row for the new filesystem). → Task 5 test `test_wipeHidesItsRows`.

---

### Task 1: Probe reports drives, kind and busy

**Files:**
- Modify: `cachyos/iso/lib/probe.jq`
- Modify: `cachyos/iso/configs/airootfs/usr/local/bin/fledge-probe` (lsblk columns)
- Modify: `cachyos/iso/test/fixtures/lsblk.json`
- Test: `cachyos/iso/test-probe.sh`

**Interfaces:**
- Produces: `facts.disks[].kind`; new `facts.drives[]` = `{path, size, model, tran, kind, busy, parts}` for every whole disk except the live one and zram/ram/loop, **USB included**, in lsblk order. `busy` ∈ `"" | "lvm" | "raid" | "crypt" | "swap" | "mounted"`; `parts` as in `disks[]`. `datafs[]` unchanged.

- [ ] **Step 1: Extend the fixture.** Add `"rota"` and `"mountpoints"` to every node (lsblk 2.40 JSON: `rota` is a boolean, `mountpoints` an array, `[null]` when unmounted). Make `/dev/sda` `rota:false`; add `/dev/sdf` (`tran:"sata"`, `rota:true`, no model) whose `sdf1` (`fstype:"LVM2_member"`) has a child `{type:"lvm", path:"/dev/mapper/vg-root"}`; give `/dev/nvme0n1p4` `mountpoints:["[SWAP]"]`.

- [ ] **Step 2: Write the failing tests** in `test-probe.sh`:

```bash
check "disks: kind nvme"           "nvme" "$(probe '.disks[] | select(.path=="/dev/nvme2n1") | .kind')"
check "disks: kind ssd (sata, not rotational)" "ssd" "$(probe '.disks[0].kind')"
check "drives: usb kept, live stick dropped" "/dev/sda /dev/sdd /dev/nvme2n1 /dev/nvme0n1 /dev/vde /dev/sdf" "$(probe '[.drives[].path] | join(" ")')"
check "drives: kind usb"           "usb"  "$(probe '.drives[] | select(.path=="/dev/sdd") | .kind')"
check "drives: kind hdd"           "hdd"  "$(probe '.drives[] | select(.path=="/dev/sdf") | .kind')"
check "drives: active lvm is busy" "lvm"  "$(probe '.drives[] | select(.path=="/dev/sdf") | .busy')"
check "drives: active swap is busy" "swap" "$(probe '.drives[] | select(.path=="/dev/nvme0n1") | .busy')"
check "drives: closed LUKS is free" ""    "$(probe '.drives[] | select(.path=="/dev/nvme2n1") | .busy')"
```

- [ ] **Step 3: Run, expect FAIL:** `cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test-probe.sh'` → new checks fail.

- [ ] **Step 4: Implement.** In `probe.jq`: `def kind` (accept `rota` as `true/false`, `"1"/"0"` or `1/0`); `def busy`: scan descendants (not the disk itself) in order — any `type == "lvm"` → `lvm`, `type` starting `raid` → `raid`, `type == "crypt"` → `crypt`, a mountpoint `"[SWAP]"` → `swap`, any other non-null mountpoint → `mounted`, else `""`. Keep existing outputs byte-identical apart from the added `kind`. In `fledge-probe`, add `ROTA,MOUNTPOINTS` to the `lsblk -o` list (and `TYPE` children come for free with `-J`).

- [ ] **Step 5: Run, expect PASS** (all old and new checks).

- [ ] **Step 6: Commit** `iso: the probe lists every drive with its kind (nvme, ssd, hdd, usb) and whether the live system holds it`

---

### Task 2: Answers: `DATA_WIPES` and label rules (bash)

**Files:**
- Modify: `cachyos/install/lib/answers.sh`
- Test: `cachyos/install/test-answers.sh`

**Interfaces:**
- Produces: `valid_data_label <label>` → 0/1. `parse_data_wipes <spec>` → lines `disk<TAB>path<TAB>label`, returns 1 on: no two `:`, bad label, path refused by `valid_mount_path`, disk not matching `^/dev/[^,[:space:]]+$`, a disk, path or label (lowercased) used twice. `DATA_WIPES` added to `ANSWER_KEYS`.

- [ ] **Step 1: Write the failing tests:**

```bash
check "label: kind name"           yes "$(ok valid_data_label nvme1)"
check "label: spaces inside"       yes "$(ok valid_data_label 'Game Drive')"
check "label: 16 bytes"            yes "$(ok valid_data_label abcdefghijklmnop)"
check "label: 17 bytes refused"     no "$(ok valid_data_label abcdefghijklmnopq)"
check "label: empty refused"        no "$(ok valid_data_label '')"
check "label: edge space refused"   no "$(ok valid_data_label ' x')"
check "label: colon refused"        no "$(ok valid_data_label 'a:b')"
check "label: comma refused"        no "$(ok valid_data_label 'a,b')"
check "wipes: two" "$(printf '/dev/nvme0n1\t/home/e/nvme1\tnvme1\n/dev/disk/by-id/usb-X-0:0\t/data\tStick')" \
  "$(parse_data_wipes 'nvme1:/home/e/nvme1:/dev/nvme0n1,Stick:/data:/dev/disk/by-id/usb-X-0:0')"
check "wipes: empty"               "" "$(parse_data_wipes '')"
check "wipes: same label any case"  no "$(ok parse_data_wipes 'a:/x1:/dev/sda,A:/x2:/dev/sdb')"
check "wipes: same disk"            no "$(ok parse_data_wipes 'a:/x1:/dev/sda,b:/x2:/dev/sda')"
check "wipes: same folder"          no "$(ok parse_data_wipes 'a:/x1:/dev/sda,b:/x1:/dev/sdb')"
check "wipes: system folder"        no "$(ok parse_data_wipes 'a:/var/x:/dev/sda')"
check "wipes: malformed"            no "$(ok parse_data_wipes 'a:/x1')"
```

- [ ] **Step 2: Run, expect FAIL** (`vm.sh run 'bash ~/proj/fledge/cachyos/install/test-answers.sh'`).
- [ ] **Step 3: Implement** both functions next to `parse_data_mounts`, same style; split each entry as label = up to the first `:`, path = up to the second, disk = the rest.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `install: answers take DATA_WIPES (label:folder:disk) and check labels`

---

### Task 3: Install wipes drives and prunes stale boot entries

**Files:**
- Modify: `cachyos/install/lib/detect.sh` (pure helpers)
- Modify: `cachyos/install/lib/disk.sh` (`format_data_disk`, `own_wiped_roots`)
- Modify: `cachyos/install/install-cachyos.sh`
- Test: `cachyos/install/test-detect.sh`, fixtures inline

**Interfaces:**
- Consumes: `parse_data_wipes`, `valid_data_label` (Task 2).
- Produces (detect.sh, pure): `busy_reason <"TYPE MOUNTPOINT" lines of a disk's descendants>` → `lvm|raid|crypt|swap|mounted|""` (same rules as Task 1); `stale_boot_entries <efibootmgr -v text> <guid>...` → matching 4-hex boot numbers, one per line, GUIDs compared case-insensitively; `boot_entry_for <efibootmgr -v text> <guid>` → the first matching number; `order_first <BootOrder csv> <num>` → csv with `num` first and no duplicate.
- Produces (disk.sh): `format_data_disk <disk> <label>` → prints the new UUID on stdout; `own_wiped_roots` (uses globals `WIPED_UUIDS`, `USERNAME`).

- [ ] **Step 1: Write the failing tests** in `test-detect.sh`:

```bash
EFI=$'BootCurrent: 0001\nBootOrder: 0003,0001,0002,0000\nBoot0000* UiApp\tFvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(462caa21-7614-4503-836e-8ab6f4662331)\nBoot0001* Limine\tHD(1,GPT,6C2D0E1A-0000-4000-8000-000000000001,0x800,0x400000)/File(\\EFI\\limine\\BOOTX64.EFI)\nBoot0002* Windows Boot Manager\tHD(1,GPT,aaaa0000-0000-4000-8000-0000000000bb,0x800,0x32000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\nBoot0003* CachyOS\tHD(1,GPT,6c2d0e1a-0000-4000-8000-000000000009,0x800,0x400000)/File(\\EFI\\limine\\BOOTX64.EFI)'
check "boot: erased drives' entries" $'0001\n0003' "$(stale_boot_entries "$EFI" 6c2d0e1a-0000-4000-8000-000000000001 6C2D0E1A-0000-4000-8000-000000000009)"
check "boot: kept drive and firmware untouched" "" "$(stale_boot_entries "$EFI" 00000000-0000-4000-8000-000000000000)"
check "boot: entry for the new ESP" "0002" "$(boot_entry_for "$EFI" AAAA0000-0000-4000-8000-0000000000BB)"
check "boot: order first"   "0004,0003,0001" "$(order_first 0003,0004,0001 0004)"
check "boot: order new"     "0004,0003"      "$(order_first 0003 0004)"
check "busy: lvm"   lvm  "$(busy_reason $'part \nlvm /')"
check "busy: swap"  swap "$(busy_reason $'part [SWAP]')"
check "busy: mount" mounted "$(busy_reason $'part /run/media/x')"
check "busy: free"  ""   "$(busy_reason $'part \npart ')"
```
(A closed LUKS partition appears only as `part`, so it is free.)

- [ ] **Step 2: Run, expect FAIL** (`vm.sh run 'bash ~/proj/fledge/cachyos/install/test-detect.sh'`).
- [ ] **Step 3: Implement the pure helpers** in `detect.sh`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Implement the install path** in `install-cachyos.sh`:
  - `DATA_WIPES=""` default; with answers, `DATA_WIPES_TSV="$(parse_data_wipes "$DATA_WIPES")" || die "answers DATA_WIPES is malformed, repeats a disk, folder or label, or uses a system path"`. Without answers it stays empty (no wipes on manual runs).
  - Add `mkfs.ext4` to the preflight tool list; print `storage wipes : N drive(s)` in the summary.
  - After the existing data-disk guard loop, per wipe: die unless `[[ -b $disk ]]` and `lsblk -dno TYPE` is `disk`; die if it equals `$DISK_KNAME`, backs the live `/`, or `busy_reason "$(lsblk -rno TYPE,MOUNTPOINT "$disk" | tail -n +2)"` is non-empty; die if any `DATA_MOUNTS_TSV` UUID lives on it or any wipe folder equals a mount folder; die if its label (lowercased) equals a `lsblk -rno LABEL` label on any disk that is neither the target, a wipe disk, nor the live root disk.
  - Before `partition_disk`: `ERASED_GUIDS=($(lsblk -rno PARTUUID "$DISK_KNAME" <each wipe disk> | grep .))`, then new `rule "Storage drives"`: per wipe `uuid="$(format_data_disk "$disk" "$label")"`, append `uuid<TAB>path` to `DATA_MOUNTS_TSV`, add uuid to `WIPED_UUIDS`.
  - `format_data_disk`: refuse a mounted disk (same `findmnt` check as `partition_disk`), `wipefs -a`, `sgdisk --zap-all`, `sgdisk -n1:0:0 -t1:8300 -c1:"$label"`, `partprobe`, `udevadm settle`, `mkfs.ext4 -F -L "$label" <part>`, print `blkid -s UUID -o value <part>`; logs to stderr via `_log`.
  - After `add_data_mounts`: `own_wiped_roots` mounts each wiped UUID on a `mktemp -d`, `chown uid:gid` its root, unmounts.
  - After the chroot (bootloader done), still before `add_data_mounts`: read `efibootmgr -v`; `efibootmgr -b <n> -B` each `stale_boot_entries` match for `ERASED_GUIDS`; find fledge's entry with `boot_entry_for` on the new ESP's PARTUUID and set `efibootmgr -o "$(order_first <current BootOrder> <n>)"`. A failure here warns, never dies (the system boots either way).
- [ ] **Step 6: shellcheck** `cachyos/install/install-cachyos.sh cachyos/install/lib/*.sh` (in the VM) → clean.
- [ ] **Step 7: Commit** `install: wipe chosen drives into fresh ext4 storage before partitioning, and drop the boot entries of every erased drive`

---

### Task 4: Pure JS: kinds, suggestions, labels, answers

**Files:**
- Create: `cachyos/iso/installer/lib/Drives.js`
- Modify: `cachyos/iso/installer/lib/Validate.js`, `cachyos/iso/installer/lib/Answers.js`
- Test: `cachyos/iso/installer/test/tst_validate.qml`

**Interfaces:**
- Produces (`Drives.js`, `.pragma library`):
  - `kindName(kind) -> string` (`NVMe`, `SATA SSD`, `Hard disk`, `USB`).
  - `name(drive) -> string`: model, else the path's last component.
  - `suggest(kind, home, usedAbs, usedLabels) -> string`: smallest `"~/" + kind + n` whose expansion isn't in `usedAbs` (array of absolute paths) and whose basename, lowercased, isn't in `usedLabels` (array, lowercased).
  - `labelFor(path) -> string`: the path's last component, cut to 16 bytes.
- Produces (`Validate.js`): `dataLabel(label) -> ""|message` mirroring `valid_data_label` (messages: "Up to 16 letters, digits, spaces, . _ -", "No space at the start or end").
- Produces (`Answers.js`): `text(a)` takes `a.wipes = [{ disk, path, label }]` and emits `DATA_WIPES=<label>:<abs>:<disk>,…` as the last key before `END`.

- [ ] **Step 1: Write the failing tests:**

```qml
function test_drivesNames() {
    compare(D.kindName("ssd"), "SATA SSD");
    compare(D.name({ path: "/dev/vdc", model: "" }), "vdc");
    compare(D.suggest("nvme", "/home/e", ["/home/e/nvme2"], []), "~/nvme1");
    compare(D.suggest("nvme", "/home/e", ["/home/e/nvme1", "/home/e/nvme2"], []), "~/nvme3");
    compare(D.suggest("ssd", "/home/e", [], ["ssd1"]), "~/ssd2");
    compare(D.labelFor("~/games"), "games");
    compare(D.labelFor("/data/abcdefghijklmnopqrst"), "abcdefghijklmnop");
}
function test_dataLabel() {
    compare(V.dataLabel("nvme1"), ""); compare(V.dataLabel("Game Drive"), "");
    verify(V.dataLabel("") !== ""); verify(V.dataLabel(" x") !== "");
    verify(V.dataLabel("abcdefghijklmnopq") !== ""); verify(V.dataLabel("a:b") !== "");
}
function test_answersWipes() {
    const t = A.text({ disk: "/dev/vda", hostname: "h", timezone: "UTC", username: "e", password: "a",
                       sameLuks: true, luks: "", layout: "us", variant: "", mounts: [],
                       wipes: [{ disk: "/dev/vdc", path: "~/hdd1", label: "hdd1" }] });
    verify(t.endsWith("DATA_WIPES=hdd1:/home/e/hdd1:/dev/vdc\nEND\n"));
}
```
Update `test_answers` / `test_answersNoNewlines` for the new key (`wipes: []` → `DATA_WIPES=\n`; line count 13).

- [ ] **Step 2: Run, expect FAIL** (`vm.sh run 'bash ~/proj/fledge/cachyos/iso/test-installer-qml.sh'`).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `iso: name storage folders by drive kind and check wipe labels in the installer's JS`

---

### Task 5: Installer state: per-drive choices

**Files:**
- Modify: `cachyos/iso/installer/services/Installer.qml`
- Modify: `cachyos/iso/installer/shell.qml` (IPC)
- Create: `cachyos/iso/installer/test/tst_installer.qml` (loads `Installer.qml` with stubbed `Probe`/`Run`; if the singleton can't be loaded under `qmltestrunner`, move the logic below into a pure `lib/Choices.js` with the same function names and test that instead)
- Modify: `cachyos/iso/test-installer-qml.sh` (run the new file too)

**Interfaces:**
- Consumes: `facts.drives[]` (Task 1), `Drives.js`, `V.dataLabel` (Task 4).
- Produces:
  - `mounts`: uuid → `{ on, path, edited }`. `wipes`: disk path → `{ on, path, label, pathEdited, labelEdited, confirmed }`.
  - `readonly property var dataDrives`: `facts.drives` minus the target disk.
  - `dataRows`: as today, minus rows on the target **and rows on a drive with `wipes[disk].on`**.
  - `choice(disk) -> "leave"|"mount"|"wipe"`; `setChoice(disk, c)`: `"wipe"` sets `on`, `confirmed:false`, un-ticks that drive's mounts; `"mount"`/`"leave"` sets wipe `on:false, confirmed:false` (`"leave"` also un-ticks its mounts; `"mount"` ticks none by itself).
  - `setMount(uuid, on, path, edited)`; `setWipePath(disk, path)` (sets `pathEdited`); `setWipeLabel(disk, label)` (sets `labelEdited`); `confirmWipe(disk)`.
  - `names()`: recompute. Active (ticked mount / wipe on) items that aren't edited keep their path once given; inactive items and newly active ones get `D.suggest(kind, home, used, labels)` where `used` = profile defaults of rows off the target + paths of all other active items, and `labels` = lowercased labels of every part on kept drives (not the target, not a wipe-on drive). A wipe's label is `D.labelFor(path)` until `labelEdited`. Called from `onFactsChanged`, `onDiskChanged`, and after every setter.
  - `errors("data")` adds, per wipe-on drive: key `"wipe:" + disk` → `V.mountPath`/folder clash ("Two disks can't share a folder"); `"label:" + disk` → `V.dataLabel` or "Another drive is already called " + label; `"confirm:" + disk` → "Confirm the erase to continue".
  - `skipped("data")`: `dataDrives.length === 0`.
  - `answers()` passes `wipes: [{ disk, path, label }]` for wipe-on drives off the target.
  - IPC: `setWipe(path: string): string` → `setChoice(path,"wipe")` + `confirmWipe(path)`, returns `"ok"` or `"refused: busy"`/`"refused: target"`.

- [ ] **Step 1: Write the failing tests** (`tst_installer.qml`), using a facts stub with drives `/dev/nvme1n1` (nvme, target), `/dev/nvme0n1` (nvme, LUKS only), `/dev/nvme2n1` (nvme, ext4 uuid `S`, default `~/nvme2`), `/dev/sdb` (ssd, ext4 uuid `C`, default `~/ssd1`, label `ssd2`):

```qml
function test_sn570GetsNvme1() { I.disk = "/dev/nvme1n1"; I.setChoice("/dev/nvme0n1", "wipe");
    compare(I.wipes["/dev/nvme0n1"].path, "~/nvme1"); compare(I.wipes["/dev/nvme0n1"].label, "nvme1"); }
function test_labelFollowsFolderUntilTyped() { I.setWipePath("/dev/nvme0n1", "~/games"); compare(I.wipes["/dev/nvme0n1"].label, "games");
    I.setWipeLabel("/dev/nvme0n1", "Fast"); I.setWipePath("/dev/nvme0n1", "~/g2"); compare(I.wipes["/dev/nvme0n1"].label, "Fast"); }
function test_labelClashIgnoresCase() { I.setWipeLabel("/dev/nvme0n1", "SSD2"); I.show("data");
    compare(I.err("data", "label:/dev/nvme0n1"), "Another drive is already called SSD2"); }
function test_confirmRequired() { verify(I.errors("data")["confirm:/dev/nvme0n1"] !== undefined); I.confirmWipe("/dev/nvme0n1");
    compare(I.errors("data")["confirm:/dev/nvme0n1"], undefined); }
function test_choiceSwitching() { I.setChoice("/dev/nvme2n1", "wipe"); compare(I.mounts["S"].on, false);
    I.setChoice("/dev/nvme2n1", "mount"); I.setChoice("/dev/nvme2n1", "wipe"); compare(I.wipes["/dev/nvme2n1"].confirmed, false); }
function test_wipeHidesItsRows() { verify(!I.dataRows.some(r => r.uuid === "S")); }
function test_targetDropsWipe() { I.disk = "/dev/nvme0n1"; verify(I.answers().includes("DATA_WIPES=\n"));
    I.disk = "/dev/nvme1n1"; compare(I.wipes["/dev/nvme0n1"].confirmed, false); }
function test_refreshKeepsChoices() { I.setWipePath("/dev/nvme0n1", "~/fast"); /* re-assign facts stub with an extra usb drive */
    compare(I.wipes["/dev/nvme0n1"].path, "~/fast"); compare(I.choice("/dev/nvme0n1"), "wipe"); }
function test_neverWipeByDefault() { /* fresh facts */ verify(Object.values(I.wipes).every(w => !w.on)); }
```
(Each test sets up its own state in `init()`; the comments mark where the stub is re-assigned.)

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the state above; keep `setMount`'s "unchanged → no new object" guard (binding-loop reason in its comment).
- [ ] **Step 4: Run, expect PASS**, plus the existing `tst_validate.qml`.
- [ ] **Step 5: Commit** `iso: the installer keeps a leave/mount/wipe choice per drive, with folders and labels named by kind`

---

### Task 6: Data disks cards and Review rows

**Files:**
- Modify: `cachyos/iso/installer/steps/DataDisks.qml`, `cachyos/iso/installer/steps/Review.qml`
- Modify: `cachyos/iso/installer/ui/Input.qml` (add `signal edited(string text)` from `TextInput.textEdited`, so only typing marks a field edited)
- Modify: `cachyos/iso/installer/dev/facts.json` (add `drives[]` and `kind`; mirror the user's machine: Predator target, SN570 LUKS, Sabrent, Crucial, PNY, a USB stick)
- Test: `cachyos/iso/test/verify-installer-focus.sh`, `cachyos/iso/test/verify-installer-screens.sh`

**Interfaces:**
- Consumes: Task 5's state and setters; `D.kindName`, `D.name`.

- [ ] **Step 1: Write the failing VM checks.** In `verify-installer-focus.sh`: on the data step, Tab reaches each card's `Choice` (objectName `"<name> choice"`), Right moves Leave→Mount→Wipe, Tab from a Wipe card goes Mount at → Label → `Erase this drive`; Space/Return on the button confirms (`ipc get` on the confirm error is gone). In `verify-installer-screens.sh`: a shot of Data disks with one card per choice, and of Review with two Erase rows (target + `ipc call installer setWipe /dev/nvme0n1`).
- [ ] **Step 2: Run, expect FAIL** (`bash cachyos/iso/test/verify-installer-focus.sh` from the host; it drives the VM only).
- [ ] **Step 3: Implement `DataDisks.qml`:** title sub "Mounted drives are left as they are. Wiped drives are erased when the install starts."; a card per `Installer.dataDrives` (header: `D.name` · size · `D.kindName(kind)` · path muted); a `Choice` with Leave alone / Mount (only when the drive has `dataRows`) / Wipe (absent when `busy`, replaced by the muted line "In use as <LVM|RAID|an open LUKS volume|swap|a mounted filesystem> here, can't be wiped"); Mount shows today's rows for that drive; Wipe shows the red warning, `Mount at` and `Label` Inputs wired to `setWipePath`/`setWipeLabel` via `edited`, and an **Erase this drive** `Button` (Return on it confirms, held repeats ignored, like Disk.qml).
- [ ] **Step 4: Implement `Review.qml`:** one `["Erase", name · size · path + "  →  " + folder, "data"]` row per wipe-on drive, after the target's Erase row.
- [ ] **Step 5: Run the VM checks, expect PASS;** look at the screenshots.
- [ ] **Step 6: Commit** `iso: Data disks shows a card per drive with Leave alone, Mount or Wipe, and Review names every drive to be erased`

---

### Task 7: Profile, VM disk, end-to-end and docs

**Files:**
- Modify: `cachyos/install/profile.sh` (`DATA_DISKS`)
- Modify: `cachyos/vm/provision-vm.sh` (third blank disk), `cachyos/vm/destroy-vm.sh` (remove it)
- Modify: `cachyos/iso/test/verify-install.sh`
- Modify: `cachyos/iso/README.md`, `cachyos/install/README.md`, `README.md` (Data disks screenshot), spec status
- Test: full ISO install in the VM

- [ ] **Step 1: `profile.sh`:** `77d7988e…:~/nvme2`, `5e62f799…:~/ssd1`, `ceb2ac52…:~/ssd2`; drop `55cefb4f…`; keep the test entry `~/testdata`. Update the comment above: defaults pre-tick Mount, never Wipe.
- [ ] **Step 2: VM:** `VM_WIPE_DISK_GB=4`, `--disk size=$VM_WIPE_DISK_GB,path=…/${VM_NAME}-wipe.qcow2`; destroy removes it.
- [ ] **Step 3: `verify-install.sh`:** `VERIFY_WIPE=<folder>:<label>` checks: exactly one partition on the disk mounted there, `ext4`, label matches, fstab line present with `nofail,x-systemd.automount`, mounts on access, `touch "$folder/.w" && rm` as the user works; `efibootmgr -v` has no `HD(…)` GUID absent from `lsblk -rno PARTUUID`; `BootOrder`'s first entry is on the installed ESP; with `VERIFY_DATA_MOUNT`, the test data disk's marker file is still there.
- [ ] **Step 4: Run end to end:** build the ISO, `cachyos/vm/destroy-vm.sh; cachyos/iso/bin/fledge-iso-boot`, install twice (the second run exercises stale NVRAM entries from the first): target `vda`, test data disk mounted, `vdc` wiped with the default `~/hdd1` / `hdd1`. Then `VERIFY_WIPE=~/hdd1:hdd1 VERIFY_DATA_MOUNT=~/testdata` per the ISO README. Expected: all checks pass.
- [ ] **Step 5: Docs:** ISO README (third disk, `VERIFY_WIPE`), install README (`DATA_WIPES` key), retake the Data disks README screenshot (recipe in the installer-followups notes), spec status → implemented.
- [ ] **Step 6: Commit** `install: name the profile's storage drives by kind; vm: a third disk to wipe; test: verify a wiped drive and pruned boot entries`
