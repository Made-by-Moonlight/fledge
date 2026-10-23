# fledge update: design

Date: 2026-10-23. Branch: `update`. Replaces the README's manual upgrade
(`git pull` + `bootstrap.sh`) and Omarchy's `omarchy-update`, which fledge
never vendored (`libexec/` has only `update-firmware` and `update-time`).

## Why

The user: "The next thing to build is the update functionality that omarchy
had". Omarchy's update ran in a floating terminal: btrfs snapshot, pull the
repo, migrations, pacman and AUR updates, restart what changed, offer a reboot
when the kernel changed; the bar showed an icon when a release was out.

The user's choices:

- **Everything in one run:** fledge, system packages (pacman + AUR), firmware.
- **fledge comes from release tags** (`vYYYY.MM.DD[.N]`, cut from `main`; the
  tag builds the ISO), not every merge to `main`.
- **Bootable snapshots:** snapper + `limine-snapper-sync`, a snapshot before
  each update, listed in the boot menu.
- **Bar icon + terminal:** a bar module when something is pending; clicking
  runs `fledge update` in a floating terminal.

Success: on an installed system, the bar shows pending updates; one click
snapshots `/`, updates packages, moves fledge to the newest release and re-runs
its bootstrap, applies firmware, and says whether to reboot. A broken update
can be booted around from Limine's Snapshots menu.

## Commands

A builtin (`lib/update.sh`, like `settings` and `screenshare`), so the
`update` group keeps `fledge update firmware` / `fledge update time` from
`libexec/`:

| | |
|---|---|
| `fledge update` | the whole run (below); `--yes` skips the confirmation |
| `fledge update check [--json]` | what's pending, no root, no changes |
| `fledge update firmware` / `time` | unchanged (libexec) |
| `fledge version` | the release this checkout is at (`git describe --tags --dirty`: `v2026.10.21`, or `v2026.10.21-3-gabc1234-dirty` past it) |

`fledge help update` lists all four.

## What's pending (`check`)

| Part | How | Needs |
|---|---|---|
| fledge | `git fetch --tags` from `origin`; the newest `v*` tag (version sort) that is a descendant of `HEAD` | network |
| packages | `checkupdates` (pacman-contrib: a temp copy of the sync db, no root, no partial-upgrade risk) | network |
| AUR | `paru -Qua` | network |
| firmware | `fwupdmgr get-updates --json`, when fwupd is installed and the machine has updatable devices | network; skipped in a VM |

`--json` prints `{"fledge": {"from": "v2026.10.21", "to": "v2026.10.23"} | null,
"packages": N, "aur": N, "firmware": N, "dev": bool, "errors": [...]}`; a part
that couldn't be checked (offline, tool missing) goes in `errors` and counts 0,
it doesn't fail the command.

**A dev checkout is left alone.** fledge updates only when the checkout is on
`main`, has no uncommitted changes, and `HEAD` is an ancestor of the new tag
(so a local commit or a checkout ahead of the release is never rewound). Any
of those false → `dev: true`, the fledge part is reported as skipped with the
reason, and the rest of the run goes ahead. The user's desktop is such a
checkout (on a feature branch), so there `update` updates packages and
firmware only.

`fledge update check` is also what the bar runs.

## The run (`fledge update`)

1. **Check** (as above) and print the list. Nothing pending → say so, exit 0.
2. **Confirm** (`[Y/n]`), unless `--yes`.
3. **Snapshot** `/`: `sudo snapper -c root create --type pre --cleanup-algorithm
   number --print-number --description "fledge update"`;
   `limine-snapper-sync` adds it to the boot menu. After the run, the matching
   `post` snapshot. No snapper config (not btrfs, or never set up) → a warning
   and the run continues without one.
4. **Packages:** `sudo pacman -Syu`, then `paru -Sua` (AUR only, so pacman's
   upgrade isn't run twice). Interactive: conflicts, `.pacnew` notes and
   provider choices reach the user as pacman prints them.
5. **fledge:** `git merge --ff-only <tag>` on `main` (it keeps tracking
   `origin/main`, as the ISO set it up), then `cachyos/bootstrap.sh`. Bootstrap
   is idempotent and already the upgrade path: it installs what a release adds,
   removes what it retires, restows, regenerates settings, reloads Hyprland and
   restarts the shell. After packages, so bootstrap's installs are against a
   synced db.
6. **Firmware:** `fwupdmgr update` when step 1 found any (fwupd asks per
   device and may schedule a reboot).
7. **Finish:** the post snapshot; then **reboot?** when the running kernel's
   modules are gone (`/usr/lib/modules/$(uname -r)` missing: the kernel package
   was upgraded; seen in the VM, 7.3.0-2 → 7.3.0-5). Otherwise "Updated."
   fwupd asks about its own reboot. Then the bar is asked to recheck
   (`shell.recheck`), however the run ended.

A failing step stops the run with the step's name; steps after it don't run,
and the guide below takes over.

## When an update fails: guided recovery

Added after the first review. The user asked what happens on a failure, then:
"I'd also like recovery a guided process if possible". Their choices:
**terminal guide + shell dialog**, and **keep pacman and paru separate**.

### What going back means (VM, 2026-10-23)

- `/boot` is the FAT ESP and isn't in the snapshot, so `snapper undochange`
  on a running system brings back the old kernel's modules under the new
  kernel's UKI: unbootable. The first version printed that as the way back;
  it's gone.
- The way back is limine-snapper-sync's: boot **Snapshots › N** in Limine
  (each entry keeps the kernel it was taken with, in `limine_history/`), then
  `limine-snapper-restore` from inside it. Seen in the VM: the menu shows
  `N │ <date>`, newest first; `/proc/cmdline` has
  `rootflags=subvol=/@/.snapshots/N/snapshot`; the root is the read-only
  snapshot, so a few units fail (`ldconfig`, `systemd-sysusers`), but the
  session, shell and `/home` work. The restore asks `[r] restore | [l] list |
  [c] cancel`, then a description for the backup of the current system (Enter
  is fine), keeps it as a snapshot ("backup before restore #N"), asks to
  reboot (`[Y/n]`), and the next normal boot is the snapshot's system.
- `limine-snapper-restore` reads its answers from a terminal only (piped input
  hangs), and a killed one leaves `/run/lock/limine-snapper-restore.lock`
  behind, which blocks the next run until a reboot.
- The package's own "restore this snapshot" notification (an XDG autostart)
  fires before the shell's notification server is up and is lost. fledge's
  dialog replaces it; the autostart is hidden for the user.

### The guide (terminal)

When a step fails or the run is interrupted (Ctrl+C), the run stops as before
and then, unless `--yes`, asks:

```
fledge update: AUR packages failed; the steps after it didn't run.
A snapshot from before the update is in the boot menu: Snapshots › 7 │ 2026-10-23 21:24.

What now?
  1  Try again
  2  Go back to before the update
  3  Leave it for now (to come back here later: fledge update recover)
```

- **Try again** runs `fledge update` again.
- **Go back** says how: reboot, in the boot menu (3 seconds; any arrow key
  stops the countdown) open Snapshots and boot `7 │ 2026-10-23 21:24`; once
  logged in, fledge offers to make it permanent. Then "Reboot now? [y/N]".
  Not offered when no snapshot was taken.
- Interrupting exits 1, not 130, so the terminal stays open on the guide.

`fledge update recover` is the same guide on demand:

- **Booted into a snapshot:** says which (number, date, how that update
  ended), that `/home` isn't affected, and that restoring keeps the current
  system as a backup snapshot. On yes: clears a stale restore lock (no
  restore running), then runs `sudo limine-snapper-restore`, saying what it
  will ask (`r`; a description, Enter is fine; Enter to reboot).
- **Otherwise:** the menu above for the last failed run; with none, the
  `fledge update` snapshots there are, newest first, and how to boot one.

Runs are recorded in `~/.local/state/fledge/update.json` (in `/home`, so a
booted snapshot still sees them): per snapshot its number, snapper's date (as
the boot menu shows it) and how the run ended (`running`, `ok`,
`failed: <step>`, `interrupted: <step>`), worded for people as "failed
(AUR packages)", "was stopped (…)", "didn't finish". A new snapshot replaces an
older record with its number: numbers start over when snapper's config is made
again (seen in the VM).

### The dialog (shell)

Booted into a snapshot (from `/proc/cmdline`), the shell shows, once per boot:

```
 󰁯  Running a snapshot
 This is snapshot 7, taken before the update on 23 Oct at 21:24.
 Changes to the system aren't kept until it's restored; your files are fine.
                                         [ Not now ]  [ Restore it… ]
```

**Restore it…** opens `fledge update recover` in a floating terminal. The
bar's updates module shows `󰁯 snapshot` (error colour) the whole time, and
clicking it opens the dialog again.

### A bootstrap that didn't finish

`bootstrap.sh` records the release it finished at in
`~/.local/state/fledge/bootstrapped` (`git describe`); `update` marks it
unfinished before running bootstrap. `check` reports `"bootstrap": true` when
the file is there and doesn't match the checkout, and the next run runs
bootstrap again. No file (an install from before this) reports nothing.

### Reboot prompt

Also when a package that only takes effect at boot was upgraded: a kernel
(`linux`, `linux-*` but not `-headers`/`-docs`/`linux-api-headers`),
`linux-firmware*`, `*-ucode`, `nvidia*`. The list comes from what
`checkupdates` and `paru -Qua` reported; the message names them.

### Snapshot entries

`post` snapshots stay in snapper (`snapper status pre..post` shows what an
update changed) but not in the boot menu (`EXCLUDE_SNAPSHOT_TYPES="post"`):
booting one is booting the current system, and each entry costs ESP space.

No migrations directory: a release that needs a change on existing machines
puts it in `bootstrap.sh`, which every update runs. (AGENTS.md: no migration
code for the pre-rename names; that still holds.)

## Snapshots (bootstrap)

`bootstrap.sh` sets them up, so new installs and every updated machine get
them, when `/` is btrfs:

- install `snapper`, `limine-snapper-sync` (both in the CachyOS repos);
- `snapper -c root create-config /` when there's no `root` config. The
  installer already made `@/.snapshots` (profile `CREATE_SNAPSHOTS_SUBVOL`),
  and `create-config` refuses an existing `.snapshots`: an empty one is
  removed first and recreated by snapper (one with snapshots in it is left,
  and the config step reports it);
- the config: `NUMBER_LIMIT=5`, `NUMBER_LIMIT_IMPORTANT=5`, `TIMELINE_CREATE=no`
  (snapshots are for updates, not hourly);
- `limine-snapper-sync.service` and `snapper-cleanup.timer` enabled (enable
  only, no `--now`, like the other units bootstrap enables from firstboot).
  Without `inotify-tools` the watcher exits and the package's snapper plugin
  does the work: in the VM a new snapshot was in `/boot/limine.conf` at once.
  The installer's `/etc/default/limine` already has
  `BOOT_ORDER="*, *fallback, Snapshots"`.

`/home` (`@home`) isn't snapshotted: rolling back an update must not roll back
the user's files.

## The bar

A new bar module, `updates`, in `bar.right`'s defaults before `glyphs`:

- Hidden when nothing is pending or the check hasn't run.
- Otherwise `󰚰 N` (N = packages + AUR + firmware, + 1 for a fledge release);
  hovering spells the parts out in place ("fledge v2026.10.23 · 34 packages ·
  2 AUR"): the shell has no tooltips.
- Click: `fledge update` in a floating terminal (the same launcher the menu's
  terminal tools use). The run asks the shell to re-check when it ends (the
  terminal is detached, so the shell can't see it close).
- The check runs 2 minutes after the shell starts (not at login, when the
  network may not be up), then every 6 hours, through a `Process` in a new
  `Updates` service. One check at a time.

It's a module, not a status glyph: glyphs open quick settings on click.
Existing user files with their own `bar.right` don't get it added; the Bar
settings page can add it (it's one more entry in its module list).

The fledge menu's Setup gets **Update** (`fledge update`) above Firmware.

### Testing recovery

`test-update.sh` covers the guide's choices, Ctrl+C, the record, the unfinished
bootstrap, the reboot list and `recover` (booted or not, with or without a
record). `verify-recovery.sh fail | snapshot | after` runs it for real around
two reboots (`vm.sh reboot snapshot` boots the newest Snapshots entry through
Limine's menu and unlocks the disk; `vm.sh reboot` a normal boot): an AUR step
that changes `/` and fails, the guide naming the entry, the change gone in the
snapshot, the dialog's text, the restore answered through a pty, and the
normal boot after it on the restored system with no failed units. Passed in
the VM, twice.

## Non-goals

- A shell window with progress (chosen: the terminal).
- Choosing a channel (`main` vs tags), unattended or scheduled updates.
- Rolling back from the shell; Limine and snapper do it.
- Snapshotting `/home`.
- Flatpak (not used by fledge).

## Testing

All in the `cachyos-test` VM.

- `test-update.sh` (unit, stubs on `PATH` for `git`-less parts:
  `checkupdates`, `paru`, `fwupdmgr`, `snapper`, `sudo`): `check --json` from
  stubbed outputs; dev-checkout rules (branch, dirty, ahead of the tag) against
  a scratch repo with a local "origin" and tags; the run's order; a failing
  step stops it and names the snapshot; nothing pending exits early; reboot
  detection from a fake modules dir.
- `verify-update.sh [fresh] [packages]` (VM end-to-end): `fresh` puts `/`
  back as the installer leaves it and checks bootstrap sets snapshots up (and
  runs twice); then a scratch checkout at an older tag with a local origin
  carrying a newer one: `fledge update --yes` takes a pre/post pair,
  fast-forwards to the tag and runs that release's bootstrap (a stub: the real
  one would restow `~` from the scratch checkout); the snapshot is in
  `/boot/limine.conf`. `packages` lets it upgrade the VM's real packages, and
  the bar module hides after. Its sudo goes through `SUDO_ASKPASS`: a password
  piped on stdin emptied every `sudo tee <<EOF` in bootstrap (the lock's PAM
  file among them) on the first try.
- `verify-shell.sh` stays green with the new module.
