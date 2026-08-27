# CachyOS migration — resume prompt

Paste this whole file as your first message in a fresh session to pick up
where we left off. Delete this file once you've resumed (it's a handoff
note, not permanent project doc).

## What this project is

Migrating the user's Arch/Omarchy Hyprland desktop (waybar, walker, mako,
swayosd, starship, kitty, Zen browser) to CachyOS, proven out in a
disposable QEMU/KVM test VM first, then to real hardware later. Full
design/plan history: `docs/superpowers/specs/2026-08-26-cachyos-migration-design.md`
and `docs/superpowers/plans/2026-08-26-cachyos-migration.md` in
`~/proj/dotfiles` (that worktree — see "Repo layout" below).

**The actual distribution mechanism** (confirmed, not aspirational): boot
the *stock* official CachyOS ISO on real hardware, run `install-cachyos.sh`
then `bootstrap.sh`. No custom ISO — the live installer's own desktop
never carries into the installed system, so a different ISO variant
wouldn't help with anything; all the actual desktop setup comes from
these two scripts.

## Repo layout — READ THIS FIRST, it's not obvious

- **`~/proj/slievr-cachy`** (GitHub: `slievr/slievr-cachy`, private) — this
  is where ALL real work now lives: `cachyos/` (VM scripts, bootstrap.sh),
  `dot-config/`, `dot-local/` (stow-managed dotfiles). **Work here.**
- **`~/proj/dotfiles`** (this session's worktree at
  `.claude/worktrees/cachyos-migration`) — the ORIGINAL personal dotfiles
  repo. Early work happened here before a mid-session pivot (see below)
  to a separate repo so this work never touches the host's real, live
  dotfiles. Has a few **stale uncommitted changes** left over from before
  the pivot (`.gitignore`, `dot-config/zen/`, `docs/`) — safe to ignore or
  just discard; nothing there is current.

## Why the separate repo

The VM's Hyprland setup turned out to be built on the
[Omarchy](https://github.com/basecamp/omarchy) framework (not just
hand-picked Hyprland packages) — `bindings.conf` and other configs call
dozens of `omarchy-*` commands and source files from
`~/.local/share/omarchy/default/`. Decision made: vendor what's needed
(not install the full Omarchy framework — its installer overrides the
pacman mirrorlist and would fight with CachyOS's own repos), then rename
every `omarchy-*` command to `slievr-*` since it's a permanent fork, not
synced from upstream. All of `dot-local/share/slievr-cachy/bin/` (282
scripts) is that vendored, renamed tree.

## VM access

VM name: `cachyos-test` (libvirt/QEMU). Login: `slievr` / `TestPass1`
(also root). Passwordless sudo already set up for `slievr` on the VM.
SSH key auth already set up from host → VM (no password needed for
`ssh`/`scp`).

**`cachyos/vm/dev-up.sh`** brings an already-installed VM up for testing:
starts it if stopped, waits for SSH, sets up key auth automatically if
missing, opens `virt-viewer`. It does NOT provision from scratch — that
needs one manual GUI step (see script header) because this CachyOS
desktop-edition live ISO doesn't attach a shell to the serial console, so
`unlock-console.exp`'s automated approach doesn't apply to it.

To get the VM's current IP if `dev-up.sh` isn't used:
`sudo virsh domifaddr cachyos-test`

## Deploy workflow used throughout this session

```bash
# From host, after editing files in ~/proj/slievr-cachy:
ssh slievr@<vm-ip> 'rm -rf ~/proj/slievr-cachy'
scp -r ~/proj/slievr-cachy slievr@<vm-ip>:~/proj/slievr-cachy
scp ~/proj/slievr-cachy/cachyos/bootstrap.sh slievr@<vm-ip>:~/bootstrap.sh
ssh slievr@<vm-ip> '~/bootstrap.sh'
```

(A partial `scp` of just the changed file(s) also works and is faster —
just don't forget `bootstrap.sh` itself needs a separate `scp` to
`~/bootstrap.sh`, it's not read from `~/proj/slievr-cachy` when invoked as
`~/bootstrap.sh`.)

To test changes: **must fully restart Hyprland**, not just `hyprctl
reload` — env var changes (`~/.config/uwsm/env`) only take effect on a
fresh session start:

```bash
ssh slievr@<vm-ip> 'systemctl --user stop wayland-wm@hyprland.service'
# then in the VM's console: uwsm start -e -D Hyprland hyprland.desktop
```

(`uwsm start hyprland` also works but triggers a "started without
start-hyprland" warning — the `hyprland-uwsm.desktop` invocation above is
the correct one, resolves that warning.)

## Current state: working

SDDM login (custom "SLIEVR" DodgerBlue-on-`#131315` themed greeter,
`cachyos/sddm-theme/slievr-cachy/`) → Hyprland session → waybar (icons
render now, needed 3 separate nerd font packages that were never
installed) → walker launcher, background/theme picker (via `elephant` +
its specific provider packages, not the bloated `elephant-all-bin`) →
zsh default shell → kitty terminal → Thunar file manager → Discord →
ProtonVPN GTK app → ffmpeg/wifi/bluetooth/audio TUIs (`nmtui`, `bluetui`,
`wiremix` — not `impala`, which needs `iwd` not NetworkManager).

`cachyos-hyprland-settings` (CachyOS's opinionated Hyprland metapackage,
pulls in kvantum/wofi/bemenu/grimblast/etc.) was removed — this repo has
its own equivalents for everything it provided that's actually used.

## Known open items (not fixed, in priority-ish order)

1. **Zen webapp windows show full browser chrome** (URL bar, tabs,
   sidebar) instead of a seamless standalone app window. Zen (Firefox-
   based) has no CLI-scriptable equivalent to Chromium's `--app=` mode —
   its real "Web App" feature is GUI-only. `--kiosk` was tried and
   rejected: forced fullscreen, still showed full chrome, then crashed
   after ~6s (confirmed via `journalctl`). Current state: plain
   `--new-window` (`dot-local/share/slievr-cachy/bin/slievr-launch-webapp`)
   — stable but not seamless. **Next idea to try**: a dedicated Firefox
   profile with a `userChrome.css` that hides `#nav-bar`/`#TabsToolbar` —
   standard technique for this on Firefox-family browsers, more setup
   than a flag, not attempted yet.
2. **"gazelle" wifi TUI** — the *original* waybar config's network-icon
   click handler and the user's memory both referenced a tool called
   "gazelle" as an nmtui/impala alternative. Confirmed: not in official
   repos or AUR. User says it came from a GitHub repo they can't
   currently pin down. Currently substituted with `nmtui` everywhere
   (works, just not the exact originally-intended tool). Revisit if the
   repo gets found.
3. **Multi-monitor app-placement bindings** (`dot-config/hypr/monitors.conf`,
   `workspaces.conf` — 3 real monitors by EDID description, workspace 9/10
   pinned to side monitors, Discord/Spotify/YouTube Music pinned to
   workspace 9) were reviewed for correctness but **cannot be tested** in
   this single-virtual-monitor VM. Only verifiable on real hardware.
4. **Bare-metal deployment not yet done.** `install-cachyos.sh` has
   `DISK=/dev/vda` hardcoded — needs to change to the real target disk
   (e.g. `/dev/nvme0n1`) before running on actual hardware. This is
   otherwise the literal distribution mechanism (see top).
5. `.conf` config format deprecation warning in Hyprland's startup
   overlay — cosmetic only, not actionable: Hyprland 0.57 (where it's
   actually removed) hasn't shipped, and there's no published
   replacement spec or migration tool yet to move to.
6. A handful of vendored `slievr-*` self-management commands
   (`slievr-update*`, `slievr-reinstall*`, `slievr-migrate`, theme-catalog
   browsing, some `slievr-refresh-*`) still reference `$OMARCHY_PATH`,
   which assumed a live upstream git checkout that isn't vendored.
   Intentionally left inert — documented in
   `dot-local/share/slievr-cachy/README.md` — nothing in the active
   desktop config calls them.

## Useful context for the next session

- User prefers being told the reasoning/tradeoff, not just the fix — several
  turns this session involved presenting 2-3 options with a recommendation
  before acting on anything architecturally significant (e.g. Omarchy
  vendoring scope, the metapackage removal).
- User caught at least one case where I stated something as fact without
  verifying first (the "cold-start timing quirk" claim about a glob error
  that was actually a real path bug) — be correspondingly careful about
  confidence framing; verify against the actual on-screen error/log rather
  than inferring from indirect signals when the two might disagree.
- A recurring failure mode this session: editing a file locally and
  believing it's deployed, when actually a stale copy was still on the
  VM (either `~/bootstrap.sh` not re-synced after editing
  `cachyos/bootstrap.sh`, or an `scp -r` nesting into an already-existing
  destination directory instead of overwriting it cleanly). When
  something "isn't picking up a fix," verify the actual bytes on the VM
  match the local file before looking elsewhere.
