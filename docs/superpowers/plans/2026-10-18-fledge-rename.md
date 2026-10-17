# Rename to fledge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One name, `fledge`, for every command, path, service, theme and the repo; one `fledge <group> <action>` command replacing `mbm` and the `slievr-*` scripts; unreachable scripts and webapps pruned.

**Architecture:** Scripts move to `dot-local/share/fledge/libexec/<group>-<action>`; `fledge` resolves the longest matching word prefix to a libexec file, with `hypr` and `settings` built in. Everything named `mbm`/`slievr`/`made-by-moonlight` is renamed mechanically, guarded by a CI name check and a VM walker that proves every bind and menu command resolves.

**Tech Stack:** bash, jq, Quickshell QML, Hyprland Lua config, archiso, gh.

**Spec:** `docs/superpowers/specs/2026-10-18-fledge-rename-design.md`.

## Global Constraints

- Never run project code on the host (AGENTS.md rule 1): tests, shellcheck, qs, installs run in the VM `cachyos-test` via `cachyos/vm/vm.sh`. ISO build via `cachyos/iso/bin/slievr-iso-make` (renamed in this branch — use whichever name exists at the time) is the allowed host build. Reading files and `git` on the host are fine.
- No migration code: no shims, no compatibility symlinks, no "if old path exists" logic. Old names disappear.
- Use `git mv` for renames so history follows.
- Brand: product `fledge` (lowercase); org byline "made by moonlight" stays in user-visible branding copy only; owl unchanged. Default username stays `slievr`.
- `fledge` resolution: longest leading word run `w1-…-wn` matching an executable `libexec/w1-…-wn`; built-ins `hypr`, `settings`, `help` first; words must match `^[a-z0-9][a-z0-9_.]*$` (no `/`, no `..`) or exit 2.
- After any change to Hyprland config in the VM: `hyprctl reload` (autoreload is off); after config-manager-level changes: `vm.sh relogin`.
- Shell scripts: bash, `set -euo pipefail`, shellcheck-clean (`-x -S warning`), comments explain why. Commit messages `area: what and why` (`fledge:`, `shell:`, `iso:`, `install:`, `theme:`, `docs:`, `vm:`, `ci:`).

## Review Focus

- **A bind, menu entry, shell action or script calling a name that no longer exists**: Task 7's walker resolves every exec/shell string in the defaults and every `fledge …` in the menu/scripts/QML.
- **A dynamically built script name** (`"slievr-$x"`, `slievr-${kind}-…`): Task 1 must find these before pruning; Task 3 must convert them.
- **Live installer** after the rename: sudoers paths, `/etc/fledge-installer`, the live user, `/usr/share/fledge` all line up (Task 5 sanity checks + Task 7 ISO run).
- **Path traversal through `fledge` words**: rejected (Task 3 tests).

---

### Task 1: Reachability inventory (no deletions)

**Files:** Create `docs/superpowers/notes/2026-10-18-script-inventory.md`.

- [ ] For every file in `dot-local/share/slievr-cachy/bin/`, find references across the repo (`git grep -n` of its name, plus dynamic forms: `slievr-\$`, `slievr-\${`, `"slievr-"`, string concatenation in QML/JS/Lua, `.desktop`/`systemd` units, `dot-config/**`, `dot-local/share/mbm/defaults/settings.json`, the shell QML, `cachyos/**`). Build the call graph from roots: settings defaults (exec/shell actions), `slievr-menu` and what it offers, shell QML, Hyprland Lua config, bootstrap/installer/firstboot, units, ISO airootfs.
- [ ] Write the inventory: a table `script | kept/dropped | reached from (or "unreachable") | notes`, a list of every `webapp` script (dropped), and a list of dynamic-name call sites with what they can resolve to. Proposed new name for each kept script (`slievr-<g>-<a>` → `fledge <g> <a>`), flagging awkward groups (one-off prefixes) with a suggested regrouping only where the current name is misleading — default is the mechanical mapping.
- [ ] Commit `docs: script inventory for the fledge rename (kept, dropped, dynamic call sites)`. **Stop: the controller shows the drop list to the user for veto before Task 2.**

### Task 2: Prune

- [ ] `git rm` every script the approved inventory drops (incl. all webapp scripts) and any menu entries, binds, defaults, docs or tests that only served them. Run all suites + shellcheck in the VM. Commit `fledge: prune unreachable and webapp scripts (inventory in docs/superpowers/notes)`.

### Task 3: One tree, `fledge` dispatcher, scripts to libexec

**Files:** `git mv dot-local/share/mbm/{lib,defaults,assets,test}` → `dot-local/share/fledge/…` (merge `test/` with fledge's), `dot-local/share/slievr-cachy/bin/slievr-*` → `dot-local/share/fledge/libexec/*` (strip `slievr-`), `dot-local/share/slievr-cachy/default` → `dot-local/share/fledge/default`, its README/LICENSE/VENDORED_VERSION → `dot-local/share/fledge/` (README rewritten for fledge; keep the Omarchy LICENSE + attribution); delete `dot-local/share/mbm/bin/mbm` after folding its logic into `fledge`. Modify `dot-local/share/fledge/bin/fledge`, PATH wiring (stowed uwsm env; only `~/.local/share/fledge/bin`), every caller.

**Interfaces — Produces:** `fledge settings <…>` (exactly the old `mbm settings` subcommands/flags), `fledge hypr <…>` (unchanged), `fledge help [group]`, `fledge <group> <action> [args]` → `libexec/<group>-<action>`.

Dispatcher core (put in `fledge`):

```bash
# Longest-prefix resolution: `fledge a b c x` runs libexec/a-b-c if it exists
# (with x as its argument), else libexec/a-b (with c x), else libexec/a.
resolve() {
  local -a words=("$@") ; local n name
  for ((n = ${#words[@]}; n >= 1; n--)); do
    name="$(IFS=-; echo "${words[*]:0:n}")"
    [[ -x "$LIBEXEC/$name" ]] && { printf '%s\n%d\n' "$name" "$n"; return 0; }
  done
  return 1
}
```

Validate every word against `^[a-z0-9][a-z0-9_.]*$` before resolving (`..`, `/`, uppercase → exit 2). `help` prints groups (first word of libexec names) or a group's actions with each script's first `#` comment line after the shebang.

- [ ] **TDD** `dot-local/share/fledge/test/test-dispatch.sh` with a temp `LIBEXEC` (env override): longest match wins; args pass through verbatim (spaces, quotes); built-ins (`hypr`, `settings`, `help`) first; unknown → exit 2 + "did you mean" (prefix matches); `../x`, `a/b`, `A` rejected; `help` and `help capture` output.
- [ ] Move trees; convert every caller: settings defaults exec/shell strings, menu (now `libexec/menu`), other libexec scripts (`slievr-x-y` → `fledge x y`, including dynamic forms from the inventory), shell QML, Hyprland Lua config (autostart, rules, binds generator if it references scripts), bootstrap, installer files, units, tests, verify scripts, `vm.sh`. `mbm settings …` → `fledge settings …` everywhere. Settings defaults must be migrated in place (they're v2 data — just string edits) and the v1 fixture (`defaults-v1.json`) left byte-identical (it's history; migration tests that map old strings must now produce `fledge …` forms — update the migration table's zoom mapping and expectations accordingly).
- [ ] All suites + shellcheck in the VM; `vm.sh restow`, `fledge settings apply`, `vm.sh shell`; spot-check 10 binds and 10 menu entries. Commit in logical pieces (`fledge: one tree …`, `fledge: dispatcher …`, `fledge: callers use fledge <group> <action>`).

### Task 4: Shell, config and state dirs, env vars

- [ ] `git mv dot-config/quickshell/mbm` → `dot-config/quickshell/fledge`; `mbm-shell.service` → `fledge-shell.service` (+ its `.wants` link); every `qs -c mbm` → `qs -c fledge` (IPC calls in defaults, scripts, QML, tests, docs); `~/.config/mbm` → `~/.config/fledge`, `~/.local/state/mbm` → `~/.local/state/fledge` everywhere (settings.sh defaults, QML Settings, env-hyprland, hyprland.lua loader paths, toggles, verify scripts); `MBM_*` → `FLEDGE_*`; QML type/file names containing `mbm` → `fledge`; the `mbm-record` submap → `fledge-record`; `mbm-lock` PAM service → `fledge-lock`.
- [ ] VM: restow (the old `~/.config/mbm` etc. on the dev VM are stale — remove them by hand in the VM, no migration code), apply, relogin; shell up via `fledge-shell.service`; IPC calls work; settings window edits persist under `~/.config/fledge`. All suites. Commit `shell: the shell, its service and its config are fledge`.

### Task 5: Installer, ISO, firstboot, themes, repo URL

- [ ] Installer qs config `mbm-installer` → `fledge-installer`; `/etc/mbm-installer` → `/etc/fledge-installer`; `mbm-probe|install|cleanup` → `fledge-probe|install|cleanup` (sudoers rule, polkit, file_permissions, sanity list); `/run/mbm-answers.env` → `/run/fledge-answers.env`; `/var/log/mbm-install.log` → `/var/log/fledge-install.log`; `@@mbm` → `@@fledge` (progress.sh, Progress.js, replay.sh, tests); live user `moonlight` → `fledge` (sysusers, getty autologin, home dir, polkit, sudoers); `/usr/share/slievr-cachy` → `/usr/share/fledge`; `slievr-firstboot` → `fledge-firstboot` (+ done-guard path, `99-slievr-firstboot`); `99-mbm-install` → `99-fledge-install`; Plymouth and SDDM theme dirs `slievr-cachy` → `fledge`; colour theme `made-by-moonlight` → `fledge` (theme dir, `current` symlink target, theme.name, render-theme defaults, tests, branding scripts); `DOTFILES_REPO` → `https://github.com/made-by-moonlight/fledge.git`; checkout path `~/proj/slievr-cachy` → `~/proj/fledge` in installer, bootstrap, firstboot, verify scripts, `vm.sh` (`VM_REPO`); `cachyos/iso/bin/slievr-iso-make|boot` → `fledge-iso-make|boot`; `release/` ISO name already `fledge-*`.
- [ ] All suites + shellcheck; build the ISO. Commit in logical pieces.

### Task 6: Name guard, docs

- [ ] `cachyos/check-names.sh` (CI step): fail on `slievr` (allowed: `USERNAME="slievr"` default in profile.sh, the `slievr` VM user in `cachyos/vm/*` and tests, history docs under `docs/superpowers/{specs,plans}` dated before 2026-10-18 and `docs/superpowers/notes/2026-10-18-script-inventory.md`), `\bmbm\b`/`mbm-`/`MBM_`, and `made-by-moonlight` (allowed: the GitHub org URL, the brand byline text "made by moonlight" with spaces is always allowed). Test it against a temp file with each forbidden form.
- [ ] AGENTS.md (brand rule: product fledge, byline made by moonlight; new components use `fledge`; layout section; roadmap: B's command shape done, internals pending), README.md, every component README (`dot-local/share/fledge/README.md`, `cachyos/*/README.md`). Commit `docs: fledge everywhere`.

### Task 7: Verify end to end

- [ ] Walker `cachyos/iso/test/verify-commands.sh` (runs in a session): every exec/shell action in the merged settings resolves (`fledge …` → `fledge help`-resolvable libexec or built-in; `qs -c fledge ipc call t f` → target/function exists in `Ipc.qml`); every `fledge …` string in libexec scripts and shell QML resolves. Add to verify-shell.sh or run alongside.
- [ ] Rebuild ISO; destroy VM; fresh keyboard-driven install; `verify-install.sh`, `verify-shell.sh`, `verify-commands.sh` all PASS (except the known `git_main_branch` on a branch build).
- [ ] FINAL STATE: destroy + re-boot the VM from the final ISO on the installer Welcome page (`fledge-iso-boot` in background), screenshot.

### Task 8: Repo move (controller, with the user)

- [ ] After merge approval, and confirming with the user right before each: `gh repo rename fledge` then `gh repo transfer made-by-moonlight` (check `gh` syntax/version; or `gh api`), `git remote set-url origin https://github.com/made-by-moonlight/fledge.git`, push. Then move `~/proj/slievr-cachy` → `~/proj/fledge` and the Claude project memory folder (`~/.claude/projects/-home-slievr-proj-slievr-cachy` → `…-fledge`).
