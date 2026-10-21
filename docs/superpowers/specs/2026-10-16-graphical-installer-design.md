# Graphical installer (roadmap D) — design

**Date:** 2026-10-16
**Status:** implemented (see plan)
**Branch:** `graphical-installer`

## Problem

The ISO boots to `mbm-configurator`, a `gum` TUI on tty1: five text screens,
then `mbm-install` runs `install-cachyos.sh --answers` and shows its raw log.
After the reboot, `slievr-firstboot.service` runs `bootstrap.sh` on a text
console for another long stretch before SDDM appears. It works, but it looks
nothing like the desktop it installs, gives no sense of progress, has no
keyboard layout choice, a fragile Wi-Fi path (`iwctl`), and data disks come
from verbatim fstab lines in `profile.sh` tied to one username.

The user migrates their main PC with this next, so it has to be both nicer and
dependable on that machine (Radeon RX 9070 + Raphael iGPU, root on
`nvme2n1`, four ext4 data disks that must mount permanently).

## Goals

- A **graphical installer** on the ISO: Quickshell under a minimal Hyprland,
  built from the mbm shell's `theme/` and `components/`, so it looks like the
  desktop.
- A **smoother flow**: back navigation everywhere, inline validation,
  keyboard layout (live), graphical Wi-Fi, a data-disk review, a review page
  with jump-to-edit, and a live progress screen.
- **Permanent data-disk mounts** chosen in the installer: UUID fstab entries
  with `nofail`, mounted on every boot with no manual
  remounting, never blocking boot when a disk is missing.
- **The desktop is installed before the reboot**: `bootstrap.sh` runs in the
  chroot as the user, so the first boot lands on SDDM. firstboot stays as the
  fallback.
- The bash install logic (`install-cachyos.sh`, `lib/`) stays the backend.

## Non-goals

- A TUI fallback. The user chose graphical only; if Hyprland cannot start,
  tty1 shows the log path and a shell. The `gum` configurator is removed.
- Project C (theme). The installer uses `theme/Theme.qml` as it is today.
- Dual-boot, manual partitioning, choosing filesystems or encryption off.
  The disk layout is unchanged.
- Locale choice (stays `profile.sh`'s `LOCALE`). Timezone auto-detection.
- Formatting data disks. The review only mounts what is already there.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Compositor | Minimal Hyprland | Live layout switching (`hyprctl keyword input:kb_layout`), sane multi-monitor, same compositor as the target. cage reads XKB once at start. |
| UI | New Quickshell config `mbm-installer`, reusing `mbm/theme` + `mbm/components` | One look, no duplicated widgets |
| Backend | Existing bash installer + a JSON probe | Keeps tested logic; QML only collects answers and shows progress |
| Privilege | Unprivileged live user `moonlight`; a sudoers rule for four commands | Quickshell/Hyprland don't run as root; the root surface stays tiny |
| Network | NetworkManager in the live env (replaces iwd + systemd-networkd) | The shell's `Net` service and `WifiPicker` use `Quickshell.Networking`, which needs NM; Wi-Fi profiles copy straight to the target |
| Fallback | None (graphical only) | User's call |
| Desktop | `bootstrap.sh` in the chroot before reboot | One progress screen; first boot lands on SDDM |
| Data disks | Detected in the installer, defaults from `profile.sh` | Works on any machine and any username |
| Live Hyprland config | One small hand-written `hyprland.conf` on the ISO | ~10 lines, no binds; listed in the 0.57 migration risk below |

## Naming

The distro is **fledge**: the ISO is `fledge-<date>-x86_64.iso`, the boot
menu says "fledge installer" and the installer's title is "fledge". "made by
moonlight" is the org byline under it (rail, Welcome), never the distro name.

## User flow

Full-screen window on every monitor; the UI lives on the focused/primary one,
others show the wallpaper owl. Layout: a left rail (owl, wordmark, step list:
current step amber, finished steps ticked) and the step panel, with a footer
**Back** / **Next**. Next is disabled until the step is valid; errors show
inline under the field. Enter = Next, Esc = Back. A small terminal button in
the rail opens `foot`.

1. **Welcome**: owl, "made by moonlight", one line on what happens, **Install**.
2. **Keyboard**: searchable xkb layout list (+ variant), default `us`;
   applied live via `hyprctl`; a "type here to test" field.
3. **Network**: in the rail always, auto-skipped when already online. Wired
   status line + the shell's `WifiPicker` (signal, lock, password). Next
   unlocks when `mbm-probe online` succeeds.
4. **Region**: searchable timezone list (from `/usr/share/zoneinfo`), default
   `profile.sh`'s `TIMEZONE`, local time preview.
5. **Account**: username, hostname, password + confirm (show toggle),
   "use the same passphrase to unlock the disk" (on by default; off reveals
   passphrase + confirm). Validated with `valid_username` / `valid_hostname`
   rules, mirrored in JS and re-checked by `install-cachyos.sh`.
6. **Disk**: a card per installable disk (model, size, transport, existing
   partitions + labels). USB disks and the ISO's own device are hidden.
   Selecting one shows a red panel "Everything on *<model>* will be erased"
   with one **Erase this disk** button (Return presses it), which confirms
   and moves on. No typed confirmation: the Review page names the disk
   again before anything is written.
7. **Data disks**: every filesystem on the *other* disks (swap, LUKS, the
   ESP and anything on the target disk excluded): checkbox, label, fstype,
   size, editable mountpoint. Rows whose UUID is in `profile.sh`'s
   `DATA_DISKS` map are pre-ticked with that mountpoint; others are unticked
   with `~/storageN` suggested. Mountpoints must be absolute or start with
   `~/`, unique, and not a system path (`/`, `/boot`, `/home`, `/usr`, `/var`,
   …). Note: "Mounted at every boot by UUID; a missing disk won't stop boot."
   Skipped automatically when there is nothing to show.
8. **Review**: every answer plus detected microcode, GPU, memory, zram and
   hibernate swap. Each row has **Edit**, jumping to its step and back.
   Button: **Erase and install**.
9. **Installing**: stage list with state icons, an overall bar, a collapsible
   live log. No Back.
   Stages: Prepare · Partition & encrypt · Base system (n/m packages) ·
   Configure · Bootloader · Desktop (n/m packages) · Finish.
10. **Done**: "Remove the USB stick", **Reboot now**, a cancellable 10 s
    countdown.
    **Failed** (base stages): failed stage, last 20 log lines, **Clean up and
    start over** (back to Review, answers kept in memory), **Open terminal**.
    **Failed** (Desktop stage only): the system is installed; **Retry desktop**
    or **Reboot anyway** (firstboot retries on first boot), plus **Open
    terminal**.

## Architecture

```
tty1 autologin (moonlight) ─► Hyprland (live conf) ─► qs -c mbm-installer
                                                         │
                    sudo mbm-probe  ◄──── JSON ──────────┤
                    sudo mbm-install <answers> ── stdout ─┤  @@mbm lines + log
                    sudo mbm-cleanup / reboot ────────────┘
mbm-install ─► install-cachyos.sh --answers  (MBM_PROGRESS=1)
              └─► stage "desktop": arch-chroot runuser -l <user> bootstrap.sh
```

### Live environment (`cachyos/iso/configs/`)

- `packages.extra` adds: `hyprland`, `quickshell`, `qt6-svg`,
  `networkmanager`, `foot`, `ttf-jetbrains-mono-nerd`, `jq`, and anything the
  reused components import. `gum` is dropped.
- releng's root autologin on tty1 is replaced by a `moonlight` user
  (no password, groups `video input`) autologged in on tty1 (getty drop-in).
  Its `~/.bash_profile` on tty1 runs `Hyprland -c /etc/mbm-installer/hyprland.conf`
  and, if it exits non-zero, prints the log path and leaves a shell.
- `/etc/sudoers.d/mbm-installer`: `moonlight` may run, as root with no
  password, exactly `/usr/local/bin/mbm-probe`, `/usr/local/bin/mbm-install`,
  `/usr/local/bin/mbm-cleanup`, `/usr/bin/reboot`. Other tty logins are still
  root (rescue use).
- polkit rule: `moonlight` may use `org.freedesktop.NetworkManager.*`.
- NetworkManager enabled; `iwd.service`, `systemd-networkd`,
  `systemd-resolved` integration from releng disabled. NM uses its default
  wpa_supplicant backend.
- `/etc/mbm-installer/hyprland.conf`: no binds; sets `input:kb_layout = us`,
  turns off animations and `misc:disable_hyprland_logo`, and runs
  `exec-once = qs -c mbm-installer; hyprctl dispatch exit` so Hyprland ends
  when the installer does.
- The palette console script (`.automated_script.sh`) is removed; Plymouth
  is not on the ISO, so tty1 shows plain text only for the instant before
  Hyprland.

### Quickshell config (`cachyos/iso/installer/`)

Installed on the ISO at `/etc/xdg/quickshell/mbm-installer/` (system config
path, so `qs -c mbm-installer` finds it). In the repo, `theme` and
`components` are symlinks to `../../../dot-config/quickshell/mbm/{theme,components}`;
`build-iso.sh` copies with `cp -rL` so the ISO has real files. It does **not**
live under `dot-config/`, so it is never stowed onto a desktop.

```
cachyos/iso/installer/
  shell.qml            PanelWindow per screen, the step host
  Installer.qml        state singleton: answers, step index, validation
  steps/               Welcome Keyboard Network Region Account Disk DataDisks Review Installing Done
  services/Probe.qml   runs `sudo mbm-probe`, exposes the JSON
  services/Run.qml     runs `sudo mbm-install`, parses @@mbm lines, keeps the log
  services/Net.qml     symlink to mbm/services/Net.qml
  pickers/WifiPicker.qml  symlink to mbm/quicksettings/pickers/WifiPicker.qml
  Validate.js          username/hostname/mountpoint rules (mirrors bash)
  theme -> …  components -> …
```

Passwords live only in QML memory until `mbm-install` is started; the answers
file is written by `mbm-install` itself from stdin (see below), never by QML.

### `mbm-probe` (new, `cachyos/iso/configs/airootfs/usr/local/bin/`)

Root, bash, sources `profile.sh` and `lib/detect.sh`. Subcommands print JSON
(built with `jq -n`):

- `mbm-probe facts`: `{ disks: [{kname, byid, model, size, tran, parts:[…]}],
  datafs: [{uuid, fstype, label, size, disk, mount}], ucode, gpu,
  memMiB, zramMiB, swapMiB, timezone, online }`.
  `disks` = `list_disks` minus USB and the boot device; `datafs` = `blkid`
  filesystems of type ext4/btrfs/xfs/ntfs/exfat/vfat, minus ESPs (GPT type
  EF00) and swap/LUKS; `mount` = the `DATA_DISKS` default or `null`.
- `mbm-probe online`: exit 0/1 (`mbm_online` from today's `lib/mbm.sh`).

The QML side filters `datafs` to drop anything on the chosen target disk.

### Answers (`lib/answers.sh`)

`mbm-install` reads the answers on **stdin** (QML writes them to the process),
writes `/run/mbm-answers.env` mode 600 itself, and passes it on. New keys:

| Key | Format | Used by |
|---|---|---|
| `XKB_LAYOUT` | xkb layout, e.g. `gb` or `us,de` | `vconsole.conf` `XKBLAYOUT=`; user's `~/.config/mbm/settings.json` `input.kbLayout` |
| `XKB_VARIANT` | optional | `vconsole.conf` `XKBVARIANT=`; `input.kbVariant` (added to the schema + generator if missing) |
| `DATA_MOUNTS` | `uuid:/abs/path` comma-separated, `~` already expanded; may be empty | fstab + mountpoint creation |

Validated in `install-cachyos.sh` like the existing keys: layout against
`/usr/share/X11/xkb/rules/base.lst`, each UUID present in `blkid`, each path
absolute, unique, not a system path, no `,` `:` or whitespace.

`KEYMAP` in `vconsole.conf` is replaced by `XKBLAYOUT`/`XKBVARIANT`
(systemd-vconsole-setup derives the console map; `sd-vconsole` in the
initramfs gives the LUKS prompt the same layout).

### Data disks (`profile.sh`, `install-cachyos.sh`)

`EXTRA_FSTAB_ENTRIES` is replaced by a defaults map:

```bash
# Per-machine, optional: data filesystems to pre-select in the installer,
# uuid -> mountpoint (~ = the new user's home). Mounted permanently by UUID.
DATA_DISKS=(
  "ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7:~/storage1"
  …
)
```

`install-cachyos.sh` writes, per `DATA_MOUNTS` entry,
`UUID=<uuid> <path> <fstype> defaults,nofail,x-systemd.device-timeout=10 0 0`
(fstype from `blkid`; ntfs → `ntfs3`, vfat/exfat get `uid=,gid=` of the
user), creates the mountpoint in the target and chowns it (and, for paths in
the user's home, its parents up to home) to the user. A pure
`fstab_line <uuid> <fstype> <path> <uid> <gid>` in `lib/detect.sh` is unit
tested. `filter_fstab_entries` and its tests go.

Without `--answers` (manual run), all present `DATA_DISKS` are used, as
`EXTRA_FSTAB_ENTRIES` were.

### Progress protocol

With `MBM_PROGRESS=1`, `install-cachyos.sh` and `bootstrap.sh` print, on
stdout, lines of exactly:

```
@@mbm stage <id> <title…>      a stage starts (ids: prepare disk base config boot desktop finish)
@@mbm count <n> <m>            within-stage progress (optional)
@@mbm fail <id>                the stage failed (before a non-zero exit)
@@mbm done                     everything succeeded
```

`rule` in `install-cachyos.sh` maps its headings onto these ids. Package
counts come from a filter in `mbm-install` that watches pacstrap/pacman/paru
`( n/m) installing` lines and emits `@@mbm count`. Everything (markers
included) is appended to `/var/log/mbm-install.log`; QML hides marker lines
from the visible log. Without `MBM_PROGRESS`, output is unchanged.

### Desktop stage (`install-cachyos.sh`)

After the repo is staged and before unmounting:

1. Drop `/mnt/etc/sudoers.d/99-mbm-install` (`<user> ALL=(ALL) NOPASSWD:ALL`).
2. Copy NM profiles (`/etc/NetworkManager/system-connections/*`) to the
   target (replaces `install_wifi_profiles` from iwd); `resolv.conf` comes
   from `arch-chroot`.
3. `arch-chroot /mnt runuser -l <user> -c 'MBM_PROGRESS=1 ~/proj/slievr-cachy/cachyos/bootstrap.sh'`,
   up to 3 attempts with `pacman -Syy` between (same as firstboot).
4. Remove the sudoers drop-in (trap, so it goes on failure too).
5. Success: `systemctl disable slievr-firstboot.service`, touch
   `/var/lib/slievr-firstboot-done`, `systemctl enable sddm.service` (bootstrap
   already enables it), copy the install log to `/mnt/var/log/`, unmount,
   close LUKS, `@@mbm done`.
   Failure: `@@mbm fail desktop`, exit **3**, leave `/mnt` mounted and LUKS
   open. firstboot stays enabled.

`mbm-install --desktop-only` re-runs steps 1–5 against the still-mounted
target (**Retry desktop**). `mbm-cleanup` unmounts `/mnt` and closes LUKS
(**Reboot anyway**, **Clean up and start over**, and a leftover attempt at
startup, replacing `cleanup_previous`).

`bootstrap.sh` changes needed for the chroot (checked during implementation,
each already guarded or harmless):

- `systemctl enable --now pkgfile-update.timer`: inside a chroot the start is
  skipped; the timer runs on the next boot. Keep, verify the exit status.
- `pkgfile -u` needs network only; fine.
- AUR builds via `paru` as the user: fine in `arch-chroot` (`/dev`, `/proc`
  bind-mounted). `paru` needs `--noconfirm` everywhere (already).
- Emits `@@mbm count` via the shared filter only; no other changes expected.

## Removed

- `cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator`, the `gum`
  half of `mbm-install`, `root/.automated_script.sh`, `gum` from
  `packages.extra`.
- `lib/mbm.sh` shrinks to what `mbm-probe` uses (`list_disks`, `disk_by_id`,
  `mbm_online`, `valid_hostname`); `parse_networks`, `mask_answers`,
  `write_answers` go with their tests if unused.
- `install_wifi_profiles` (iwd → NM conversion).
- `EXTRA_FSTAB_ENTRIES`, `filter_fstab_entries`.

## Failure handling

| Failure | Result |
|---|---|
| Hyprland won't start | tty1: "The graphical installer couldn't start. Log: ~/.local/share/hyprland/hyprland.log" and a shell |
| `qs` crashes | Hyprland exits with it (same as above); re-run with `Hyprland -c …` |
| Offline | Network step blocks Next |
| Leftover `/mnt` or LUKS from a previous attempt | Welcome shows "A previous attempt is still open" + **Clean up** (`mbm-cleanup`) |
| Base stage fails | Failed screen, `/mnt` kept for inspection, **Clean up and start over** |
| Desktop stage fails | **Retry desktop** / **Reboot anyway** (firstboot retries) |
| Mirror mid-sync | existing retries (pacstrap ×3, bootstrap ×3) |

## Testing (everything in the VM)

- Unit (`test-*.sh`, `lib.sh`): `test-answers.sh` (new keys, bad layouts,
  bad mounts), `test-detect.sh` (`fstab_line`), `test-probe.sh` (probe JSON
  against `lsblk`/`blkid` fixtures), `test-progress.sh` (pacman line filter →
  `@@mbm count`). Run in the VM like the existing ones.
- `cachyos/vm/` gains a second virtual disk with an ext4 filesystem so the
  data-disk path is exercised.
- End to end: build the ISO, boot it in `cachyos-test`, drive the GUI
  (screenshots for each step), install. `verify-install.sh` gains checks:
  data-disk fstab line present + mounts on access, `vconsole.conf` has
  `XKBLAYOUT`, `settings.json` has the layout, firstboot disabled + done-guard
  present, SDDM is the first thing on boot, `/var/log/mbm-install.log`
  present.
- Failure paths: kill the network mid-Desktop stage → Retry desktop works;
  Reboot anyway → firstboot completes the desktop.

## Open risks

- **ISO size**: Hyprland + Qt6 + Quickshell + NM + fonts add a few hundred
  MiB; the build already fails at GitHub's 2 GiB limit. Measure early.
- **Hyprland 0.57** removes `.conf`: the live `hyprland.conf` is a second
  file to migrate alongside the generator (small, no binds).
- **Hyprland in a VM**: needs virtio-gpu with 3D or falls back to software
  rendering; the test VM's graphics settings may need changing.
- **bootstrap in chroot** is new territory for `bootstrap.sh`; anything that
  assumes a booted system surfaces in the VM run. The firstboot fallback
  covers it on real hardware.
- `Quickshell.Networking` against NM with no logged-in seat session: the
  polkit rule must cover it; verify early.
