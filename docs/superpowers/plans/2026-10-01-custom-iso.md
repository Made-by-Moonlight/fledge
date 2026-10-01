# made-by-moonlight Install ISO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Omarchy-style installer ISO: boots to a branded `gum` configurator on tty1 that asks everything up front, then runs `install-cachyos.sh` unattended and reboots into the existing firstboot → `bootstrap.sh` flow.

**Architecture:** `install-cachyos.sh` gains an `--answers FILE` mode (parsed by a new `lib/answers.sh`) so it can run with no prompts; the interactive path is unchanged. A live-ISO configurator (`mbm-configurator`, helpers in `cachyos/iso/lib/mbm.sh`) writes that answers file and hands over to `mbm-install`. The ISO is Arch's `releng` archiso profile, patched at build time (CachyOS repo, packages, titles, our `airootfs/` overlay, the repo baked in at `/usr/share/slievr-cachy`) and built with `mkarchiso` inside a privileged `archlinux/archlinux:latest` Docker container by `cachyos/iso/bin/slievr-iso-make`. Brand assets (console art, Plymouth logo, about screen) are generated from `cachyos/branding/owl.svg`.

**Tech Stack:** bash, `gum`, archiso/`mkarchiso`, Docker, Python 3 (stdlib only) + ImageMagick/librsvg for rendering, libvirt/QEMU for integration tests. Unit tests are plain bash assertion scripts, like the existing `cachyos/install/test-detect.sh`.

**Spec:** `docs/superpowers/specs/2026-10-01-custom-iso-design.md`

## Global Constraints

- Brand name is **"made by moonlight"** (lowercase). Never use "slievr" as a brand, title or wordmark. (`slievr` stays as the username, script prefix and repo name.)
- Palette, exact values: background `#171e28`, surface `#212a33`, lines `#2f3640`, text/mark `#ffffff`, accent `#f4af03`, muted `#6c7787`, error `#e5626a`, success `#8fcf8a`.
- **Kernel 7.2 or newer** (`MIN_KERNEL="7.2"` in `profile.sh`) for both the installed `linux-cachyos` and the ISO's live `linux`. Enforced: the installer refuses an older repo kernel (Task 2), the ISO build fails on an older live kernel (Task 6), and the VM check asserts `uname -r` (Task 7). Checked 2026-10-01: CachyOS `linux-cachyos` 7.2.7, Arch `core/linux` 7.2.7.
- Online install. No offline mirror, no cidata autoinstall, no signing/upload/CI.
- Live env: Arch stock `linux` kernel; generic `[cachyos]` repo only (above `[core]`). The installed system keeps `linux-cachyos`, and `chroot-setup.sh` still runs `cachyos-repo.sh` for v3/v4 repos.
- Username fixed to `profile.sh`'s `USERNAME` (`slievr`). Root is **locked** in answers mode (`ROOT_PASSWORD` empty → `passwd -l root`). Interactive mode keeps asking for a root password, as today.
- Passwords exist only in RAM: the answers file lives in `/run`, mode `600`, deleted as soon as it is read. Never print a password (dry-run output masks them).
- The disk-typed confirmation stays: the user types the disk **model**, or the kernel name (e.g. `vda`) when the model is empty.
- The ISO ships the repo's committed `HEAD` only; uncommitted work is excluded with a warning.
- `set -euo pipefail` in every new script (`set -uo pipefail` where a failure must be handled, not abort). `shellcheck` clean.
- The working tree has **unrelated uncommitted GPU changes** (`cachyos/bootstrap.sh`, `dot-config/hypr/hyprland.conf`, `dot-config/omarchy/scripts/nvidia-power.sh`, `dot-config/uwsm/`, `dot-local/share/slievr-cachy/bin/slievr-hw-display-gpu`). Never stage them: always `git add` explicit paths. Task 6's edits to `bootstrap.sh` don't exist; that file is only *read*.
- Docker is already installed and active on the build host (`docker 29.5.1`); the plan only checks for it.
- Some CachyOS/archiso details are **UNVERIFIED** and called out where used (CachyOS signing key ID, releng's boot-entry file names, `iwctl` output format). Verify them where the plan says so; adjust, don't block.

## File Structure

| File | Responsibility |
| --- | --- |
| `cachyos/install/test/lib.sh` (new) | shared `check`/`contains` assertions for bash test scripts |
| `cachyos/install/lib/detect.sh` | + `filter_fstab_entries`, + `disk_by_id` (pure, fixture-tested) |
| `cachyos/install/lib/answers.sh` (new) | `load_answers`: parse + validate + delete the answers file |
| `cachyos/install/install-cachyos.sh` | `--answers` mode; uses the new helpers |
| `cachyos/install/lib/disk.sh` | `luks_format_open` takes `LUKS_PASSPHRASE` when set |
| `cachyos/install/lib/chroot-setup.sh` | locks root when `ROOT_PASSWORD` is empty |
| `cachyos/install/test-answers.sh` (new) | tests for `answers.sh` |
| `cachyos/branding/palette.sh` (new) | brand colours + VT palette escapes |
| `cachyos/branding/render-console.py` (new) | SVG → half-block console art |
| `cachyos/branding/build-assets.sh` (new) | regenerates committed assets (about.txt, Plymouth logo) |
| `cachyos/branding/test-branding.sh` (new) | tests for the two above |
| `cachyos/plymouth-theme/slievr-cachy/*` | owl logo + brand background |
| `dot-config/omarchy/branding/about.txt` | owl console art (generated) |
| `cachyos/iso/lib/mbm.sh` (new) | configurator helpers: hostname check, answers writing/masking, online check |
| `cachyos/iso/test-mbm.sh` (new) | tests for `mbm.sh` |
| `cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator` (new) | the gum TUI |
| `cachyos/iso/configs/airootfs/usr/local/bin/mbm-install` (new) | runs the unattended install, logs, reboots or reports failure |
| `cachyos/iso/configs/airootfs/root/.automated_script.sh` (new) | tty1 entry: brand palette → configurator |
| `cachyos/iso/configs/packages.extra`, `pacman-cachyos.conf` (new) | live-env package additions; the `[cachyos]` section |
| `cachyos/iso/builder/build-iso.sh` (new) | in-container build: keyring, patch releng, overlay, bake, mkarchiso |
| `cachyos/iso/bin/slievr-iso-make` (new) | host: clone HEAD, run the container |
| `cachyos/iso/bin/slievr-iso-boot` (new) | host: boot an ISO in the test VM |
| `cachyos/iso/test/verify-install.sh` (new) | post-install checks run over SSH in the VM |
| `cachyos/vm/provision-vm.sh`, `cachyos/vm/host-deps.sh` | `ISO_PATH` override; Docker + gum host deps |
| `cachyos/iso/README.md` (new), `.gitignore`, spec | docs, ignores, spec deviations |

**Spec deviations** (recorded in the spec by Task 8):
1. Answers are *parsed* (`KEY=value`, whitelisted keys), not `source`d, so a value can never execute.
2. releng's `profiledef.sh`, `pacman.conf` and boot entries are **patched by `build-iso.sh`**, not vendored under `configs/`, so we track releng upstream instead of forking it.
3. Boot menu: retitled + a "safe graphics (nomodeset)" entry for UEFI (systemd-boot). No splash image in v1.
4. Disk confirmation falls back to the kernel name when the model is empty (virtio disks have no model).

---

### Task 1: Shared test helpers + `filter_fstab_entries`

**Files:**
- Create: `cachyos/install/test/lib.sh`
- Modify: `cachyos/install/test-detect.sh` (use the shared helpers; add cases)
- Modify: `cachyos/install/lib/detect.sh` (append `filter_fstab_entries`)
- Modify: `cachyos/install/install-cachyos.sh` (detection summary + fstab section)

**Interfaces:**
- Produces: `cachyos/install/test/lib.sh` defining `check <desc> <expected> <actual>`, `contains <desc> <needle> <haystack>`, global `fail` (0/1). Every test script ends with `exit $fail`.
- Produces: `filter_fstab_entries <present_uuids> <entry>...`. `present_uuids` is newline-separated (as `blkid -s UUID -o value` prints). Prints kept entries, one per line. Entries without a leading `UUID=` pass through. Exact UUID match only.

- [ ] **Step 1: Extract the assertion helpers**

Create `cachyos/install/test/lib.sh`:

```bash
# shellcheck shell=bash
# Assertions shared by the bash test scripts. Source it, run checks, then
# `exit $fail`.
fail=0
check() { # <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n        expected: [%s]\n        actual:   [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}
contains() { # <description> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n        [%s] not in [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}
```

In `cachyos/install/test-detect.sh`, replace the `fail=0` line and the two function definitions (`check() { ... }` and `contains() { ... }`) with:

```bash
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
```

- [ ] **Step 2: Run the existing tests (still green after the refactor)**

Run: `bash cachyos/install/test-detect.sh`
Expected: 18 `PASS` lines, exit 0.

- [ ] **Step 3: Write the failing tests**

Append to `cachyos/install/test-detect.sh`, just before `exit $fail`:

```bash
present=$'aaaa-1111\nbbbb-2222'
A="UUID=aaaa-1111 /a ext4 defaults,nofail 0 0"
B="UUID=bbbb-2222 /b ext4 defaults,nofail 0 0"
C="UUID=cccc-3333 /c ext4 defaults,nofail 0 0"
check "fstab filter keeps present"       "$A" "$(filter_fstab_entries "$present" "$A")"
check "fstab filter drops absent"        ""   "$(filter_fstab_entries "$present" "$C")"
check "fstab filter mixed keeps order"   "$A"$'\n'"$B" "$(filter_fstab_entries "$present" "$A" "$C" "$B")"
check "fstab filter no entries"          ""   "$(filter_fstab_entries "$present")"
check "fstab filter non-UUID passes"     "/dev/sdz1 /z ext4 defaults 0 0" \
  "$(filter_fstab_entries "" "/dev/sdz1 /z ext4 defaults 0 0")"
check "fstab filter exact match only"    ""   "$(filter_fstab_entries "aaaa-11112" "$A")"
```

- [ ] **Step 4: Run to see them fail**

Run: `bash cachyos/install/test-detect.sh`
Expected: the six new checks FAIL (`filter_fstab_entries: command not found`), exit 1.

- [ ] **Step 5: Implement**

Append to `cachyos/install/lib/detect.sh`:

```bash
# filter_fstab_entries <present_uuids> <entry>...  ->  the entries whose
# UUID= source is in present_uuids (newline-separated, as printed by
# `blkid -s UUID -o value`), one per line, in order. Entries that don't start
# with UUID= pass through. Lets one profile.sh list every machine's data disks.
filter_fstab_entries() {
  local present="$1" entry; shift
  for entry in "$@"; do
    if [[ "$entry" =~ ^UUID=([^[:space:]]+) ]]; then
      grep -qxF -- "${BASH_REMATCH[1]}" <<<"$present" || continue
    fi
    printf '%s\n' "$entry"
  done
}
```

- [ ] **Step 6: Run to see them pass**

Run: `bash cachyos/install/test-detect.sh`
Expected: 24 `PASS`, exit 0.

- [ ] **Step 7: Use it in the installer**

In `cachyos/install/install-cachyos.sh`, in the "Hardware detection" section, after the `SWAPFILE_SIZE` block and before the `cat <<EOF` summary, add:

```bash
mapfile -t KEEP_FSTAB < <(filter_fstab_entries "$(blkid -s UUID -o value)" "${EXTRA_FSTAB_ENTRIES[@]}")
```

Add this line to the summary heredoc, after the `hostname` line:

```
  data disks     : ${#KEEP_FSTAB[@]} of ${#EXTRA_FSTAB_ENTRIES[@]} fstab entries present on this machine
```

In the "fstab" section, replace

```bash
for e in "${EXTRA_FSTAB_ENTRIES[@]}"; do
```

with

```bash
for e in "${KEEP_FSTAB[@]}"; do
```

- [ ] **Step 8: Lint and commit**

Run: `shellcheck cachyos/install/install-cachyos.sh cachyos/install/lib/detect.sh cachyos/install/test-detect.sh cachyos/install/test/lib.sh && bash cachyos/install/test-detect.sh`
Expected: no shellcheck output; tests pass.

```bash
git add cachyos/install/test/lib.sh cachyos/install/test-detect.sh cachyos/install/lib/detect.sh cachyos/install/install-cachyos.sh
git commit -m "install: only write data-disk fstab entries whose UUID is present"
```

---

### Task 2: Unattended `--answers` mode

**Files:**
- Create: `cachyos/install/lib/answers.sh`, `cachyos/install/test-answers.sh`
- Modify: `cachyos/install/lib/detect.sh` (append `disk_by_id`), `cachyos/install/test-detect.sh`
- Modify: `cachyos/install/install-cachyos.sh`, `cachyos/install/lib/disk.sh`, `cachyos/install/lib/chroot-setup.sh`, `cachyos/install/profile.sh` (`MIN_KERNEL`)

**Interfaces:**
- Consumes: `test/lib.sh` (Task 1).
- Produces: `load_answers <file>`. Requires mode `600`/`400`. Accepts lines `KEY=value` (value = everything after the first `=`, unquoted), blank lines, and `#` comments. Allowed keys: `DISK DISK_CONFIRMED HOSTNAME TIMEZONE USER_PASSWORD LUKS_PASSPHRASE ROOT_PASSWORD`. Sets them as globals and deletes the file. Returns 1, never echoing a value, on a missing file, wrong mode, malformed line or unknown key; the file is left in place.
- Produces: `disk_by_id <kname> [byid_dir]`. Prints the `/dev/disk/by-id` link for a whole disk (never `-part*`, `wwn-*` or `*eui.*`), or `kname` itself when there is none.
- Produces: `install-cachyos.sh [--allow-usb] [--answers FILE]`. In answers mode `DISK`, `HOSTNAME`, `USER_PASSWORD` and `LUKS_PASSPHRASE` are required; `DISK_CONFIRMED=yes` skips the typed confirmations; `ROOT_PASSWORD` empty → root locked; no reboot prompt at the end.

- [ ] **Step 1: Failing tests for `disk_by_id`**

Append to `cachyos/install/test-detect.sh` before `exit $fail`:

```bash
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/dev" "$T/by-id"
: > "$T/dev/nvme0n1"; : > "$T/dev/nvme0n1p1"; : > "$T/dev/vda"
ln -s ../dev/nvme0n1   "$T/by-id/wwn-0x5000000000000001"
ln -s ../dev/nvme0n1   "$T/by-id/nvme-eui.0025385a01234567"
ln -s ../dev/nvme0n1p1 "$T/by-id/nvme-Samsung_SSD_990_PRO_2TB_S123-part1"
ln -s ../dev/nvme0n1   "$T/by-id/nvme-Samsung_SSD_990_PRO_2TB_S123"
check "disk_by_id picks the model link" "$T/by-id/nvme-Samsung_SSD_990_PRO_2TB_S123" \
  "$(disk_by_id "$T/dev/nvme0n1" "$T/by-id")"
check "disk_by_id falls back to kname"  "$T/dev/vda" "$(disk_by_id "$T/dev/vda" "$T/by-id")"
```

Run: `bash cachyos/install/test-detect.sh`
Expected: the two new checks FAIL (`disk_by_id: command not found`).

- [ ] **Step 2: Implement `disk_by_id`**

Append to `cachyos/install/lib/detect.sh`:

```bash
# disk_by_id <kname> [byid_dir]  ->  stable by-id path for a whole disk, or
# kname when there is none (e.g. virtio). Skips -partN, wwn-* and eui links,
# which are either partitions or opaque.
disk_by_id() {
  local kname="$1" dir="${2:-/dev/disk/by-id}" link want
  want="$(realpath "$kname")"
  for link in "$dir"/*; do
    [[ -e "$link" ]] || continue
    [[ "$link" == *-part* ]] && continue
    case "${link##*/}" in wwn-*|*eui.*) continue ;; esac
    if [[ "$(realpath "$link")" == "$want" ]]; then
      echo "$link"; return 0
    fi
  done
  echo "$kname"
}
```

Run: `bash cachyos/install/test-detect.sh`
Expected: 26 `PASS`, exit 0.

- [ ] **Step 3: Failing tests for `load_answers`**

Create `cachyos/install/test-answers.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for lib/answers.sh. No VM.
#   bash cachyos/install/test-answers.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/answers.sh
source "$DIR/lib/answers.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mk() { # <name> <mode> <content>
  printf '%s' "$3" > "$T/$1"; chmod "$2" "$T/$1"; echo "$T/$1"
}

f="$(mk ok 600 $'# written by mbm-configurator\nDISK=/dev/disk/by-id/nvme-X\nDISK_CONFIRMED=yes\n\nHOSTNAME=glaux\nUSER_PASSWORD=pa=ss word\nLUKS_PASSPHRASE=luks\n')"
out="$( load_answers "$f" && printf '%s|%s|%s|%s|%s' "$DISK" "$DISK_CONFIRMED" "$HOSTNAME" "$USER_PASSWORD" "$LUKS_PASSPHRASE" )"
check "answers: loads keys, keeps '=' and spaces in values" \
  "/dev/disk/by-id/nvme-X|yes|glaux|pa=ss word|luks" "$out"
check "answers: file deleted after load" "gone" "$([[ -e "$f" ]] && echo present || echo gone)"

f="$(mk unknown 600 $'DISK=/dev/x\nEVIL=1\n')"
check "answers: unknown key rejected" "1" "$( load_answers "$f" 2>/dev/null; echo $? )"
check "answers: rejected file kept"   "present" "$([[ -e "$f" ]] && echo present || echo gone)"

f="$(mk loose 644 $'DISK=/dev/x\n')"
check "answers: world-readable file rejected" "1" "$( load_answers "$f" 2>/dev/null; echo $? )"

f="$(mk bad 600 $'USER_PASSWORD secret\n')"
err="$( load_answers "$f" 2>&1 )"; rc=$?
check "answers: malformed line rejected" "1" "$rc"
check "answers: errors never echo values" "" "$(grep -o 'secret' <<<"$err")"

check "answers: missing file rejected" "1" "$( load_answers "$T/nope" 2>/dev/null; echo $? )"

exit $fail
```

Run: `bash cachyos/install/test-answers.sh`
Expected: FAIL. The `source` of the missing `lib/answers.sh` errors, so the checks fail.

- [ ] **Step 4: Implement `answers.sh`**

Create `cachyos/install/lib/answers.sh`:

```bash
# shellcheck shell=bash
# Unattended-install answers. The ISO configurator (mbm-configurator) writes a
# root-only file under /run with one KEY=value per line (value = everything
# after the first '=', unquoted). It is parsed, never sourced, so a value can
# never run as code.

ANSWER_KEYS=(DISK DISK_CONFIRMED HOSTNAME TIMEZONE USER_PASSWORD LUKS_PASSPHRASE ROOT_PASSWORD)

# load_answers <file>  ->  sets the ANSWER_KEYS globals present in the file,
# then deletes it. Returns 1 (file kept) on any problem. Never echoes a value.
load_answers() {
  local file="$1" line key value mode n=0
  [[ -f "$file" ]] || { echo "answers: file not found: $file" >&2; return 1; }
  mode="$(stat -c '%a' "$file")"
  [[ "$mode" == 600 || "$mode" == 400 ]] \
    || { echo "answers: $file must be mode 600 (is $mode)" >&2; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || { echo "answers: line $n is not KEY=value" >&2; return 1; }
    key="${line%%=*}"; value="${line#*=}"
    if [[ " ${ANSWER_KEYS[*]} " != *" $key "* ]]; then
      echo "answers: unknown key on line $n" >&2; return 1
    fi
    printf -v "$key" '%s' "$value"
  done < "$file"
  rm -f -- "$file"
}
```

Run: `bash cachyos/install/test-answers.sh`
Expected: 8 `PASS`, exit 0.

- [ ] **Step 5: `disk.sh` takes the LUKS passphrase from the answers**

In `cachyos/install/lib/disk.sh`, replace the start of `luks_format_open`:

```bash
# luks_format_open <luks_part>   (reads passphrase on stdin, twice)
luks_format_open() {
  local part="$1" p1 p2
  read -rsp "LUKS passphrase: " p1; echo >&2
  read -rsp "Confirm passphrase: " p2; echo >&2
  [[ "$p1" == "$p2" && -n "$p1" ]] || { echo "passphrases differ or empty" >&2; return 1; }
```

with:

```bash
# luks_format_open <luks_part>   (LUKS_PASSPHRASE if set, else prompts twice)
luks_format_open() {
  local part="$1" p1 p2
  if [[ -n "${LUKS_PASSPHRASE:-}" ]]; then
    p1="$LUKS_PASSPHRASE"
  else
    read -rsp "LUKS passphrase: " p1; echo >&2
    read -rsp "Confirm passphrase: " p2; echo >&2
    [[ "$p1" == "$p2" && -n "$p1" ]] || { echo "passphrases differ or empty" >&2; return 1; }
  fi
```

Also update the header comment line `# Consumes from profile.sh:` block by adding:

```bash
# Consumes (optional):      LUKS_PASSPHRASE (unattended install)
```

- [ ] **Step 6: `chroot-setup.sh` locks root when no password is given**

In `cachyos/install/lib/chroot-setup.sh`, replace:

```bash
printf 'root:%s\n' "${ROOT_PASSWORD}" | chpasswd
```

with:

```bash
if [[ -n "${ROOT_PASSWORD:-}" ]]; then
  printf 'root:%s\n' "${ROOT_PASSWORD}" | chpasswd
else
  passwd -l root            # unattended (ISO) install: no root login, sudo via wheel
fi
```

- [ ] **Step 7: `install-cachyos.sh` answers mode**

Edit `cachyos/install/install-cachyos.sh`:

(a) Update the usage line in the header comment:

```bash
#   sudo /path/to/cachyos/install/install-cachyos.sh [--allow-usb] [--answers FILE]
```

(b) Add `answers.sh` next to the other `source` lines:

```bash
# shellcheck source=lib/answers.sh
source "$HERE/lib/answers.sh"
```

(c) Replace

```bash
ALLOW_USB=0
[[ "${1:-}" == "--allow-usb" ]] && ALLOW_USB=1

die()  { printf '\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
```

with

```bash
die()  { printf '\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }

ALLOW_USB=0
ANSWERS=""
while (( $# )); do
  case "$1" in
    --allow-usb) ALLOW_USB=1 ;;
    --answers)   ANSWERS="${2:?--answers needs a file}"; shift ;;
    *)           die "unknown argument: $1" ;;
  esac
  shift
done
if [[ -n "$ANSWERS" ]]; then
  load_answers "$ANSWERS" || die "unusable answers file: $ANSWERS"
  for k in DISK HOSTNAME USER_PASSWORD LUKS_PASSPHRASE; do
    [[ -n "${!k:-}" ]] || die "answers file is missing $k"
  done
  ROOT_PASSWORD="${ROOT_PASSWORD:-}"     # empty -> root locked (chroot-setup.sh)
fi
```

Keep `warn()` and `rule()` right after `die()` as they are.

(d) In the "Target disk" section, replace everything from `mapfile -t DISKS < <(list_disks)` down to and including the by-id loop's closing `[[ -n "$DISK" ]] || DISK="$DISK_KNAME"` with:

```bash
if [[ -n "${DISK:-}" ]]; then
  [[ -b "$DISK" ]] || die "answers DISK is not a block device: $DISK"
  DISK_KNAME="$(realpath "$DISK")"
  DISK_TRAN="$(lsblk -dno TRAN "$DISK_KNAME")"
else
  mapfile -t DISKS < <(list_disks)
  (( ${#DISKS[@]} > 0 )) || die "no candidate disks found"

  echo "Candidate disks:"
  i=0
  for d in "${DISKS[@]}"; do
    printf '  [%d] %s\n' "$i" "$d"
    i=$(( i + 1 ))
  done
  read -rp "Select target disk number (its ENTIRE contents will be destroyed): " idx
  [[ "$idx" =~ ^[0-9]+$ && "$idx" -lt "${#DISKS[@]}" ]] || die "invalid selection"

  DISK_KNAME="$(awk '{print $1}' <<<"${DISKS[$idx]}")"           # /dev/nvme1n1
  DISK_TRAN="$(awk '{print $NF}' <<<"${DISKS[$idx]}")"           # nvme|sata|usb|...
  DISK="$(disk_by_id "$DISK_KNAME")"
fi
DISK_MODEL="$(lsblk -dno MODEL "$DISK_KNAME" | sed 's/[[:space:]]*$//')"
```

(e) Wrap the two confirmation prompts:

```bash
read -rp "Type the disk MODEL exactly to confirm [${DISK_MODEL}]: " typed
[[ "$typed" == "$DISK_MODEL" ]] || die "model string did not match - aborting"
read -rp "Last chance. Type YES to DESTROY $DISK_KNAME: " last
[[ "$last" == "YES" ]] || die "aborted"
```

becomes:

```bash
if [[ "${DISK_CONFIRMED:-}" != yes ]]; then
  read -rp "Type the disk MODEL exactly to confirm [${DISK_MODEL}]: " typed
  [[ "$typed" == "$DISK_MODEL" ]] || die "model string did not match - aborting"
  read -rp "Last chance. Type YES to DESTROY $DISK_KNAME: " last
  [[ "$last" == "YES" ]] || die "aborted"
fi
```

(f) In the "Passphrases" section, wrap the four `read -rsp` lines and their two checks:

```bash
if [[ -z "$ANSWERS" ]]; then
  read -rsp "New user (${USERNAME}) password: " USER_PASSWORD; echo
  read -rsp "Confirm user password: "                p2;      echo
  [[ "$USER_PASSWORD" == "$p2" && -n "$USER_PASSWORD" ]] || die "user passwords differ/empty"
  read -rsp "New root password: " ROOT_PASSWORD; echo
  read -rsp "Confirm root password: " p2;        echo
  [[ "$ROOT_PASSWORD" == "$p2" && -n "$ROOT_PASSWORD" ]] || die "root passwords differ/empty"
fi
```

and change the `luks_format_open` call's comment to `# LUKS_PASSPHRASE from answers, else prompts x2`.

(g) At the very end, replace

```bash
read -rp "Reboot now? [y/N] " r
[[ "$r" == [yY] ]] && reboot
```

with

```bash
if [[ -z "$ANSWERS" ]]; then
  read -rp "Reboot now? [y/N] " r
  [[ "$r" == [yY] ]] && reboot
fi
```

(mbm-install does the reboot in answers mode.)

- [ ] **Step 8: Refuse a kernel older than 7.2**

In `cachyos/install/profile.sh`, after `KERNEL="linux-cachyos"`, add:

```bash
MIN_KERNEL="7.2"                  # refuse to install an older $KERNEL (hardware needs 7.2+)
```

In `cachyos/install/install-cachyos.sh`, at the end of the "Preflight" section (after the `ping` warning), add:

```bash
pacman -Sy --noconfirm >/dev/null || die "couldn't sync package databases"
KERNEL_VER="$(pacman -Si "$KERNEL" 2>/dev/null | awk '/^Version/ {print $3; exit}')"
[[ -n "$KERNEL_VER" ]] || die "$KERNEL is not in the configured repos"
(( $(vercmp "$KERNEL_VER" "$MIN_KERNEL") >= 0 )) \
  || die "$KERNEL $KERNEL_VER is older than the required $MIN_KERNEL"
```

and add `  kernel         : ${KERNEL} ${KERNEL_VER} (minimum ${MIN_KERNEL})` as the first line of the detection summary heredoc.

Check `vercmp`'s behaviour on the host (it ships with pacman):
Run: `vercmp 7.2.7-1 7.2; vercmp 7.1.9.arch1-2 7.2; vercmp 7.2 7.2`
Expected: `1`, `-1`, `0`.

- [ ] **Step 9: Lint, run all unit tests, commit**

Run: `shellcheck cachyos/install/*.sh cachyos/install/lib/*.sh cachyos/install/test/lib.sh && bash cachyos/install/test-detect.sh && bash cachyos/install/test-answers.sh`
Expected: no shellcheck output; both suites pass.

```bash
git add cachyos/install/lib/answers.sh cachyos/install/test-answers.sh cachyos/install/lib/detect.sh \
  cachyos/install/test-detect.sh cachyos/install/install-cachyos.sh cachyos/install/lib/disk.sh \
  cachyos/install/lib/chroot-setup.sh cachyos/install/profile.sh
git commit -m "install: unattended --answers mode; root locked when no root password; kernel >= 7.2"
```

- [ ] **Step 10: Prove answers mode in the VM from the stock ISO (spec testing step 3)**

This uses the existing VM loop (`cachyos/vm/README.md`, `cachyos/install/README.md`): `cachyos/vm/destroy-vm.sh` if a VM exists, then `cachyos/vm/provision-vm.sh`, and stage this commit's repo on the VM's data disk as the READMEs describe. In the live env, as root:

```bash
install -m 600 /dev/null /run/a.env
cat > /run/a.env <<'EOF'
DISK=/dev/vda
DISK_CONFIRMED=yes
HOSTNAME=answers-test
USER_PASSWORD=TestPass1
LUKS_PASSPHRASE=TestPass1
EOF
/mnt-repo/slievr-cachy/cachyos/install/install-cachyos.sh --answers /run/a.env
```

Expected: it runs to "Install complete." with **no prompts**, `/run/a.env` no longer exists, and there's no reboot prompt. Then `reboot`, unlock with `TestPass1`, wait for firstboot, and check over SSH (or the console) as `slievr`:

```bash
sudo passwd -S root | awk '{print $2}'      # expect: L
grep -c 'Bootstrap complete.' /var/log/slievr-firstboot.log   # expect: 1
```

Record the result in the task's review notes. If the stock-ISO live env lacks something answers mode needs, fix it in this task.

---

### Task 3: Brand assets (palette, console renderer, Plymouth, about screen)

**Files:**
- Create: `cachyos/branding/palette.sh`, `cachyos/branding/render-console.py`, `cachyos/branding/build-assets.sh`, `cachyos/branding/test-branding.sh`, `cachyos/branding/README.md`
- Modify (generated): `dot-config/omarchy/branding/about.txt`, `cachyos/plymouth-theme/slievr-cachy/logo.png`
- Modify: `cachyos/plymouth-theme/slievr-cachy/slievr-cachy.script` (lines 3–4), `cachyos/plymouth-theme/slievr-cachy/slievr-cachy.plymouth`, `cachyos/plymouth-theme/README.md`

**Interfaces:**
- Consumes: `cachyos/branding/owl.svg` (committed; `viewBox="0 0 1670 1094"`, `fill="currentColor"`), `test/lib.sh`.
- Produces: `palette.sh` defining `MBM_BG MBM_SURFACE MBM_LINE MBM_FG MBM_ACCENT MBM_MUTED MBM_ERROR MBM_OK`, the array `MBM_VT_PALETTE` (16 hex colours, index = ANSI colour number), and `mbm_vt_palette`, which prints the Linux-console `\e]P<hex index><rrggbb>` escapes. ANSI slot meanings used by later tasks: **0** background, **1** error, **2** success, **3** accent, **7** text, **8** muted, **15** mark.
- Produces: `render-console.py <svg> [--cols N] [--ansi] [--sgr CODE]`, which prints block art (`' ▀▄█'`), no trailing spaces and no leading or trailing blank lines. Rows = `round(cols * h / w / 2)` before trimming. `--ansi` wraps each line in `\e[<sgr>m … \e[0m` (default `97` = slot 15).

- [ ] **Step 1: Failing tests**

Create `cachyos/branding/test-branding.sh`:

```bash
#!/usr/bin/env bash
# Tests for the brand palette and console renderer. Needs python3 + magick.
#   bash cachyos/branding/test-branding.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
# shellcheck source=SCRIPTDIR/palette.sh
source "$DIR/palette.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R=(python3 "$DIR/render-console.py")

# palette
check "palette has 16 VT slots" "16" "${#MBM_VT_PALETTE[@]}"
esc="$(mbm_vt_palette)"
contains "VT slot 0 is the background" $'\e]P0171e28' "$esc"
contains "VT slot 3 is the accent"     $'\e]P3f4af03' "$esc"
contains "VT slot 15 is the mark"      $'\e]PFffffff' "$esc"

# renderer: a fully filled square -> 4 cols x 2 rows of full blocks
cat > "$T/full.svg" <<'EOF'
<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" fill="currentColor"/></svg>
EOF
check "full square renders as full blocks" $'████\n████' "$("${R[@]}" "$T/full.svg" --cols 4)"

# top quarter only -> one row of upper half blocks; trailing blank rows trimmed
cat > "$T/top.svg" <<'EOF'
<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><rect width="10" height="2.5" fill="currentColor"/></svg>
EOF
check "top quarter renders as upper halves" "▀▀▀▀" "$("${R[@]}" "$T/top.svg" --cols 4)"

check "--ansi wraps lines in the SGR colour" $'\e[97m████\e[0m\n\e[97m████\e[0m' \
  "$("${R[@]}" "$T/full.svg" --cols 4 --ansi)"

# the real mark
owl="$("${R[@]}" "$DIR/owl.svg" --cols 48)"
check "owl fits 48 columns" "yes" "$(awk 'length > 48 {bad=1} END {print bad ? "no" : "yes"}' <<<"$owl")"
check "owl uses only block characters" "" "$(tr -d ' ▀▄█\n' <<<"$owl")"
contains "owl has solid areas" "█" "$owl"

exit $fail
```

Run: `bash cachyos/branding/test-branding.sh`
Expected: FAIL. `palette.sh` and `render-console.py` don't exist yet.

- [ ] **Step 2: Implement `palette.sh`**

```bash
# shellcheck shell=bash
# made by moonlight brand palette. Hex values for graphics; MBM_VT_PALETTE maps
# ANSI colour numbers (what gum and \e[3Xm use on the Linux console) to brand
# colours. The live ISO loads it with mbm_vt_palette.
# shellcheck disable=SC2034  # consumed by scripts that source this file
MBM_BG="#171e28"
MBM_SURFACE="#212a33"
MBM_LINE="#2f3640"
MBM_FG="#ffffff"
MBM_ACCENT="#f4af03"
MBM_MUTED="#6c7787"
MBM_ERROR="#e5626a"
MBM_OK="#8fcf8a"

MBM_VT_PALETTE=(
  "$MBM_BG"      # 0  background
  "$MBM_ERROR"   # 1  error
  "$MBM_OK"      # 2  success
  "$MBM_ACCENT"  # 3  accent (selection, buttons)
  "$MBM_LINE"    # 4  lines
  "$MBM_ACCENT"  # 5
  "$MBM_MUTED"   # 6
  "$MBM_FG"      # 7  text
  "$MBM_MUTED"   # 8  muted hints
  "$MBM_ERROR"   # 9
  "$MBM_OK"      # 10
  "$MBM_ACCENT"  # 11
  "$MBM_SURFACE" # 12 surface
  "$MBM_ACCENT"  # 13
  "$MBM_MUTED"   # 14
  "$MBM_FG"      # 15 the mark
)

# mbm_vt_palette  ->  escapes that load MBM_VT_PALETTE into the Linux console
mbm_vt_palette() {
  local i
  for i in "${!MBM_VT_PALETTE[@]}"; do
    printf '\e]P%X%s' "$i" "${MBM_VT_PALETTE[$i]#\#}"
  done
}
```

- [ ] **Step 3: Implement `render-console.py`**

```python
#!/usr/bin/env python3
"""Render an SVG mark as Linux-console block art.

Each character cell shows two stacked pixels, so the mark is rasterised at
COLS x (2 * rows) and each pixel pair becomes ' ', '▀', '▄' or '█'. The
console draws these in one foreground colour, so the art works with the
16-colour VT palette. Needs ImageMagick (`magick`) with SVG support.

  render-console.py owl.svg --cols 48 --ansi > owl.ansi
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

CELLS = " ▀▄█"   # index = top + 2 * bottom


def raster(svg_path: str, cols: int) -> list[list[bool]]:
    svg = Path(svg_path).read_text().replace("currentColor", "#000000")
    m = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg)
    if not m:
        sys.exit(f"render-console: {svg_path} has no viewBox")
    w, h = float(m.group(1)), float(m.group(2))
    rows = max(1, round(cols * h / w / 2))
    px_h = rows * 2
    raw = subprocess.run(
        ["magick", "-background", "none", "-density", "600", "svg:-",
         "-resize", f"{cols}x{px_h}!", "-alpha", "extract", "-depth", "8", "gray:-"],
        input=svg.encode(), capture_output=True, check=True).stdout
    if len(raw) != cols * px_h:
        sys.exit(f"render-console: expected {cols * px_h} pixels, got {len(raw)}")
    return [[raw[y * cols + x] >= 128 for x in range(cols)] for y in range(px_h)]


def blocks(px: list[list[bool]]) -> list[str]:
    lines = []
    for top, bottom in zip(px[0::2], px[1::2]):
        lines.append("".join(CELLS[t + 2 * b] for t, b in zip(top, bottom)).rstrip())
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return lines


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("svg")
    ap.add_argument("--cols", type=int, default=48)
    ap.add_argument("--ansi", action="store_true", help="wrap lines in an SGR colour")
    ap.add_argument("--sgr", default="97", help="SGR colour code for --ansi (default 97 = slot 15)")
    a = ap.parse_args()
    lines = blocks(raster(a.svg, a.cols))
    if a.ansi:
        lines = [f"\x1b[{a.sgr}m{line}\x1b[0m" if line else line for line in lines]
    print("\n".join(lines))


if __name__ == "__main__":
    main()
```

Run: `chmod +x cachyos/branding/render-console.py && bash cachyos/branding/test-branding.sh`
Expected: 10 `PASS`, exit 0. If the `top quarter` case renders `▀▀▀▀` plus an extra row because of antialiasing at the edge, check the raw alpha values with `magick ... gray:- | xxd`. The 128 threshold should hold for an edge on an exact pixel boundary (2.5/10 × 4 px = 1 px).

- [ ] **Step 4: `build-assets.sh` and the generated assets**

Create `cachyos/branding/build-assets.sh`:

```bash
#!/usr/bin/env bash
# Regenerate the committed brand assets from owl.svg. Run after changing the
# mark, then commit the results.
#   cachyos/branding/build-assets.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SVG="$HERE/owl.svg"

# About screen (slievr-launch-about): plain block art, 54 columns wide.
python3 "$HERE/render-console.py" "$SVG" --cols 54 > "$REPO/dot-config/omarchy/branding/about.txt"

# Plymouth logo: the mark in white on transparent, 320 px wide.
sed 's/currentColor/#ffffff/g' "$SVG" \
  | rsvg-convert -w 320 -o "$REPO/cachyos/plymouth-theme/slievr-cachy/logo.png"

echo "updated dot-config/omarchy/branding/about.txt and cachyos/plymouth-theme/slievr-cachy/logo.png"
```

Append to `test-branding.sh`, before `exit $fail`:

```bash
# generated assets are current
bash "$DIR/build-assets.sh" >/dev/null
repo="$(cd "$DIR/../.." && pwd)"
check "about.txt is the owl at 54 cols" "$("${R[@]}" "$DIR/owl.svg" --cols 54)" \
  "$(cat "$repo/dot-config/omarchy/branding/about.txt")"
check "plymouth logo is 320px wide" "320" \
  "$(magick identify -format '%w' "$repo/cachyos/plymouth-theme/slievr-cachy/logo.png")"
```

Run: `chmod +x cachyos/branding/build-assets.sh && bash cachyos/branding/test-branding.sh`
Expected: 12 `PASS`.
Then look at the result: `cat dot-config/omarchy/branding/about.txt` should show the owl (brow, beak, two eyes); `xdg-open cachyos/plymouth-theme/slievr-cachy/logo.png` should show the white owl.

- [ ] **Step 5: Plymouth background to the brand colour**

In `cachyos/plymouth-theme/slievr-cachy/slievr-cachy.script`, replace lines 3–4:

```
Window.SetBackgroundTopColor(0.101, 0.105, 0.149);
Window.SetBackgroundBottomColor(0.101, 0.105, 0.149);
```

with (`#171e28` = 23/30/40 ÷ 255):

```
Window.SetBackgroundTopColor(0.090, 0.118, 0.157);
Window.SetBackgroundBottomColor(0.090, 0.118, 0.157);
```

In `slievr-cachy.plymouth`: `Description=made by moonlight boot splash (adapted from Omarchy's).` and `ConsoleLogBackgroundColor=0x171e28`.

In `cachyos/plymouth-theme/README.md`, replace the sentences starting at "`logo.png` (and `logos/oma.png`) are still Omarchy's mark" with:

```
`logo.png` is the made by moonlight owl, generated from
`cachyos/branding/owl.svg` by `cachyos/branding/build-assets.sh`; the
background is the brand `#171e28`. (`logos/oma.png` is unused by the script.)
```

- [ ] **Step 6: Branding README**

Create `cachyos/branding/README.md`:

```markdown
# cachyos/branding/

made by moonlight brand source files.

| File | What |
| --- | --- |
| `owl.svg` | The mark: the owner's brow-and-beak owl logo, traced with potrace (brow + beak + both eyes; right eye rebuilt as a ring cut off by the brow). `fill="currentColor"`. |
| `palette.sh` | Brand colours and the 16-slot Linux-console palette (`mbm_vt_palette`). |
| `render-console.py` | SVG → console block art (`▀▄█`). |
| `build-assets.sh` | Regenerates committed assets: `dot-config/omarchy/branding/about.txt` and the Plymouth `logo.png`. |
| `test-branding.sh` | Tests for the above. |

The ISO build renders `owl.ansi` itself (`cachyos/iso/builder/build-iso.sh`).
Changing the mark: replace `owl.svg`, run `build-assets.sh`, commit.
```

- [ ] **Step 7: Lint and commit**

Run: `shellcheck cachyos/branding/*.sh && python3 -m py_compile cachyos/branding/render-console.py && bash cachyos/branding/test-branding.sh`
Expected: clean; 12 `PASS`.

```bash
git add cachyos/branding/ dot-config/omarchy/branding/about.txt cachyos/plymouth-theme/
git commit -m "branding: made by moonlight palette, console renderer, owl Plymouth logo + about screen"
```

---

### Task 4: Configurator (`mbm-configurator` + `mbm.sh`)

**Files:**
- Create: `cachyos/iso/lib/mbm.sh`, `cachyos/iso/test-mbm.sh`
- Create: `cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator`
- Modify: `cachyos/vm/host-deps.sh` (add `gum`, so dry-runs work on the host)

**Interfaces:**
- Consumes: `profile.sh` (`USERNAME TIMEZONE EXTRA_FSTAB_ENTRIES`); `detect.sh` (`list_disks detect_ucode detect_gpu_pkgs zram_size filter_fstab_entries disk_by_id`); `palette.sh` slot meanings (Task 3); `render-console.py` for the dry-run owl; the answers keys from Task 2.
- Produces: `mbm.sh` with `valid_hostname <name>` (0/1), `write_answers <file> KEY=value...` (creates a mode-600 file; fails and removes it on a newline in any argument), `mask_answers <file>` (prints with `USER_PASSWORD`, `LUKS_PASSPHRASE`, `ROOT_PASSWORD` values replaced by `********`), and `mbm_online` (0 if `https://mirror.cachyos.org` answers within 5 s).
- Produces: `mbm-configurator [--dry-run]`. Env: `MBM_REPO` (default `/usr/share/slievr-cachy`), `MBM_ANSWERS` (default `/run/mbm-answers.env`), `MBM_OWL` (default `/usr/share/mbm/owl.ansi`). It ends with `exec mbm-install "$MBM_ANSWERS"`, or with dry-run, prints the masked answers. Exits 130 when the user picks "Shell" or presses Ctrl-C.

- [ ] **Step 1: Failing tests for `mbm.sh`**

Create `cachyos/iso/test-mbm.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for cachyos/iso/lib/mbm.sh. No ISO, no network.
#   bash cachyos/iso/test-mbm.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/mbm.sh
source "$DIR/lib/mbm.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

ok()  { "$@" && echo yes || echo no; }
check "hostname: simple"            yes "$(ok valid_hostname glaux)"
check "hostname: digits and dash"   yes "$(ok valid_hostname ninox-2)"
check "hostname: uppercase rejected" no "$(ok valid_hostname Glaux)"
check "hostname: leading dash"       no "$(ok valid_hostname -glaux)"
check "hostname: trailing dash"      no "$(ok valid_hostname glaux-)"
check "hostname: dot rejected"       no "$(ok valid_hostname glaux.local)"
check "hostname: empty rejected"     no "$(ok valid_hostname '')"
check "hostname: 63 chars ok"       yes "$(ok valid_hostname "$(printf 'a%.0s' {1..63})")"
check "hostname: 64 chars rejected"  no "$(ok valid_hostname "$(printf 'a%.0s' {1..64})")"

write_answers "$T/a.env" "DISK=/dev/disk/by-id/nvme-X" "USER_PASSWORD=s3cret pass" "LUKS_PASSPHRASE=luks=pw"
check "answers: mode 600" "600" "$(stat -c '%a' "$T/a.env")"
check "answers: one KEY=value per line" \
  $'DISK=/dev/disk/by-id/nvme-X\nUSER_PASSWORD=s3cret pass\nLUKS_PASSPHRASE=luks=pw' "$(cat "$T/a.env")"
check "answers: masked for display" \
  $'DISK=/dev/disk/by-id/nvme-X\nUSER_PASSWORD=********\nLUKS_PASSPHRASE=********' "$(mask_answers "$T/a.env")"

check "answers: newline refused" "1" "$(write_answers "$T/b.env" $'USER_PASSWORD=a\nDISK=/dev/sda' 2>/dev/null; echo $?)"
check "answers: refused file removed" "gone" "$([[ -e "$T/b.env" ]] && echo present || echo gone)"

exit $fail
```

Run: `bash cachyos/iso/test-mbm.sh`
Expected: FAIL (no `lib/mbm.sh`).

- [ ] **Step 2: Implement `mbm.sh`**

Create `cachyos/iso/lib/mbm.sh`:

```bash
# shellcheck shell=bash
# Helpers for the made by moonlight live-ISO configurator. Pure where
# possible so test-mbm.sh can cover them without an ISO.

# valid_hostname <name>  ->  0 for a single RFC 1123 label in lowercase
valid_hostname() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

# write_answers <file> KEY=value...  ->  mode-600 answers file for
# install-cachyos.sh --answers (one KEY=value per line, unquoted). Refuses,
# and removes the file, if any argument contains a newline.
write_answers() {
  local file="$1" kv; shift
  ( umask 077; : > "$file" )
  chmod 600 "$file"
  for kv in "$@"; do
    if [[ "$kv" == *$'\n'* ]]; then
      echo "write_answers: a value contains a newline" >&2
      rm -f -- "$file"; return 1
    fi
    printf '%s\n' "$kv" >> "$file"
  done
}

# mask_answers <file>  ->  the file with password values replaced by ********
mask_answers() {
  sed -E 's/^((USER_PASSWORD|LUKS_PASSPHRASE|ROOT_PASSWORD)=).*/\1********/' "$1"
}

# mbm_online  ->  0 if the CachyOS mirror answers (pacstrap needs it)
mbm_online() {
  curl -fsI --max-time 5 https://mirror.cachyos.org >/dev/null 2>&1
}
```

Run: `bash cachyos/iso/test-mbm.sh`
Expected: 14 `PASS`, exit 0.

- [ ] **Step 3: The configurator**

Create `cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator` (and `chmod +x` it):

```bash
#!/usr/bin/env bash
# made by moonlight installer: asks everything up front, then hands over to
# mbm-install, which runs install-cachyos.sh --answers unattended.
#   mbm-configurator            live ISO, tty1, as root
#   mbm-configurator --dry-run  anywhere: walk every screen, print the answers
set -euo pipefail

MBM_REPO="${MBM_REPO:-/usr/share/slievr-cachy}"
MBM_ANSWERS="${MBM_ANSWERS:-/run/mbm-answers.env}"
MBM_OWL="${MBM_OWL:-/usr/share/mbm/owl.ansi}"
DRY_RUN=0
[[ "${1:-}" == --dry-run ]] && DRY_RUN=1

# shellcheck source=SCRIPTDIR/../../../../../../install/profile.sh
source "$MBM_REPO/cachyos/install/profile.sh"
# shellcheck source=SCRIPTDIR/../../../../../../install/lib/detect.sh
source "$MBM_REPO/cachyos/install/lib/detect.sh"
# shellcheck source=SCRIPTDIR/../../../../../lib/mbm.sh
source "$MBM_REPO/cachyos/iso/lib/mbm.sh"

# gum colours are ANSI slots; on the live console .automated_script.sh has
# loaded the brand palette into them (3 accent, 0 background, 8 muted, 1 error).
export GUM_INPUT_CURSOR_FOREGROUND=3 GUM_INPUT_PROMPT_FOREGROUND=3
export GUM_CHOOSE_CURSOR_FOREGROUND=3 GUM_CHOOSE_SELECTED_FOREGROUND=3
export GUM_FILTER_INDICATOR_FOREGROUND=3 GUM_FILTER_MATCH_FOREGROUND=3
export GUM_CONFIRM_SELECTED_BACKGROUND=3 GUM_CONFIRM_SELECTED_FOREGROUND=0

header() { clear; gum style --foreground 3 --bold --margin "1 2" "$1"; }
note()   { gum style --foreground 8 --margin "0 2" -- "$@"; }
fail()   { gum style --foreground 1 --margin "0 2" -- "$@"; }

show_owl() {
  if [[ -r "$MBM_OWL" ]]; then
    cat "$MBM_OWL"
  elif command -v magick >/dev/null; then
    python3 "$MBM_REPO/cachyos/branding/render-console.py" \
      "$MBM_REPO/cachyos/branding/owl.svg" --cols 48 --ansi || true
  fi
}

welcome() {
  clear
  show_owl
  echo
  gum style --bold --margin "0 2" "m a d e   b y   m o o n l i g h t"
  note "CachyOS · Hyprland · encrypted btrfs"
  echo
  gum confirm --affirmative "Let's go" --negative "Shell" \
    "Install made by moonlight on this machine?" || exit 130
}

# UNVERIFIED: iwctl's table layout. If no networks parse, "Open iwctl" is the fallback.
wifi_connect() {
  local dev ssid pass
  dev="$(iwctl device list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '$NF == "station" {print $1; exit}')"
  if [[ -z "$dev" ]]; then fail "No Wi-Fi device found."; sleep 2; return; fi
  iwctl station "$dev" scan; sleep 3
  mapfile -t nets < <(iwctl station "$dev" get-networks 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | awk 'NR > 4 && NF >= 3 { line = $0; sub(/^[ \t>]+/, "", line); n = split(line, a, /[ \t]+/);
                               s = a[1]; for (i = 2; i <= n - 2; i++) s = s " " a[i]; print s }')
  if (( ${#nets[@]} == 0 )); then
    note "Couldn't list networks; opening iwctl. Type 'exit' when connected."
    iwctl || true; return
  fi
  ssid="$(printf '%s\n' "${nets[@]}" | gum choose --header "Wi-Fi network")" || return
  pass="$(gum input --password --placeholder "Passphrase for $ssid")" || return
  iwctl --passphrase "$pass" station "$dev" connect "$ssid" || fail "Couldn't connect to $ssid."
  sleep 3
}

ensure_online() {
  while ! mbm_online; do
    header "No internet connection"
    note "The install downloads packages, so it needs a connection."
    case "$(gum choose "Connect to Wi-Fi" "Retry" "Shell")" in
      "Connect to Wi-Fi") wifi_connect ;;
      Retry) ;;
      *) exit 130 ;;
    esac
  done
}

ask_hostname() {
  local h="${HOST:-}"
  header "1 / 5 · Hostname"
  note "The machine's name on your network."
  while true; do
    h="$(gum input --placeholder "e.g. glaux" --value "$h")"
    valid_hostname "$h" && break
    fail "Use lowercase letters, digits and '-', up to 63 characters."
  done
  HOST="$h"
}

ask_timezone() {
  header "2 / 5 · Timezone"
  note "Type to search. Default: $TIMEZONE"
  TZ_CHOICE="$( { echo "$TIMEZONE"; timedatectl list-timezones | grep -vxF "$TIMEZONE"; } \
    | gum filter --height 12)"
}

read_twice() { # <label>  ->  prints the confirmed, non-empty secret
  local p1 p2
  while true; do
    p1="$(gum input --password --placeholder "$1")"
    p2="$(gum input --password --placeholder "Confirm $1")"
    [[ -n "$p1" && "$p1" == "$p2" ]] && { printf '%s' "$p1"; return; }
    fail "Empty, or they don't match. Try again." >&2
  done
}

ask_password() {
  header "3 / 5 · Password"
  note "For your account, $USERNAME. The root account stays locked; use sudo."
  USER_PW="$(read_twice "password")"
  if gum confirm "Use the same passphrase to unlock the disk at boot?"; then
    LUKS_PW="$USER_PW"
  else
    LUKS_PW="$(read_twice "disk passphrase")"
  fi
}

ask_disk() {
  local line kname model want typed disks
  header "4 / 5 · Disk"
  note "The disk you pick is erased completely. USB drives and this installer are hidden."
  mapfile -t disks < <(list_disks | awk '$NF != "usb"')
  (( ${#disks[@]} )) || { fail "No installable disks found."; exit 1; }
  while true; do
    line="$(printf '%s\n' "${disks[@]}" | gum choose --height 10)"
    kname="${line%% *}"
    model="$(lsblk -dno MODEL "$kname" | sed 's/[[:space:]]*$//')"
    want="${model:-${kname##*/}}"                 # virtio disks have no model
    fail "Everything on $kname will be destroyed."
    typed="$(gum input --placeholder "Type \"$want\" to confirm, or leave empty to pick again")"
    [[ "$typed" == "$want" ]] && break
    note "That didn't match. Pick the disk again."
  done
  DISK_PATH="$(disk_by_id "$kname")"
}

summary() {
  local ucode gpu memkb keep
  ucode="$(detect_ucode /proc/cpuinfo || true)"
  gpu="$(detect_gpu_pkgs "$(lspci -nn 2>/dev/null || true)")"
  memkb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
  mapfile -t keep < <(filter_fstab_entries "$(blkid -s UUID -o value 2>/dev/null || true)" "${EXTRA_FSTAB_ENTRIES[@]}")
  header "5 / 5 · Ready to install"
  gum style --margin "0 2" \
    "Hostname    $HOST" \
    "Timezone    $TZ_CHOICE" \
    "Account     $USERNAME (root locked)" \
    "Disk        $DISK_PATH" \
    "Microcode   $ucode" \
    "GPU         ${gpu:-generic}" \
    "Memory      $(( memkb / 1024 )) MiB, zram $(zram_size "$memkb") MiB" \
    "Data disks  ${#keep[@]} of ${#EXTRA_FSTAB_ENTRIES[@]} fstab entries present"
  echo
  gum confirm --affirmative "Install" --negative "Back" "Erase $DISK_PATH and install?"
}

welcome
ensure_online
while true; do
  ask_hostname; ask_timezone; ask_password; ask_disk
  summary && break
done

answers=(
  "DISK=$DISK_PATH" "DISK_CONFIRMED=yes" "HOSTNAME=$HOST" "TIMEZONE=$TZ_CHOICE"
  "USER_PASSWORD=$USER_PW" "LUKS_PASSPHRASE=$LUKS_PW"
)
if (( DRY_RUN )); then
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  write_answers "$tmp" "${answers[@]}"
  echo; note "Dry run. install-cachyos.sh --answers would receive:"; mask_answers "$tmp"
  exit 0
fi
write_answers "$MBM_ANSWERS" "${answers[@]}"
exec mbm-install "$MBM_ANSWERS"
```

- [ ] **Step 4: gum on the host for dry runs**

In `cachyos/vm/host-deps.sh`, change the `PACKAGES` line to:

```bash
PACKAGES=(qemu-full libvirt virt-manager virt-viewer dnsmasq edk2-ovmf swtpm expect shellcheck gum)
```

and update its comment: `# ... plus tooling used by the other scripts (expect, shellcheck) and the ISO configurator dry run (gum).` (Docker is already installed and active on this host; `slievr-iso-make` checks for it.)

Run: `cachyos/vm/host-deps.sh`
Expected: installs `gum`; `gum --version` prints a version.

- [ ] **Step 5: Dry-run walkthrough (manual)**

Run: `MBM_REPO="$PWD" cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator --dry-run`
Expected, in order:
1. the owl renders, then "m a d e   b y   m o o n l i g h t" and the "Let's go / Shell" prompt;
2. no network screen when online;
3. hostname rejects `Glaux` with the error line, accepts `glaux`;
4. timezone list starts with `UTC` and filters as you type;
5. mismatched passwords are rejected; "same passphrase" yes;
6. the disk list shows this host's disks (no USB). Typing a wrong model goes back to the list; the right model continues;
7. the summary shows real microcode/GPU/RAM and "4 of 4" data disks on the desktop;
8. "Install" prints the answers with both passwords as `********`, exit 0.

Also check that "Shell" on the first screen exits with status 130 (`echo $?`).

- [ ] **Step 6: Lint and commit**

Run: `shellcheck -x cachyos/iso/lib/mbm.sh cachyos/iso/test-mbm.sh cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator cachyos/vm/host-deps.sh && bash cachyos/iso/test-mbm.sh`
Expected: clean; 14 `PASS`.

```bash
git add cachyos/iso/lib/mbm.sh cachyos/iso/test-mbm.sh cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator cachyos/vm/host-deps.sh
git commit -m "iso: gum configurator that writes the unattended-install answers"
```

---

### Task 5: Live entry point + `mbm-install`

**Files:**
- Create: `cachyos/iso/configs/airootfs/root/.automated_script.sh`
- Create: `cachyos/iso/configs/airootfs/usr/local/bin/mbm-install`

**Interfaces:**
- Consumes: `palette.sh` (`mbm_vt_palette`), `mbm-configurator` (exit 130 = user left), `install-cachyos.sh --answers` (Task 2).
- Produces: `mbm-install [answers-file]` (default `/run/mbm-answers.env`). It logs to `/var/log/mbm-install.log` and reboots after a 10 s countdown on success. On failure it shows the last 20 log lines, doesn't reboot, leaves `/mnt` mounted, removes any leftover answers file, and exits 1.
- Note: releng's `/root/.zlogin` runs `~/.automated_script.sh` on login; we replace releng's version of that file.

- [ ] **Step 1: `mbm-install`**

```bash
#!/usr/bin/env bash
# Runs the unattended install from the configurator's answers file, then
# reboots into firstboot. On failure: show what failed, keep /mnt mounted, no
# reboot.
#   mbm-install [/run/mbm-answers.env]
set -uo pipefail

MBM_REPO="${MBM_REPO:-/usr/share/slievr-cachy}"
ANSWERS="${1:-/run/mbm-answers.env}"
LOG=/var/log/mbm-install.log

clear
gum style --foreground 3 --bold --margin "1 2" "Installing made by moonlight"
gum style --foreground 8 --margin "0 2" "This takes a while. Full log: $LOG"
echo

"$MBM_REPO/cachyos/install/install-cachyos.sh" --answers "$ANSWERS" 2>&1 | tee -a "$LOG"
status="${PIPESTATUS[0]}"
rm -f -- "$ANSWERS"        # normally already deleted by load_answers

if (( status == 0 )); then
  echo
  gum style --foreground 2 --bold --margin "0 2" "Installed. Remove the USB stick."
  for s in {10..1}; do printf '\r  Rebooting in %2d s (Ctrl-C to stay)' "$s"; sleep 1; done
  echo
  reboot
fi

echo
gum style --foreground 1 --bold --margin "0 2" "The install failed (exit $status)."
gum style --foreground 8 --margin "0 2" "Last 20 lines of $LOG:"
tail -n 20 "$LOG"
echo
gum style --foreground 8 --margin "0 2" \
  "The target is still mounted at /mnt. Run mbm-configurator to start over."
exit 1
```

- [ ] **Step 2: `.automated_script.sh`**

```bash
#!/usr/bin/env bash
# Live ISO entry point. releng's ~/.zlogin runs this on each root login; it
# only acts on tty1: load the brand console palette, then run the
# configurator. Leaving the configurator lands you in this root shell.
[[ "$(tty)" == /dev/tty1 ]] || exit 0

MBM_REPO=/usr/share/slievr-cachy
# shellcheck source=SCRIPTDIR/../../../../branding/palette.sh
source "$MBM_REPO/cachyos/branding/palette.sh"
mbm_vt_palette
clear

if ! mbm-configurator; then
  echo
  echo "Installer closed. Run 'mbm-configurator' to start again."
fi
```

Run: `chmod +x cachyos/iso/configs/airootfs/usr/local/bin/mbm-install cachyos/iso/configs/airootfs/root/.automated_script.sh`

- [ ] **Step 3: Check the palette escapes on a real console**

On the host, switch to a spare VT (Ctrl+Alt+F3), log in, and run:

```bash
source ~/proj/slievr-cachy/cachyos/branding/palette.sh; mbm_vt_palette; clear
printf '\e[33maccent\e[0m \e[90mmuted\e[0m \e[31merror\e[0m \e[97mmark\e[0m\n'
cat ~/proj/slievr-cachy/dot-config/omarchy/branding/about.txt
```

Expected: a `#171e28` background, amber "accent", grey "muted", red "error", and the owl in white. Run `setvtrgb default` (or log out) to restore. If the host boots straight into a graphical session with no spare VT, defer this check to Task 7's VM run.

- [ ] **Step 4: Lint and commit**

Run: `shellcheck -x cachyos/iso/configs/airootfs/usr/local/bin/mbm-install cachyos/iso/configs/airootfs/root/.automated_script.sh`
Expected: clean.

```bash
git add cachyos/iso/configs/airootfs/usr/local/bin/mbm-install cachyos/iso/configs/airootfs/root/.automated_script.sh
git commit -m "iso: tty1 entry point and unattended install runner"
```

---

### Task 6: ISO build

**Files:**
- Create: `cachyos/iso/configs/packages.extra`, `cachyos/iso/configs/pacman-cachyos.conf`
- Create: `cachyos/iso/builder/build-iso.sh`, `cachyos/iso/bin/slievr-iso-make`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: everything under `cachyos/iso/configs/airootfs/` (Tasks 4–5); `cachyos/branding/{owl.svg,render-console.py}` (Task 3); `DOTFILES_REPO` read from `cachyos/bootstrap.sh` (read only, never edited here).
- Produces: `cachyos/iso/bin/slievr-iso-make`, which writes `release/made-by-moonlight-YYYY.MM.DD-x86_64.iso` plus `.sha256` (names come from mkarchiso's `iso_name`/`iso_version`; keep whatever it produces). Inside the ISO: the repo at `/usr/share/slievr-cachy` (with `.git`, `origin` = `DOTFILES_REPO`), `/usr/share/mbm/owl.ansi`, `/etc/pacman.conf` with `[cachyos]` above `[core]`, and boot entries titled "made by moonlight installer".

- [ ] **Step 1: Config files**

`cachyos/iso/configs/packages.extra` (releng already ships most install tools; duplicates are removed during the build):

```
# Added to releng's packages.x86_64 by builder/build-iso.sh.
gum
git
curl
gptfdisk
pciutils
arch-install-scripts
cryptsetup
btrfs-progs
dosfstools
efibootmgr
cachyos-keyring
cachyos-mirrorlist
```

`cachyos/iso/configs/pacman-cachyos.conf`:

```
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
```

- [ ] **Step 2: `builder/build-iso.sh`**

```bash
#!/usr/bin/env bash
# Runs INSIDE the archlinux container started by bin/slievr-iso-make.
#   /src      read-only clone of the repo at HEAD (origin = DOTFILES_REPO)
#   /release  output dir (the host's release/)
#   HOST_UID / HOST_GID  owner for the outputs
set -euo pipefail

ISO=/src/cachyos/iso
PROFILE=/tmp/profile
OUT=/tmp/out
# UNVERIFIED: CachyOS packaging key, from CachyOS's "add the repo manually"
# instructions. Confirm against https://wiki.cachyos.org before relying on it.
CACHYOS_KEY=F3B607488DB35A47

die() { echo "build-iso: $*" >&2; exit 1; }
step() { printf '\n>>> %s\n' "$*"; }

step "container packages"
pacman-key --init
# Full upgrade, not -Sy: a cached :latest image can be months old.
pacman --noconfirm -Syu archiso git python imagemagick librsvg

step "CachyOS keyring + mirrorlist"
pacman-key --recv-keys "$CACHYOS_KEY" --keyserver keyserver.ubuntu.com \
  || die "couldn't fetch the CachyOS signing key $CACHYOS_KEY"
pacman-key --lsign-key "$CACHYOS_KEY"
# shellcheck disable=SC2016  # $arch/$repo are pacman variables
printf 'Server = https://mirror.cachyos.org/repo/$arch/$repo\n' > /etc/pacman.d/cachyos-mirrorlist
cat "$ISO/configs/pacman-cachyos.conf" >> /etc/pacman.conf
pacman --noconfirm -Sy --overwrite /etc/pacman.d/cachyos-mirrorlist cachyos-keyring cachyos-mirrorlist \
  || die "couldn't install cachyos-keyring / cachyos-mirrorlist"
pacman-key --populate cachyos

step "live kernel >= MIN_KERNEL"
# shellcheck source=/dev/null
MIN_KERNEL="$(. /src/cachyos/install/profile.sh; echo "$MIN_KERNEL")"
live_ver="$(pacman -Si linux | awk '/^Version/ {print $3; exit}')"
(( $(vercmp "$live_ver" "$MIN_KERNEL") >= 0 )) || die "live kernel linux $live_ver is older than $MIN_KERNEL"
echo "live kernel: linux $live_ver (minimum $MIN_KERNEL)"

step "profile: releng + our overlay"
cp -r /usr/share/archiso/configs/releng "$PROFILE"
rm -f "$PROFILE/airootfs/etc/motd"
rm -rf "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service" \
       "$PROFILE/airootfs/etc/systemd/system/reflector.service.d" \
       "$PROFILE/airootfs/etc/xdg/reflector"
cp -rT "$ISO/configs/airootfs" "$PROFILE/airootfs"

# packages: releng's + ours, de-duplicated
grep -v '^#' "$ISO/configs/packages.extra" | sed '/^$/d' >> "$PROFILE/packages.x86_64"
sort -u -o "$PROFILE/packages.x86_64" "$PROFILE/packages.x86_64"

# pacman.conf: [cachyos] above [core], used for the build AND shipped in the live env
awk -v snip="$(cat "$ISO/configs/pacman-cachyos.conf")" \
  '/^\[core\]/ && !done { print snip; print ""; done = 1 } { print }' \
  "$PROFILE/pacman.conf" > "$PROFILE/pacman.conf.new"
mv "$PROFILE/pacman.conf.new" "$PROFILE/pacman.conf"
install -Dm644 "$PROFILE/pacman.conf" "$PROFILE/airootfs/etc/pacman.conf"

# profiledef: our name, label, publisher; permissions for our scripts
# shellcheck disable=SC2016  # $(date ...) is evaluated when mkarchiso sources profiledef.sh
sed -i \
  -e 's/^iso_name=.*/iso_name="made-by-moonlight"/' \
  -e 's/^iso_label=.*/iso_label="MBM_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
  -e 's/^iso_publisher=.*/iso_publisher="made by moonlight"/' \
  -e 's/^iso_application=.*/iso_application="made by moonlight installer"/' \
  "$PROFILE/profiledef.sh"
cat >> "$PROFILE/profiledef.sh" <<'EOF'
file_permissions+=(
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/mbm-configurator"]="0:0:755"
  ["/usr/local/bin/mbm-install"]="0:0:755"
)
EOF

step "boot menu"
# UNVERIFIED: releng's title string and UEFI entry file names. Check with
#   grep -rn title "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux
# and adjust the patterns if releng renamed them.
grep -rlZ 'Arch Linux install medium' "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux 2>/dev/null \
  | xargs -0r sed -i 's/Arch Linux install medium/made by moonlight installer/g'
for f in "$PROFILE"/efiboot/loader/entries/*linux*.conf; do
  [[ -e "$f" && "$f" != *speech* ]] || continue
  sed -e 's/^title .*/& (safe graphics)/' -e 's/^options .*/& nomodeset/' "$f" > "${f%.conf}-nomodeset.conf"
  break
done
grep -rq 'made by moonlight installer' "$PROFILE"/efiboot || die "boot entries were not retitled"
compgen -G "$PROFILE/efiboot/loader/entries/*nomodeset.conf" >/dev/null || die "no safe-graphics boot entry"

step "bake repo + branding"
cp -a /src "$PROFILE/airootfs/usr/share/slievr-cachy"
mkdir -p "$PROFILE/airootfs/usr/share/mbm"
python3 /src/cachyos/branding/render-console.py /src/cachyos/branding/owl.svg --cols 48 --ansi \
  > "$PROFILE/airootfs/usr/share/mbm/owl.ansi"

step "sanity checks"
for f in usr/share/slievr-cachy/cachyos/install/install-cachyos.sh usr/share/slievr-cachy/.git/HEAD \
         usr/share/mbm/owl.ansi usr/local/bin/mbm-configurator usr/local/bin/mbm-install \
         root/.automated_script.sh etc/pacman.conf; do
  [[ -s "$PROFILE/airootfs/$f" ]] || die "missing or empty airootfs/$f"
done
grep -q '^\[cachyos\]' "$PROFILE/airootfs/etc/pacman.conf" || die "live pacman.conf lacks [cachyos]"
[[ "$(git -C "$PROFILE/airootfs/usr/share/slievr-cachy" remote get-url origin)" == https://* ]] \
  || die "baked repo's origin is not the GitHub URL"

step "mkarchiso"
mkarchiso -v -w /tmp/work -o "$OUT" "$PROFILE"
iso="$(ls "$OUT"/*.iso)"
cp "$iso" /release/
( cd /release && sha256sum "${iso##*/}" > "${iso##*/}.sha256" )
chown "${HOST_UID:-0}:${HOST_GID:-0}" "/release/${iso##*/}" "/release/${iso##*/}.sha256"
step "done: release/${iso##*/}"
```

(It writes to `/tmp/out` first and copies at the end, so a failed build never leaves a partial ISO in `release/`.)

- [ ] **Step 3: `bin/slievr-iso-make`**

```bash
#!/usr/bin/env bash
# Build the made by moonlight installer ISO from this repo's committed HEAD.
#   cachyos/iso/bin/slievr-iso-make   ->  release/made-by-moonlight-*.iso (+ .sha256)
# Needs docker (running; sudo is used if you're not in the docker group).
set -euo pipefail

HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
RELEASE="$REPO/release"
die() { echo "slievr-iso-make: $*" >&2; exit 1; }

# One source of truth for the GitHub URL (also used by bootstrap.sh).
DOTFILES_REPO="$(sed -n 's/^DOTFILES_REPO="\(.*\)"$/\1/p' "$REPO/cachyos/bootstrap.sh")"
[[ -n "$DOTFILES_REPO" ]] || die "couldn't read DOTFILES_REPO from cachyos/bootstrap.sh"

if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo "WARNING: uncommitted changes are NOT in the ISO (it ships HEAD $(git -C "$REPO" rev-parse --short HEAD)):" >&2
  git -C "$REPO" status --short >&2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone -q --no-hardlinks "$REPO" "$work/src"
git -C "$work/src" remote set-url origin "$DOTFILES_REPO"
mkdir -p "$RELEASE"

command -v docker >/dev/null || die "docker is not installed"
DOCKER=(docker)
docker version >/dev/null 2>&1 || DOCKER=(sudo docker)   # not in the docker group
"${DOCKER[@]}" pull -q archlinux/archlinux:latest
"${DOCKER[@]}" run --rm --privileged \
  -v "$work/src:/src:ro" -v "$RELEASE:/release" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  archlinux/archlinux:latest /src/cachyos/iso/builder/build-iso.sh

ls -1t "$RELEASE"/*.iso | head -n1
```

Run: `chmod +x cachyos/iso/builder/build-iso.sh cachyos/iso/bin/slievr-iso-make`

- [ ] **Step 4: Ignore build outputs and the brainstorm scratch dir**

Append to `.gitignore`:

```
# ISO build output (cachyos/iso/bin/slievr-iso-make)
release/
# superpowers brainstorming scratch
.superpowers/
```

- [ ] **Step 5: Commit, then build** (the ISO ships committed HEAD, so commit first)

Run: `shellcheck cachyos/iso/builder/build-iso.sh cachyos/iso/bin/slievr-iso-make`
Expected: clean.

```bash
git add cachyos/iso/configs/packages.extra cachyos/iso/configs/pacman-cachyos.conf \
  cachyos/iso/builder/build-iso.sh cachyos/iso/bin/slievr-iso-make .gitignore
git commit -m "iso: build the made by moonlight ISO with mkarchiso in docker"
```

Run: `cachyos/iso/bin/slievr-iso-make`
Expected: the uncommitted-changes warning lists only the unrelated GPU files; every `>>>` step passes, including `live kernel: linux 7.2.x (minimum 7.2)`; it ends with a path under `release/`. Then check:
`(cd release && sha256sum -c ./*.sha256)` → `OK`
`du -h release/*.iso` → roughly 1–1.5 GB.

If the CachyOS key step fails, confirm the key ID on the CachyOS wiki and fix `CACHYOS_KEY`. If the boot-menu checks fail, inspect the releng files as the UNVERIFIED comment says and fix the patterns. Commit any fix and rebuild.

---

### Task 7: Boot the ISO in the VM and verify the whole flow

**Files:**
- Modify: `cachyos/vm/provision-vm.sh` (`ISO_PATH` override)
- Create: `cachyos/iso/bin/slievr-iso-boot`, `cachyos/iso/test/verify-install.sh`

**Interfaces:**
- Consumes: `release/*.iso` (Task 6); the VM scripts in `cachyos/vm/`.
- Produces: `slievr-iso-boot [iso]` (default: the newest `release/*.iso`), and `verify-install.sh`, which is run on the installed VM as `slievr` and exits non-zero on any failed check.

- [ ] **Step 1: `ISO_PATH` override**

In `cachyos/vm/provision-vm.sh`, replace

```bash
iso_path=$("$SCRIPT_DIR/download-iso.sh")
```

with

```bash
# ISO_PATH: boot a specific ISO (e.g. our own, via cachyos/iso/bin/slievr-iso-boot);
# default is the latest stock CachyOS ISO.
iso_path="${ISO_PATH:-$("$SCRIPT_DIR/download-iso.sh")}"
```

- [ ] **Step 2: `slievr-iso-boot`**

```bash
#!/usr/bin/env bash
# Boot a made by moonlight ISO in the disposable libvirt test VM.
#   cachyos/iso/bin/slievr-iso-boot [path/to.iso]   (default: newest release/*.iso)
# Run cachyos/vm/destroy-vm.sh first if the VM already exists.
set -euo pipefail

HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
iso="${1:-$(ls -1t "$REPO"/release/*.iso 2>/dev/null | head -n1)}"
[[ -f "$iso" ]] || { echo "no ISO; build one with cachyos/iso/bin/slievr-iso-make" >&2; exit 1; }

# host-deps.sh grants libvirt-qemu traverse rights on this cache dir only.
cache="${ISO_CACHE_DIR:-$HOME/.cache/cachyos-iso}"
mkdir -p "$cache"
cp -f "$iso" "$cache/"
ISO_PATH="$cache/${iso##*/}" "$REPO/cachyos/vm/provision-vm.sh"
echo "Open the console: virt-viewer --connect qemu:///system cachyos-test"
```

- [ ] **Step 3: `verify-install.sh`**

```bash
#!/usr/bin/env bash
# Post-install checks for a VM installed from the made by moonlight ISO.
# Run as slievr on the installed system, e.g.
#   ssh slievr@<vm-ip> 'bash -s' < cachyos/iso/test/verify-install.sh
set -uo pipefail

bad=0
ok()  { printf 'PASS  %s\n' "$1"; }
no()  { printf 'FAIL  %s\n' "$1"; bad=1; }
is()  { [[ "$2" == "$3" ]] && ok "$1" || no "$1 (got: $3)"; }

is "exactly one boot (no hang/retry)"  1      "$(journalctl --list-boots --no-pager | grep -c .)"
is "firstboot finished bootstrap"      1      "$(grep -c 'Bootstrap complete.' /var/log/slievr-firstboot.log)"
is "no failed units"                   0      "$(systemctl --failed --no-legend | grep -c .)"
is "sddm active"                       active "$(systemctl is-active sddm)"
is "firstboot disabled"                disabled "$(systemctl is-enabled slievr-firstboot.service 2>/dev/null)"
is "root account locked"               L      "$(sudo passwd -S root | awk '{print $2}')"
bloat="$(pacman -Qq | grep -E '^(plasma|kde|kwin|gnome-shell|xfce|lxqt|cinnamon|mate-|cachyos-.+-settings$)' || true)"
is "no desktop bloat"                  ""     "$bloat"
is "linux-cachyos kernel"              yes    "$(pacman -Q linux-cachyos >/dev/null 2>&1 && echo yes || echo no)"
is "running kernel >= 7.2"             yes    "$( (( $(vercmp "$(uname -r | sed 's/-.*//')" 7.2) >= 0 )) && echo yes || echo no)"
is "repo origin is GitHub"             yes    "$(git -C ~/proj/slievr-cachy remote get-url origin | grep -q '^https://github.com/' && echo yes || echo no)"

exit $bad
```

Run: `chmod +x cachyos/iso/bin/slievr-iso-boot && shellcheck cachyos/iso/bin/slievr-iso-boot cachyos/iso/test/verify-install.sh cachyos/vm/provision-vm.sh`
Expected: clean. (`sudo passwd -S` prompts for slievr's password over SSH; run it with `ssh -t`, or answer the prompt.)

- [ ] **Step 4: Commit (before the run, so a rebuild includes these)**

```bash
git add cachyos/vm/provision-vm.sh cachyos/iso/bin/slievr-iso-boot cachyos/iso/test/verify-install.sh
git commit -m "iso: boot our ISO in the test VM; post-install verification script"
```

- [ ] **Step 5: Full run (manual, in virt-viewer)**

```bash
cachyos/vm/destroy-vm.sh            # if a cachyos-test VM exists
cachyos/iso/bin/slievr-iso-boot
virt-viewer --connect qemu:///system cachyos-test
```

Expected:
1. The boot menu is titled "made by moonlight installer" and has a "(safe graphics)" entry.
2. tty1 switches to the brand palette and shows the owl and the configurator, with no login prompt.
3. Walk it through: hostname `iso-test`, timezone default, password `TestPass1`, same for disk, disk = the **40 GB** virtio disk (not the 8 GB data disk). It has no model, so type its kernel name (e.g. `vda`). The summary shows "0 of 4" data disks.
4. Install. The progress scrolls, then "Installed." and the 10 s countdown → reboot.
5. If the VM boots the ISO again, pick the disk in the UEFI boot menu (or eject the CD: `virsh -c qemu:///system change-media cachyos-test sda --eject`).
6. The Plymouth unlock screen shows the **owl** on `#171e28`; unlock with `TestPass1`.
7. Firstboot runs on tty1 and then SDDM appears.

- [ ] **Step 6: Verify**

```bash
ip="$(virsh -c qemu:///system domifaddr cachyos-test | awk '/ipv4/ {sub(/\/.*/, "", $4); print $4; exit}')"
ssh -t "slievr@$ip" 'bash -s' < cachyos/iso/test/verify-install.sh
```

Expected: all `PASS`, exit 0.

Then, in virt-viewer, **log in at SDDM as `slievr`**: Hyprland starts, waybar shows, and Super+Space opens walker. (This closes the "Hyprland login not yet verified" gap from `cachyos/NEXT-SESSION.md`.) Also check the about screen (`slievr-launch-about`, or the menu entry) shows the owl.

- [ ] **Step 7: Fix and record**

For each failure: fix it in the owning task's files, commit, rebuild (`slievr-iso-make`), and rerun from Step 5. When everything is green, note the date and the ISO's sha256 in the commit message of Task 8.

---

### Task 8: Docs and spec deviations

**Files:**
- Create: `cachyos/iso/README.md`
- Modify: `cachyos/install/README.md`, `docs/superpowers/specs/2026-10-01-custom-iso-design.md`, `cachyos/NEXT-SESSION.md`

- [ ] **Step 1: `cachyos/iso/README.md`**

```markdown
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
    ssh -t slievr@<vm-ip> 'bash -s' < cachyos/iso/test/verify-install.sh

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
```

- [ ] **Step 2: Installer README**

In `cachyos/install/README.md`, add a section after "Running":

```markdown
## Unattended (`--answers`)

The ISO's configurator writes `/run/mbm-answers.env` (mode 600) and runs

    install-cachyos.sh --answers /run/mbm-answers.env

Keys: `DISK` (by-id path), `DISK_CONFIRMED=yes`, `HOSTNAME`, `TIMEZONE`,
`USER_PASSWORD`, `LUKS_PASSPHRASE`, optional `ROOT_PASSWORD` (empty → root
locked). One `KEY=value` per line, unquoted; parsed by `lib/answers.sh`, never
sourced; deleted once read. Without `--answers` everything prompts as before.
Data-disk fstab entries from `profile.sh` are only written when their UUID is
present on the machine.
```

Also add `lib/answers.sh` and `test-answers.sh` rows to its Files table.

- [ ] **Step 3: Spec deviations**

In `docs/superpowers/specs/2026-10-01-custom-iso-design.md`, change `**Status:**` to `implemented (see plan)` and append:

```markdown
## Deviations during implementation

1. Answers are parsed (`KEY=value`, whitelisted keys), not `source`d, so a
   value can never execute.
2. releng's `profiledef.sh`, `pacman.conf` and boot entries are patched by
   `builder/build-iso.sh` instead of being vendored under `configs/`; we track
   releng upstream rather than fork it.
3. Boot menu: retitled plus a "safe graphics (nomodeset)" UEFI entry; no
   splash image in v1.
4. The disk confirmation accepts the kernel name when the disk has no model
   (virtio).
```

- [ ] **Step 4: NEXT-SESSION**

At the top of `cachyos/NEXT-SESSION.md`, under the resume header, add a dated bullet: the ISO exists (`cachyos/iso/`), the result of Task 7's VM run (pass/fail per check, and whether the Hyprland login was verified), and the built ISO's sha256.

- [ ] **Step 5: Commit**

```bash
git add cachyos/iso/README.md cachyos/install/README.md docs/superpowers/specs/2026-10-01-custom-iso-design.md cachyos/NEXT-SESSION.md
git commit -m "docs: made by moonlight ISO README, --answers docs, spec deviations"
```
