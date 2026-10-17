# Rename to fledge: design

**Date:** 2026-10-18
**Status:** design approved, plan pending
**Branch:** `rename-fledge` (from `main` with the installer and Hyprland-on-Lua merged)

## Problem

The distro is "fledge", made by the org "made by moonlight". The code still
carries three older names: `slievr` (the user's handle, from the vendored
Omarchy fork: `slievr-*` scripts, `slievr-cachy` repo/paths/themes,
`slievr-firstboot`), `mbm` (the shell, settings CLI, config dirs, services,
installer helpers, `MBM_*` env vars) and `made-by-moonlight` as a theme name.
The GitHub repo is `slievr/slievr-cachy`. AGENTS.md rule 2 already says
`slievr` must not be the brand.

## Goals

- One product name everywhere: `fledge`. "made by moonlight" stays only as
  the org byline and in branding copy; the owl stays.
- One command, `fledge <group> <action> [args]`, replacing `mbm` and the
  `slievr-*` scripts (project B's CLI shape; script internals unchanged).
- Prune scripts nothing reaches, and every webapp script (AGENTS.md rule 3).
- Repo moves to `github.com/made-by-moonlight/fledge`; local checkout to
  `~/proj/fledge`.

## Non-goals

- Migrating existing installs. Every machine installs fresh from the new ISO
  (user decision); the VM is disposable. Old names simply disappear.
- Rewriting script internals (project B proper) or the theme system
  (project C).
- Renaming the user's account: the default username stays `slievr` (the
  user's own handle, not the brand).

## The `fledge` command

`dot-local/share/fledge/bin/fledge` (on PATH via the stowed uwsm env, as
today):

- `fledge <word> [<word>…] [args…]`: find the longest run of leading words
  `w1-w2-…-wn` for which `libexec/w1-…-wn` exists and is executable, and
  `exec` it with the remaining arguments. So `fledge capture screenshot`
  runs `libexec/capture-screenshot`, `fledge hyprland window pop 800`
  runs `libexec/hyprland-window-pop 800`.
- Built-in groups stay in the `fledge` script itself, checked first:
  `hypr` (dispatch/set/eval/quote, from the Lua branch) and `settings`
  (the former `mbm settings`, implemented by `lib/settings.sh`).
- `fledge help [group]` lists groups / actions (from the libexec names and
  each script's first comment line); unknown commands exit 2 with the
  nearest matches.
- Scripts in `libexec/` are the former `slievr-*` files renamed
  `slievr-<group>-<action>` → `<group>-<action>`. Internal calls between
  them use `fledge <group> <action>` (not direct paths), so the command
  surface is the only interface.

## Layout

| Today | After |
|---|---|
| repo `slievr-cachy`, checkout `~/proj/slievr-cachy`, ISO `/usr/share/slievr-cachy` | `fledge`, `~/proj/fledge`, `/usr/share/fledge` |
| `dot-local/share/mbm/{bin,lib,defaults,assets,test}`, `dot-local/share/slievr-cachy/{bin,default}`, `dot-local/share/fledge/{bin,test}` | one tree `dot-local/share/fledge/{bin,libexec,lib,defaults,default,assets,test}` |
| `~/.config/mbm`, `~/.local/state/mbm` | `~/.config/fledge`, `~/.local/state/fledge` |
| `dot-config/quickshell/mbm`, `qs -c mbm`, `mbm-shell.service`, IPC `qs -c mbm ipc call …` | `dot-config/quickshell/fledge`, `qs -c fledge`, `fledge-shell.service` |
| `cachyos/iso/installer` qs config `mbm-installer`, `/etc/mbm-installer`, `mbm-probe/install/cleanup`, `/run/mbm-answers.env`, `/var/log/mbm-install.log`, live user `moonlight` | `fledge-installer`, `/etc/fledge-installer`, `fledge-probe/install/cleanup`, `/run/fledge-answers.env`, `/var/log/fledge-install.log`, live user `fledge` |
| `slievr-firstboot.{sh,service}`, `/var/lib/slievr-firstboot-done`, `99-mbm-install` sudoers | `fledge-firstboot`, `/var/lib/fledge-firstboot-done`, `99-fledge-install` |
| Plymouth/SDDM theme dir `slievr-cachy`, colour theme `made-by-moonlight`, `dot-config/omarchy/themes/made-by-moonlight` | `fledge` |
| env `MBM_*` | `FLEDGE_*` |
| `@@mbm` progress markers | `@@fledge` |
| `DOTFILES_REPO=https://github.com/slievr/slievr-cachy.git` | `https://github.com/made-by-moonlight/fledge.git` |

Kept: "made by moonlight" byline text, owl assets, `ISO publisher`, default
username `slievr`, git history, the `dot-config/omarchy/` directory name
(project C retires it).

## Pruning

Before renaming, list every `slievr-*` script and keep it only if reached
from: a bind or default setting, the menu (`slievr-menu` and what it calls),
the shell QML, bootstrap/installer/firstboot, a Hyprland config file, a
desktop/systemd unit, or (transitively) another kept script. Delete the rest
plus every `webapp` script. The plan's first task produces the list (kept /
dropped with the reason) for the user to veto before anything is deleted.

## Docs

AGENTS.md (brand rule, layout, roadmap: B's command shape done), README,
every component README, spec/plan cross-references in new docs. Old specs and
plans are history and keep their old names.

## Repo move (last, each step confirmed with the user right before)

1. `gh repo rename fledge` + `gh repo transfer made-by-moonlight` (or the
   equivalent API), then `git remote set-url origin
   https://github.com/made-by-moonlight/fledge.git`. GitHub redirects the old
   URL.
2. Move the local checkout `~/proj/slievr-cachy` → `~/proj/fledge` and the
   Claude project memory folder keyed to that path.

## Testing

- Unit suites renamed/moved and passing; new tests for the `fledge`
  dispatcher (longest-prefix match, args passthrough, built-ins first, help,
  unknown → exit 2 + suggestions, no path traversal from words).
- A repo-wide check (CI step, extending `check-legacy-ipc.sh` or a sibling):
  no `slievr` outside the default username and history docs, no `\bmbm\b`, no
  `made-by-moonlight` outside the byline/org URL; fails the build.
- VM: fresh ISO install, `verify-install.sh` and `verify-shell.sh` (renamed
  paths), every bind and menu entry that runs a `fledge` command exercised
  by a script walking the defaults (exec/shell actions resolve to an existing
  libexec or built-in).

## Risks

- Missed references break at runtime (a bind or menu entry calling a gone
  `slievr-*`). The walker check above and the repo-wide grep are the guard.
- Pruning could drop a script that's only reached dynamically (built names,
  `"slievr-$x"`). The reachability pass must search for dynamic forms, and the
  user vetoes the list.
- The GitHub transfer needs the user's org rights; it's the last step and
  fully reversible by GitHub (rename/transfer back, redirects).
