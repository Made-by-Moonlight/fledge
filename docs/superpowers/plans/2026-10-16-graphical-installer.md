# Graphical installer (roadmap D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ISO's `gum` configurator with a Quickshell installer under a minimal Hyprland, with live progress, keyboard layout, graphical Wi-Fi, permanent data-disk mounts, and the desktop layer (`bootstrap.sh`) installed before the first reboot.

**Architecture:** QML (`cachyos/iso/installer/`, reusing the mbm shell's `theme/`, `components/`, `Net` and `WifiPicker`) collects answers and shows progress. Root work stays in bash: `mbm-probe` (facts as JSON), `mbm-install` (answers on stdin → `install-cachyos.sh --answers`, progress markers on stdout), `mbm-cleanup`. The live ISO autologs in an unprivileged `moonlight` user that runs Hyprland, with a sudoers rule for exactly those commands.

**Tech Stack:** bash, jq, Quickshell (QML/JS, Qt 6), Hyprland 0.56, NetworkManager, archiso.

**Spec:** `docs/superpowers/specs/2026-10-16-graphical-installer-design.md` (read it first; this plan argues from it).

## Global Constraints

- **Never run project code on the host** (AGENTS.md rule 1). Every test, shellcheck run, `qs` run and install happens in the VM `cachyos-test` via `cachyos/vm/vm.sh` (`sync`, `run`, `sudo`, `shot`, `type`). Reading files and building the ISO with `cachyos/iso/bin/slievr-iso-make` (docker container) are fine on the host.
- Unit test commands in this plan all take the form `cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy && bash <test>'`. The VM's repo copy is at `~/proj/slievr-cachy`.
- Brand: "made by moonlight", lowercase. `slievr` is never a logo or wordmark. New components use `mbm`.
- Shell scripts: bash, `set -euo pipefail` (except where noted, matching the existing file), shellcheck-clean at `-S warning` with `-x`, comments explain *why*.
- Tests use `cachyos/install/test/lib.sh` (`check` / `contains`, then `exit $fail`).
- Commit messages: `area: what changed and why`, lowercase area (`install:`, `iso:`, `mbm:`, `docs:`, `vm:`).
- Answers file: one `KEY=value` per line, mode 600, parsed never sourced, deleted once read. New keys: `XKB_LAYOUT`, `XKB_VARIANT`, `DATA_MOUNTS` (`uuid:/abs/path,…`, `~` already expanded, may be empty).
- Progress protocol, exactly: `@@mbm stage <id> <title…>`, `@@mbm count <n> <m>`, `@@mbm fail <id>`, `@@mbm done`. Stage ids in order: `prepare disk base config boot desktop finish`. Gated by `MBM_PROGRESS=1`.
- Data-disk fstab options: `defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10`; ntfs → `ntfs3` plus `uid=,gid=`; vfat/exfat plus `uid=,gid=,umask=022`.
- `install-cachyos.sh` exit codes: 0 installed, 3 only the Desktop stage failed (target left mounted, LUKS open), anything else failed.
- Live user `moonlight` (uid 1000) may run as root, no password, exactly: `/usr/local/bin/mbm-probe`, `/usr/local/bin/mbm-install`, `/usr/local/bin/mbm-cleanup`, `/usr/bin/reboot`.
- Hyprland 0.56; the live `hyprland.conf` is hand-written, no binds.
- No webapps. No TUI fallback.

## Review Focus

- **Two data filesystems given the same mountpoint, or a mountpoint that shadows a system dir or the user's home** (`/home/ethan`, `/var`, `~`): refused in the UI *and* by `install-cachyos.sh`. Tests in Task 2 (`valid_mount_path`, `parse_data_mounts` duplicates) and Task 7 (`tst_validate.qml`).
- **A data filesystem that lives on the disk being erased** (user ticks storage on `nvme2n1` then picks `nvme2n1` as target): the UI drops those rows, and `install-cachyos.sh` dies before partitioning. Guard in Task 4; UI filter in Task 7 (`dataRows`), checked in Task 8 Step 9.
- **Disks with no model string** (virtio, some NVMe): the confirm word falls back to the device name (`vda`). Task 8 Step 1 test of `confirmWord`.
- **Desktop stage fails, then Retry or Reboot anyway**: the target must stay mounted after exit 3, retry must not re-partition, and Reboot anyway must leave firstboot enabled. Task 5 tests `--desktop-only` guards; Task 9 Step 3 (dev) and Task 11 Steps 6-7 (real ISO) exercise it.
- **Hyprland or Quickshell fails to start on the live ISO**: tty1 must explain and leave a usable shell, not loop. Task 10 `.bash_profile`; Task 11 Step 3 checks it by killing qs.

---

### Task 1: mbm settings gain `input.kbVariant`

The installer writes the chosen xkb variant into the user's settings; the schema, validator and generator must accept it.

**Files:**
- Modify: `dot-local/share/mbm/defaults/settings.json` (input block, ~line 104)
- Modify: `dot-local/share/mbm/lib/check.jq:116-117`
- Modify: `dot-local/share/mbm/lib/gen-input.jq:5`
- Modify: `dot-local/share/mbm/test/fixtures/defaults.json:32`
- Modify: `dot-local/share/mbm/test/fixtures/expected-input.conf:3`
- Modify: `dot-config/quickshell/mbm/settings/pages/Input.qml:29`
- Test: `dot-local/share/mbm/test/test-settings.sh`

**Interfaces:**
- Produces: settings key `.input.kbVariant` (string, default `""`), rendered as `kb_variant = <value>` in `~/.local/state/mbm/hypr/input.conf`. Task 5's `seed_user_settings` writes it.

- [ ] **Step 1: Write the failing tests.** In `test-settings.sh`, next to the existing `bad "kbOptions" …` line (~line 168), add:

```bash
bad "kbVariant"                  "input.kbVariant"                      '{"input":{"kbVariant":5}}'
```

and after the block that checks generated input (search for `expected-input.conf`), add:

```bash
fresh
printf '{"input":{"kbLayout":"gb","kbVariant":"extd"}}\n' > "$T/u.json"; mkdir -p "$MBM_CONFIG_DIR"; cp "$T/u.json" "$MBM_CONFIG_DIR/settings.json"
MBM_NO_RELOAD=1 "$MBM" settings apply >/dev/null
contains "input: variant rendered" "kb_variant = extd" "$(cat "$MBM_HYPR_DIR/input.conf")"
contains "input: layout rendered"  "kb_layout = gb"    "$(cat "$MBM_HYPR_DIR/input.conf")"
```

- [ ] **Step 2: Run, expect FAIL** (unknown field `kbVariant`, no `kb_variant` line):
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/dot-local/share/mbm/test/test-settings.sh'`

- [ ] **Step 3: Implement.**
  - `defaults/settings.json` input block: after `"kbLayout": "us",` add `"kbVariant": "",`.
  - `fixtures/defaults.json` line 32: after `"kbLayout": "us",` add ` "kbVariant": "",`.
  - `check.jq`: add `"kbVariant"` to the `unknown([...]; "input")` list after `"kbLayout"`, and after the kbLayout rule add
    `(if (.kbVariant // "" | type == "string") then empty else "input.kbVariant must be text" end),`
  - `gen-input.jq`: after the `kb_layout` line add `"  kb_variant = \($i.kbVariant)",`
  - `fixtures/expected-input.conf`: after `  kb_layout = us` add `  kb_variant = ` (two spaces, `kb_variant = `, nothing after the space). Then make sure the trailing-space line matches what jq emits (run the test; if the only diff is that line, copy jq's output).
  - `Input.qml` line 29: after the layout Field add
    `Field { Layout.fillWidth: true; label: "Keyboard variant (xkb, e.g. dvorak; empty for default)"; text: page.val("kbVariant", ""); onEdited: t => page.put("kbVariant", t) }`

- [ ] **Step 4: Run, expect PASS**, plus `test-defaults.sh`:
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/dot-local/share/mbm/test && bash test-settings.sh && bash test-defaults.sh'`

- [ ] **Step 5: Commit**

```bash
git add dot-local/share/mbm dot-config/quickshell/mbm/settings/pages/Input.qml
git commit -m "mbm: settings gain input.kbVariant (the installer seeds the chosen xkb variant)"
```

---

### Task 2: install libs — answers keys, mount validation, data-disk defaults, fstab lines, console keymap

Pure functions with unit tests. Nothing calls them yet.

**Files:**
- Modify: `cachyos/install/lib/answers.sh`
- Modify: `cachyos/install/lib/detect.sh` (replace `filter_fstab_entries`, extract `live_disk` from `list_disks`, add `data_disk_defaults`, `fstab_line`, `console_keymap`)
- Modify: `cachyos/install/profile.sh` (`KEYMAP` and `EXTRA_FSTAB_ENTRIES` → `DATA_DISKS`)
- Create: `cachyos/install/test/fixtures/base.lst`, `cachyos/install/test/fixtures/kbd-model-map`
- Test: `cachyos/install/test-answers.sh`, `cachyos/install/test-detect.sh`

**Interfaces:**
- Produces (answers.sh):
  - `ANSWER_KEYS` now also has `XKB_LAYOUT XKB_VARIANT DATA_MOUNTS`
  - `valid_xkb_layout <layouts> [base.lst]` → 0 if every comma-separated layout is in the `! layout` section
  - `valid_xkb_variant <variant>` → 0 for `^[a-z0-9_-]*(,[a-z0-9_-]*)*$`
  - `valid_mount_path <abs path>` → 0 if usable as a data mountpoint
  - `parse_data_mounts <spec>` → stdout `uuid<TAB>path` lines; return 1 on any bad entry or a repeated uuid/path
- Produces (detect.sh):
  - `live_disk` → `/dev/<disk>` holding the live medium, or nothing
  - `data_disk_defaults <present_uuids> <uuid:path>...` → `uuid<TAB>path` (path raw, may start `~`) for present uuids
  - `fstab_line <uuid> <fstype> <path> <uid> <gid>` → one fstab line
  - `console_keymap <xkb layout> <xkb variant> [kbd-model-map]` → console keymap name, `us` fallback
- Produces (profile.sh): `DATA_DISKS=( "uuid:~/path" ... )`; `KEYMAP` removed.

- [ ] **Step 1: Fixtures.** `cachyos/install/test/fixtures/base.lst` (trimmed copy of xkeyboard-config's):

```
! model
  pc105           Generic 105-key PC

! layout
  us              English (US)
  gb              English (UK)
  de              German

! variant
  dvorak          us: English (Dvorak)
  extd            gb: English (UK, extended, Windows)
  nodeadkeys      de: German (no dead keys)

! option
  grp                  Switching to another layout
```

`cachyos/install/test/fixtures/kbd-model-map` (trimmed systemd file, tabs or spaces):

```
# Generated from system-config-keyboard's model list
# consolelayout		xlayout	xmodel		xvariant	xoptions
us			us	pc105+inet	-		terminate:ctrl_alt_bksp
uk			gb	pc105+inet	-		terminate:ctrl_alt_bksp
de			de	pc105		-		terminate:ctrl_alt_bksp
de-latin1-nodeadkeys	de	pc105		nodeadkeys	terminate:ctrl_alt_bksp
dvorak			us	pc105		dvorak		terminate:ctrl_alt_bksp
```

- [ ] **Step 2: Write the failing tests.** Append to `test-answers.sh` before `exit $fail`:

```bash
FIX="$DIR/test/fixtures"
check "xkb: known layout"         yes "$(ok valid_xkb_layout gb "$FIX/base.lst")"
check "xkb: two layouts"          yes "$(ok valid_xkb_layout us,de "$FIX/base.lst")"
check "xkb: unknown layout"        no "$(ok valid_xkb_layout zz "$FIX/base.lst")"
check "xkb: variant is not a layout" no "$(ok valid_xkb_layout dvorak "$FIX/base.lst")"
check "xkb: injection refused"     no "$(ok valid_xkb_layout 'us;rm' "$FIX/base.lst")"
check "xkb: empty layout refused"  no "$(ok valid_xkb_layout '' "$FIX/base.lst")"
check "xkb variant: empty ok"     yes "$(ok valid_xkb_variant '')"
check "xkb variant: name"         yes "$(ok valid_xkb_variant dvorak)"
check "xkb variant: bad chars"     no "$(ok valid_xkb_variant 'a b')"

check "mount: under home"           yes "$(ok valid_mount_path /home/ethan/storage1)"
check "mount: own top-level dir"    yes "$(ok valid_mount_path /data)"
check "mount: under /mnt"           yes "$(ok valid_mount_path /mnt/games)"
check "mount: relative refused"      no "$(ok valid_mount_path storage1)"
check "mount: tilde refused"         no "$(ok valid_mount_path '~/storage1')"
check "mount: root refused"          no "$(ok valid_mount_path /)"
check "mount: a home itself refused" no "$(ok valid_mount_path /home/ethan)"
check "mount: /home refused"         no "$(ok valid_mount_path /home)"
check "mount: /mnt refused"          no "$(ok valid_mount_path /mnt)"
check "mount: system tree refused"   no "$(ok valid_mount_path /var/lib/x)"
check "mount: /boot refused"         no "$(ok valid_mount_path /boot)"
check "mount: dotdot refused"        no "$(ok valid_mount_path /home/ethan/../root)"
check "mount: trailing slash refused" no "$(ok valid_mount_path /data/)"
check "mount: space refused"         no "$(ok valid_mount_path '/data/my disk')"
check "mount: comma refused"         no "$(ok valid_mount_path /data,x)"

check "data mounts: empty spec"  "" "$(parse_data_mounts '')"
check "data mounts: two entries" $'aaaa-1\t/home/e/s1\nBB-2\t/data' "$(parse_data_mounts 'aaaa-1:/home/e/s1,BB-2:/data')"
check "data mounts: duplicate path"  1 "$(parse_data_mounts 'a-1:/data,b-2:/data' >/dev/null; echo $?)"
check "data mounts: duplicate uuid"  1 "$(parse_data_mounts 'a-1:/data,a-1:/d2' >/dev/null; echo $?)"
check "data mounts: system path"     1 "$(parse_data_mounts 'a-1:/usr' >/dev/null; echo $?)"
check "data mounts: no colon"        1 "$(parse_data_mounts 'a-1' >/dev/null; echo $?)"
check "data mounts: bad uuid chars"  1 "$(parse_data_mounts 'a/1:/data' >/dev/null; echo $?)"

f="$(mk keys 600 $'XKB_LAYOUT=gb\nXKB_VARIANT=\nDATA_MOUNTS=a-1:/data\n')"
check "answers: new keys load" "gb||a-1:/data" "$( load_answers "$f" && printf '%s|%s|%s' "$XKB_LAYOUT" "$XKB_VARIANT" "$DATA_MOUNTS" )"
```

In `test-detect.sh`, replace the `filter_fstab_entries` block (from `present=$'aaaa-1111\nbbbb-2222'` through the `"fstab filter exact match only"` check) with:

```bash
present=$'aaaa-1111\nbbbb-2222'
check "data defaults keep present, in order" $'aaaa-1111\t~/s1\nbbbb-2222\t/data' \
  "$(data_disk_defaults "$present" "aaaa-1111:~/s1" "cccc-3333:~/s3" "bbbb-2222:/data")"
check "data defaults none present" "" "$(data_disk_defaults "" "aaaa-1111:~/s1")"
check "data defaults exact uuid only" "" "$(data_disk_defaults "aaaa-11112" "aaaa-1111:~/s1")"

O="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10"
check "fstab ext4"  "UUID=u1 /home/e/s1 ext4 $O 0 0"                         "$(fstab_line u1 ext4 /home/e/s1 1000 1000)"
check "fstab ntfs"  "UUID=u2 /data ntfs3 $O,uid=1000,gid=1000 0 0"          "$(fstab_line u2 ntfs /data 1000 1000)"
check "fstab vfat"  "UUID=u3 /data vfat $O,uid=1000,gid=1000,umask=022 0 0" "$(fstab_line u3 vfat /data 1000 1000)"
check "fstab exfat" "UUID=u4 /data exfat $O,uid=1000,gid=1000,umask=022 0 0" "$(fstab_line u4 exfat /data 1000 1000)"

KM="$FIX/kbd-model-map"
check "keymap us"            us                   "$(console_keymap us '' "$KM")"
check "keymap gb"            uk                   "$(console_keymap gb '' "$KM")"
check "keymap variant"       de-latin1-nodeadkeys "$(console_keymap de nodeadkeys "$KM")"
check "keymap us dvorak"     dvorak               "$(console_keymap us dvorak "$KM")"
check "keymap unknown variant falls back to layout" uk "$(console_keymap gb extd "$KM")"
check "keymap first of several layouts" de        "$(console_keymap de,us '' "$KM")"
check "keymap unknown layout" us                  "$(console_keymap zz '' "$KM")"
check "keymap missing map file" us                "$(console_keymap gb '' /nonexistent)"
```

- [ ] **Step 3: Run, expect FAIL** (functions missing):
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/install && bash test-answers.sh; bash test-detect.sh'`

- [ ] **Step 4: Implement `answers.sh`.** Change the keys line and update the header comment's writer name (`mbm-install` now writes the file):

```bash
# Unattended-install answers. The ISO's mbm-install writes a root-only file
# under /run with one KEY=value per line (value = everything after the first
# '=', unquoted). It is parsed, never sourced, so a value can never run as code.

ANSWER_KEYS=(DISK DISK_CONFIRMED HOSTNAME TIMEZONE USERNAME USER_PASSWORD LUKS_PASSPHRASE ROOT_PASSWORD
             XKB_LAYOUT XKB_VARIANT DATA_MOUNTS)
```

Append:

```bash
# valid_xkb_layout <layouts> [base.lst]  ->  0 when every comma-separated
# layout is listed in the "! layout" section of xkeyboard-config's rules.
# The charset check first: the value reaches vconsole.conf and settings JSON.
valid_xkb_layout() {
  local spec="$1" lst="${2:-/usr/share/X11/xkb/rules/base.lst}" known l parts
  [[ "$spec" =~ ^[a-z0-9_]+(,[a-z0-9_]+)*$ ]] || return 1
  known="$(awk '/^! /{s = $2; next} s == "layout" && NF {print $1}' "$lst" 2>/dev/null)" || return 1
  IFS=, read -ra parts <<<"$spec"
  for l in "${parts[@]}"; do
    grep -qxF -- "$l" <<<"$known" || return 1
  done
}

# valid_xkb_variant <variant>  ->  0 for empty or plain xkb variant names
valid_xkb_variant() {
  [[ "$1" =~ ^[a-z0-9_-]*(,[a-z0-9_-]*)*$ ]]
}

# valid_mount_path <path>  ->  0 for an absolute, clean path that is safe to
# mount a data disk on: not a system tree, not a whole home, not /home or /mnt
# themselves. Mirrored in cachyos/iso/installer/lib/Validate.js.
valid_mount_path() {
  local p="$1" parts
  [[ "$p" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
  [[ "$p" == *//* || "$p" == */ || "$p/" == *"/./"* || "$p/" == *"/../"* ]] && return 1
  IFS=/ read -ra parts <<<"${p#/}"
  case "${parts[0]}" in
    boot|efi|usr|var|etc|bin|sbin|lib|lib64|root|run|proc|sys|dev|tmp|swap) return 1 ;;
    home) (( ${#parts[@]} >= 3 )) || return 1 ;;
    mnt|srv|media|opt) (( ${#parts[@]} >= 2 )) || return 1 ;;
  esac
  return 0
}

# parse_data_mounts <"uuid:/path,uuid:/path">  ->  "uuid<TAB>path" lines.
# Empty spec -> nothing. Returns 1 (callers die) on a malformed entry, a path
# valid_mount_path refuses, or a uuid or path used twice.
parse_data_mounts() {
  local spec="$1" e uuid path seen=$'\n' entries
  [[ -n "$spec" ]] || return 0
  IFS=, read -ra entries <<<"$spec"
  for e in "${entries[@]}"; do
    [[ "$e" == *:* ]] || return 1
    uuid="${e%%:*}"; path="${e#*:}"
    [[ "$uuid" =~ ^[A-Za-z0-9-]+$ ]] || return 1
    valid_mount_path "$path" || return 1
    [[ "$seen" == *$'\n'"u:$uuid"$'\n'* || "$seen" == *$'\n'"p:$path"$'\n'* ]] && return 1
    seen+="u:$uuid"$'\n'"p:$path"$'\n'
    printf '%s\t%s\n' "$uuid" "$path"
  done
}
```

- [ ] **Step 5: Implement `detect.sh`.** Replace `filter_fstab_entries` (and its comment) with:

```bash
# data_disk_defaults <present_uuids> <uuid:path>...  ->  "uuid<TAB>path" for
# the profile.sh DATA_DISKS entries whose UUID is on this machine
# (present_uuids is newline-separated, as `blkid -s UUID -o value` prints).
# Paths stay as written (may start with ~); callers expand them.
data_disk_defaults() {
  local present="$1" e; shift
  for e in "$@"; do
    grep -qxF -- "${e%%:*}" <<<"$present" || continue
    printf '%s\t%s\n' "${e%%:*}" "${e#*:}"
  done
}

# fstab_line <uuid> <fstype> <path> <uid> <gid>  ->  a permanent data mount:
# by UUID, automounted on first access, and nofail with a short timeout so a
# missing disk never holds up boot. Filesystems without Unix owners (ntfs,
# vfat, exfat) are mounted as the user so they're writable.
fstab_line() {
  local uuid="$1" fs="$2" path="$3" uid="$4" gid="$5"
  local opts="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10"
  case "$fs" in
    ntfs|ntfs3) fs=ntfs3; opts+=",uid=$uid,gid=$gid" ;;
    vfat|exfat) opts+=",uid=$uid,gid=$gid,umask=022" ;;
  esac
  printf 'UUID=%s %s %s %s 0 0\n' "$uuid" "$path" "$fs" "$opts"
}

# console_keymap <xkb layout> <xkb variant> [kbd-model-map]  ->  the console
# keymap localectl would pick (first layout only): exact variant match, else
# the layout's plain entry, else us. The LUKS prompt uses this keymap.
console_keymap() {
  local layout="${1%%,*}" variant="${2%%,*}" map="${3:-/usr/share/systemd/kbd-model-map}" km=""
  km="$(awk -v l="$layout" -v v="${variant:--}" '!/^#/ && $2 == l && $4 == v {print $1; exit}' "$map" 2>/dev/null)" || km=""
  if [[ -z "$km" && -n "$variant" ]]; then
    km="$(awk -v l="$layout" '!/^#/ && $2 == l && $4 == "-" {print $1; exit}' "$map" 2>/dev/null)" || km=""
  fi
  echo "${km:-us}"
}
```

Extract `live_disk` from `list_disks` (behaviour unchanged; `mbm-probe` reuses it):

```bash
# live_disk  ->  /dev/<disk> backing the live medium, or nothing when it can't
# be identified (e.g. Ventoy's device-mapper node, which lsblk can't resolve).
live_disk() {
  local src pk
  src="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null \
    || findmnt -no SOURCE /run/archiso/cowspace 2>/dev/null || true)"
  [[ -n "$src" ]] || return 0
  pk="$({ lsblk -no PKNAME "$src" 2>/dev/null || true; } | head -n1)"
  if [[ -n "$pk" ]]; then echo "/dev/$pk"; fi
}
```

and in `list_disks` replace the `livesrc`/`lminusb` lines with `local live; live="$(live_disk)"` and pass `-v live="$live"` to awk (the awk body is unchanged). Keep `list_disks`'s comment, dropping the parts that moved to `live_disk`.

- [ ] **Step 6: `profile.sh`.** Delete `KEYMAP="us"`. Update the header comment's per-machine list (`HOSTNAME` and `DATA_DISKS`). Replace the `EXTRA_FSTAB_ENTRIES` block (comment and array) with:

```bash
# Per-machine, optional: data filesystems the installer pre-selects for a
# permanent mount, "uuid:mountpoint" (~ = the new user's home). Entries whose
# UUID isn't on the machine are ignored, so one list serves every machine.
# The installer writes them to fstab by UUID with nofail + automount.
DATA_DISKS=(
  "ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7:~/storage1"
  "5e62f799-8df9-4ee3-b4d7-4da62c8c65ff:~/storage2"
  "77d7988e-2e64-4654-bda2-481d321eecdd:~/storage3"
  "55cefb4f-6b27-4dbc-bbf8-5e9120defa26:~/storage4"
  # The VM's test data disk (cachyos/vm, formatted with this UUID by the
  # end-to-end test); absent on every real machine.
  "00000000-0000-4000-8000-00000000da7a:~/testdata"
)
```

- [ ] **Step 7: Run, expect PASS**, then shellcheck:
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/install && bash test-answers.sh && bash test-detect.sh && shellcheck -x -S warning lib/*.sh profile.sh'`
(`install-cachyos.sh` still references `KEYMAP`/`filter_fstab_entries`; Task 4 fixes it. Don't shellcheck it yet.)

- [ ] **Step 8: Commit**

```bash
git add cachyos/install/lib/answers.sh cachyos/install/lib/detect.sh cachyos/install/profile.sh \
        cachyos/install/test-answers.sh cachyos/install/test-detect.sh cachyos/install/test/fixtures/base.lst \
        cachyos/install/test/fixtures/kbd-model-map
git commit -m "install: answers gain keyboard + data-mount keys; data disks become a uuid->mountpoint map"
```

---

### Task 3: progress markers and NetworkManager profile copy

**Files:**
- Create: `cachyos/install/lib/progress.sh`
- Create: `cachyos/install/test-progress.sh`
- Modify: `cachyos/install/lib/network.sh` (replace iwd conversion with `copy_nm_profiles`)
- Modify: `cachyos/install/test-network.sh` (rewrite)

**Interfaces:**
- Produces (progress.sh): `progress_stage <id> <title>` (sets `MBM_STAGE`), `progress_fail [id]` (defaults to `$MBM_STAGE`), `progress_done`, all silent unless `MBM_PROGRESS=1`; `progress_filter` (stdin→stdout, always active) adds `@@mbm count n m` after pacman `( n/m) installing|upgrading|reinstalling` lines, flushing per line.
- Produces (network.sh): `copy_nm_profiles <src dir> <dst dir>` copies `*.nmconnection` mode 600 into a 700 dir, prints `network: <name>` per file; no-op when none.

- [ ] **Step 1: Write failing tests.** `cachyos/install/test-progress.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for lib/progress.sh. No VM state touched.
#   bash cachyos/install/test-progress.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/progress.sh
source "$DIR/lib/progress.sh"

check "silent without MBM_PROGRESS" "" "$(unset MBM_PROGRESS; progress_stage base 'Base system'; progress_fail; progress_done)"
export MBM_PROGRESS=1
check "stage marker"   "@@mbm stage base Base system" "$(progress_stage base 'Base system')"
check "fail uses current stage" "@@mbm fail disk" "$(progress_stage disk Disk >/dev/null; progress_fail)"
check "fail explicit"  "@@mbm fail desktop" "$(progress_fail desktop)"
check "done marker"    "@@mbm done" "$(progress_done)"

in=$'( 1/245) installing base\n:: Running post-transaction hooks...\n(245/245) upgrading zstd\nwarning: ( 3/4) is not a count'
check "filter adds counts after install lines" \
  $'( 1/245) installing base\n@@mbm count 1 245\n:: Running post-transaction hooks...\n(245/245) upgrading zstd\n@@mbm count 245 245\nwarning: ( 3/4) is not a count' \
  "$(progress_filter <<<"$in")"
check "filter passes markers through" "@@mbm stage x X" "$(progress_filter <<<'@@mbm stage x X')"

exit $fail
```

Rewrite `cachyos/install/test-network.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for lib/network.sh. No VM state touched.
#   bash cachyos/install/test-network.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/network.sh
source "$DIR/lib/network.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkdir -p "$T/src"
printf '[connection]\nid=Owl House\n' > "$T/src/Owl House.nmconnection"
printf '[connection]\nid=cafe\n'      > "$T/src/cafe.nmconnection"
printf 'not a profile\n'              > "$T/src/README"
out="$(copy_nm_profiles "$T/src" "$T/dst")"
check "copies every profile, reports names" $'network: Owl House\nnetwork: cafe' "$out"
check "profiles are root-only"   "600" "$(stat -c '%a' "$T/dst/cafe.nmconnection")"
check "dir is root-only"         "700" "$(stat -c '%a' "$T/dst")"
check "only .nmconnection files" "no"  "$([[ -e $T/dst/README ]] && echo yes || echo no)"
check "nothing to copy is fine"  ""    "$(copy_nm_profiles "$T/none" "$T/dst2")"
check "nothing to copy makes no dir" "no" "$([[ -e $T/dst2 ]] && echo yes || echo no)"

exit $fail
```

- [ ] **Step 2: Run, expect FAIL:**
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/install && bash test-progress.sh; bash test-network.sh'`

- [ ] **Step 3: Implement `lib/progress.sh`:**

```bash
# shellcheck shell=bash
# Progress markers for the graphical installer. With MBM_PROGRESS=1 the
# installer prints, on stdout, lines of exactly:
#   @@mbm stage <id> <title>   a stage starts (prepare disk base config boot desktop finish)
#   @@mbm count <n> <m>        package n of m in the current pacman transaction
#   @@mbm fail <id>            the stage failed (just before a non-zero exit)
#   @@mbm done                 everything succeeded
# Without it, output is exactly as before. The UI (Run.qml) parses these.

MBM_STAGE="${MBM_STAGE:-prepare}"

progress_on() { [[ "${MBM_PROGRESS:-}" == 1 ]]; }

progress_stage() { # <id> <title>
  MBM_STAGE="$1"
  if progress_on; then printf '@@mbm stage %s %s\n' "$1" "$2"; fi
}

progress_fail() { # [id]  (default: the stage that was running)
  if progress_on; then printf '@@mbm fail %s\n' "${1:-$MBM_STAGE}"; fi
}

progress_done() {
  if progress_on; then printf '@@mbm done\n'; fi
}

# progress_filter: stdin -> stdout unchanged, plus "@@mbm count n m" after each
# pacman/pacstrap/paru "( n/m) installing ..." line, so the UI can show package
# counts without pacman knowing about it. Flushes per line: the UI reads live.
progress_filter() {
  awk '{
    print
    if (match($0, /^\( *[0-9]+\/[0-9]+\) (installing|upgrading|reinstalling) /)) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9\/]/, "", s); split(s, a, "/")
      printf "@@mbm count %d %d\n", a[1], a[2]
    }
    fflush()
  }'
}
```

- [ ] **Step 4: Implement `lib/network.sh`.** Replace the whole file:

```bash
# shellcheck shell=bash
# Carry the live ISO's networks into the installed system. Both run
# NetworkManager, so the keyfiles the live session saved (Wi-Fi joined in the
# installer) copy straight across and the first boot is online.

# copy_nm_profiles <src dir> <dst dir>  ->  every *.nmconnection into dst
# (dir 700, files 600: they hold Wi-Fi passwords). Prints what it carried.
copy_nm_profiles() {
  local src="$1" dst="$2" f
  compgen -G "$src/*.nmconnection" >/dev/null || return 0
  install -d -m 700 "$dst"
  for f in "$src"/*.nmconnection; do
    install -m 600 "$f" "$dst/"
    printf 'network: %s\n' "$(basename "$f" .nmconnection)"
  done
}
```

- [ ] **Step 5: Run, expect PASS**, plus shellcheck:
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/install && bash test-progress.sh && bash test-network.sh && shellcheck -x -S warning lib/progress.sh lib/network.sh test-progress.sh test-network.sh'`

- [ ] **Step 6: Commit**

```bash
git add cachyos/install/lib/progress.sh cachyos/install/test-progress.sh cachyos/install/lib/network.sh cachyos/install/test-network.sh
git commit -m "install: progress markers for the graphical installer; NM profiles copy as-is (the live ISO runs NM now)"
```

---

### Task 4: `install-cachyos.sh` — stages, keyboard, data mounts

Wire Task 2/3 into the installer. The Desktop stage comes in Task 5; this task ends the install exactly where it ends today (staging + firstboot), plus the new pieces.

**Files:**
- Modify: `cachyos/install/install-cachyos.sh`
- Modify: `cachyos/install/lib/chroot-setup.sh:4,18` (vconsole) and before `source "${HERE}/bootloader.sh"` (boot marker)
- Modify: `cachyos/install/lib/disk.sh` (add `add_data_mounts`)

**Interfaces:**
- Consumes: Task 2 (`valid_xkb_layout`, `valid_xkb_variant`, `parse_data_mounts`, `data_disk_defaults`, `fstab_line`, `console_keymap`, `DATA_DISKS`), Task 3 (`progress_*`, `copy_nm_profiles`).
- Produces: globals `XKB_LAYOUT`, `XKB_VARIANT`, `DATA_MOUNTS_TSV` (`uuid<TAB>/abs/path` lines) inside the installer; `add_data_mounts` in `lib/disk.sh` (uses `DATA_MOUNTS_TSV`, `USERNAME`; target at `/mnt`, user already created); chroot-setup env gains `XKB_LAYOUT XKB_VARIANT MBM_PROGRESS` and `KEYMAP` is now derived.

- [ ] **Step 1: Sources, trap, defaults.** After `source "$HERE/lib/network.sh"` add:

```bash
# shellcheck source=lib/progress.sh
source "$HERE/lib/progress.sh"
```

After the `rule()` definition add:

```bash
# Any non-zero exit marks the running stage as failed for the graphical
# installer (no-op without MBM_PROGRESS). die() lands here too.
trap 'rc=$?; if (( rc != 0 )); then progress_fail; fi' EXIT
```

Before `if [[ -n "$ANSWERS" ]]; then` (the `load_answers` block) add defaults that the answers file may override:

```bash
XKB_LAYOUT="us"
XKB_VARIANT=""
DATA_MOUNTS=""
```

Inside the answers block, after the TIMEZONE check, add:

```bash
  XKB_LAYOUT="${XKB_LAYOUT:-us}"
  valid_xkb_layout "$XKB_LAYOUT"   || die "answers XKB_LAYOUT is not a known xkb layout: $XKB_LAYOUT"
  valid_xkb_variant "$XKB_VARIANT" || die "answers XKB_VARIANT is malformed: $XKB_VARIANT"
  DATA_MOUNTS_TSV="$(parse_data_mounts "$DATA_MOUNTS")" \
    || die "answers DATA_MOUNTS is malformed, repeats a disk or folder, or uses a system path"
```

After the answers block (closing `fi`) add:

```bash
progress_stage prepare "Prepare"
```

- [ ] **Step 2: Hardware detection.** Replace `mapfile -t KEEP_FSTAB < <(filter_fstab_entries ...)` with:

```bash
# Without answers (manual run), mount every profile.sh data disk that's here.
if [[ -z "$ANSWERS" ]]; then
  DATA_MOUNTS_TSV=""
  while IFS=$'\t' read -r uuid path; do
    [[ -n "$uuid" ]] || continue
    DATA_MOUNTS_TSV+="$uuid"$'\t'"${path/#\~//home/$USERNAME}"$'\n'
  done < <(data_disk_defaults "$(blkid -s UUID -o value)" "${DATA_DISKS[@]}")
  DATA_MOUNTS_TSV="${DATA_MOUNTS_TSV%$'\n'}"
fi
```

and in the summary heredoc replace the `data disks` line with:

```
  keyboard       : ${XKB_LAYOUT}${XKB_VARIANT:+ (${XKB_VARIANT})}
  data disks     : $(grep -c . <<<"$DATA_MOUNTS_TSV" || true) to mount permanently
```

- [ ] **Step 3: Target disk.** Put `progress_stage disk "Partition & encrypt"` immediately before the `rule "Target disk"` banner block. After the `# guards` block's USB check, add:

```bash
# Data disks are mounted, never formatted: one on the disk about to be erased
# would vanish. The UI hides those; this catches manual runs and bad answers.
while IFS=$'\t' read -r uuid _; do
  [[ -n "$uuid" ]] || continue
  dev="$(blkid -U "$uuid" 2>/dev/null)" || die "data disk $uuid isn't on this machine"
  if [[ "$dev" == "$DISK_KNAME" || "$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1)" == "${DISK_KNAME##*/}" ]]; then
    die "data disk $uuid is on $DISK_KNAME, the disk about to be erased"
  fi
done <<<"$DATA_MOUNTS_TSV"
```

- [ ] **Step 4: Stage markers + fstab.** Put `progress_stage base "Base system"` before the `rule "pacstrap"` banner and `progress_stage config "Configure"` before the `rule "fstab"` banner. In the fstab section delete the `for e in "${KEEP_FSTAB[@]}"` loop.

- [ ] **Step 5: chroot env.** In the `arch-chroot /mnt env \` call replace `KEYMAP="$KEYMAP"` with:

```bash
  KEYMAP="$(console_keymap "$XKB_LAYOUT" "$XKB_VARIANT")" XKB_LAYOUT="$XKB_LAYOUT" XKB_VARIANT="$XKB_VARIANT" \
  MBM_PROGRESS="${MBM_PROGRESS:-}" \
```

After `rm -f /mnt/root/chroot-setup.sh /mnt/root/bootloader.sh` add:

```bash
add_data_mounts
```

- [ ] **Step 6: `chroot-setup.sh`.** Header env list: replace `KEYMAP` with `KEYMAP XKB_LAYOUT XKB_VARIANT MBM_PROGRESS`. Replace `echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf` with:

```bash
# KEYMAP for the console and the LUKS prompt (sd-vconsole in the initramfs);
# XKB* so localectl and anything reading vconsole.conf see the real layout.
{
  echo "KEYMAP=${KEYMAP}"
  echo "XKBLAYOUT=${XKB_LAYOUT}"
  if [[ -n "${XKB_VARIANT:-}" ]]; then echo "XKBVARIANT=${XKB_VARIANT}"; fi
} > /etc/vconsole.conf
```

Before `echo ">>> bootloader" >&2` add:

```bash
if [[ "${MBM_PROGRESS:-}" == 1 ]]; then echo "@@mbm stage boot Bootloader"; fi
```

- [ ] **Step 7: `add_data_mounts` in `lib/disk.sh`** (append):

```bash
# add_data_mounts  ->  fstab entries + mountpoints for DATA_MOUNTS_TSV
# ("uuid<TAB>/path" lines) in the target at /mnt. Runs after the user exists
# (chroot-setup.sh) so ntfs/vfat mounts and folders in the home get their ids.
# Folders inside the user's home are created owned by the user, parents too.
add_data_mounts() {
  local uid gid uuid path dev fs d
  [[ -n "${DATA_MOUNTS_TSV:-}" ]] || return 0
  uid="$(arch-chroot /mnt id -u "$USERNAME")"; gid="$(arch-chroot /mnt id -g "$USERNAME")"
  printf '\n# Data disks (made by moonlight installer): mounted by UUID on every boot;\n# nofail, so a missing disk never holds up boot.\n' >> /mnt/etc/fstab
  while IFS=$'\t' read -r uuid path; do
    [[ -n "$uuid" ]] || continue
    dev="$(blkid -U "$uuid")"
    fs="$(blkid -s TYPE -o value "$dev")"
    fstab_line "$uuid" "$fs" "$path" "$uid" "$gid" >> /mnt/etc/fstab
    mkdir -p "/mnt$path"
    if [[ "$path" == "/home/$USERNAME/"* ]]; then
      d="$path"
      while [[ "$d" != "/home/$USERNAME" ]]; do chown "$uid:$gid" "/mnt$d"; d="${d%/*}"; done
    fi
    _log "data disk $uuid ($fs) -> $path"
  done <<<"$DATA_MOUNTS_TSV"
}
```

- [ ] **Step 8: NM profiles.** In the staging section replace the `install_wifi_profiles /var/lib/iwd ...` line and its comment with:

```bash
# Networks the live session joined (the installer's Wi-Fi picker saves NM
# keyfiles), so first boot is online on a laptop.
copy_nm_profiles /etc/NetworkManager/system-connections /mnt/etc/NetworkManager/system-connections
```

- [ ] **Step 9: Verify statically.** No test can run the installer outside a live ISO; Task 10 runs it end to end. Check syntax, shellcheck and the unit suites:
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/install && bash -n install-cachyos.sh && shellcheck -x -S warning install-cachyos.sh lib/*.sh && for t in test-*.sh; do bash $t >/dev/null || echo "FAIL $t"; done; grep -n "KEEP_FSTAB\|EXTRA_FSTAB\|filter_fstab\|install_wifi_profiles\|KEYMAP=\"\$KEYMAP\"" install-cachyos.sh lib/*.sh || echo "no stale references"'`
Expected: no shellcheck output, no `FAIL`, `no stale references`.

- [ ] **Step 10: Commit**

```bash
git add cachyos/install
git commit -m "install: progress stages, xkb layout in vconsole, data disks mounted by UUID from the answers"
```

---

### Task 5: Desktop stage before reboot, `--desktop-only`, finish

**Files:**
- Create: `cachyos/install/lib/desktop.sh`
- Modify: `cachyos/install/install-cachyos.sh` (args, `desktop_and_finish`, Done section)
- Modify: `cachyos/install/README.md` (Unattended section keys, new flow)
- Test: `cachyos/install/test-desktop.sh` (create)

**Interfaces:**
- Consumes: Task 4 globals; `progress_stage`, `progress_done`.
- Produces:
  - `run_desktop_stage <user>` → 0 when `bootstrap.sh` completed in the chroot (then firstboot disabled + done-guard + sddm enabled); 1 otherwise (firstboot left enabled).
  - `seed_user_settings <user> <layout> <variant>` → writes `/mnt/home/<user>/.config/mbm/settings.json` with `{"input":{"kbLayout":…,"kbVariant":…}}` unless layout is `us` and variant empty.
  - `finish_install` → copies `/var/log/mbm-install.log` to `/mnt/var/log/` (600), `umount -R /mnt`, `cryptsetup close $LUKS_NAME`.
  - `install-cachyos.sh --desktop-only <user>` → requires `/mnt` mounted; runs Desktop + Finish only; exit 0 / 3.
  - `MBM_TARGET` (default `/mnt`): the functions use `$MBM_TARGET` instead of a literal `/mnt` so the test can point them at a temp dir.

- [ ] **Step 1: Write the failing test** `cachyos/install/test-desktop.sh`. It covers what can run without a chroot: settings seeding and the `--desktop-only` guards.

```bash
#!/usr/bin/env bash
# Unit tests for lib/desktop.sh's pure parts and install-cachyos.sh's
# --desktop-only guards. No chroot, no disks.
#   bash cachyos/install/test-desktop.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/desktop.sh
source "$DIR/lib/desktop.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

export MBM_TARGET="$T/mnt"
mkdir -p "$MBM_TARGET/home/ethan"
seed_user_settings ethan us "" 1000 1000
check "us layout: no settings file" "no" "$([[ -e $MBM_TARGET/home/ethan/.config/mbm/settings.json ]] && echo yes || echo no)"
seed_user_settings ethan gb extd "$(id -u)" "$(id -g)"
check "layout seeded" '{"input":{"kbLayout":"gb","kbVariant":"extd"}}' "$(tr -d ' \n' < "$MBM_TARGET/home/ethan/.config/mbm/settings.json")"

out="$(bash "$DIR/install-cachyos.sh" --desktop-only 'Bad Name' 2>&1)"; rc=$?
check "desktop-only: bad user refused" 1 "$rc"
contains "desktop-only: says why" "not a valid user name" "$out"

exit $fail
```

(The `--desktop-only` check runs as a normal user: the name check must come before the root check so this works. Order it that way in Step 4.)

- [ ] **Step 2: Run, expect FAIL:**
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/install && bash test-desktop.sh'`

- [ ] **Step 3: Implement `lib/desktop.sh`:**

```bash
# shellcheck shell=bash
# The desktop layer, installed before the first reboot: bootstrap.sh runs as
# the new user inside the target (arch-chroot), so the first boot lands on the
# login screen. If it fails, slievr-firstboot.service (already enabled) runs it
# again on first boot, as it always used to.
# Sourced by install-cachyos.sh. The target is mounted at $MBM_TARGET.

MBM_TARGET="${MBM_TARGET:-/mnt}"

# seed_user_settings <user> <xkb layout> <xkb variant> <uid> <gid>  ->  the
# chosen layout as the user's mbm settings override, so Hyprland and the
# settings window start with it. Nothing for the default (us, no variant).
# Values are validated (valid_xkb_layout/variant) before they get here.
seed_user_settings() {
  local user="$1" layout="$2" variant="$3" uid="$4" gid="$5" dir
  [[ "$layout" == us && -z "$variant" ]] && return 0
  dir="$MBM_TARGET/home/$user/.config/mbm"
  install -d -o "$uid" -g "$gid" "$MBM_TARGET/home/$user/.config" "$dir"
  printf '{ "input": { "kbLayout": "%s", "kbVariant": "%s" } }\n' "$layout" "$variant" > "$dir/settings.json"
  chown "$uid:$gid" "$dir/settings.json"
}

# run_desktop_stage <user>  ->  0 once bootstrap.sh completed in the target.
# bootstrap.sh calls sudo throughout: passwordless sudo for this stage only.
# runuser -l starts from a clean login environment, so bootstrap sees no
# Hyprland session and skips its live-session steps (hyprctl, systemctl --user).
run_desktop_stage() {
  local user="$1" sudoers="$MBM_TARGET/etc/sudoers.d/99-mbm-install" attempt ok=0
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" > "$sudoers"
  chmod 440 "$sudoers"
  for attempt in 1 2 3; do
    echo ">>> desktop: bootstrap.sh as $user (attempt $attempt/3)"
    if arch-chroot "$MBM_TARGET" runuser -l "$user" -c 'bash ~/proj/slievr-cachy/cachyos/bootstrap.sh'; then
      ok=1; break
    fi
    # Mirrors are sometimes mid-sync (a listed package 404s); bootstrap.sh is safe to re-run.
    if (( attempt < 3 )); then
      echo ">>> bootstrap failed; refreshing package databases and retrying in 30s"
      sleep 30
      arch-chroot "$MBM_TARGET" pacman -Syy --noconfirm || true
    fi
  done
  rm -f "$sudoers"
  (( ok )) || return 1
  arch-chroot "$MBM_TARGET" systemctl disable slievr-firstboot.service
  touch "$MBM_TARGET/var/lib/slievr-firstboot-done"
  arch-chroot "$MBM_TARGET" systemctl enable sddm.service
}

# finish_install  ->  keep the install log in the new system, then close it up.
finish_install() {
  if [[ -f /var/log/mbm-install.log ]]; then
    install -Dm600 /var/log/mbm-install.log "$MBM_TARGET/var/log/mbm-install.log"
  fi
  umount -R "$MBM_TARGET"
  cryptsetup close "$LUKS_NAME"
}
```

- [ ] **Step 4: Wire into `install-cachyos.sh`.**
  - Source it after progress.sh: `# shellcheck source=lib/desktop.sh` / `source "$HERE/lib/desktop.sh"`.
  - Arg parsing: add `DESKTOP_ONLY=""` beside `ANSWERS=""` and the case
    `--desktop-only) DESKTOP_ONLY="${2:?--desktop-only needs a user}"; shift ;;`
  - Update the usage line in the header comment: `[--allow-usb] [--answers FILE] [--desktop-only USER]`.
  - Define, after the trap:

```bash
# The last two stages. Also the whole of --desktop-only, which the graphical
# installer's "Retry desktop" runs against the still-mounted target.
desktop_and_finish() {
  rule "Desktop (bootstrap.sh in the new system)"
  progress_stage desktop "Desktop"
  if ! run_desktop_stage "$USERNAME"; then
    warn "the desktop layer failed. The system is installed; /mnt is still mounted."
    warn "Retry with --desktop-only $USERNAME, or reboot: firstboot runs it on first boot."
    exit 3
  fi
  rule "Finish"
  progress_stage finish "Finish"
  finish_install
  progress_done
}
```

  - Immediately after argument parsing (before the answers block):

```bash
if [[ -n "$DESKTOP_ONLY" ]]; then
  valid_username "$DESKTOP_ONLY" || die "--desktop-only: not a valid user name: $DESKTOP_ONLY"
  [[ $EUID -eq 0 ]] || die "must run as root"
  mountpoint -q /mnt || die "--desktop-only: the target isn't mounted at /mnt"
  [[ -d "/mnt/home/$DESKTOP_ONLY/proj/slievr-cachy" ]] || die "--desktop-only: no staged repo for $DESKTOP_ONLY in /mnt"
  USERNAME="$DESKTOP_ONLY"
  desktop_and_finish
  exit 0
fi
```

  - After `add_data_mounts` (Task 4 Step 5) add:

```bash
seed_user_settings "$USERNAME" "$XKB_LAYOUT" "$XKB_VARIANT" \
  "$(arch-chroot /mnt id -u "$USERNAME")" "$(arch-chroot /mnt id -g "$USERNAME")"
```

  - Replace the whole `rule "Done"` section (umount, cryptsetup close, heredoc, reboot prompt) with:

```bash
desktop_and_finish
cat <<EOF

Install complete. On reboot, unlock the disk, then log in.
If anything in the desktop layer is missing, its log is /var/log/mbm-install.log.

EOF
if [[ -z "$ANSWERS" ]]; then
  read -rp "Reboot now? [y/N] " r
  [[ "$r" == [yY] ]] && reboot
fi
```

  - Update the firstboot comment in the staging section: firstboot is now the fallback that runs only when the Desktop stage didn't finish.

- [ ] **Step 5: Run, expect PASS**, plus shellcheck and the other suites:
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/install && bash test-desktop.sh && shellcheck -x -S warning install-cachyos.sh lib/*.sh test-desktop.sh && for t in test-*.sh; do bash $t >/dev/null || echo "FAIL $t"; done'`

- [ ] **Step 6: Check bootstrap.sh is chroot-safe** (read-only review; fix only if a finding is real). Confirm each, noting line numbers in the commit message body:
  - every `hyprctl`, `pkill` and `systemctl --user` call is behind `in_session` or the `XDG_RUNTIME_DIR`/`show-environment` guard (`bootstrap.sh:342-353`, `:383`, `:449-470`);
  - `systemctl enable --now pkgfile-update.timer` (`:402`) is `|| echo WARN`, so a skipped start in a chroot can't fail bootstrap;
  - nothing reads `/run/user`, `loginctl`, `timedatectl`, `localectl` or `hostnamectl`.
  If all hold, no change.

- [ ] **Step 7: README.** In `cachyos/install/README.md`: "Unattended" lists the new keys (`XKB_LAYOUT`, `XKB_VARIANT`, `DATA_MOUNTS`) and says `mbm-install` (not the configurator) writes the file; "Before you run it" says `DATA_DISKS` instead of `EXTRA_FSTAB_ENTRIES`; "Running" says the installer now runs `bootstrap.sh` itself before the reboot (firstboot is the fallback) and documents `--desktop-only USER`.

- [ ] **Step 8: Commit**

```bash
git add cachyos/install
git commit -m "install: run bootstrap.sh in the chroot before reboot (firstboot stays as the fallback); --desktop-only retries it"
```

---

### Task 6: ISO backend — `mbm-probe`, `mbm-install`, `mbm-cleanup`

**Files:**
- Create: `cachyos/iso/lib/probe.jq`
- Create: `cachyos/iso/configs/airootfs/usr/local/bin/mbm-probe`
- Create: `cachyos/iso/configs/airootfs/usr/local/bin/mbm-cleanup`
- Rewrite: `cachyos/iso/configs/airootfs/usr/local/bin/mbm-install`
- Modify: `cachyos/iso/lib/mbm.sh` (drop `mask_answers`, `parse_networks`)
- Modify: `cachyos/iso/test-mbm.sh` (drop their tests)
- Create: `cachyos/iso/test-probe.sh`, `cachyos/iso/test/fixtures/lsblk.json`

**Interfaces:**
- Consumes: `live_disk`, `disk_by_id`, `zram_size`, `hibernate_swap_size`, `detect_ucode`, `detect_gpu_pkgs` (detect.sh); `write_answers`, `mbm_online` (mbm.sh); `progress_filter` (progress.sh); `DATA_DISKS`, `TIMEZONE`, `SWAP`, `LUKS_NAME` (profile.sh).
- Produces:
  - `mbm-probe facts` → JSON `{disks:[{path,size,model,tran,parts:[{path,size,fstype,label}]}], datafs:[{uuid,fstype,label,size,disk,mount}], ucode, gpu, memMiB, zramMiB, swapMiB, timezone, online, leftover}`. `size` in bytes; `mount` = raw `DATA_DISKS` path (may start `~`) or `null`.
  - `mbm-probe online` → exit 0/1.
  - `mbm-install` → reads `KEY=value` lines on stdin until a line `END`; `DISK` may be a kernel path (mapped to by-id); streams the install log with markers on stdout; same exit code as `install-cachyos.sh`.
  - `mbm-install --desktop-only USER` → no stdin; runs the retry.
  - `mbm-cleanup` → unmounts `/mnt`, closes LUKS; exit 0 when nothing is left open.

- [ ] **Step 1: Fixture** `cachyos/iso/test/fixtures/lsblk.json` (shaped like the user's desktop plus the live USB stick; `lsblk -J -b -o PATH,SIZE,MODEL,TRAN,TYPE,FSTYPE,UUID,LABEL,PARTTYPE`):

```json
{
  "blockdevices": [
    {"path": "/dev/sda", "size": 480103981056, "model": "PNY CS900 480GB SSD  ", "tran": "sata", "type": "disk", "fstype": null, "uuid": null, "label": null, "parttype": null,
     "children": [
       {"path": "/dev/sda1", "size": 480102916096, "model": null, "tran": null, "type": "part", "fstype": "ext4", "uuid": "ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7", "label": null, "parttype": "0fc63daf-8483-4772-8e79-3d69d8477de4"}
     ]},
    {"path": "/dev/sdc", "size": 32010928128, "model": "Ultra USB 3.0", "tran": "usb", "type": "disk", "fstype": "iso9660", "uuid": "2026-10-16-00-00-00-00", "label": "MBM_202610", "parttype": null,
     "children": [
       {"path": "/dev/sdc2", "size": 1048576, "model": null, "tran": null, "type": "part", "fstype": "vfat", "uuid": "AAAA-BBBB", "label": "ARCHISO_EFI", "parttype": "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"}
     ]},
    {"path": "/dev/sdd", "size": 64023257088, "model": "Extreme", "tran": "usb", "type": "disk", "fstype": "exfat", "uuid": "1234-ABCD", "label": "photos", "parttype": null},
    {"path": "/dev/nvme2n1", "size": 1000204886016, "model": "WD Blue SN570 1TB", "tran": "nvme", "type": "disk", "fstype": null, "uuid": null, "label": null, "parttype": null,
     "children": [
       {"path": "/dev/nvme2n1p1", "size": 2147483648, "model": null, "tran": null, "type": "part", "fstype": "vfat", "uuid": "87B6-F21D", "label": null, "parttype": "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"},
       {"path": "/dev/nvme2n1p2", "size": 998056312320, "model": null, "tran": null, "type": "part", "fstype": "crypto_LUKS", "uuid": "0c99f7a8-02e0-421c-8d4a-9d2a60202af0", "label": null, "parttype": "0fc63daf-8483-4772-8e79-3d69d8477de4"}
     ]},
    {"path": "/dev/nvme0n1", "size": 4000787030016, "model": "Predator SSD GM7 4TB", "tran": "nvme", "type": "disk", "fstype": null, "uuid": null, "label": null, "parttype": null,
     "children": [
       {"path": "/dev/nvme0n1p3", "size": 3900000000000, "model": null, "tran": null, "type": "part", "fstype": "ext4", "uuid": "55cefb4f-6b27-4dbc-bbf8-5e9120defa26", "label": "big", "parttype": "0fc63daf-8483-4772-8e79-3d69d8477de4"},
       {"path": "/dev/nvme0n1p4", "size": 34359738368, "model": null, "tran": null, "type": "part", "fstype": "swap", "uuid": "37299452-ecec-4937-8e67-b00311334d13", "label": null, "parttype": "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"}
     ]},
    {"path": "/dev/zram0", "size": 4294967296, "model": null, "tran": null, "type": "disk", "fstype": "swap", "uuid": null, "label": null, "parttype": null}
  ]
}
```

- [ ] **Step 2: Write the failing test** `cachyos/iso/test-probe.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for lib/probe.jq (mbm-probe's disk logic) against a fixture.
#   bash cachyos/iso/test-probe.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
FIX="$DIR/test/fixtures/lsblk.json"
defaults='{"ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7":"~/storage1"}'
probe() { jq -c --arg live /dev/sdc --argjson defaults "$defaults" -f "$DIR/lib/probe.jq" "$FIX" | jq -r "$1"; }

check "disks: no live stick, no usb, no zram" "/dev/sda /dev/nvme2n1 /dev/nvme0n1" "$(probe '[.disks[].path] | join(" ")')"
check "disks: model trimmed"     "PNY CS900 480GB SSD" "$(probe '.disks[0].model')"
check "disks: parts listed"      "2" "$(probe '.disks[1].parts | length')"
check "datafs: data filesystems, usb included, live stick/ESP/LUKS/swap excluded" \
  "ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7 1234-ABCD 55cefb4f-6b27-4dbc-bbf8-5e9120defa26" "$(probe '[.datafs[].uuid] | join(" ")')"
check "datafs: whole-disk filesystem keeps its disk" "/dev/sdd" "$(probe '.datafs[1].disk')"
check "datafs: default mount from profile" "~/storage1" "$(probe '.datafs[0].mount')"
check "datafs: no default is null"  "null" "$(probe '.datafs[2].mount')"
check "datafs: label kept"          "big"  "$(probe '.datafs[2].label')"
check "no live disk known: stick listed as usb, still hidden" "/dev/sda /dev/nvme2n1 /dev/nvme0n1" \
  "$(jq -c --arg live '' --argjson defaults '{}' -f "$DIR/lib/probe.jq" "$FIX" | jq -r '[.disks[].path] | join(" ")')"

exit $fail
```

- [ ] **Step 3: Run, expect FAIL:**
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/iso && bash test-probe.sh'`

- [ ] **Step 4: Implement `cachyos/iso/lib/probe.jq`:**

```jq
# lsblk -J -b -o PATH,SIZE,MODEL,TRAN,TYPE,FSTYPE,UUID,LABEL,PARTTYPE  ->  {disks, datafs}
#   $live      the disk holding the live medium ("" when unknown): never listed
#   $defaults  {uuid: mountpoint} from profile.sh DATA_DISKS
# disks:  install targets (whole disks, not USB, not zram/ram/loop)
# datafs: filesystems that can be mounted as data disks, on any disk but the
#         live one (USB included); ESPs, swap and LUKS never qualify. The UI
#         drops the ones on the disk chosen as the target.
def esp: (.parttype // "" | ascii_downcase) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
[.blockdevices[]
 | select(.type == "disk" and .path != $live and (.path | test("/(zram|ram|loop)[0-9]+$") | not))] as $all
| {
    disks: [$all[] | select(.tran != "usb") | {
      path, size,
      model: ((.model // "") | sub("\\s+$"; "")),
      tran: (.tran // ""),
      parts: [(.children // [])[] | {path, size, fstype: (.fstype // ""), label: (.label // "")}]
    }],
    datafs: [$all[] | .path as $disk | (., (.children // [])[])
      | select((.fstype // "") | IN("ext4", "btrfs", "xfs", "ntfs", "exfat", "vfat"))
      | select(esp | not)
      | {uuid, fstype, label: (.label // ""), size, disk: $disk, mount: ($defaults[.uuid] // null)}]
  }
```

- [ ] **Step 5: Run, expect PASS** (same command as Step 3).

- [ ] **Step 6: `mbm-probe`:**

```bash
#!/usr/bin/env bash
# What the graphical installer needs to know about this machine.
#   mbm-probe facts    JSON: disks, data filesystems, hardware, defaults
#   mbm-probe online   exit 0 when the CachyOS mirror answers
# Root (via the live user's sudoers rule): blkid and lsblk need it for UUIDs.
set -euo pipefail

MBM_REPO="${MBM_REPO:-/usr/share/slievr-cachy}"
# shellcheck source=SCRIPTDIR/../../../../../../install/profile.sh
source "$MBM_REPO/cachyos/install/profile.sh"
# shellcheck source=SCRIPTDIR/../../../../../../install/lib/detect.sh
source "$MBM_REPO/cachyos/install/lib/detect.sh"
# shellcheck source=SCRIPTDIR/../../../../../lib/mbm.sh
source "$MBM_REPO/cachyos/iso/lib/mbm.sh"

case "${1:-}" in
  online) mbm_online ;;
  facts)
    memkb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
    swap=0
    if [[ "$SWAP" == hibernate ]]; then swap="$(hibernate_swap_size "$memkb")"; fi
    online=false; if mbm_online; then online=true; fi
    leftover=false
    if mountpoint -q /mnt || [[ -e "/dev/mapper/$LUKS_NAME" ]]; then leftover=true; fi
    defaults="$(for e in "${DATA_DISKS[@]}"; do printf '%s\t%s\n' "${e%%:*}" "${e#*:}"; done \
      | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}')"
    lsblk -J -b -o PATH,SIZE,MODEL,TRAN,TYPE,FSTYPE,UUID,LABEL,PARTTYPE \
      | jq --arg live "$(live_disk)" --argjson defaults "$defaults" -f "$MBM_REPO/cachyos/iso/lib/probe.jq" \
      | jq --arg ucode "$(detect_ucode /proc/cpuinfo || true)" \
           --arg gpu "$(detect_gpu_pkgs "$(lspci -nn 2>/dev/null || true)")" \
           --argjson mem "$(( memkb / 1024 ))" --argjson zram "$(zram_size "$memkb")" --argjson swap "$swap" \
           --arg tz "$TIMEZONE" --argjson online "$online" --argjson leftover "$leftover" \
           '. + {ucode: $ucode, gpu: $gpu, memMiB: $mem, zramMiB: $zram, swapMiB: $swap,
                 timezone: $tz, online: $online, leftover: $leftover}' ;;
  *) echo "usage: mbm-probe facts|online" >&2; exit 2 ;;
esac
```

- [ ] **Step 7: `mbm-install`** (replace the file):

```bash
#!/usr/bin/env bash
# Runs the install for the graphical installer and streams its progress.
#   mbm-install                       answers on stdin: KEY=value lines, then END
#   mbm-install --desktop-only USER   retry the Desktop stage on the mounted target
# stdout: the install log plus @@mbm marker lines (cachyos/install/lib/progress.sh),
# also appended to /var/log/mbm-install.log. Exit code is install-cachyos.sh's:
# 0 installed, 3 only the Desktop stage failed (target left mounted), else failed.
set -uo pipefail

MBM_REPO="${MBM_REPO:-/usr/share/slievr-cachy}"
LOG=/var/log/mbm-install.log
ANSWERS=/run/mbm-answers.env
# shellcheck source=SCRIPTDIR/../../../../../../install/lib/detect.sh
source "$MBM_REPO/cachyos/install/lib/detect.sh"
# shellcheck source=SCRIPTDIR/../../../../../../install/lib/progress.sh
source "$MBM_REPO/cachyos/install/lib/progress.sh"
# shellcheck source=SCRIPTDIR/../../../../../lib/mbm.sh
source "$MBM_REPO/cachyos/iso/lib/mbm.sh"

if [[ "${1:-}" == --desktop-only ]]; then
  args=(--desktop-only "${2:?--desktop-only needs a user}")
else
  # END rather than EOF: the UI writes to a pipe it keeps open.
  lines=()
  while IFS= read -r line; do
    [[ "$line" == END ]] && break
    # The UI knows disks by kernel path; the installer wants a stable by-id path.
    if [[ "$line" == DISK=* ]]; then line="DISK=$(disk_by_id "${line#DISK=}")"; fi
    lines+=("$line")
  done
  write_answers "$ANSWERS" "${lines[@]}" || exit 1
  args=(--answers "$ANSWERS")
fi

MBM_PROGRESS=1 bash "$MBM_REPO/cachyos/install/install-cachyos.sh" "${args[@]}" 2>&1 \
  | progress_filter | tee -a "$LOG"
status="${PIPESTATUS[0]}"
rm -f -- "$ANSWERS"        # normally already deleted by load_answers
exit "$status"
```

- [ ] **Step 8: `mbm-cleanup`:**

```bash
#!/usr/bin/env bash
# Closes a previous install attempt so the installer can start over: a failed
# install leaves the target mounted at /mnt (for inspection) and LUKS open.
#   mbm-cleanup     exit 0 when nothing is left open; the error on stderr if not
set -euo pipefail

MBM_REPO="${MBM_REPO:-/usr/share/slievr-cachy}"
# shellcheck source=SCRIPTDIR/../../../../../../install/profile.sh
source "$MBM_REPO/cachyos/install/profile.sh"

if mountpoint -q /mnt; then umount -R /mnt; fi
if [[ -e "/dev/mapper/$LUKS_NAME" ]]; then cryptsetup close "$LUKS_NAME"; fi
```

- [ ] **Step 9: Trim `mbm.sh`.** Delete `mask_answers` and `parse_networks` with their comments; update the header comment to "Helpers for the live ISO's installer scripts (mbm-probe, mbm-install)". In `test-mbm.sh` delete the `parse_networks` fixture/tests and the `mask_answers` check; keep hostname and `write_answers` tests.

- [ ] **Step 10: Run tests + shellcheck:**
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/iso && bash test-mbm.sh && bash test-probe.sh && shellcheck -x -S warning lib/mbm.sh test-*.sh configs/airootfs/usr/local/bin/mbm-probe configs/airootfs/usr/local/bin/mbm-install configs/airootfs/usr/local/bin/mbm-cleanup'`
Then a real `facts` run in the VM (it's the installed VM, not a live ISO; `live_disk` is empty and that's fine):
`cachyos/vm/vm.sh sudo 'MBM_REPO=/home/slievr/proj/slievr-cachy bash /home/slievr/proj/slievr-cachy/cachyos/iso/configs/airootfs/usr/local/bin/mbm-probe facts | jq .'`
Expected: valid JSON, `disks` lists `/dev/vda` and `/dev/vdb`, `online: true`, `leftover: false`.

- [ ] **Step 11: Commit**

```bash
git add cachyos/iso
git commit -m "iso: mbm-probe/mbm-install/mbm-cleanup, the root side of the graphical installer"
```

(`mbm-configurator` is still present and now broken against the new `mbm-install`; Task 9 deletes it. The ISO isn't built between these tasks.)

---

### Task 7: Installer QML — frame, state, services, dev loop, first four steps

**Files** (all under `cachyos/iso/installer/`):
- Create symlinks: `theme -> ../../../dot-config/quickshell/mbm/theme`, `components -> ../../../dot-config/quickshell/mbm/components`, `services/Net.qml -> ../../../../dot-config/quickshell/mbm/services/Net.qml`, `quicksettings/pickers/WifiPicker.qml -> ../../../../../dot-config/quickshell/mbm/quicksettings/pickers/WifiPicker.qml`
- Create: `shell.qml`, `services/Installer.qml`, `services/Probe.qml`, `services/Xkb.qml`, `services/Zones.qml`, `services/Run.qml` (stub here, full in Task 9), `lib/Validate.js`, `lib/Format.js`, `lib/Progress.js`, `ui/Frame.qml`, `ui/Rail.qml`, `ui/Footer.qml`, `ui/Input.qml`, `ui/SearchList.qml`, `ui/Title.qml`, `steps/Welcome.qml`, `steps/Keyboard.qml`, `steps/Network.qml`, `steps/Region.qml`
- Create: `dev/run.sh`, `dev/facts.json`, `dev/replay.sh`
- Test: `test/tst_validate.qml`

**Interfaces:**
- Produces (singleton `Installer`): `dev`, `repo`, `steps` (array of `{id,title,page}`), `step`, `current`, `indexOf(id)`, answer properties `layout variant timezone username hostname password password2 sameLuks luks luks2 disk confirmText mounts`, derived `facts diskInfo confirmWord dataRows home`, `errors(id)`, `valid(id)`, `err(id, field)`, `show(id)`, `next()`, `back()`, `edit(id)`, `setMount(uuid, on, path)`, `mountError(uuid)`, `answers()`, `terminal`, `openTerminal()`.
- Produces (singleton `Probe`): `facts`, `online`, `refresh()`.
- Produces (singleton `Run`, stub now): `state` (`"idle"`), `start(text)`, `retryDesktop()`, `reboot()`, `cleanup(after)`; Task 9 completes it.
- Produces (`Installer`): `primary()`, the Installing page's main action (reboot / retry desktop / clean up and go to Review), also what Return does on that page.
- Produces (`Validate.js`): `username(u)`, `hostname(h)`, `expand(p, home)`, `mountPath(p, home)` → `""` or a reason.
- Produces (`Progress.js`): `parse(line)` → `null` or `{kind:"stage"|"count"|"fail"|"done", id, n, m}`; `fraction(stages, doneMap, current, n, m)` → 0..1.
- Produces (`ui/Input.qml`): props `label text placeholder error secret`, signal `accepted()`, `focusInput()`.
- Produces (`ui/SearchList.qml`): props `items` (`[{value,label}]`), `value`, `placeholder`; signals `picked(value)`, `accepted()`; `focusInput()`.

Quickshell notes for the implementer: a directory with `pragma Singleton` files works without a `qmldir` (the mbm shell relies on it). Relative imports resolve against the file's path; `dev/run.sh` and the ISO build both copy the tree with `cp -rL`, so the symlinked files sit at real paths where `../../theme` etc. resolve inside `installer/`.

- [ ] **Step 1: Write the failing JS test** `test/tst_validate.qml`:

```qml
import QtQuick
import QtTest
import "../lib/Validate.js" as V
import "../lib/Progress.js" as P

TestCase {
    name: "installer"
    function test_username() {
        verify(V.username("ethan")); verify(V.username("_svc")); verify(V.username("e_b-2"));
        verify(!V.username("Ethan")); verify(!V.username("2e")); verify(!V.username("root"));
        verify(!V.username("systemd-x")); verify(!V.username(""));
    }
    function test_hostname() {
        verify(V.hostname("glaux")); verify(!V.hostname("Glaux")); verify(!V.hostname("-a")); verify(!V.hostname("a.b"));
    }
    function test_mountPath() {
        const h = "/home/ethan";
        compare(V.mountPath("~/storage1", h), "");
        compare(V.mountPath("/data", h), "");
        compare(V.mountPath("/mnt/games", h), "");
        verify(V.mountPath("~", h) !== "");
        verify(V.mountPath("/home/ethan", h) !== "");
        verify(V.mountPath("/home", h) !== "");
        verify(V.mountPath("/mnt", h) !== "");
        verify(V.mountPath("/var/x", h) !== "");
        verify(V.mountPath("storage", h) !== "");
        verify(V.mountPath("/data/", h) !== "");
        verify(V.mountPath("/a/../b", h) !== "");
        verify(V.mountPath("/my disk", h) !== "");
        compare(V.expand("~/s", h), "/home/ethan/s");
        compare(V.expand("/x/~", h), "/x/~");
    }
    function test_progress() {
        compare(P.parse("hello"), null);
        compare(P.parse("@@mbm stage base Base system").id, "base");
        compare(P.parse("@@mbm count 3 40").n, 3);
        compare(P.parse("@@mbm count 3 40").m, 40);
        compare(P.parse("@@mbm fail desktop").kind, "fail");
        compare(P.parse("@@mbm done").kind, "done");
        const ids = ["prepare", "disk", "base", "config", "boot", "desktop", "finish"];
        compare(P.fraction(ids, {}, "", 0, 0), 0);
        compare(P.fraction(ids, { prepare: true, disk: true, base: true, config: true, boot: true, desktop: true, finish: true }, "", 0, 0), 1);
        const half = P.fraction(ids, { prepare: true, disk: true }, "base", 20, 40);
        verify(half > 0.2 && half < 0.3);
    }
}
```

- [ ] **Step 2: Run, expect FAIL** (missing JS files). First confirm the runner exists in the VM:
`cachyos/vm/vm.sh run 'ls /usr/lib/qt6/bin/qmltestrunner'` (if missing: `cachyos/vm/vm.sh sudo 'pacman -S --needed --noconfirm qt6-declarative'`, which is already a quickshell dependency).
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/iso/installer && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input test/tst_validate.qml'`

- [ ] **Step 3: `lib/Validate.js`:**

```js
.pragma library
// Mirrors cachyos/install/lib/answers.sh (valid_username, valid_mount_path) and
// cachyos/iso/lib/mbm.sh (valid_hostname). install-cachyos.sh re-checks all of
// it, so a mismatch fails the install loudly rather than writing a bad system.

const reserved = /^(root|bin|daemon|mail|ftp|http|nobody|dbus|polkitd|git|sddm|systemd-.*)$/;
function username(u) { return /^[a-z_][a-z0-9_-]{0,31}$/.test(u) && !reserved.test(u); }
function hostname(h) { return /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(h); }
function expand(p, home) { return p.replace(/^~(?=\/|$)/, home); }

const system = ["boot", "efi", "usr", "var", "etc", "bin", "sbin", "lib", "lib64", "root", "run", "proc", "sys", "dev", "tmp", "swap"];
// "" when p (absolute, or ~/...) is a usable data mountpoint, else why not.
function mountPath(p, home) {
    const abs = expand(p, home);
    if (!/^\/[A-Za-z0-9._\/-]+$/.test(abs)) return "Use a folder like ~/storage or /data (letters, digits, . _ -)";
    if (/\/\/|\/$|(^|\/)\.\.?(\/|$)/.test(abs)) return "That folder path isn't clean";
    const parts = abs.split("/").slice(1);
    if (system.includes(parts[0])) return "That's a system folder";
    if (parts[0] === "home" && parts.length < 3) return "Pick a folder inside the home folder";
    if (["mnt", "srv", "media", "opt"].includes(parts[0]) && parts.length < 2) return "Pick a folder inside " + abs;
    return "";
}
```

`lib/Format.js`:

```js
.pragma library
function size(bytes) {
    const u = ["B", "KiB", "MiB", "GiB", "TiB"];
    let n = bytes, i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i >= 3 ? n.toFixed(1) : Math.round(n)) + " " + u[i];
}
```

`lib/Progress.js`:

```js
.pragma library
// The installer's @@mbm marker lines (cachyos/install/lib/progress.sh).
function parse(line) {
    const m = /^@@mbm (stage|count|fail|done)(?: (\S+))?(?: (.*))?$/.exec(line);
    if (!m) return null;
    if (m[1] === "count") return { kind: "count", n: parseInt(m[2]), m: parseInt(m[3]) };
    return { kind: m[1], id: m[2] ?? "" };
}
// Rough share of the total time each stage takes; package stages dominate.
const weight = { prepare: 2, disk: 5, base: 35, config: 6, boot: 4, desktop: 43, finish: 5 };
function fraction(ids, done, current, n, m) {
    let total = 0, got = 0;
    for (const id of ids) {
        total += weight[id];
        if (done[id]) got += weight[id];
        else if (id === current) got += weight[id] * (m > 0 ? n / m : 0.1);
    }
    return total ? got / total : 0;
}
```

- [ ] **Step 4: Run, expect PASS** (Step 2 command).

- [ ] **Step 5: Symlinks.** From `cachyos/iso/installer/`:

```bash
ln -s ../../../dot-config/quickshell/mbm/theme theme
ln -s ../../../dot-config/quickshell/mbm/components components
mkdir -p services quicksettings/pickers
ln -s ../../../../dot-config/quickshell/mbm/services/Net.qml services/Net.qml
ln -s ../../../../../dot-config/quickshell/mbm/quicksettings/pickers/WifiPicker.qml quicksettings/pickers/WifiPicker.qml
```

Check: `ls -L theme/Theme.qml components/Button.qml services/Net.qml quicksettings/pickers/WifiPicker.qml` (read-only, fine on the host).

- [ ] **Step 6: Services.** `services/Installer.qml`:

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/Validate.js" as V

// Every answer and the step machine. Steps only read and set these; nothing
// leaves the UI until Review's "Erase and install" hands answers() to mbm-install.
Singleton {
    id: root
    readonly property bool dev: Quickshell.env("MBM_INSTALLER_DEV") === "1"
    readonly property string repo: Quickshell.env("MBM_REPO") || "/usr/share/slievr-cachy"

    readonly property var steps: [
        { id: "welcome", title: "Welcome", page: "Welcome" },
        { id: "keyboard", title: "Keyboard", page: "Keyboard" },
        { id: "network", title: "Network", page: "Network" },
        { id: "region", title: "Region", page: "Region" },
        { id: "account", title: "Account", page: "Account" },
        { id: "disk", title: "Disk", page: "Disk" },
        { id: "data", title: "Data disks", page: "DataDisks" },
        { id: "review", title: "Review", page: "Review" },
        { id: "install", title: "Install", page: "Installing" }
    ]
    function indexOf(id) { return steps.findIndex(s => s.id === id); }
    property int step: 0
    property int returnTo: -1          // Review's Edit: Next/Back come back here
    readonly property string current: steps[step].id

    property string layout: "us"
    property string variant: ""
    property string timezone: ""
    property string username: ""
    property string hostname: ""
    property string password: ""
    property string password2: ""
    property bool sameLuks: true
    property string luks: ""
    property string luks2: ""
    property string disk: ""           // kernel path, e.g. /dev/nvme2n1
    property string confirmText: ""
    property var mounts: ({})          // uuid -> { on, path }

    readonly property var facts: Probe.facts
    readonly property var diskInfo: facts ? (facts.disks.find(d => d.path === disk) ?? null) : null
    // Typed to confirm the erase. Disks without a model (virtio) use their name.
    readonly property string confirmWord: diskInfo ? (diskInfo.model || diskInfo.path.split("/").pop()) : ""
    readonly property var dataRows: facts ? facts.datafs.filter(f => f.disk !== disk) : []
    readonly property string home: "/home/" + (username || "you")

    onDiskChanged: confirmText = ""
    onLayoutChanged: Xkb.apply(layout, variant)
    onVariantChanged: Xkb.apply(layout, variant)
    onFactsChanged: {
        if (!facts) return;
        if (timezone === "") timezone = facts.timezone;
        // Keep choices across a refresh; new filesystems get the profile default
        // (ticked) or the next free ~/storageN (unticked).
        const used = new Set(facts.datafs.map(f => f.mount).filter(p => p));
        const m = {};
        let n = 1;
        for (const f of facts.datafs) {
            if (mounts[f.uuid]) { m[f.uuid] = mounts[f.uuid]; continue; }
            if (f.mount) { m[f.uuid] = { on: true, path: f.mount }; continue; }
            while (used.has("~/storage" + n)) n++;
            used.add("~/storage" + n);
            m[f.uuid] = { on: false, path: "~/storage" + n };
        }
        mounts = m;
    }
    function setMount(uuid, on, path) {
        const m = Object.assign({}, mounts);
        m[uuid] = { on: on, path: path };
        mounts = m;
    }
    function mountError(uuid) {
        const r = mounts[uuid];
        if (!r || !r.on) return "";
        const e = V.mountPath(r.path, home);
        if (e) return e;
        const abs = V.expand(r.path, home);
        const clash = dataRows.some(o => o.uuid !== uuid && mounts[o.uuid]?.on && V.expand(mounts[o.uuid].path, home) === abs);
        return clash ? "Two disks can't share a folder" : "";
    }

    // step id -> { field: message }. Empty object: the step is complete.
    function errors(id) {
        const e = {};
        switch (id) {
        case "welcome":
            if (!facts) e.facts = "Looking at this machine…";
            else if (facts.leftover) e.leftover = "Clean up the previous attempt first";
            break;
        case "keyboard": if (layout === "") e.layout = "Pick a layout"; break;
        case "network": if (!Probe.online) e.net = "Not connected yet"; break;
        case "region": if (timezone === "") e.timezone = "Pick a timezone"; break;
        case "account":
            if (!V.username(username)) e.username = "Start with a lowercase letter; then lowercase letters, digits, _ or -, up to 32";
            if (!V.hostname(hostname)) e.hostname = "Lowercase letters, digits and -, up to 63";
            if (password === "") e.password = "Choose a password";
            else if (password !== password2) e.password2 = "Doesn't match";
            if (!sameLuks) {
                if (luks === "") e.luks = "Choose a passphrase";
                else if (luks !== luks2) e.luks2 = "Doesn't match";
            }
            break;
        case "disk":
            if (!diskInfo) e.disk = "Pick the disk to install to";
            else if (confirmText !== confirmWord) e.confirm = "Type " + confirmWord + " to confirm";
            break;
        case "data":
            for (const r of dataRows) { const m = mountError(r.uuid); if (m) e[r.uuid] = m; }
            break;
        }
        return e;
    }
    function valid(id) { return Object.keys(errors(id)).length === 0; }
    // Errors show once Next has been tried on a step, not while typing the first time.
    property var shown: ({})
    function show(id) { const s = Object.assign({}, shown); s[id] = true; shown = s; }
    function err(id, field) { return shown[id] ? (errors(id)[field] ?? "") : ""; }

    function skipped(i) {
        const id = steps[i].id;
        return (id === "network" && Probe.online) || (id === "data" && dataRows.length === 0);
    }
    function next() {
        if (current === "install") { primary(); return; }
        if (!valid(current)) { show(current); return; }
        if (current === "review") { step = indexOf("install"); Run.start(answers()); return; }
        if (returnTo >= 0) { step = returnTo; returnTo = -1; return; }
        let i = step + 1;
        while (i < steps.length - 1 && skipped(i)) i++;
        step = i;
    }
    function back() {
        if (current === "install") return;
        if (returnTo >= 0) { step = returnTo; returnTo = -1; return; }
        let i = step - 1;
        while (i > 0 && skipped(i)) i--;
        step = Math.max(i, 0);
    }
    function edit(id) { returnTo = step; step = indexOf(id); }
    // The Installing page's main button, also on Return.
    function primary() {
        if (Run.state === "done") Run.reboot();
        else if (Run.state === "desktopFailed") Run.retryDesktop();
        else if (Run.state === "failed") Run.cleanup(() => { Probe.refresh(); step = indexOf("review"); });
    }

    // KEY=value lines for mbm-install, END-terminated (it reads until END).
    function answers() {
        const dm = dataRows.filter(r => mounts[r.uuid]?.on)
                           .map(r => r.uuid + ":" + V.expand(mounts[r.uuid].path, "/home/" + username)).join(",");
        return ["DISK=" + disk, "DISK_CONFIRMED=yes", "HOSTNAME=" + hostname, "TIMEZONE=" + timezone,
                "USERNAME=" + username, "USER_PASSWORD=" + password,
                "LUKS_PASSPHRASE=" + (sameLuks ? password : luks),
                "XKB_LAYOUT=" + layout, "XKB_VARIANT=" + variant, "DATA_MOUNTS=" + dm, "END", ""].join("\n");
    }

    // The installer layer steps aside (Frame.qml) while the terminal is open.
    property bool terminal: false
    function openTerminal() { terminal = true; term.running = true; }
    Process {
        id: term
        command: root.dev ? ["kitty"] : ["foot", "--title", "terminal", "sh", "-c",
            "echo 'A root console is on Ctrl+Alt+F2 (log in as root, no password).'; exec bash -l"]
        onExited: root.terminal = false
    }
}
```

`services/Probe.qml`:

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// mbm-probe's facts, and whether the internet is reachable (rechecked every
// 3 s until it is, so the Network step unlocks by itself).
Singleton {
    id: p
    property var facts: null
    property bool online: false
    function refresh() { factsProc.running = true; }

    Process {
        id: factsProc
        running: true
        command: Installer.dev ? ["cat", Installer.repo + "/cachyos/iso/installer/dev/facts.json"]
                               : ["sudo", "-n", "/usr/local/bin/mbm-probe", "facts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const f = JSON.parse(text); p.facts = f; p.online = f.online; }
                catch (e) { console.warn("mbm-probe facts: " + e); }
            }
        }
    }
    Process {
        id: onlineProc
        command: Installer.dev ? ["true"] : ["sudo", "-n", "/usr/local/bin/mbm-probe", "online"]
        onExited: code => p.online = code === 0
    }
    Timer { interval: 3000; repeat: true; running: !p.online; onTriggered: onlineProc.running = true }
}
```

`services/Xkb.qml`:

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// xkb layouts and variants from xkeyboard-config's rules, and live switching
// (hyprctl) so the chosen layout is what the password fields type.
Singleton {
    id: k
    property var layouts: []        // [{ value, label }]
    property var variants: ({})     // layout -> [{ value, label }]
    FileView {
        path: "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: k.parse(text())
    }
    function parse(t) {
        const L = [], V = {};
        let sec = "";
        for (const line of t.split("\n")) {
            if (line.startsWith("! ")) { sec = line.slice(2).trim(); continue; }
            const m = /^\s+(\S+)\s+(.*)$/.exec(line);
            if (!m) continue;
            if (sec === "layout") L.push({ value: m[1], label: m[1] + "  ·  " + m[2] });
            else if (sec === "variant") {
                const v = /^(\S+):\s*(.*)$/.exec(m[2]);
                if (v) (V[v[1]] = V[v[1]] || []).push({ value: m[1], label: v[2] });
            }
        }
        layouts = L; variants = V;
    }
    function apply(layout, variant) {
        if (Installer.dev) return;      // don't rewire the dev VM's desktop keyboard
        Quickshell.execDetached(["hyprctl", "keyword", "input:kb_layout", layout]);
        Quickshell.execDetached(["hyprctl", "keyword", "input:kb_variant", variant]);
    }
}
```

`services/Zones.qml`:

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: z
    property var zones: []
    property string preview: ""      // local time in the chosen zone
    Process {
        running: true
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: z.zones = text.split("\n").filter(s => s !== "") }
    }
    Process {
        id: clock
        command: ["env", "TZ=" + Installer.timezone, "date", "+%H:%M · %a %d %b"]
        stdout: StdioCollector { onStreamFinished: z.preview = text.trim() }
    }
    Connections { target: Installer; function onTimezoneChanged() { clock.running = true; } }
    Timer { interval: 30000; repeat: true; running: true; triggeredOnStart: true; onTriggered: clock.running = true }
}
```

`services/Run.qml` (stub; Task 9 replaces it):

```qml
pragma Singleton
import Quickshell
import QtQuick

Singleton {
    property string state: "idle"
    function start(text) { state = "running"; }
    function retryDesktop() {}
    function reboot() {}
    function cleanup(after) { if (after) after(); }
}
```

- [ ] **Step 7: UI pieces.** `ui/Title.qml`:

```qml
import QtQuick
import "../theme"
import "../components"

Column {
    property string text
    property string sub
    spacing: 6
    Glyph { text: parent.text; font.pixelSize: 24; font.bold: true }
    Glyph { text: parent.sub; color: Theme.muted; visible: parent.sub !== ""; width: 640; wrapMode: Text.WordWrap }
}
```

`ui/Input.qml`:

```qml
import QtQuick
import "../theme"
import "../components"

// A labelled line of text. `error` shows under it; `secret` hides what's typed
// (eye icon to show it). Return emits accepted() and stops there, so a step
// decides whether Return moves to the next field or the next step.
Column {
    id: f
    property string label
    property alias text: input.text
    property string placeholder
    property string error
    property bool secret: false
    property bool shown: false
    signal accepted()
    spacing: 4
    width: 420
    function focusInput() { input.forceActiveFocus(); }
    Glyph { text: f.label; color: Theme.muted; font.pixelSize: Theme.fontSmall; visible: f.label !== "" }
    Rectangle {
        width: f.width; height: 38; radius: 7; color: Theme.bgRaised
        border.color: f.error !== "" ? Theme.error : input.activeFocus ? Theme.accent : Theme.surface
        TextInput {
            id: input
            anchors { fill: parent; margins: 10; rightMargin: f.secret ? 40 : 10 }
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize
            echoMode: f.secret && !f.shown ? TextInput.Password : TextInput.Normal
            Keys.onReturnPressed: ev => { ev.accepted = true; f.accepted(); }
            Keys.onEnterPressed: ev => { ev.accepted = true; f.accepted(); }
            Text { visible: !parent.text; text: f.placeholder; textFormat: Text.PlainText; color: Theme.muted; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
        }
        Glyph {
            visible: f.secret
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: f.shown ? "󰈉" : "󰈈"; color: Theme.muted
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: f.shown = !f.shown }
        }
    }
    Glyph { text: f.error; color: Theme.error; font.pixelSize: Theme.fontSmall; visible: f.error !== "" }
}
```

`ui/SearchList.qml`:

```qml
import QtQuick
import "../theme"
import "../components"

// A filter box over a long list (layouts, variants, timezones).
// Return picks the first match when the current value isn't among the matches,
// then emits accepted(). Up/Down move the selection.
Column {
    id: s
    property var items: []                 // [{ value, label }]
    property string value
    property string placeholder: "Type to search"
    property int listHeight: 360
    signal picked(string value)
    signal accepted()
    spacing: 8
    width: 520
    readonly property var matches: {
        const q = search.text.toLowerCase();
        return q === "" ? s.items : s.items.filter(i => i.value.toLowerCase().includes(q) || i.label.toLowerCase().includes(q));
    }
    function focusInput() { search.focusInput(); }
    function move(d) {
        const i = s.matches.findIndex(m => m.value === s.value);
        const j = Math.max(0, Math.min(s.matches.length - 1, i + d));
        if (s.matches[j]) { s.picked(s.matches[j].value); list.positionViewAtIndex(j, ListView.Contain); }
    }
    Input {
        id: search; width: s.width; placeholder: s.placeholder
        onAccepted: {
            if (s.matches.length > 0 && !s.matches.some(m => m.value === s.value)) s.picked(s.matches[0].value);
            s.accepted();
        }
        Keys.onUpPressed: s.move(-1)
        Keys.onDownPressed: s.move(1)
    }
    Rectangle {
        width: s.width; height: s.listHeight; radius: Theme.radius; color: Theme.bgRaised; clip: true
        ListView {
            id: list
            anchors { fill: parent; margins: 6 }
            model: s.matches
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: modelData.value === s.value
                width: list.width; height: 30; radius: 6
                color: sel ? Theme.accentSoft : ma.containsMouse ? Theme.surface : "transparent"
                Glyph {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.label; elide: Text.ElideRight
                    color: parent.sel ? Theme.accent : Theme.fg
                }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: s.picked(parent.modelData.value) }
            }
            Component.onCompleted: positionViewAtIndex(Math.max(0, s.matches.findIndex(m => m.value === s.value)), ListView.Center)
        }
    }
}
```

`ui/Rail.qml`:

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"

Rectangle {
    color: Theme.bgRaised
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 36 }
        spacing: 26
        Image {
            source: "file://" + Installer.repo + "/cachyos/branding/owl.svg"
            width: 72; height: 72; sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectFit
        }
        Glyph { text: "made by moonlight"; font.pixelSize: Theme.fontLarge; font.bold: true }
        Column {
            spacing: 12
            Repeater {
                model: Installer.steps
                delegate: Row {
                    required property var modelData
                    required property int index
                    readonly property bool cur: index === Installer.step
                    readonly property bool done: index < Installer.step
                    spacing: 12
                    Glyph { width: 16; text: parent.done ? "󰄬" : parent.cur ? "󰧞" : "·"; color: parent.cur || parent.done ? Theme.accent : Theme.muted }
                    Glyph { text: parent.modelData.title; color: parent.cur ? Theme.accent : parent.done ? Theme.fg : Theme.muted; font.bold: parent.cur }
                }
            }
        }
    }
    Button {
        anchors { left: parent.left; bottom: parent.bottom; margins: 36 }
        text: "󰆍  Terminal"
        onClicked: Installer.openTerminal()
    }
}
```

`ui/Footer.qml`:

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"

Item {
    height: 44
    visible: Installer.current !== "install"
    Row {
        anchors.right: parent.right
        spacing: 10
        Button { text: "Back"; visible: Installer.step > 0; onClicked: Installer.back() }
        Button {
            primary: true
            text: Installer.current === "welcome" ? "Install" : Installer.current === "review" ? "Erase and install" : "Next"
            enabled: Installer.valid(Installer.current) || !Installer.shown[Installer.current]
            onClicked: Installer.next()
        }
    }
}
```

`ui/Frame.qml`:

```qml
import QtQuick
import "../theme"
import "../services"

// Rail + the current step + footer. Return goes forward and Esc back when the
// focused field doesn't take the key itself (Input stops Return).
FocusScope {
    id: frame
    focus: true
    Keys.onReturnPressed: Installer.next()
    Keys.onEnterPressed: Installer.next()
    Keys.onEscapePressed: Installer.back()
    Rail { id: rail; width: 300; anchors { top: parent.top; bottom: parent.bottom; left: parent.left } }
    Item {
        anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 56 }
        Loader {
            id: page
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; bottomMargin: 24 }
            focus: true
            source: "../steps/" + Installer.steps[Installer.step].page + ".qml"
            // The old page's focused field is gone: take focus back so Return/Esc
            // still reach this scope (a page's own focusInput() survives this).
            onLoaded: forceActiveFocus()
        }
        Footer { id: footer; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } }
    }
}
```

- [ ] **Step 8: `shell.qml`:**

```qml
//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "services"
import "theme"
import "ui"

// The made by moonlight installer: one full-screen layer per monitor; the
// first screen gets the installer, the others the owl. Run by the live ISO's
// Hyprland (/etc/mbm-installer/hyprland.conf); dev: dev/run.sh.
ShellRoot {
    settings.watchFiles: Installer.dev
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            readonly property bool main: modelData === Quickshell.screens[0]
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            // Below windows while the terminal is open, so it shows and takes the keyboard.
            WlrLayershell.layer: Installer.terminal ? WlrLayer.Bottom : WlrLayer.Overlay
            WlrLayershell.keyboardFocus: main && !Installer.terminal ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "mbm-installer"
            color: Theme.bg
            Loader { anchors.fill: parent; active: win.main; focus: true; sourceComponent: Component { Frame {} } }
            Image {
                visible: !win.main
                anchors.centerIn: parent
                source: "file://" + Installer.repo + "/cachyos/branding/owl.svg"
                width: 160; height: 160; sourceSize: Qt.size(320, 320); fillMode: Image.PreserveAspectFit
                opacity: 0.6
            }
            Shortcut { sequence: "Ctrl+Q"; enabled: Installer.dev; onActivated: Qt.quit() }
        }
    }
    // Lets tests jump to a step and set answers without a mouse:
    //   qs -p <config> ipc call installer go review
    //   qs -p <config> ipc call installer set username ethan
    IpcHandler {
        target: "installer"
        function go(id: string): void { Installer.step = Installer.indexOf(id); }
        function set(key: string, value: string): void {
            Installer[key] = value === "true" ? true : value === "false" ? false : value;
        }
        function setDisk(path: string): void { Installer.disk = path; Installer.confirmText = Installer.confirmWord; }
        function next(): void { Installer.next(); }
    }
}
```

- [ ] **Step 9: Steps.** `steps/Welcome.qml`:

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"

Column {
    spacing: 18
    Image {
        source: "file://" + Installer.repo + "/cachyos/branding/owl.svg"
        width: 150; height: 150; sourceSize: Qt.size(300, 300); fillMode: Image.PreserveAspectFit
    }
    Glyph { text: "m a d e   b y   m o o n l i g h t"; font.pixelSize: 30; font.bold: true }
    Glyph { text: "CachyOS · Hyprland · encrypted btrfs"; color: Theme.muted }
    Glyph {
        width: 600; wrapMode: Text.WordWrap; color: Theme.fgDim
        text: "This installs made by moonlight on one disk of this computer and erases that disk. Nothing changes until you confirm on the Review page."
    }
    Glyph { visible: !Probe.facts; text: "Looking at this machine…"; color: Theme.muted }
    Rectangle {
        visible: Probe.facts?.leftover ?? false
        width: 600; height: leftCol.implicitHeight + 28; radius: Theme.radius
        color: Theme.bgRaised; border.color: Theme.error
        Column {
            id: leftCol; anchors { fill: parent; margins: 14 }; spacing: 10
            Glyph { width: parent.width; wrapMode: Text.WordWrap; text: "A previous install attempt is still open: its disk is mounted or unlocked." }
            Button { text: "Clean up"; onClicked: Run.cleanup(() => Probe.refresh()) }
        }
    }
}
```

`steps/Keyboard.qml`:

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

Column {
    spacing: 16
    Title { text: "Keyboard"; sub: "Changes right away, so the passwords you type later use it." }
    Row {
        spacing: 16
        SearchList {
            id: layouts
            items: Xkb.layouts; value: Installer.layout; placeholder: "Layout, e.g. gb or German"
            onPicked: v => { Installer.variant = ""; Installer.layout = v; }
            onAccepted: Installer.next()
        }
        SearchList {
            width: 380
            items: [{ value: "", label: "Default" }].concat(Xkb.variants[Installer.layout] ?? [])
            value: Installer.variant; placeholder: "Variant"
            onPicked: v => Installer.variant = v
            onAccepted: Installer.next()
        }
    }
    Input { label: "Try it here"; width: 520; onAccepted: Installer.next() }
    Component.onCompleted: layouts.focusInput()
}
```

`steps/Network.qml`:

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../quicksettings/pickers"

Column {
    spacing: 16
    Title { text: "Network"; sub: "The install downloads packages, so it needs the internet." }
    Glyph { text: Probe.online ? "󰄬  Connected" : "Not connected yet"; color: Probe.online ? Theme.ok : Theme.muted }
    Glyph { text: Net.wired ? "󰈀  Wired: connected" : "󰈂  No wired connection"; color: Theme.fgDim }
    Rectangle {
        width: 560; height: 440; radius: Theme.radius; color: Theme.bgRaised
        WifiPicker { anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 } }
    }
}
```

`steps/Region.qml`:

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

Column {
    spacing: 16
    Title { text: "Region"; sub: "Sets the clock. Type a city or region." }
    SearchList {
        id: z
        items: Zones.zones.map(s => ({ value: s, label: s.replace(/_/g, " ") }))
        value: Installer.timezone; placeholder: "e.g. London"
        onPicked: v => Installer.timezone = v
        onAccepted: Installer.next()
    }
    Glyph { text: Zones.preview ? "Local time there: " + Zones.preview : ""; color: Theme.muted }
    Component.onCompleted: z.focusInput()
}
```

The Account, Disk, DataDisks, Review and Installing pages don't exist yet; for this task create each as a placeholder file containing only

```qml
import QtQuick
import "../ui"
Title { text: "(next task)" }
```

so the Loader never hits a missing file. Task 8/9 replace them.

- [ ] **Step 10: Dev tooling.** `dev/facts.json` (a VM-like machine with a data disk):

```json
{
  "disks": [
    {"path": "/dev/vda", "size": 42949672960, "model": "", "tran": "", "parts": []},
    {"path": "/dev/nvme0n1", "size": 1000204886016, "model": "WD Blue SN570 1TB", "tran": "nvme",
     "parts": [{"path": "/dev/nvme0n1p1", "size": 2147483648, "fstype": "vfat", "label": ""},
               {"path": "/dev/nvme0n1p2", "size": 998056312320, "fstype": "crypto_LUKS", "label": ""}]}
  ],
  "datafs": [
    {"uuid": "ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7", "fstype": "ext4", "label": "", "size": 480102916096, "disk": "/dev/sda", "mount": "~/storage1"},
    {"uuid": "1234-ABCD", "fstype": "exfat", "label": "photos", "size": 64023257088, "disk": "/dev/sdd", "mount": null},
    {"uuid": "55cefb4f-6b27-4dbc-bbf8-5e9120defa26", "fstype": "ext4", "label": "big", "size": 3900000000000, "disk": "/dev/nvme0n1", "mount": "~/storage4"}
  ],
  "ucode": "amd-ucode", "gpu": "vulkan-radeon lib32-vulkan-radeon", "memMiB": 31744, "zramMiB": 8192,
  "swapMiB": 34816, "timezone": "UTC", "online": true, "leftover": false
}
```

`dev/replay.sh`:

```bash
#!/usr/bin/env bash
# Dev stand-in for mbm-install (MBM_INSTALLER_DEV=1): reads the answers the way
# mbm-install does, then replays a short fake install with progress markers.
# Username "fail" fails the Base system stage; "faildesktop" fails the Desktop
# stage with exit 3 (as install-cachyos.sh does), and --desktop-only then works.
set -euo pipefail

stage() { echo "@@mbm stage $1 $2"; echo "== $2 =="; sleep 0.6; }
packages() { local i; for i in $(seq 1 "$1"); do echo "( $i/$1) installing pkg$i"; echo "@@mbm count $i $1"; sleep 0.05; done; }

if [[ "${1:-}" == --desktop-only ]]; then
  stage desktop Desktop; packages 30; stage finish Finish; echo "@@mbm done"; exit 0
fi
user=""
while IFS= read -r line; do
  [[ "$line" == END ]] && break
  [[ "$line" == USERNAME=* ]] && user="${line#USERNAME=}"
  echo "answer: ${line%%=*}"            # keys only: values may be passwords
done
stage prepare Prepare; stage disk "Partition & encrypt"; stage base "Base system"; packages 40
if [[ "$user" == fail ]]; then echo "error: failed to commit transaction (dev)"; echo "@@mbm fail base"; exit 1; fi
stage config Configure; stage boot Bootloader; stage desktop Desktop; packages 60
if [[ "$user" == faildesktop ]]; then echo "bootstrap failed (dev)"; echo "@@mbm fail desktop"; exit 3; fi
stage finish Finish; echo "@@mbm done"
```

`dev/run.sh`:

```bash
#!/usr/bin/env bash
# Dev loop for the installer UI, in the VM's desktop session (never the host):
#   cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/cachyos/iso/installer/dev/run.sh'
# Copies the config with symlinks resolved (as build-iso.sh does) and starts it
# in dev mode: canned facts, a fake install, no keyboard-layout changes.
# Ctrl+Q quits. Drive it with: qs -p /tmp/mbm-installer ipc call installer go <step>
set -euo pipefail

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../.." && pwd)"
pkill -f 'qs -p /tmp/mbm-installer' || true
rm -rf /tmp/mbm-installer
cp -rL "$REPO/cachyos/iso/installer" /tmp/mbm-installer
: > /tmp/mbm-installer.log
# Started by Hyprland, not this SSH login, so it lands in the graphical session.
hyprctl dispatch exec "env MBM_INSTALLER_DEV=1 MBM_REPO=$REPO qs -p /tmp/mbm-installer >/tmp/mbm-installer.log 2>&1" >/dev/null
sleep 3
grep -E 'WARN|ERROR' /tmp/mbm-installer.log | tail -n 40 || true
```

`chmod +x dev/run.sh dev/replay.sh`.

- [ ] **Step 11: Run it and look.** In the VM session:

```bash
cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/cachyos/iso/installer/dev/run.sh'
cachyos/vm/vm.sh shot inst-welcome
cachyos/vm/vm.sh run 'qs -p /tmp/mbm-installer ipc call installer go keyboard'; cachyos/vm/vm.sh shot inst-keyboard
cachyos/vm/vm.sh run 'qs -p /tmp/mbm-installer ipc call installer go network'; cachyos/vm/vm.sh shot inst-network
cachyos/vm/vm.sh run 'qs -p /tmp/mbm-installer ipc call installer go region'; cachyos/vm/vm.sh shot inst-region
```

Open each PNG (`.superpowers/shots/`) with the Read tool. Expected: dark `#171e28` background, rail with owl + amber current step, no QML errors in the run.sh output; keyboard shows two lists (layouts populated); network shows the Wi-Fi list (the VM has no Wi-Fi: "No Wi-Fi adapter" is correct) and "Connected"; region lists zones with UTC selected and a time preview. Fix anything off before moving on. Quit with `cachyos/vm/vm.sh run 'pkill -f "qs -p /tmp/mbm-installer"'`.

- [ ] **Step 12: Commit**

```bash
git add cachyos/iso/installer
git commit -m "iso: installer UI frame, state and the first four steps (Quickshell, reusing the mbm shell's theme and widgets)"
```

---

### Task 8: Installer QML — Account, Disk, Data disks, Review

**Files:**
- Replace placeholders: `cachyos/iso/installer/steps/Account.qml`, `Disk.qml`, `DataDisks.qml`, `Review.qml`
- Modify: `cachyos/iso/installer/test/tst_validate.qml` (confirm-word + answers tests via a tiny harness, below)

**Interfaces:**
- Consumes: `Installer` (Task 7), `Format.size`, `ui/Input`, `ui/Title`, `components/Toggle`, `components/Button`.

- [ ] **Step 1: Write the failing test** for the confirm word and the answers text. These live in `Installer.qml`, which needs the Quickshell runtime, so pull the two pure pieces into `lib/Answers.js` and test them. Add to `tst_validate.qml`:

```qml
import "../lib/Answers.js" as A
// ...inside TestCase:
    function test_confirmWord() {
        compare(A.confirmWord({ path: "/dev/nvme2n1", model: "WD Blue SN570 1TB" }), "WD Blue SN570 1TB");
        compare(A.confirmWord({ path: "/dev/vda", model: "" }), "vda");
        compare(A.confirmWord(null), "");
    }
    function test_answers() {
        const t = A.text({ disk: "/dev/vda", hostname: "glaux", timezone: "Europe/London", username: "ethan",
                           password: "pw one", sameLuks: true, luks: "", layout: "gb", variant: "",
                           mounts: [{ uuid: "u-1", path: "~/storage1" }, { uuid: "u-2", path: "/data" }] });
        compare(t, "DISK=/dev/vda\nDISK_CONFIRMED=yes\nHOSTNAME=glaux\nTIMEZONE=Europe/London\nUSERNAME=ethan\n"
                 + "USER_PASSWORD=pw one\nLUKS_PASSPHRASE=pw one\nXKB_LAYOUT=gb\nXKB_VARIANT=\n"
                 + "DATA_MOUNTS=u-1:/home/ethan/storage1,u-2:/data\nEND\n");
        const own = A.text({ disk: "/dev/vda", hostname: "h", timezone: "UTC", username: "e", password: "a",
                             sameLuks: false, luks: "b", layout: "us", variant: "", mounts: [] });
        verify(own.includes("LUKS_PASSPHRASE=b\n"));
        verify(own.includes("DATA_MOUNTS=\n"));
    }
```

- [ ] **Step 2: Run, expect FAIL** (`Answers.js` missing):
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy/cachyos/iso/installer && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input test/tst_validate.qml'`

- [ ] **Step 3: `lib/Answers.js`** and switch `Installer.qml` to it:

```js
.pragma library
.import "Validate.js" as V

// Typed to confirm the erase. Disks without a model (virtio) use their name.
function confirmWord(d) { return d ? (d.model || d.path.split("/").pop()) : ""; }

// KEY=value lines for mbm-install, END-terminated (it reads until END).
// a.mounts: the ticked data disks, [{ uuid, path }] with path as typed (~ ok).
function text(a) {
    const home = "/home/" + a.username;
    const dm = a.mounts.map(m => m.uuid + ":" + V.expand(m.path, home)).join(",");
    return ["DISK=" + a.disk, "DISK_CONFIRMED=yes", "HOSTNAME=" + a.hostname, "TIMEZONE=" + a.timezone,
            "USERNAME=" + a.username, "USER_PASSWORD=" + a.password,
            "LUKS_PASSPHRASE=" + (a.sameLuks ? a.password : a.luks),
            "XKB_LAYOUT=" + a.layout, "XKB_VARIANT=" + a.variant, "DATA_MOUNTS=" + dm, "END", ""].join("\n");
}
```

In `Installer.qml`: add `import "../lib/Answers.js" as A`; set `confirmWord: A.confirmWord(diskInfo)`; replace the body of `answers()` with

```js
        return A.text({ disk: disk, hostname: hostname, timezone: timezone, username: username,
                        password: password, sameLuks: sameLuks, luks: luks, layout: layout, variant: variant,
                        mounts: dataRows.filter(r => mounts[r.uuid]?.on).map(r => ({ uuid: r.uuid, path: mounts[r.uuid].path })) });
```

- [ ] **Step 4: Run, expect PASS** (Step 2 command).

- [ ] **Step 5: `steps/Account.qml`:**

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

Column {
    spacing: 14
    Title { text: "Account"; sub: "Your login. The root account stays locked; you'll use sudo." }
    Row {
        spacing: 16
        Input {
            id: user; width: 300; label: "Username"; placeholder: "e.g. ethan"
            error: Installer.err("account", "username")
            onTextChanged: Installer.username = text
            onAccepted: host.focusInput()
            Component.onCompleted: text = Installer.username
        }
        Input {
            id: host; width: 300; label: "Computer name"; placeholder: "e.g. glaux"
            error: Installer.err("account", "hostname")
            onTextChanged: Installer.hostname = text
            onAccepted: pw.focusInput()
            Component.onCompleted: text = Installer.hostname
        }
    }
    Row {
        spacing: 16
        Input {
            id: pw; width: 300; label: "Password"; secret: true
            error: Installer.err("account", "password")
            onTextChanged: Installer.password = text
            onAccepted: pw2.focusInput()
            Component.onCompleted: text = Installer.password
        }
        Input {
            id: pw2; width: 300; label: "Password again"; secret: true
            error: Installer.err("account", "password2")
            onTextChanged: Installer.password2 = text
            onAccepted: Installer.sameLuks ? Installer.next() : luks.focusInput()
            Component.onCompleted: text = Installer.password2
        }
    }
    Toggle {
        label: "Use the same password to unlock the disk at boot"
        checked: Installer.sameLuks
        onToggled: c => Installer.sameLuks = c
    }
    Row {
        spacing: 16
        visible: !Installer.sameLuks
        Input {
            id: luks; width: 300; label: "Disk passphrase"; secret: true
            error: Installer.err("account", "luks")
            onTextChanged: Installer.luks = text
            onAccepted: luks2.focusInput()
            Component.onCompleted: text = Installer.luks
        }
        Input {
            id: luks2; width: 300; label: "Disk passphrase again"; secret: true
            error: Installer.err("account", "luks2")
            onTextChanged: Installer.luks2 = text
            onAccepted: Installer.next()
            Component.onCompleted: text = Installer.luks2
        }
    }
    Component.onCompleted: user.focusInput()
}
```

- [ ] **Step 6: `steps/Disk.qml`:**

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt

// Up/Down pick a disk (they reach here from the confirm field, which doesn't use them).
FocusScope {
    id: page
    focus: true
    readonly property var disks: Installer.facts?.disks ?? []
    function move(d) {
        if (disks.length === 0) return;
        const i = disks.findIndex(x => x.path === Installer.disk);
        const j = i < 0 ? 0 : Math.max(0, Math.min(disks.length - 1, i + d));
        Installer.disk = disks[j].path;
        confirm.text = "";
        confirm.focusInput();
    }
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Column {
        spacing: 14
        Title { text: "Disk"; sub: "The disk you pick is erased completely. USB drives and this installer's own stick aren't listed. ↑ ↓ to choose." }
        Repeater {
            model: page.disks
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: Installer.disk === modelData.path
                width: 680; height: col.implicitHeight + 24; radius: Theme.radius
                color: sel ? Theme.accentSoft : Theme.bgRaised
                border.color: sel ? Theme.accent : "transparent"
                Column {
                    id: col; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }; spacing: 4
                    Glyph {
                        font.bold: true
                        text: (modelData.model || modelData.path) + "   " + Fmt.size(modelData.size)
                              + (modelData.tran ? "   " + modelData.tran : "") + "   " + modelData.path
                    }
                    Glyph {
                        width: parent.width; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.fontSmall
                        text: modelData.parts.length === 0 ? "Empty" : modelData.parts.map(p =>
                            p.path.split("/").pop() + " " + (p.fstype || "unknown") + (p.label ? " “" + p.label + "”" : "") + " " + Fmt.size(p.size)).join("    ")
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: { Installer.disk = modelData.path; confirm.text = ""; confirm.focusInput(); } }
            }
        }
        Glyph { text: Installer.err("disk", "disk"); color: Theme.error; visible: text !== "" }
        Rectangle {
            visible: Installer.diskInfo !== null
            width: 680; height: warn.implicitHeight + 28; radius: Theme.radius
            color: Theme.bgRaised; border.color: Theme.error
            Column {
                id: warn; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }; spacing: 10
                Glyph { text: "Everything on " + Installer.confirmWord + " will be erased."; color: Theme.error; font.bold: true }
                Input {
                    id: confirm; width: 420
                    label: "Type " + Installer.confirmWord + " to confirm"
                    error: Installer.err("disk", "confirm")
                    onTextChanged: Installer.confirmText = text
                    onAccepted: Installer.next()
                    Component.onCompleted: text = Installer.confirmText
                }
            }
        }
    }
    Component.onCompleted: if (Installer.diskInfo) confirm.focusInput(); else page.forceActiveFocus()
}
```

- [ ] **Step 7: `steps/DataDisks.qml`:**

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt

Column {
    spacing: 14
    Title {
        text: "Data disks"
        sub: "Tick the disks to mount. They're mounted by UUID at every boot, and a missing disk won't stop the computer starting. Nothing on them is changed."
    }
    Repeater {
        model: Installer.dataRows
        delegate: Row {
            id: row
            required property var modelData
            readonly property var m: Installer.mounts[modelData.uuid] ?? { on: false, path: "" }
            spacing: 16
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: row.m.on
                onToggled: c => Installer.setMount(row.modelData.uuid, c, row.m.path)
            }
            Column {
                width: 300; anchors.verticalCenter: parent.verticalCenter
                Glyph { text: (row.modelData.label || row.modelData.uuid.slice(0, 13)) + "   " + row.modelData.fstype + "   " + Fmt.size(row.modelData.size) }
                Glyph { text: row.modelData.disk; color: Theme.muted; font.pixelSize: Theme.fontSmall }
            }
            Input {
                width: 320; label: "Mount at"; opacity: row.m.on ? 1 : 0.5
                error: Installer.err("data", row.modelData.uuid)
                onTextChanged: Installer.setMount(row.modelData.uuid, row.m.on, text)
                onAccepted: Installer.next()
                Component.onCompleted: text = row.m.path
            }
        }
    }
}
```

- [ ] **Step 8: `steps/Review.qml`:**

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt

Column {
    spacing: 14
    readonly property var f: Installer.facts
    readonly property var ticked: Installer.dataRows.filter(r => Installer.mounts[r.uuid]?.on)
    readonly property var rows: [
        ["Keyboard", Installer.layout + (Installer.variant ? " (" + Installer.variant + ")" : ""), "keyboard"],
        ["Timezone", Installer.timezone, "region"],
        ["Account", Installer.username + "  ·  root locked", "account"],
        ["Computer name", Installer.hostname, "account"],
        ["Disk unlock", Installer.sameLuks ? "Same as your password" : "Its own passphrase", "account"],
        ["Erase", Installer.confirmWord + "  ·  " + (Installer.diskInfo ? Fmt.size(Installer.diskInfo.size) : "") + "  ·  " + Installer.disk, "disk"],
        ["Data disks", ticked.length === 0 ? "None" : ticked.map(r => (r.label || r.uuid.slice(0, 13)) + "  →  " + Installer.mounts[r.uuid].path).join("\n"),
         Installer.dataRows.length > 0 ? "data" : ""],
        ["Microcode", f?.ucode ?? "", ""],
        ["Graphics", f?.gpu || "generic (Mesa)", ""],
        ["Memory", f ? f.memMiB + " MiB  ·  zram " + f.zramMiB + " MiB  ·  hibernate swap " + f.swapMiB + " MiB" : "", ""]
    ]
    Title { text: "Review"; sub: "Nothing has changed yet. Erase and install starts the install." }
    Repeater {
        model: parent.rows
        delegate: Row {
            required property var modelData
            spacing: 16
            Glyph { width: 160; text: modelData[0]; color: Theme.muted }
            Glyph { width: 480; text: modelData[1]; wrapMode: Text.WordWrap; color: modelData[0] === "Erase" ? Theme.error : Theme.fg }
            Glyph {
                visible: modelData[2] !== ""; text: "Edit"; color: Theme.accent
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: Installer.edit(modelData[2]) }
            }
        }
    }
}
```

- [ ] **Step 9: Look at it.** Run the dev loop (Task 7 Step 11), then:

```bash
q() { cachyos/vm/vm.sh run "qs -p /tmp/mbm-installer ipc call installer $*"; }
q go account; cachyos/vm/vm.sh shot inst-account-empty
q set username ethan; q set hostname glaux; q set password pw; q set password2 px
q next; cachyos/vm/vm.sh shot inst-account-errors        # stays on Account: "Doesn't match" under the second field
q set password2 pw
q go disk; cachyos/vm/vm.sh shot inst-disk-none
q setDisk /dev/vda; q go disk; cachyos/vm/vm.sh shot inst-disk-vda
q go data; cachyos/vm/vm.sh shot inst-data
q set disk /dev/nvme0n1; q go data; cachyos/vm/vm.sh shot inst-data-no-nvme
q go review; cachyos/vm/vm.sh shot inst-review
```

Read each PNG. Expected: account fields in two rows, toggle on, errors only in the shot taken after `next`; disk page shows two cards, the vda card's confirm word is `vda` (no model), the red panel appears once selected; data page lists three rows with storage1 ticked at `~/storage1` and photos unticked at `~/storage1`'s next free slot (`~/storage2`); with `/dev/nvme0n1` as the target the `big` row disappears; review shows every row, Erase in red, Edit links. Fix what's off.

- [ ] **Step 10: Commit**

```bash
git add cachyos/iso/installer
git commit -m "iso: installer account, disk, data-disk and review steps"
```

---

### Task 9: Installer QML — Installing, Done, Failed

**Files:**
- Replace: `cachyos/iso/installer/services/Run.qml`, `cachyos/iso/installer/steps/Installing.qml`

**Interfaces:**
- Consumes: `Progress.parse`, `Progress.fraction` (Task 7); `mbm-install`, `mbm-cleanup` (Task 6); `dev/replay.sh`.
- Produces (`Run`): `stages` (`[[id,title]…]`), `state` (`idle|running|done|failed|desktopFailed`), `current`, `doneStages`, `failedStage`, `n`, `m`, `log` (array, last 500 lines), `progress` (0..1), `stageState(id)` (`done|running|failed|waiting`), `start(text)`, `retryDesktop()`, `cleanup(after)`, `reboot()`.

- [ ] **Step 1: `services/Run.qml`:**

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/Progress.js" as P

// Runs mbm-install (or dev/replay.sh), reads its @@mbm markers into stage
// state, keeps the log. Exit 3 = only the Desktop stage failed.
Singleton {
    id: r
    readonly property var stages: [["prepare", "Prepare"], ["disk", "Partition & encrypt"], ["base", "Base system"],
        ["config", "Configure"], ["boot", "Bootloader"], ["desktop", "Desktop"], ["finish", "Finish"]]
    property string state: "idle"
    property string current: ""
    property var doneStages: ({})
    property string failedStage: ""
    property int n: 0
    property int m: 0
    property var log: []
    readonly property real progress: P.fraction(stages.map(s => s[0]), doneStages, current, n, m)
    property string pending: ""          // answers, written once the process has started

    function stageState(id) {
        if (doneStages[id]) return "done";
        if (failedStage === id) return "failed";
        if (current === id && state === "running") return "running";
        return "waiting";
    }
    function mark(id) { if (!id) return; const d = Object.assign({}, doneStages); d[id] = true; doneStages = d; }
    function push(line) { const l = log.concat([line]); log = l.length > 500 ? l.slice(-500) : l; }
    function handle(line) {
        const k = P.parse(line);
        if (!k) { push(line); return; }
        if (k.kind === "stage") { mark(current); current = k.id; n = 0; m = 0; }
        else if (k.kind === "count") { n = k.n; m = k.m; }
        // The installer can only name the stage it set itself; a failure inside the
        // chroot's Bootloader stage arrives as "config", which already looks done.
        else if (k.kind === "fail") failedStage = doneStages[k.id] ? current : k.id;
        else if (k.kind === "done") { mark(current); current = ""; }
    }

    function start(text) {
        state = "running"; current = ""; doneStages = ({}); failedStage = ""; n = 0; m = 0; log = [];
        pending = text;
        proc.command = Installer.dev ? ["bash", Installer.repo + "/cachyos/iso/installer/dev/replay.sh"]
                                     : ["sudo", "-n", "/usr/local/bin/mbm-install"];
        proc.running = true;
    }
    function retryDesktop() {
        state = "running"; failedStage = ""; pending = "";
        proc.command = Installer.dev ? ["bash", Installer.repo + "/cachyos/iso/installer/dev/replay.sh", "--desktop-only"]
                                     : ["sudo", "-n", "/usr/local/bin/mbm-install", "--desktop-only", Installer.username];
        proc.running = true;
    }
    property var afterCleanup: null
    function cleanup(after) {
        afterCleanup = after ?? null;
        cleanProc.running = true;
    }
    function reboot() {
        if (Installer.dev) { Qt.quit(); return; }
        Quickshell.execDetached(["sudo", "-n", "/usr/bin/reboot"]);
    }

    Process {
        id: proc
        stdinEnabled: true
        onStarted: if (r.pending !== "") { write(r.pending); r.pending = ""; }
        stdout: SplitParser { onRead: line => r.handle(line) }
        stderr: SplitParser { onRead: line => r.push(line) }
        onExited: code => {
            r.state = code === 0 ? "done" : code === 3 ? "desktopFailed" : "failed";
            if (code !== 0 && r.failedStage === "") r.failedStage = r.current || "prepare";
        }
    }
    Process {
        id: cleanProc
        command: Installer.dev ? ["true"] : ["sudo", "-n", "/usr/local/bin/mbm-cleanup"]
        stderr: SplitParser { onRead: line => r.push(line) }
        onExited: code => {
            if (code !== 0) { r.push("mbm-cleanup failed (exit " + code + ")"); return; }
            r.state = "idle";
            const f = r.afterCleanup; r.afterCleanup = null;
            if (f) f();
        }
    }
}
```

- [ ] **Step 2: `steps/Installing.qml`:**

```qml
import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

Column {
    id: page
    spacing: 16
    width: 680
    property bool showLog: false
    property int secs: 10
    property bool cancelled: false
    Title {
        text: Run.state === "done" ? "Installed" : Run.state === "running" ? "Installing made by moonlight"
            : Run.state === "desktopFailed" ? "Installed, but the desktop setup failed" : "The install failed"
        sub: Run.state === "running" ? "This takes a while. You can leave it." : Run.state === "idle" ? "" : "Return does the highlighted action."
    }
    Repeater {
        model: Run.stages
        delegate: Row {
            required property var modelData
            readonly property string st: Run.stageState(modelData[0])
            spacing: 12
            Glyph {
                width: 18
                text: parent.st === "done" ? "󰄬" : parent.st === "running" ? "󰔟" : parent.st === "failed" ? "󰅖" : "·"
                color: parent.st === "failed" ? Theme.error : parent.st === "waiting" ? Theme.muted : Theme.accent
            }
            Glyph {
                text: modelData[1] + (parent.st === "running" && Run.m > 0 ? "   " + Run.n + " / " + Run.m + " packages" : "")
                color: parent.st === "waiting" ? Theme.muted : Theme.fg
            }
        }
    }
    Rectangle {
        width: page.width; height: 8; radius: 4; color: Theme.bgRaised
        Rectangle {
            width: parent.width * Run.progress; height: parent.height; radius: 4
            color: Run.state === "failed" ? Theme.error : Theme.accent
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }

    // Done
    Column {
        visible: Run.state === "done"; spacing: 12
        Glyph { text: "Remove the USB stick, then reboot. Unlock the disk and log in."; color: Theme.fgDim }
        Row {
            spacing: 10
            Button { primary: true; text: "Reboot now"; onClicked: Installer.primary() }
            Button { text: "Stay here"; visible: !page.cancelled; onClicked: page.cancelled = true }
        }
        Glyph { visible: !page.cancelled; text: "Rebooting in " + page.secs + " s"; color: Theme.muted }
    }
    Timer {
        interval: 1000; repeat: true
        running: Run.state === "done" && !page.cancelled
        onTriggered: { page.secs -= 1; if (page.secs <= 0) Run.reboot(); }
    }

    // Failed in a base stage: the disk is half-written, start over.
    Row {
        visible: Run.state === "failed"; spacing: 10
        Button { primary: true; text: "Clean up and start over"; onClicked: Installer.primary() }
        Button { text: "Open terminal"; onClicked: Installer.openTerminal() }
    }
    // Failed in Desktop: the system is installed and firstboot can finish it.
    Column {
        visible: Run.state === "desktopFailed"; spacing: 12
        Glyph {
            width: page.width; wrapMode: Text.WordWrap; color: Theme.fgDim
            text: "The system is installed. Retry the desktop setup, or reboot and it finishes on the first boot."
        }
        Row {
            spacing: 10
            Button { primary: true; text: "Retry desktop"; onClicked: Installer.primary() }
            Button { text: "Reboot anyway"; onClicked: Run.cleanup(() => Run.reboot()) }
            Button { text: "Open terminal"; onClicked: Installer.openTerminal() }
        }
    }

    Button {
        visible: Run.state === "running" || Run.state === "done"
        text: page.showLog ? "Hide log" : "Show log"
        onClicked: page.showLog = !page.showLog
    }
    Rectangle {
        visible: page.showLog || Run.state === "failed" || Run.state === "desktopFailed"
        width: page.width; height: 260; radius: Theme.radius; color: Theme.bgRaised; clip: true
        ListView {
            id: logView
            anchors { fill: parent; margins: 10 }
            model: Run.state === "running" || Run.state === "done" ? Run.log : Run.log.slice(-20)
            delegate: Glyph {
                required property var modelData
                width: logView.width; text: modelData; font.pixelSize: Theme.fontSmall; color: Theme.fgDim; elide: Text.ElideRight
            }
            onCountChanged: positionViewAtEnd()
        }
    }
}
```

- [ ] **Step 3: Exercise all three outcomes** with the dev loop (restarting it resets state). `q next` on Review starts the install; on the Installing page `q next` is the primary action (Return does the same).

```bash
q() { cachyos/vm/vm.sh run "qs -p /tmp/mbm-installer ipc call installer $*"; }
setup() { cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/cachyos/iso/installer/dev/run.sh'
          q set username "$1"; q set hostname glaux; q set password pw; q set password2 pw; q setDisk /dev/vda; q go review; }
setup ethan;       q next; sleep 3; cachyos/vm/vm.sh shot inst-running; sleep 6; cachyos/vm/vm.sh shot inst-done
setup fail;        q next; sleep 6; cachyos/vm/vm.sh shot inst-failed
q next; sleep 1;   cachyos/vm/vm.sh shot inst-failed-cleaned        # back on Review, answers kept
setup faildesktop; q next; sleep 10; cachyos/vm/vm.sh shot inst-desktop-failed
q next; sleep 1;   cachyos/vm/vm.sh shot inst-retry-running; sleep 4; cachyos/vm/vm.sh shot inst-retry-done
```

Read the PNGs. Expected: running shows ticks for finished stages, a package count on the current one and the bar moving; done shows the countdown (in dev it ends with `Qt.quit()`, so take the shot within 10 s); failed shows Base system with a red cross, the last log lines and the two buttons, and `q next` lands on Review with the answers still filled in; desktop-failed shows every stage up to Bootloader ticked, Desktop crossed and the three buttons; `q next` then runs the desktop replay to Done.

- [ ] **Step 4: Commit**

```bash
git add cachyos/iso/installer
git commit -m "iso: installer progress, done and failure screens (retry desktop, reboot anyway, start over)"
```

---

### Task 10: Live environment and ISO build

**Files:**
- Modify: `cachyos/iso/configs/packages.extra`
- Create: `cachyos/iso/configs/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf`
- Create: `cachyos/iso/configs/airootfs/home/moonlight/.bash_profile`
- Create: `cachyos/iso/configs/airootfs/etc/sudoers.d/mbm-installer`
- Create: `cachyos/iso/configs/airootfs/etc/polkit-1/rules.d/50-mbm-installer.rules`
- Create: `cachyos/iso/configs/airootfs/etc/mbm-installer/hyprland.conf`
- Delete: `cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator`, `cachyos/iso/configs/airootfs/root/.automated_script.sh`
- Modify: `cachyos/iso/builder/build-iso.sh`
- Modify: `.github/workflows/iso.yml` (test list, shellcheck list)
- Modify: `cachyos/vm/vm.sh` (`type` learns `- / . :`; new `key` command)

**Interfaces:**
- Consumes: everything above. Produces the ISO.

- [ ] **Step 1: Packages.** `packages.extra`: remove `gum`; add (one per line, with a comment line `# graphical installer`):
`hyprland`, `quickshell`, `qt6-svg`, `networkmanager`, `foot`, `ttf-jetbrains-mono-nerd`, `jq`, `sudo`, `polkit`, `xkeyboard-config`.
Check each exists: `pacman -Si hyprland quickshell qt6-svg networkmanager foot ttf-jetbrains-mono-nerd jq sudo polkit xkeyboard-config >/dev/null && echo ok` (read-only, fine on the host).

- [ ] **Step 2: Live session files.**

`etc/systemd/system/getty@tty1.service.d/autologin.conf` (replaces releng's root autologin):

```ini
# The live ISO logs the unprivileged installer user in on tty1; its
# ~/.bash_profile starts Hyprland with the installer. Other ttys stay root
# consoles (no password) for rescue work.
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin moonlight - $TERM
```

`home/moonlight/.bash_profile`:

```bash
# shellcheck shell=bash
# Live ISO, tty1: start the graphical installer. If Hyprland can't start (or
# exits with an error), say so and leave this shell; Ctrl+Alt+F2 is a root
# console. Leaving the installer normally also lands here.
if [[ "$(tty)" == /dev/tty1 && -z "${WAYLAND_DISPLAY:-}" ]]; then
  export MBM_REPO=/usr/share/slievr-cachy
  if ! Hyprland --config /etc/mbm-installer/hyprland.conf >/tmp/hyprland-installer.log 2>&1; then
    echo
    echo "The graphical installer couldn't start."
    echo "  log: /tmp/hyprland-installer.log"
    echo "  a root console is on Ctrl+Alt+F2 (log in as root, no password)"
    echo "  to try again: Hyprland --config /etc/mbm-installer/hyprland.conf"
  fi
fi
```

`etc/sudoers.d/mbm-installer`:

```
# The graphical installer runs as moonlight. These are the only root commands
# it needs (cachyos/iso/configs/airootfs/usr/local/bin/).
moonlight ALL=(root) NOPASSWD: /usr/local/bin/mbm-probe, /usr/local/bin/mbm-install, /usr/local/bin/mbm-cleanup, /usr/bin/reboot
```

`etc/polkit-1/rules.d/50-mbm-installer.rules`:

```js
// The live installer user manages networks (the Wi-Fi picker) without a prompt.
polkit.addRule(function (action, subject) {
    if (subject.user === "moonlight" && action.id.indexOf("org.freedesktop.NetworkManager.") === 0) {
        return polkit.Result.YES;
    }
});
```

`etc/mbm-installer/hyprland.conf`:

```
# made by moonlight live installer session. Hand-written on purpose: one
# client, no binds, nothing a user configures. Port it alongside the mbm
# settings generator when Hyprland 0.57 drops the .conf format.
monitor = , preferred, auto, auto

input {
    kb_layout = us
}

general {
    gaps_in = 0
    gaps_out = 0
    border_size = 0
}

decoration {
    rounding = 0
}

animations {
    enabled = false
}

misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
    background_color = 0x171e28
}

ecosystem {
    no_update_news = true
    no_donation_nag = true
}

# The session ends when the installer does.
exec-once = qs -c mbm-installer; hyprctl dispatch exit
```

Delete `usr/local/bin/mbm-configurator` and `root/.automated_script.sh` (`git rm`).

- [ ] **Step 3: `build-iso.sh`.**
  - In "profile: releng + our overlay", after `cp -rT "$ISO/configs/airootfs" "$PROFILE/airootfs"`, add the user, NM and the installer config:

```bash
# The live installer user (uid 1000). releng ships these four files; refuse to
# build if that changes rather than produce an ISO with no installer user.
for f in passwd shadow group gshadow; do
  [[ -f "$PROFILE/airootfs/etc/$f" ]] || die "releng no longer ships airootfs/etc/$f"
done
echo 'moonlight:x:1000:1000::/home/moonlight:/usr/bin/bash' >> "$PROFILE/airootfs/etc/passwd"
echo 'moonlight:!*:14871::::::'                          >> "$PROFILE/airootfs/etc/shadow"
echo 'moonlight:x:1000:'                                 >> "$PROFILE/airootfs/etc/group"
echo 'moonlight:!*::'                                    >> "$PROFILE/airootfs/etc/gshadow"

# NetworkManager instead of iwd + systemd-networkd: the installer's Wi-Fi
# picker talks to NM (Quickshell.Networking), and the profiles it saves copy
# straight into the installed system.
find "$PROFILE/airootfs/etc/systemd/system" \( -name 'iwd.service' -o -name 'systemd-networkd*' \
  -o -name 'dbus-org.freedesktop.network1.service' \) -print -delete
mkdir -p "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service \
  "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

# The installer UI, symlinks into dot-config/quickshell/mbm resolved (-L).
mkdir -p "$PROFILE/airootfs/etc/xdg/quickshell"
cp -rL "$ISO/installer" "$PROFILE/airootfs/etc/xdg/quickshell/mbm-installer"
```

  - In the `file_permissions+=(` heredoc, replace the `.automated_script.sh` and `mbm-configurator` entries with:

```
  ["/usr/local/bin/mbm-install"]="0:0:755"
  ["/usr/local/bin/mbm-probe"]="0:0:755"
  ["/usr/local/bin/mbm-cleanup"]="0:0:755"
  ["/etc/sudoers.d/mbm-installer"]="0:0:440"
  ["/etc/gshadow"]="0:0:400"
  ["/home/moonlight"]="1000:1000:750"
  ["/home/moonlight/.bash_profile"]="1000:1000:644"
```

  - Delete the `owl.ansi` render step (`mkdir -p .../usr/share/mbm` and the `render-console.py` call): only the configurator used it.
  - Sanity checks: replace the file list with

```bash
for f in usr/share/slievr-cachy/cachyos/install/install-cachyos.sh usr/share/slievr-cachy/.git/HEAD \
         usr/local/bin/mbm-install usr/local/bin/mbm-probe usr/local/bin/mbm-cleanup \
         etc/sudoers.d/mbm-installer etc/mbm-installer/hyprland.conf home/moonlight/.bash_profile \
         etc/xdg/quickshell/mbm-installer/shell.qml etc/xdg/quickshell/mbm-installer/theme/Theme.qml \
         etc/xdg/quickshell/mbm-installer/components/Button.qml etc/xdg/quickshell/mbm-installer/services/Net.qml \
         etc/xdg/quickshell/mbm-installer/quicksettings/pickers/WifiPicker.qml etc/pacman.conf; do
  [[ -s "$PROFILE/airootfs/$f" ]] || die "missing or empty airootfs/$f"
done
if find "$PROFILE/airootfs/etc/xdg/quickshell/mbm-installer" -type l | grep -q .; then
  die "installer config still has symlinks (cp -rL should have resolved them)"
fi
grep -q '^moonlight:' "$PROFILE/airootfs/etc/passwd" || die "no moonlight user"
[[ -e "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]] || die "NetworkManager not enabled"
```

  - After `mkarchiso`, print the size so the 2 GiB limit is visible: `du -h "$OUT"/*.iso`.

- [ ] **Step 4: CI.** In `.github/workflows/iso.yml`: add `cachyos/install/test-progress.sh cachyos/install/test-desktop.sh cachyos/iso/test-probe.sh` to the unit-test loop; in the shellcheck `git ls-files` list replace `'cachyos/iso/configs/airootfs/root/.automated_script.sh'` with `'cachyos/iso/configs/airootfs/home/moonlight/.bash_profile'`. (`cachyos/*.sh` already matches `installer/dev/*.sh`.) The `test-desktop.sh` `--desktop-only` check needs no root, so it runs in CI.

- [ ] **Step 5: `vm.sh`.** In `type`, add cases before `*)`:

```bash
        -) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_MINUS >/dev/null ;;
        /) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_SLASH >/dev/null ;;
        .) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_DOT >/dev/null ;;
        :) $VIRSH send-key "$VM_NAME" --holdtime 40 KEY_LEFTSHIFT KEY_SEMICOLON >/dev/null ;;
```

and a new command (plus its line in the usage comment):

```bash
  key)
    # Send keys without typing text, e.g. vm.sh key KEY_DOWN, vm.sh key KEY_LEFTCTRL KEY_LEFTALT KEY_F2
    shift; $VIRSH send-key "$VM_NAME" --holdtime 40 "$@" >/dev/null ;;
```

- [ ] **Step 6: Static checks in the VM:**
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'cd ~/proj/slievr-cachy && shellcheck -x -S warning cachyos/iso/builder/build-iso.sh cachyos/vm/vm.sh cachyos/iso/configs/airootfs/home/moonlight/.bash_profile cachyos/iso/installer/dev/*.sh cachyos/iso/configs/airootfs/usr/local/bin/* && visudo -cf cachyos/iso/configs/airootfs/etc/sudoers.d/mbm-installer'`

- [ ] **Step 7: Commit** (the ISO must be built from committed HEAD; `slievr-iso-make` ignores uncommitted changes):

```bash
git add -A cachyos/iso cachyos/vm/vm.sh .github/workflows/iso.yml
git commit -m "iso: live session runs the graphical installer (moonlight user, Hyprland, NetworkManager); gum configurator removed"
```

- [ ] **Step 8: Build.** `cachyos/iso/bin/slievr-iso-make`. Expected: `step "done: release/made-by-moonlight-*.iso"`, the `du` line under 2 GiB. If it's over, report the size and stop (don't trim packages without asking).

---

### Task 11: End to end in the VM, verify, docs

**Files:**
- Modify: `cachyos/iso/test/verify-install.sh`
- Modify: `cachyos/iso/README.md`, `README.md` (if it describes the configurator), `AGENTS.md` (roadmap row D)

- [ ] **Step 1: Extend `verify-install.sh`.** Replace the `firstboot finished bootstrap` check with:

```bash
is "desktop installed before reboot"   1      "$(sudo grep -c 'Bootstrap complete.' /var/log/mbm-install.log 2>/dev/null)"
is "firstboot done-guard present"      yes    "$([[ -e /var/lib/slievr-firstboot-done ]] && echo yes || echo no)"
is "console layout in vconsole.conf"   yes    "$(grep -q '^XKBLAYOUT=' /etc/vconsole.conf && echo yes || echo no)"
```

and before `exit $bad` add the optional checks, driven by env vars the test run sets:

```bash
# VERIFY_LAYOUT=gb: the installer's keyboard choice reached the user's settings.
if [[ -n "${VERIFY_LAYOUT:-}" ]]; then
  is "settings kbLayout"               "$VERIFY_LAYOUT" "$(jq -r '.input.kbLayout' "$HOME/.config/mbm/settings.json" 2>/dev/null)"
  is "vconsole XKBLAYOUT"              "XKBLAYOUT=$VERIFY_LAYOUT" "$(grep '^XKBLAYOUT=' /etc/vconsole.conf)"
fi
# VERIFY_DATA_MOUNT=~/testdata: the data disk is in fstab and mounts on access.
if [[ -n "${VERIFY_DATA_MOUNT:-}" ]]; then
  d="${VERIFY_DATA_MOUNT/#\~/$HOME}"
  is "data disk in fstab (nofail, automount)" 1 "$(grep -c " $d ext4 defaults,nofail,x-systemd.automount" /etc/fstab)"
  ls "$d" >/dev/null 2>&1
  is "data disk mounts on access"       yes   "$(findmnt -n "$d" -t ext4 >/dev/null && echo yes || echo no)"
fi
```

(The mounted ext4's own root directory is root-owned after `mkfs`, so ownership isn't checked here; `add_data_mounts` chowns the folder underneath, which the mount covers.)

- [ ] **Step 2: Fresh VM from the ISO.**

```bash
cachyos/vm/destroy-vm.sh
cachyos/iso/bin/slievr-iso-boot    # leave it running in another terminal; it waits for the install to power off
```

Wait for the live session (~60 s), then `virsh -c qemu:///system screenshot cachyos-test .superpowers/shots/live-welcome.png` and Read it. Expected: the installer's Welcome page on a `#171e28` background, no Hyprland notification or config-error bar. If Hyprland shows a config error for `ecosystem` or `background_color`, remove that option from `hyprland.conf`, recommit, rebuild (Task 10 Step 8) and start this step again.

- [ ] **Step 3: Data disk, and the session's own failure path.** Switch to tty2, log in as root, format the VM's second disk with the UUID `profile.sh` knows, then kill the installer so its facts are re-read on restart:

```bash
cachyos/vm/vm.sh key KEY_LEFTCTRL KEY_LEFTALT KEY_F2
cachyos/vm/vm.sh type root
cachyos/vm/vm.sh type 'mkfs.ext4 -F -U 00000000-0000-4000-8000-00000000da7a /dev/vdb'
cachyos/vm/vm.sh type 'pkill qs'
cachyos/vm/vm.sh key KEY_LEFTCTRL KEY_LEFTALT KEY_F1
```

Screenshot tty1. Expected: Hyprland exited with qs (status 0, so no error text) and tty1 shows a bash prompt as moonlight, not a crash loop. Restart it: `cachyos/vm/vm.sh type 'Hyprland --config /etc/mbm-installer/hyprland.conf'`. Expected: Welcome again.

- [ ] **Step 4: Drive the install by keyboard**, screenshotting each page (`virsh … screenshot` as above, then Read):

```bash
cachyos/vm/vm.sh key KEY_ENTER                 # Welcome -> Keyboard
cachyos/vm/vm.sh type gb                       # filter "gb", Enter picks it -> next (Network skipped: online) -> Region
cachyos/vm/vm.sh key KEY_ENTER                 # Region: UTC -> Account
cachyos/vm/vm.sh type slievr; cachyos/vm/vm.sh type glaux
cachyos/vm/vm.sh type TestPass1; cachyos/vm/vm.sh type TestPass1   # -> Disk
cachyos/vm/vm.sh key KEY_DOWN                  # selects /dev/vda, focus to confirm
cachyos/vm/vm.sh type vda                      # -> Data disks
cachyos/vm/vm.sh key KEY_ENTER                 # testdata pre-ticked at ~/testdata -> Review
cachyos/vm/vm.sh key KEY_ENTER                 # Erase and install
```

Note the `gb` layout applies live: from here `vm.sh type` sends keycodes, and `TestPass1`, `slievr`, `glaux`, `vda` are identical on us and gb layouts, so the typing stays correct. Screenshot the Installing page every few minutes; expected: stages tick in order, package counts during Base system and Desktop, Done at the end. The install powers off at reboot and `slievr-iso-boot` boots the installed system.

- [ ] **Step 5: Verify the installed system.** Unlock and log in: `cachyos/vm/vm.sh type TestPass1` (LUKS; the console keymap is `uk`, same keys for this string), wait ~20 s, screenshot: expected the SDDM login, **not** a firstboot text console. `cachyos/vm/vm.sh type TestPass1` to log in, then `cachyos/vm/dev-up.sh` for key auth, then:

```bash
cachyos/vm/vm.sh sync
cachyos/vm/vm.sh run 'VERIFY_LAYOUT=gb VERIFY_DATA_MOUNT=~/testdata bash ~/proj/slievr-cachy/cachyos/iso/test/verify-install.sh'
```

`verify-install.sh` uses `sudo`, which needs the password: run it as `cachyos/vm/vm.sh run 'printf "%s\n" TestPass1 | sudo -S -v && VERIFY_LAYOUT=gb …'` if the plain form prompts. Expected: all PASS. Also run `verify-shell.sh` (`cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/cachyos/iso/test/verify-shell.sh'`): all PASS.

- [ ] **Step 6: Desktop-failure path, Retry desktop.** Fresh VM (Step 2), skip the data disk, drive to Review as in Step 4 and start the install. From the host, find the VM's interface (`virsh -c qemu:///system domiflist cachyos-test`, the `vnetN` name) and screenshot every minute; once the Installing page shows Desktop running, cut the link:

```bash
virsh -c qemu:///system domif-setlink cachyos-test vnetN down
```

Expected within a few minutes (three bootstrap attempts, 30 s apart): "Installed, but the desktop setup failed", Desktop crossed, three buttons. Restore the link (`… domif-setlink cachyos-test vnetN up`), wait ~10 s for NM to reconnect, then `cachyos/vm/vm.sh key KEY_ENTER` (Retry desktop). Expected: Desktop and Finish complete, Done, the reboot lands on SDDM, and Step 5's `verify-install.sh` passes.

- [ ] **Step 7: Desktop-failure path, Reboot anyway.** Repeat Step 6 up to the failure screen, then power the VM off instead of retrying (`virsh -c qemu:///system destroy cachyos-test`; the still-waiting `slievr-iso-boot` boots the installed system) and restore the link. Expected: after the LUKS unlock, tty1 shows `slievr first-boot bootstrap`, it completes and SDDM starts. `verify-install.sh` then fails only `desktop installed before reboot` (correct: firstboot did it) and passes the rest. This proves the firstboot fallback still works.

- [ ] **Step 8: Docs.**
  - `cachyos/iso/README.md`: the intro says it boots into a graphical installer (Quickshell under Hyprland, live user `moonlight`, root consoles on other ttys); "Test" replaces the `mbm-configurator --dry-run` line with the dev loop (`installer/dev/run.sh`, IPC `go`/`set`) and adds `test-probe.sh`; the Layout table lists `installer/`, `lib/probe.jq`, `mbm-probe`, `mbm-install`, `mbm-cleanup`, `configs/airootfs/home/moonlight`, `etc/mbm-installer/hyprland.conf`.
  - `README.md`: wherever it mentions the TUI configurator, say graphical installer.
  - `AGENTS.md` roadmap row D: `done (branch graphical-installer): spec + plan in docs/superpowers/` (set to "merged" only when it is).
  - Spec status line: `implemented (see plan)`.

- [ ] **Step 9: Commit**

```bash
git add cachyos/iso/test/verify-install.sh cachyos/iso/README.md README.md AGENTS.md docs/superpowers/specs/2026-10-16-graphical-installer-design.md cachyos/vm/vm.sh
git commit -m "docs: graphical installer verified end to end in the VM; roadmap D done"
```
