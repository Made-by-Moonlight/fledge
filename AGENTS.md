# AGENTS.md

Guidance for coding agents (and people) picking up work in this repo.
Read this first, then the newest spec under `docs/superpowers/specs/`.

## What this is

**made by moonlight**: a CachyOS + Hyprland desktop and the installer ISO
that puts it on a machine. `README.md` has the user-facing overview and the
repo layout.

## Hard rules

1. **Never change the host machine.** The person working with you develops
   on their daily desktop. Do not `pacman -S`, `stow`, run `bootstrap.sh`,
   start the shell, run `mbm settings apply`, or `systemctl`/`hyprctl`
   anything on the host. Read-only inspection (reading files, `pacman -Si`)
   is fine. **Everything that runs project code goes in the test VM**
   (`cachyos/vm/`, VM name `cachyos-test`, iterate with `dev-up.sh`), and
   that includes unit tests.
2. **Brand is "made by moonlight"** (lowercase wordmark, owl mark, palette in
   `cachyos/branding/palette.sh`). `slievr` is the user's handle, not the
   brand: never use it as a logo or wordmark. New components use the
   **`mbm`** name (`mbm` CLI, `~/.config/mbm/`, `qs -c mbm`).
3. **No webapps.** Don't add or port webapp support.
4. **Branch from an up-to-date `main`.** `git fetch` then
   `git merge --ff-only origin/main` (`pull.rebase=true` here refuses to
   pull with a dirty tree). Don't commit someone's uncommitted work without asking.
5. Commit or push only when asked.

## How work is done here

New features follow the superpowers flow: brainstorm, then a spec in
`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, then a plan in
`docs/superpowers/plans/`, then implementation on its own branch.
Specs record the decisions; check them before re-deciding something.

`cachyos/NEXT-SESSION.md`, when present, is a handoff note from the last
session. Read it, act on it, delete it once resumed.

## Roadmap: making the desktop our own

The desktop UI started as Omarchy's. It's being replaced in four projects,
each with its own spec, plan and branch, and the desktop works after each one:

| # | Project | Status |
|---|---|---|
| A | **mbm shell**: Quickshell bar, launcher, notifications, OSD, lock, wallpaper, quick settings, settings window; settings JSON → generated Hyprland config | spec: `docs/superpowers/specs/2026-10-10-mbm-shell-design.md` |
| B | **`mbm` CLI**: replace the vendored `slievr-*` scripts (`dot-local/share/slievr-cachy/bin/`) | not started |
| C | **mbm theme**: palette in mbm settings, our own app-theme renderer, retire `dot-config/omarchy/` | not started |
| D | **Graphical installer**: Quickshell installer on the ISO, reusing A + C | not started |

Until B lands, the `slievr-*` scripts are a vendored, renamed Omarchy fork
(see `dot-local/share/slievr-cachy/README.md`). Treat them as legacy: call
them if needed, don't extend them.

## Layout and conventions

- `dot-config/`, `dot-local/`, `dot-zshrc` are GNU stow `--dotfiles` names
  (`dot-config` → `~/.config`). `bootstrap.sh` stows the whole repo into `~`.
- `cachyos/install/`: installer (bash). `cachyos/iso/`: ISO build/test.
  `cachyos/bootstrap.sh`: the desktop layer, run on first boot.
- Settings (once project A lands): defaults in `dot-local/share/mbm/defaults/settings.json`,
  user overrides in `~/.config/mbm/settings.json`, Hyprland fragments
  **generated** into `~/.local/state/mbm/hypr/` by `mbm settings apply`. Don't hand-edit generated files;
  change the defaults or the generator.
- Shell scripts: bash, `set -euo pipefail`, shellcheck-clean (CI runs it).
  Comments explain *why*. Match the density of the surrounding code.
- Tests: `test-*.sh` scripts using `cachyos/install/test/lib.sh`
  (`check` / `contains`, then `exit $fail`). VM end-to-end checks live in
  `cachyos/iso/test/verify-*.sh`.
- Commit messages: `area: what changed and why`, lowercase area
  (`iso:`, `install:`, `hypr:`, `gpu:`, `docs:`, `shell:`, `mbm:` …).
- Hyprland is 0.56; 0.57 removes the `.conf` format. Keep new Hyprland
  config generated so only the generator needs to change.
