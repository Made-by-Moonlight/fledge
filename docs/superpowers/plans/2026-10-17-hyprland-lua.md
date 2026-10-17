# Hyprland on Lua Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the fledge desktop and the live installer session from Hyprland's `.conf` format to its Lua config, with every IPC caller switched to the Lua dispatch/eval forms, so the ".conf format" notice is gone and nothing breaks at 0.57.

**Architecture:** A small `hyprland.lua` loads fledge-owned modules (`fledge/*.lua`, ported from today's config and the vendored Omarchy defaults) plus generated fragments that `mbm settings apply` now writes as Lua from structured bind actions (settings v2, auto-migrated). All Hyprland IPC goes through `fledge hypr dispatch|set|eval` (bash) or the `Hypr` QML singleton, which fail loudly.

**Tech Stack:** Hyprland 0.56.2 Lua API (`hl.*`, stubs at `/usr/share/hypr/stubs/hl.meta.lua`), bash, jq, Quickshell 0.3.2 QML, `luac -p` for syntax checks, archiso.

**Spec:** `docs/superpowers/specs/2026-10-17-hyprland-lua-design.md`. **Spike evidence (read it):** `docs/superpowers/notes/2026-10-17-hyprland-lua-spike.md`.

## Global Constraints

- Never run project code on the host (AGENTS.md rule 1). Tests, shellcheck, `luac`, `qs`, installs: VM `cachyos-test` only, via `cachyos/vm/vm.sh sync|run|sudo|shot|type|key`. Reading files and `git` on the host are fine. The ISO build (`cachyos/iso/bin/slievr-iso-make`, docker) is the allowed host-side build.
- Hyprland picks the config manager at session start; after changing the Hyprland config in the VM, test with `cachyos/vm/vm.sh relogin`, never only `hyprctl reload`.
- Lua dispatch forms only: `hyprctl dispatch '<hl.dsp expr>'` and `hyprctl eval '<lua>'`. Never `hyprctl keyword`, never a legacy dispatch string, never `--batch` of legacy strings. `hyprctl` exits 0 on some refusals: success = no `error:` in its output.
- Settings bind action is exactly one of `{"exec": "…"}`, `{"shell": "…"}`, `{"dsp": "<name>"[, "args": {…} | "<positional>"]}` (or a list of them). Settings `version` is 2.
- Flag → `hl.bind` option: `e` repeating, `l` locked, `r` release, `n` non_consuming, `t` transparent, `i` ignore_mods, `p` dont_inhibit; label → `description`. `m` (mouse) binds use `hl.dsp.window.drag()` / `hl.dsp.window.resize()` on `mouse:272` / `mouse:273`.
- Generated files: `~/.local/state/mbm/hypr/{binds,monitors,workspaces,input}.lua`; old `*.conf` there are removed by apply.
- Brand: distro "fledge", org byline "made by moonlight". New CLI is `fledge` (`dot-local/share/fledge/bin/fledge`). Existing `mbm` names stay (full rename is a later project).
- Behaviour must not change: same binds, rules, looks, autostart, env.
- Shell scripts: bash, `set -euo pipefail`, shellcheck-clean (`-x -S warning`), comments explain why. Tests use `cachyos/install/test/lib.sh` (`check`/`contains`, `exit $fail`). Commit messages `area: what and why` (`hypr:`, `mbm:`, `shell:`, `iso:`, `install:`, `docs:`, `vm:`).

## Review Focus

- **A user override still using `{"dispatch": …}`** (anyone with custom binds): auto-migrated once with a `.v1` backup; untranslatable entries reported by `check`, never dropped, never crash apply. Task 3 tests.
- **A syntax/runtime error in a generated fragment or toggle file**: costs only that file (notification), never emergency mode. Task 5 tests the loader; Task 9 checks in the VM by corrupting `binds.lua`.
- **Strings with quotes, backslashes, `#`, `$` in exec/shell commands** (e.g. `bash -c "…"`): rendered as valid Lua strings that run the same command. Task 4 tests.
- **Silent IPC failure** (`hyprctl` rc 0 with `error:`): `fledge hypr` and `Hypr` treat it as failure. Task 1 / Task 6 tests.
- **Mid-session upgrade on a running `.conf` session**: bootstrap says binds apply at next login; nothing deletes the running session's config before logout in a way that breaks it. Task 7.

---

### Task 1: `fledge` CLI with `fledge hypr dispatch|set|eval`

**Files:** Create `dot-local/share/fledge/bin/fledge`, `dot-local/share/fledge/test/test-fledge.sh`. Modify PATH wiring: `dot-config/uwsm/env` (or wherever `~/.local/share/mbm/bin` is put on PATH: grep for `mbm/bin` across `dot-config/`, `cachyos/bootstrap.sh`, `cachyos/vm/vm.sh` SESSION_ENV) to also add `~/.local/share/fledge/bin`; `.github/workflows/iso.yml` (test list, shellcheck globs include `dot-local/share/fledge/bin/*` and `dot-local/share/fledge/**/*.sh`).

**Interfaces — Produces:**
- `fledge hypr dispatch '<expr>'` → runs `hyprctl dispatch '<expr>'`
- `fledge hypr set '<body>'` → runs `hyprctl eval 'hl.config({ <body> })'`
- `fledge hypr eval '<lua>'` → runs `hyprctl eval '<lua>'`
- All: exit 0 on success; on any `error:` in hyprctl output, or hyprctl rc ≠ 0, print hyprctl's output to stderr prefixed `fledge hypr: ` and exit 1. Usage errors exit 2. `HYPRCTL` env var overrides the binary (for tests).

- [ ] **Step 1: Failing test** `test-fledge.sh`: a stub `hyprctl` in a temp dir (writes its argv to a file, prints `ok` or `error: …` / exits N depending on env), `HYPRCTL=$stub`. Checks: dispatch passes the expression as one argv element unchanged (incl. quotes, spaces, `{}`); set wraps as `hl.config({ … })`; eval passes through; `error:` output with rc 0 → exit 1 and message on stderr; rc 7 → exit 1; missing args → exit 2; unknown subcommand → exit 2.
- [ ] **Step 2: Run, expect FAIL** (VM): `cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/slievr-cachy/dot-local/share/fledge/test/test-fledge.sh'`
- [ ] **Step 3: Implement** `fledge` (bash; `case` on `$1 $2`; capture output with `out="$("${HYPRCTL:-hyprctl}" … 2>&1)" || rc=$?`; header comment explains why rc 0 is not trusted, citing the spike).
- [ ] **Step 4: PATH**: add `~/.local/share/fledge/bin` everywhere `~/.local/share/mbm/bin` is added (keep order: fledge, mbm, slievr-cachy). Restow in the VM and check `command -v fledge` inside the session (`vm.sh run`).
- [ ] **Step 5: Run tests + shellcheck, expect PASS.** Commit `fledge: new CLI; fledge hypr dispatch/set/eval talks Lua to Hyprland and fails loudly`.

### Task 2: Lua syntax checking for tests and CI

**Files:** Create `cachyos/install/test/luacheck.sh` (helper: `lua_syntax_ok <file>...` using `luac -p`), `dot-local/share/mbm/test/test-lua-syntax.sh` (checks every `*.lua` under `dot-config/hypr/` and `cachyos/iso/configs/airootfs/etc/mbm-installer/` that exists). Modify `.github/workflows/iso.yml` tools list (+`lua`) and test list.

- [ ] Ensure `luac` exists in the VM: `cachyos/vm/vm.sh run 'command -v luac || command -v luac5.4'`; if missing, `cachyos/vm/vm.sh sudo 'pacman -S --needed --noconfirm lua'` (VM only — never the host). Note in the report which `luac` version (Hyprland embeds 5.5; 5.4's `luac -p` accepts the subset we write — no `global` declarations).
- [ ] TDD: test-lua-syntax.sh first proves it fails on a deliberately broken temp file and passes on a good one, then checks the repo's files (zero files is fine until Task 5).
- [ ] Commit `mbm: Lua syntax check for shipped and generated Hyprland config`.

### Task 3: Settings v2 — structured actions, validation, migration

**Files:** Create `dot-local/share/mbm/lib/dsp-names.json`, `dot-local/share/mbm/lib/migrate-dispatch.jq`. Modify `dot-local/share/mbm/lib/check.jq`, `dot-local/share/mbm/lib/settings.sh` (migration on load), `dot-local/share/mbm/defaults/settings.json` (version 2; every `{"dispatch": …}` rewritten), `dot-local/share/mbm/test/fixtures/defaults.json` (same), tests in `dot-local/share/mbm/test/test-settings.sh` + new `test-migrate.sh`.

**Interfaces — Produces:** settings v2 schema (Global Constraints); `migrate-dispatch.jq`: input a legacy dispatch string, output `{dsp, args?}` or `null` when unknown; `settings.sh` migrates a version-1 user file on any `mbm settings` command that reads it (apply/check/get/set): converts, writes back atomically with `"version": 2`, keeps `settings.json.v1`, prints `mbm: migrated N binds to settings v2 (backup: …)` to stderr; untranslatable entries stay as `{"dispatch": …}` and `check` reports `binds.<id>: can't convert dispatcher "<str>"; rewrite it as {dsp, args}`.

**Translation table** (`migrate-dispatch.jq`; from the spike, `✓` verified live; verify the others against `hl.meta.lua` and in the VM in Task 9):
`exec X`→{exec:X} · `workspace N|e+1|e-1|previous|name:x`→{dsp:"focus",args:{workspace:N or "e+1"…}} ✓ · `movetoworkspace N`→{dsp:"window.move",args:{workspace:N}} ✓ · `movetoworkspacesilent N`→{dsp:"window.move",args:{workspace:N,follow:false}} ✓ · `togglespecialworkspace X`→{dsp:"workspace.toggle_special",args:"X"} ✓ · `movefocus l|r|u|d`→{dsp:"focus",args:{direction:"left"|…}} · `focusmonitor X`→{dsp:"focus",args:{monitor:X}} · `swapwindow d`→{dsp:"window.swap",args:{direction:…}} · `resizeactive X Y`→{dsp:"window.resize",args:{x:X,y:Y,relative:true}} ✓ · `movecurrentworkspacetomonitor X`→{dsp:"workspace.move",args:{monitor:X}} · `togglefloating`→{dsp:"window.float",args:{action:"toggle"}} ✓ · `fullscreen 0|1`→{dsp:"window.fullscreen"} / {dsp:"window.fullscreen",args:{mode:"maximized"}} ✓ · `fullscreenstate A B`→{dsp:"window.fullscreen_state",args:{internal:A,client:B}} · `killactive`→{dsp:"window.close"} ✓ · `pseudo`→{dsp:"window.pseudo"} · `bringactivetotop`→{dsp:"window.bring_to_top"} · `cyclenext [prev]`→{dsp:"window.cycle_next"} / args:false · `togglegroup`→{dsp:"group.toggle"} ✓ · `moveintogroup d`→{dsp:"window.move",args:{into_group:"l"…}} · `moveoutofgroup`→{dsp:"window.move",args:{out_of_group:true}} · `changegroupactive f|b|N`→{dsp:"group.next"}/{dsp:"group.prev"}/{dsp:"group.active",args:{index:N}} · `layoutmsg X`→{dsp:"layout",args:"X"} · `sendshortcut MODS, KEY, WIN`→{dsp:"send_shortcut",args:{mods,key,window}} · `submap X`→{dsp:"submap",args:"X"} ✓ · `dpms on|off`→{dsp:"dpms",args:{action:…}} ✓ · `movewindow` / `resizewindow` (mouse)→{dsp:"window.drag"} / {dsp:"window.resize"} ✓ · `exit`→{dsp:"exit"} · `forcerendererreload`→{dsp:"force_renderer_reload"}. Direction letters: l→left, r→right, u→up, d→down. Numbers become JSON numbers.
`dsp-names.json`: every function name under `HL.DspNamespace` and its sub-namespaces in `/usr/share/hypr/stubs/hl.meta.lua` (dotted, e.g. `window.move`), with a `_comment` naming the source and Hyprland version; a one-liner in the plan report shows how it was extracted.

- [ ] **Step 1: Failing tests** (`test-migrate.sh`): one check per table row (exact JSON out); unknown → null; **the old v1 defaults (copy the current `defaults/settings.json` to `test/fixtures/defaults-v1.json` before editing it) migrated == the new v2 defaults' binds**; a v1 user file with 3 dispatch binds + 1 unknown → written back v2, backup exists, unknown kept, stderr message; v2 file untouched; `check` rejects `{"dsp":"window.nope"}`, `{"dsp":"focus","args":[1]}`, two kinds in one action, and the leftover `{"dispatch": …}`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** jq table, `check.jq` (`action_ok` accepts exec|shell|dsp(+args object|string|bool|number); `dsp` in `dsp-names.json` passed via `--slurpfile`), `settings.sh` migration, rewrite the defaults to v2 (generate with the migration, then review by eye; commit the result as a static file).
- [ ] **Step 4: Run every test in `dot-local/share/mbm/test/`, expect PASS** (test-settings.sh's existing dispatch-based cases move to dsp form). Commit `mbm: settings v2: binds use structured Hyprland actions; v1 user files migrate automatically`.

### Task 4: Generators emit Lua

**Files:** Modify `dot-local/share/mbm/lib/gen-binds.jq`, `gen-monitors.jq`, `gen-workspaces.jq`, `gen-input.jq`, `settings.sh` (write `*.lua`, remove stale `*.conf` in `$MBM_HYPR_DIR`), fixtures `test/fixtures/expected-*.lua` (replace `expected-*.conf`), `test-settings.sh`.

**Interfaces — Produces:** `binds.lua`, `monitors.lua`, `workspaces.lua`, `input.lua` in `$MBM_HYPR_DIR`; each a plain Lua chunk of `hl.*` calls with the "Generated by `mbm settings apply` … Do not edit" header as `--` comments. `binds.lua` ends with `hl.define_submap("mbm-record", function() hl.bind("SUPER + CTRL + ALT + Escape", hl.dsp.submap("reset")) end)` and its two-line why-comment.

Rendering rules: jq `def lua_str: "\"" + (gsub("\\\\";"\\\\\\\\") | gsub("\"";"\\\"") | gsub("\n";"\\n")) + "\"";`; Lua table from a JSON object with sorted keys, identifier keys bare (`^[A-Za-z_][A-Za-z0-9_]*$`) else `["key"]`; mods `"SUPER SHIFT"` + key → `"SUPER + SHIFT + key"` (empty mods → just key); action → `hl.dsp.<dsp>(<args>)` / `hl.dsp.exec_cmd(<str>)`; list → `function() hl.dispatch(a) hl.dispatch(b) end`; options table only when non-empty, always with `description`. Monitors/workspaces/input: map today's generated fields 1:1 to `hl.monitor{output,mode,position,scale,transform,disabled}`, `hl.workspace_rule{workspace,monitor,default,persistent}`, `hl.config({ input = {…, touchpad = {…}} })` (keys as in today's `.conf` output, incl. `kb_variant` from Task 1 of the installer plan).

- [ ] **Step 1: Failing tests**: expected `.lua` fixtures for the fixture defaults; escaping cases (`exec` with `"`, `\`, `#`, `$`, newline); action list; each flag letter; mouse bind; empty mods; a disabled monitor; `luac -p` on every generated file (Task 2 helper); apply removes an old `binds.conf`.
- [ ] **Step 2: Run, expect FAIL.** **Step 3: Implement.** **Step 4: PASS**, including test-defaults.sh. Commit `mbm: settings apply writes Lua fragments for Hyprland`.

### Task 5: Static config in Lua; delete the .conf tree

**Files:** Create `dot-config/hypr/hyprland.lua`, `dot-config/hypr/fledge/{load,envs,looknfeel,rules,autostart,misc}.lua`. Delete `dot-config/hypr/hyprland.conf`, `dot-config/hypr/{autostart,envs,looknfeel,windows,xdph}.conf` (check `hyprsunset.conf`: keep if hyprsunset reads it), `dot-config/hypr/hypr-defaults/` (whole tree). Modify `cachyos/branding/render-theme.sh` (+ its template dir) to also emit `theme/hyprland.lua`, `cachyos/branding/test-theme.sh`; `dot-config/omarchy/current/theme/hyprland.lua` (rendered, committed like the `.conf` is); `dot-local/share/slievr-cachy/bin/slievr-hyprland-toggle` (toggle files become `.lua`); `dot-config/uwsm/env-hyprland` (fragments check looks for `.lua`).

**Interfaces — Produces:** `fledge/load.lua` returns a module `{ file = function(path) … end, dir = function(dir) … end }`: `file` runs `dofile(path)` under `pcall` if the file exists, on error calls `hl.notification.create({ text = "fledge: " .. path .. ": " .. err, … })` (check the notification API in `hl.meta.lua`) and returns false; `dir` loads every `*.lua` in a directory (sorted; via `io.popen('ls -1 …')` or `lfs`-free equivalent) through `file`. Toggles live in `~/.local/state/hypr-toggles/*.lua` and are loaded with `dir` last-but-one (before autostart), as today's `source = …/*.conf`.

Porting rules: every line of the deleted `.conf` files must land in a module or be listed in the report as intentionally dropped (with why). `source` order → load order (spec). `exec-once` → `hl.on("hyprland.start", function() hl.exec_cmd(…) end)`; `exec` (per reload) → top-level `hl.exec_cmd`. `env = K,V` → `hl.env("K", "V")`. `windowrule`/`layerrule` → `hl.window_rule{match={…}, …}` / `hl.layer_rule{…}` (field names from `hl.meta.lua` `HL.WindowRuleSpec`/`HL.LayerRuleSpec`; regex stays full-match). `$var` → Lua locals. Theme: `local theme = require`-free `load.file`-style read of `~/.config/omarchy/current/theme/hyprland.lua` returning a table; apply `theme.activeBorderColor` to `general.col.active_border` and `group.col.border_active`. Settings-window rule: match the title `fledge · settings` (spec side fix). Keep `misc.allow_session_lock_restore = true` and its comment.

- [ ] **Step 1:** Inventory: list every directive in the files to delete (count per file) in the report; this is the checklist.
- [ ] **Step 2: Failing tests**: `test-lua-syntax.sh` now finds the new files (fails until they exist); add a loader test runnable with plain `lua` (stub a minimal `hl` table: `hl.notification.create` records calls) for missing file (skipped), good file (runs), syntax error (notifies, returns false, caller continues), runtime error (same), `dir` order.
- [ ] **Step 3: Port.** Render the theme Lua. Update the toggle script and uwsm env check.
- [ ] **Step 4: VM:** `vm.sh restow`, `mbm settings apply`, `vm.sh relogin`. Check: Hyprland log line "Using lua config", `hyprctl configerrors` empty, no ".conf format" notification (`hyprctl notify`-free check: screenshot), `hyprctl binds -j | jq length` equals the bind count from settings (+1 submap bind), the settings window floats at its size, a few app rules (pip, terminals) via `hyprctl clients -j`, border colour via `hyprctl getoption general:col.active_border`. Shell dispatch callers are still on legacy strings until Task 6 — expect those (submap/dpms) to fail; note, don't fix here.
- [ ] **Step 5:** All tests + shellcheck PASS. Commit `hypr: the desktop's Hyprland config is Lua (fledge modules replace hyprland.conf and the vendored Omarchy defaults)`.

### Task 6: QML `Hypr` singleton; shell callers; keybind editor

**Files:** Create `dot-config/quickshell/mbm/services/Hypr.qml`, `dot-config/quickshell/mbm/settings/DspShort.js` (+ test `dot-config/quickshell/mbm/test/tst_dspshort.qml`, run with `qmltestrunner` offscreen like the installer's). Modify `KeyRecorder.qml`, `shell.qml` (mbm), `lock/Lock.qml`, `services/Idle.qml`, `settings/pages/Keybinds.qml`, plus any other `Hyprland.dispatch(` / `hyprctl` use under `dot-config/quickshell/mbm` (grep).

**Interfaces — Produces:** `Hypr.dispatch(expr: string)`, `Hypr.set(body: string)`, `Hypr.eval(lua: string)`; failures `console.warn("Hypr: …")`. `DspShort.parse("window.move workspace=3 follow=false")` → `{dsp:"window.move", args:{workspace:3, follow:false}}`; bare word → positional string args; numbers/booleans typed; `DspShort.format(action)` inverse; `DspShort.valid(name)` against a names list (load `dsp-names.json` via FileView or embed a copy generated in Task 3 — pick one, note it).

- [ ] TDD for DspShort (parse/format round-trip, positional, types, unknown name). Implement Hypr + callers (`submap`, `dpms`, the startup `submap reset`). Keybinds editor: "Hyprland dispatcher" field uses DspShort, shows existing dsp binds in short form, saves `{dsp, args}`.
- [ ] VM (Lua session from Task 5): lock + unlock (dpms), idle dpms if testable, KeyRecorder records a key and returns from the submap, add/edit/delete a dispatcher bind in the settings window → apply → `hyprctl binds -j` shows it. No WARN/ERROR from qs. Commit `shell: Hyprland calls go through Hypr (Lua dispatch/eval); keybind editor writes structured dispatcher actions`.

### Task 7: Scripts, zoom binds, bootstrap, verify/vm/dev scripts

**Files:** every `dot-local/share/slievr-cachy/bin/*` that calls `hyprctl dispatch|keyword|--batch` (grep; ~28 files, 24 dispatch / 12 keyword / 2 batch), `dot-local/share/mbm/defaults/settings.json` zoom binds (and anything else in defaults still shelling `hyprctl keyword|dispatch`), `cachyos/bootstrap.sh` (`:391` env SHELL; bootstrap's restow of hypr files; message about next login), `cachyos/iso/test/verify-shell.sh:61`, `cachyos/vm/vm.sh:92`, `cachyos/iso/installer/dev/run.sh:16`.

Rules: dispatch → `fledge hypr dispatch 'hl.dsp…'` using the Task 3 table; keyword `a:b v` → `fledge hypr set 'a = { b = v }'` (nested for deeper keys; device keywords → `hl.device({ name = …, enabled = … })` via `fledge hypr eval`; `monitor` keyword → `hl.monitor{…}` via eval); `--batch` → one `fledge hypr eval` with several `hl.dispatch(...)` lines. Queries (`-j`) unchanged. Where a script previously ignored failures on purpose (`|| true`), keep that, but don't add new swallowing.

- [ ] For each changed script: run it in the VM Lua session (or its relevant subcommand) and record the result in the report as a table (script, call, result). Grep at the end: `rg -n 'hyprctl (dispatch|keyword)|--batch|Hyprland\.dispatch\(' -- dot-local dot-config cachyos` returns only Lua forms or `fledge`/`Hypr` internals.
- [ ] Bootstrap: after stow + `mbm settings apply`, remove dangling `~/.config/hypr/*.conf` links that pointed into the repo (extend the existing dangling-link cleanup); if run inside a `.conf` session, print "Hyprland switches to the Lua config at your next login."
- [ ] All tests + shellcheck PASS. Commit `hypr: scripts, bootstrap and test tools use fledge hypr (Lua dispatch/eval)`.

### Task 8: Live installer session on Lua

**Files:** Create `cachyos/iso/configs/airootfs/etc/mbm-installer/hyprland.lua`; delete `…/hyprland.conf`; modify `cachyos/iso/configs/airootfs/home/moonlight/.bash_profile` (start Hyprland with the Lua config: check how 0.56 takes a Lua path, e.g. `Hyprland --config /etc/mbm-installer/hyprland.lua`, confirm in the VM), `cachyos/iso/installer/services/Xkb.qml` (`Hypr.set('input = { kb_layout = …, kb_variant = … }')`), `cachyos/iso/installer/shell.qml:67` (`Hypr.dispatch('hl.dsp.force_renderer_reload()')`), symlink `cachyos/iso/installer/services/Hypr.qml -> ../../../../dot-config/quickshell/mbm/services/Hypr.qml`, `cachyos/iso/builder/build-iso.sh` (sanity list: `.lua`), `test-lua-syntax.sh` covers the new file.

- [ ] Port the live config (no binds; animations off; misc; ecosystem; `hl.on("hyprland.start", function() hl.exec_cmd("qs -c mbm-installer; hyprctl dispatch 'hl.dsp.exit()'") end)` — verify the exit form; drop the `dismissnotify` workaround and its comment; keep `disable_watchdog_warning`).
- [ ] Dev loop check (`installer/dev/run.sh`) for Xkb/forcerendererreload paths is not possible in dev mode (they're skipped there) — verify in Task 9 on the ISO. Commit `iso: the live installer session runs Hyprland's Lua config`.

### Task 9: Verify end to end, docs

**Files:** `cachyos/iso/test/verify-shell.sh`, `cachyos/iso/test/verify-install.sh`, `AGENTS.md` (Hyprland note: Lua since this branch; IPC rule: use `fledge hypr`/`Hypr`, never keyword/legacy dispatch), `README.md`, `dot-local/share/mbm/README*` if present, `cachyos/iso/README.md`, spec status line.

- [ ] verify-shell.sh gains: "Using lua config" in the current Hyprland log; `hyprctl configerrors` empty; no notification text containing ".conf"; `hyprctl binds -j` count == settings bind count + submap; a bind description present; `hyprctl submap`-based check that `mbm-record` exists in `binds -j`; `fledge hypr dispatch 'hl.dsp.focus({workspace = 2})'` moves to workspace 2 and back; `fledge hypr set 'cursor = { zoom_factor = 1 }'` succeeds; corrupt `~/.local/state/mbm/hypr/binds.lua` → `hyprctl reload` → a fledge notification, other config intact, then `mbm settings apply` restores it.
- [ ] VM desktop: restow, apply, relogin, run verify-shell.sh — all PASS.
- [ ] ISO: rebuild (`slievr-iso-make`), destroy VM, `slievr-iso-boot` (background), check the live session (no notice; keyboard switch to gb applies live — type in the test field; switch to tty2 and back works), full keyboard-driven install as in the installer plan's Task 11 (Return on Disk confirms; wait > 0.5 s on Review), then `verify-install.sh` (README procedure: scp + `ssh -t`) — all PASS, plus verify-shell.sh in the installed system.
- [ ] **Final state:** destroy and re-boot the VM from the final ISO, left on the installer Welcome page (`slievr-iso-boot` in background), screenshot. The user verifies the final system themselves.
- [ ] Docs, commit `docs: Hyprland runs on Lua; IPC goes through fledge hypr`.
