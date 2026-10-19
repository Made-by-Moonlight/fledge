# AGENTS.md

Guidance for coding agents (and people) picking up work in this repo.
Read this first, then the newest spec under `docs/superpowers/specs/`.

## What this is

**fledge**, by made by moonlight: a CachyOS + Hyprland desktop and the
installer ISO that puts it on a machine. `README.md` has the user-facing
overview and the repo layout. The repo is
`github.com/Made-by-Moonlight/fledge` (private), checked out at `~/proj/fledge`.

## Hard rules

1. **Never change the host machine.** The person working with you develops
   on their daily desktop. Do not `pacman -S`, `stow`, run `bootstrap.sh`,
   start the shell, run `fledge settings apply`, or `systemctl`/`hyprctl`
   anything on the host. Read-only inspection (reading files, `pacman -Si`)
   is fine. **Everything that runs project code goes in the test VM**
   (`cachyos/vm/`, VM name `cachyos-test`, iterate with `dev-up.sh`), and
   that includes unit tests.
2. **The product is `fledge`; "made by moonlight" is the byline.** `fledge`
   (lowercase) names the product and every component, new ones included:
   the `fledge` CLI, `~/.config/fledge/`, `qs -c fledge`, `fledge-*` units and
   helpers, `FLEDGE_*` variables. "made by moonlight" (lowercase, with spaces)
   is the org byline, used only in branding copy, with the owl mark and the
   palette in `cachyos/branding/palette.sh`. `slievr` is the user's handle (and
   the default username), not the brand: never a product, logo or wordmark.
   The old names (`slievr`, `mbm`, `made-by-moonlight`) are gone, and
   `cachyos/check-names.sh` fails CI if one comes back; a real exception goes
   in its allowlist.
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
| A | **fledge shell**: Quickshell bar, launcher, notifications, OSD, lock, wallpaper, quick settings, settings window; settings JSON → generated Hyprland config | done (merged, released in `v2026.10.12`): spec `2026-10-10-mbm-shell-design.md` + plan in `docs/superpowers/` (written under its old name) |
| B | **fledge CLI**: one command, `fledge <group> <action>`, over the vendored scripts in `dot-local/share/fledge/libexec/`; then rewriting their internals | command shape done (branch rename-fledge, spec `2026-10-18-fledge-rename-design.md`); internals not started |
| C | **fledge theme**: the palette in fledge settings, our own app-theme renderer, retire `dot-config/omarchy/` | not started |
| D | **Graphical installer**: Quickshell installer on the ISO, reusing A + C | done (branch graphical-installer): spec + plan in `docs/superpowers/` |

Until B's internals land, `libexec/` holds a vendored, renamed Omarchy fork
(see `dot-local/share/fledge/README.md`). Treat it as legacy: call it as
`fledge <group> <action>` if needed, don't extend it.

## Layout and conventions

- `dot-config/` and `dot-local/` are GNU stow `--dotfiles` names
  (`dot-config` → `~/.config`). `bootstrap.sh` stows the repo into `~`, and
  `.stow-local-ignore` keeps everything that isn't `dot-*` out of it: a new
  top-level file or directory goes in that list (`cachyos/check-stow-ignore.sh`
  fails CI otherwise).
- `cachyos/install/`: installer (bash). `cachyos/iso/`: ISO build/test.
  `cachyos/bootstrap.sh`: the desktop layer, run on first boot.
- Settings: defaults in `dot-local/share/fledge/defaults/settings.json`,
  user overrides in `~/.config/fledge/settings.json`, Hyprland fragments
  (`binds|monitors|workspaces|input.lua`) **generated** into
  `~/.local/state/fledge/hypr/` by `fledge settings apply`. Don't hand-edit generated files;
  change the defaults or the generator. Settings are `version` 2: a bind
  action is `{"exec"}`, `{"shell"}` or `{"dsp": "<hl.dsp name>", "args": …}`;
  a version-1 user file is migrated on apply (backup `settings.json.v1`).
  Displays are keyed `desc:<description>` (the connector name when the
  description is empty or has `,` `"` `\`), and the defaults carry no layout.
- The shell runs as `fledge-shell.service`; IPC: `qs -c fledge ipc call <target> <fn>`
  (targets in `dot-config/quickshell/fledge/ipc/Ipc.qml`). Dev loop:
  `cachyos/vm/vm.sh restow && cachyos/vm/vm.sh shell`. End-to-end check:
  `cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh'`.
- Shell scripts: bash, `set -euo pipefail`, shellcheck-clean (CI runs it).
  Comments explain *why*. Match the density of the surrounding code.
- Tests: `test-*.sh` scripts using `cachyos/install/test/lib.sh`
  (`check` / `contains`, then `exit $fail`). VM end-to-end checks live in
  `cachyos/iso/test/verify-*.sh`.
- Commit messages: `area: what changed and why`, lowercase area
  (`iso:`, `install:`, `hypr:`, `gpu:`, `docs:`, `shell:`, `fledge:`, `theme:`, `ci:` …).
- Hyprland (0.56) runs a **Lua** config, desktop and live ISO alike:
  `dot-config/hypr/hyprland.lua` loads `fledge/*.lua`, the theme, the
  generated `~/.local/state/fledge/hypr/*.lua` and the toggles through a guarded
  loader (`fledge/load.lua`), so a broken file costs only its own settings and
  raises a red `fledge: <file>: <error>` notification (not a `configerrors`
  entry: Hyprland has no API for that). Keep `hyprland.lua` tiny; an error in it
  is emergency mode. Keep Hyprland-specific names in the generators, the two
  IPC helpers and `fledge/*.lua`.
- Hyprland IPC goes through **`fledge hypr dispatch|set|eval|quote`** (bash)
  or the **`Hypr`** QML singleton (`Hypr.dispatch/set/evalLua/lit`); both fail
  loudly. Never `hyprctl keyword`, a legacy dispatch string (`workspace 2`) or
  `--batch`: under Lua they are refused, often with exit 0. Queries
  (`hyprctl clients -j`, `binds -j`, `reload`, …) are fine as they are.
- Hyprland's autoreload is off (`misc.disable_autoreload`): it caught
  half-written files. Anything that writes Hyprland config runs
  `hyprctl reload` itself; after hand-editing `~/.config/hypr`, do the same
  (or fledge menu › Setup › Config › Reload Hyprland). After changing which
  config Hyprland loads, test with `cachyos/vm/vm.sh relogin`: the config
  manager is picked at login, `reload` never switches it.
- Upgrading (README "Upgrade"): `git pull` in `~/proj/fledge`, then
  `bootstrap.sh`. That works only for installs made since the fledge rename;
  older installs (repo not at `~/proj/fledge`, old component names,
  `.conf`-era Hyprland) reinstall from the ISO. Nothing migrates them, by
  design: don't add migration code for the old names.
