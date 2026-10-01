# made-by-moonlight install ISO — design

**Date:** 2026-10-01
**Status:** approved in brainstorming, pending written-spec review

## Problem

Installing today means: boot the **stock CachyOS ISO** (which boots a full KDE
live desktop), mount a disk that has a staged copy of this repo, and run
`cachyos/install/install-cachyos.sh`. Its prompts are interleaved with the
install. The install path is already lean: `pacstrap` installs an explicit
minimal list and `bootstrap.sh` adds only the Hyprland stack, so no KDE ever
reaches disk. But the live environment is KDE we don't use, and the repo has
to be staged by hand on every machine.

Goal: an Omarchy-ISO-style installer ISO of our own. Boot it, answer a short
branded TUI up front, and it installs unattended into the existing
firstboot → `bootstrap.sh` flow.

## Goals

- One ISO that installs onto the desktop or the laptop with no per-machine
  edits and no repo staging.
- **The Omarchy format:** console-only live env, auto-login on tty1, a branded
  `gum` configurator that asks everything first, then an unattended install
  and reboot.
- Reproducible build from a commit, in a throwaway Docker container, on any
  machine (CI-ready later).
- Branded as **made by moonlight** (owl mark + palette below).
- The existing paths keep working: `install-cachyos.sh` still runs
  interactively from the stock CachyOS ISO; firstboot, `bootstrap.sh` and
  `vm/` are unchanged in role.

## Non-goals (v1)

- Offline install. The ISO carries the repo; packages download during install
  and firstboot (decided: online is fine).
- cidata / answer-file-only autoinstall (Omarchy has it; YAGNI for now).
- ISO signing, upload/release tooling, CI builds.
- Dual-boot / preserving partitions on the target disk (unchanged from the
  bare-metal spec).
- Rebranding SDDM. (Plymouth and the about screen are in scope; see Branding.)
- The heart elements explored for the logo (half hearts / implied-heart
  curves). Parked to iterate on later.

## Decisions (from brainstorming)

| Topic | Decision |
| --- | --- |
| Network | Online install. |
| Boot UX | Omarchy format: tty1 autostart → gum configurator → unattended install. |
| Build base | Arch `releng` archiso profile + our overlay + CachyOS repos, built with `mkarchiso` in a privileged `archlinux:latest` container (approach A). |
| Root account | **Locked.** No root password; `sudo` via `wheel`. Today's installer asks for one; the ISO path stops doing so. |
| LUKS passphrase | Defaults to the user password; the configurator offers a separate one. |
| Username | Fixed `slievr` (from `profile.sh`); dotfiles and fstab paths assume it. |
| Data disks | `EXTRA_FSTAB_ENTRIES` stays in `profile.sh`, but only entries whose UUID exists on the machine are written. Same ISO for desktop and laptop. |
| Repo on ISO | Built from **committed `HEAD` only**: `git clone` of the local checkout, `origin` reset to the GitHub URL. A dirty tree warns and lists what's excluded. |
| Bloat | Live env is console-only; nothing desktop-related is installed beyond `bootstrap.sh`'s Hyprland stack. A test asserts it (see Testing). |

## File layout

```
cachyos/iso/
  README.md
  bin/slievr-iso-make        host: docker run --privileged archlinux:latest builder/build-iso.sh
                             -> release/made-by-moonlight-YYYY.MM.DD.iso (+ .sha256)
  bin/slievr-iso-boot        host: boot an ISO in the existing libvirt test VM (via vm/)
  builder/build-iso.sh       in container: copy releng, overlay configs/, trust CachyOS
                             keyring, bake repo + branding, mkarchiso
  configs/
    profiledef.sh            iso_name/label/publisher/version, file permissions
    packages.extra           appended to releng's packages.x86_64
    pacman.conf              releng's + [cachyos] (build AND live env)
    airootfs/
      etc/systemd/system/getty@tty1.service.d/autologin.conf   (releng already has this)
      root/.automated_script.sh          tty1 entry: console palette -> configurator -> install
      usr/local/bin/mbm-configurator     gum TUI (writes the answers file)
      usr/local/bin/mbm-install          runs install-cachyos.sh --answers, logs, reboots
    efiboot/ + grub/ + syslinux/         releng's, retitled "made by moonlight"
cachyos/branding/
  owl.svg                    the mark (single path set, fill="currentColor")
  palette.sh                 the brand colours as shell vars (sourced by scripts)
  render-console.py          owl.svg -> half-block ANSI art for the console
cachyos/vm/provision-vm.sh   gains ISO_PATH override (default: stock ISO, as today)
```

`release/` is gitignored.

## Build (`slievr-iso-make` → `builder/build-iso.sh`)

1. **Host side** (`slievr-iso-make`): refuse to run outside the repo; warn if
   the tree is dirty (list files, continue — HEAD is what ships);
   `git clone --no-hardlinks` the checkout at `HEAD` into a temp dir and set
   its `origin` to `DOTFILES_REPO` (one variable shared with `bootstrap.sh`,
   so the move to the made-by-moonlight org is a one-line change); run the
   container with the temp clone, `cachyos/iso/` and `release/` bind-mounted.
2. **Container** (`build-iso.sh`), mirroring omarchy-iso's `build-iso.sh`:
   - `pacman -Syu archiso git python librsvg imagemagick` (full upgrade, not
     `-Sy`, to avoid a partial upgrade in a stale image).
   - Trust CachyOS: install `cachyos-keyring` + `cachyos-mirrorlist` the same
     way `chroot-setup.sh` already gets them (CachyOS's `cachyos-repo.sh`
     tarball), then `pacman-key --populate cachyos`. **Fail the build** on any
     keyring/mirror error, so a broken ISO is never produced.
   - Copy `/usr/share/archiso/configs/releng` → work dir; drop reflector (as
     omarchy does); overlay `configs/`.
   - Bake the repo clone into `airootfs/usr/share/slievr-cachy`.
   - Render branding: `render-console.py` → `airootfs/usr/share/mbm/owl.ansi`;
     `rsvg-convert` → boot-menu splash PNGs.
   - `mkarchiso -v -w /tmp/work -o /release <profile>`; write `.sha256`.
3. **Live env:** Arch's stock `linux` kernel (releng default, known-good with
   archiso's hooks). The *installed* system still gets `linux-cachyos`.
   `pacman.conf` carries the generic `[cachyos]` repo only; the target's
   `chroot-setup.sh` still runs `cachyos-repo.sh`, which picks the v3/v4
   optimised repos for the real CPU (unchanged).
4. `packages.extra` (live env): `gum git` plus everything
   `install-cachyos.sh`'s preflight checks for that releng lacks (`sgdisk`
   via `gptfdisk`, `lspci` via `pciutils`, `arch-install-scripts`; verify the
   rest against releng's list during implementation). Branding is rendered at
   build time, so `python`/`librsvg`/`imagemagick` are container-only.

## Live boot flow

1. Boot menu (GRUB/systemd-boot/syslinux from releng) titled
   **made by moonlight**; default entry boots after 5 s; a
   "safe graphics (nomodeset)" entry is kept.
2. releng auto-logs root into tty1 and runs `~/.automated_script.sh`, which
   exits immediately on any other tty.
3. `.automated_script.sh` sets the 16-colour VT palette to the brand colours
   (`\e]P0…` escapes, like omarchy's Tokyo Night block), tees output to
   `/var/log/mbm-install.log`, and runs `mbm-configurator`.
4. On a confirmed summary, `mbm-install` runs
   `install-cachyos.sh --answers /run/mbm-answers.env`, then counts down 10 s
   and reboots into firstboot.

## Configurator (`mbm-configurator`)

gum-styled, brand palette, the owl (`owl.ansi`) on the welcome screen. Screens:

1. **Welcome.** Owl + "made by moonlight". If there's no network, an `iwd`
   Wi‑Fi picker (SSID list → passphrase). It does not proceed until
   `mirror.cachyos.org` is reachable.
2. **Hostname.** Required; validated as a hostname.
3. **Timezone.** `gum filter` over `timedatectl list-timezones`; default from
   `profile.sh`.
4. **Password.** For `slievr`, entered twice. Then "Use the same passphrase
   for disk encryption?" (default yes); no → separate LUKS passphrase, twice.
5. **Disk.** `gum choose` over the existing `list_disks` (live media, zram and
   USB hidden, as today), then **type the disk's model to confirm** (today's
   safety check, kept).
6. **Summary.** Detected hardware (microcode, GPU packages, RAM/zram/swap),
   the data-disk fstab entries that will be written, and the choices above.
   Install / Back.

Ctrl‑C anywhere drops to a root shell; `mbm-configurator` restarts it.
`mbm-configurator --dry-run` runs on a normal machine: walks every screen and
prints the answers file instead of installing.

## Installer contract

`install-cachyos.sh --answers FILE` sources `FILE` (shell `KEY=value`) and
skips every prompt whose value is set. Without `--answers`, behaviour is
exactly as today. The prompt code becomes "fill in what the answers didn't
set", so both paths share validation and the disk guards.

| Key | Meaning |
| --- | --- |
| `DISK` | target, as a `/dev/disk/by-id/...` path |
| `DISK_CONFIRMED=yes` | the configurator already did the model-typing check |
| `HOSTNAME` | |
| `TIMEZONE` | overrides `profile.sh` |
| `USER_PASSWORD` | |
| `LUKS_PASSPHRASE` | |
| `ROOT_PASSWORD` | optional; **empty/unset → root is locked** (`passwd -l root`) |

- The answers file lives in `/run` (tmpfs), mode 600, and is deleted as soon
  as `install-cachyos.sh` has read it. Passwords never touch a disk.
- Disk guards (mounted / backs live root / USB) still run in answers mode;
  they abort rather than prompt.
- `lib/disk.sh`: `luks_format_open` takes the passphrase from
  `LUKS_PASSPHRASE` when set, otherwise prompts as today.
- `lib/chroot-setup.sh`: the hostname prompt stays as the fallback; root is
  locked when `ROOT_PASSWORD` is empty.
- `lib/detect.sh`: new pure function
  `filter_fstab_entries <blkid_uuids> <entries...>` → only entries whose
  `UUID=` is present. `install-cachyos.sh` uses it in both modes.

## Branding

- **Name:** "made by moonlight" (lowercase), the GitHub org this repo will
  move to. "slievr" is the user's handle and is not used as a brand.
- **Mark:** `cachyos/branding/owl.svg`, the user's own brow-and-beak owl logo
  (rights confirmed), traced with potrace. Kept: brow + beak + both eyes. The
  right eye is rebuilt as a ring the brow cuts off, like the left. The "S" and
  the right-hand pieces of the source are removed.
- **Palette:** `#171e28` background, `#212a33` surface, `#2f3640` lines,
  `#ffffff` text and mark, `#f4af03` accent (selection, buttons). Derived:
  `#6c7787` muted hint text; `#e5626a` / `#8fcf8a` error / success.
- **Where it appears:**
  - ISO boot menu title and splash;
  - configurator (owl, palette) and live VT palette;
  - installed system: Plymouth theme logo (replaces the "SLIEVR" logo in
    `cachyos/plymouth-theme/slievr-cachy`) and `dot-config/omarchy/branding/about.txt`
    (replaces Omarchy's block logo with `owl.ansi`).
- **Console art** is generated, never hand-drawn: `render-console.py`
  rasterises `owl.svg` and maps each pair of vertical pixels to `▀`/`▄`/`█`
  with brand fg/bg colours, which the Linux VT renders with its 16-colour
  palette.
- Brand page used for selection:
  https://claude.ai/artifact/9nj5VWoZJ9yF5R6sh6jwFF

## Failure handling

- **Configurator aborted:** root shell; `mbm-configurator` restarts.
- **Install fails:** show the failing step, the last 20 log lines and the log
  path; do **not** reboot; leave `/mnt` mounted for inspection.
- **No network:** the configurator won't reach the disk screen.
- **Build:** keyring/mirror/mkarchiso errors fail `slievr-iso-make` with a
  non-zero exit; no partial ISO in `release/`.

## Testing

Cheapest first:

1. `test-detect.sh`: cases for `filter_fstab_entries` (all present, some
   absent, none, an entry without `UUID=` passes through).
2. `mbm-configurator --dry-run` on the host: every screen, answers printed.
3. **Answers mode from the stock ISO** in the existing VM: prove unattended
   `install-cachyos.sh --answers` before the ISO exists.
4. **Full ISO run:** `slievr-iso-boot` → configurator → install → reboot →
   firstboot → SDDM. Check:
   - what NEXT-SESSION already checks (1 boot, `Bootstrap complete.`, no
     FAILED units, sddm active, firstboot disabled + done-guard);
   - **no desktop bloat:** `pacman -Qq` has no `plasma*`, `kde*`,
     `gnome-shell`, `xfce*`, `cachyos-*-settings` or similar;
   - root is locked (`passwd -S root` → `L`);
   - **the Hyprland login** (still unverified in NEXT-SESSION).

## Open questions / risks

- **Eye colour and wordmark:** mark stays white for v1; whether the eyes go
  amber, and whether the boot menu/configurator pair the mark with
  "made by moonlight" text, is undecided. Both are one-line changes.
- **CachyOS keyring in the container:** `cachyos-repo.sh` fetches keys from a
  keyserver; flaky keyservers would fail builds. Fallback: vendor the
  `cachyos-keyring` package's key into `builder/` like omarchy vendors
  `omarchy.gpg`.
- **Live kernel hardware support:** stock Arch `linux` must drive the
  install-time hardware (RX 9070 XT, Wi‑Fi); `nomodeset` entry as escape hatch.
- **The ISO contains the repo,** including `profile.sh`'s data-disk UUIDs.
  The repo is meant to become public under made-by-moonlight; until then,
  treat the ISO as private.
- **Uncommitted GPU work** (display-GPU env, Vulkan driver selection) on this
  branch is separate from this spec and should land first or separately.
