# Hyprland on Lua: design

**Date:** 2026-10-17
**Status:** implemented on `hypr-lua` (plan `docs/superpowers/plans/2026-10-17-hyprland-lua.md`); verified end to end in the VM (desktop, rebuilt ISO live session, fresh install). Amendments made during implementation are marked **Amended**.
**Branch:** `hypr-lua` (from `main` with the graphical installer merged)
**Evidence:** `docs/superpowers/notes/2026-10-17-hyprland-lua-spike.md` (spike run in the VM on Hyprland 0.56.2; the key facts are under Problem below)

## Problem

Hyprland 0.56 shows "You are using the .conf config format, support for which
will be removed in Hyprland 0.57" on every login. There is no option to hide
it; 0.57 drops `.conf`. Hyprland 0.56 already reads `~/.config/hypr/hyprland.lua`
and picks it over `hyprland.conf` when the session starts.

The spike found the switch is not just a config translation. Under a Lua
config:

- `hyprctl dispatch <string>` is evaluated as `return hl.dispatch(<string>)`,
  so every legacy string dispatch (`workspace 2`, `exec kitty`, `submap reset`,
  `layoutmsg …`) fails. Quickshell's `Hyprland.dispatch("…")` fails the same way.
- `hyprctl keyword` is refused ("Use eval") but exits 0. `hyprctl --batch` of
  failing dispatches also exits 0. Scripts break silently.
- `hyprctl eval '<lua>'` and `hyprctl dispatch '<hl.dsp expression>'` work and
  report errors with a non-zero exit.
- Queries (`clients -j`, `monitors -j`, `activewindow`, `binds -j`, `submap`,
  `configerrors`, `dismissnotify`, `reload`) are unchanged.
- The config manager is chosen at session start; `reload` never switches.

So every caller that sends a dispatcher string or a keyword must change in the
same branch as the config.

## Goals

- The desktop (and the live installer session) run on a Lua config. No
  ".conf format" notice, empty `hyprctl configerrors`.
- The Hyprland config is ours: the vendored Omarchy `hypr-defaults/` is
  folded into fledge-owned Lua modules and deleted.
- mbm settings keep generating binds, monitors, workspaces and input, now as
  Lua, from **structured** actions.
- Every IPC caller goes through one helper per language, which fails loudly.
- Existing users' settings overrides migrate automatically.

## Non-goals

- The full `mbm` → `fledge` rename (CLI, `~/.config/mbm`, `qs -c mbm`,
  `mbm-shell.service`). That ships with the repo rename to
  `made-by-moonlight/fledge`, straight after this. This branch only introduces
  the new `fledge` CLI for the Hyprland helper.
- Rewriting the `slievr-*` scripts (project B). Only their Hyprland calls change.
- Theme editing (project C). The theme renderer only gains a Lua output.
- Changing any behaviour: binds, rules, looks and autostart stay as they are.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Bind action storage | Structured: `{"dsp": "<hl.dsp name>", "args": {…}}`, plus the existing `{"exec"}` and `{"shell"}` | Validatable, editable, maps 1:1 to `hl.dsp.*` |
| Vendored Omarchy defaults | Port into fledge-owned modules, delete `hypr-defaults/` | The config is ours now; one place per concern |
| IPC helpers | bash `fledge hypr dispatch\|set\|eval`; QML `Hypr` singleton | One place that knows the Lua syntax and checks errors |
| Theme colours | Renderer also emits a Lua table; `hyprland.lua` loads it | Minimal; project C replaces it |
| Generated/optional files | Loaded through a guarded loader (`pcall`) | A bad generated file loses only its own content, never emergency mode |

## Config layout

Stowed from `dot-config/hypr/` into `~/.config/hypr/`:

```
hyprland.lua          entry point: package.path, load order, the guarded loader
fledge/envs.lua       hl.env(...)               (from hypr-defaults/envs.conf + envs.conf)
fledge/looknfeel.lua  general/decoration/animations/curves/layouts/misc
                      (hypr-defaults/looknfeel.conf + looknfeel.conf merged)
fledge/rules.lua      window and layer rules (windows.conf, hypr-defaults/windows.conf,
                      hypr-defaults/apps.conf + apps/*.conf)
fledge/autostart.lua  hl.on("hyprland.start", …) (autostart.conf + hypr-defaults/autostart.conf)
fledge/misc.lua       anything left: xdph, hyprsunset hooks, allow_session_lock_restore, …
fledge/load.lua       the guarded loader (below)
```

`hyprland.lua` order (**Amended** to what is built): envs → looknfeel → misc →
rules → theme → binds (or the safety net, below) → input → monitors →
workspaces → toggles (`~/.local/state/hypr-toggles/*.lua`) → autostart. Later
`hl.config` calls override earlier ones, as later `source`s did.

Deleted: `hyprland.conf`, every other `dot-config/hypr/*.conf`,
`dot-config/hypr/hypr-defaults/`. Files that belong to other programs
(`hypridle.conf`, `hyprlock.conf`, `hyprsunset.conf` if Hyprsunset reads it)
stay; check each before deleting.

### Guarded loader

```lua
-- fledge/load.lua: load(path, what) -> runs a file if present; on error, keeps
-- going and tells the user, so one bad file can't take every bind with it.
```

- Missing file: silently skipped (fresh account before `mbm settings apply`).
- Error: `hl.notification.create` with the file and the message, and the error
  is returned so `configerrors`-style checks can see it.
  **Amended:** the failure surfaces as a notification (`fledge: <file>: <error>`,
  error icon, colour `rgb(ff5555)`, 15 s) plus a line on stderr (the user
  journal under uwsm), **not** in `hyprctl configerrors`: Hyprland has no API to
  add to that list. Tooling checks the notification (`hl.notification.get()`
  via `hyprctl repl`, as `verify-shell.sh` does) or the journal.
- **Amended:** `hyprland.lua` requires `fledge/load.lua` under `pcall`, with a
  minimal inline stand-in loader if it is missing or broken (a reload mid-way
  through a git pull or restow), so even that isn't emergency mode.
- Paths: generated files live in `~/.local/state/mbm/hypr/`, loaded with
  `dofile` via an absolute path built from `os.getenv("HOME")`.

- **Amended:** inside a file, one refused call costs only itself. `binds.lua`
  wraps each `hl.bind` (and the submap) in `pcall` and `fledge/rules.lua` each
  rule; what failed is listed once in a `fledge: binds.lua: …` /
  `fledge: rules.lua: …` notification (and stderr). If `binds.lua` is missing
  or fails to load, `hyprland.lua` binds a safety net: Super+Return terminal,
  Super+Space launcher, Super+K keybind settings, Super+Escape system menu,
  Super+M exit.

`hyprland.lua` itself must stay tiny and syntax-checked in CI: an error there
is emergency mode (SUPER+Q terminal, SUPER+R run, SUPER+M exit).

### Autoreload (Amended)

Hyprland's file-watch autoreload is **off** (`misc.disable_autoreload = true`,
desktop `fledge/misc.lua` and the live config). It caught half-written files
during sync/stow (emergency mode once, and a 0.56.2 deadlock rendering the
error bar). Everything that writes Hyprland config reloads explicitly:
`mbm settings apply`, the toggles, theme-set, bootstrap, `vm.sh sync|restow`.
After hand-editing `~/.config/hypr`, run `hyprctl reload` or slievr-menu ›
Setup › Config › Reload Hyprland (which also reports config errors).

## mbm settings

### Schema change (settings `version` 1 → 2)

A bind's `action` (or each element of an action list) is exactly one of:

| Form | Meaning | Generated Lua |
|---|---|---|
| `{"exec": "cmd"}` | run a command | `hl.dsp.exec_cmd("cmd")` |
| `{"shell": "target.fn args"}` | mbm shell IPC (unchanged) | `hl.dsp.exec_cmd("qs -c mbm ipc call target fn args")` |
| `{"dsp": "window.move", "args": {"workspace": 3, "follow": false}}` | a Hyprland dispatcher | `hl.dsp.window.move({workspace = 3, follow = false})` |
| `{"dsp": "window.close"}` | dispatcher without args | `hl.dsp.window.close()` |

- `dsp` is validated by `check.jq` against the dispatcher names in
  `hl.meta.lua` (`HL.DspNamespace` and its sub-namespaces), held as a list in
  `dot-local/share/mbm/lib/dsp-names.json` with a comment on how it was made.
- `args` is an object of string/number/boolean values (one level; nested only
  where a dispatcher needs it, e.g. `send_shortcut`), rendered as a Lua table.
  Some dispatchers take a positional argument (`layout("togglesplit")`,
  `submap("reset")`, `workspace.toggle_special("x")`): `"args": "togglesplit"`
  (a string) renders as a single positional argument.
- An action list becomes one function bind:
  `function() hl.dispatch(a) hl.dispatch(b) end`.
- Flags map to `hl.bind` options: `e` repeating, `l` locked, `r` release,
  `n` non_consuming, `t` transparent, `i` ignore_mods, `p` dont_inhibit;
  `label` → `description`. **Amended:** `s` (separate keysyms) has no Lua
  equivalent, so `check` rejects it and migration reports a v1 bind using it as
  unconverted (the flag is kept, never silently dropped). Mouse binds (`m`) use `hl.dsp.window.drag()` /
  `window.resize()` on `mouse:272` / `mouse:273`. Each mapping is checked
  against `HL.BindOptions` and in the VM.
- `exec` / `shell` strings are rendered as Lua string literals (escape `\`,
  `"`, newlines); the old `#` → `##` escaping goes.

### Migration

`mbm settings apply` (and `check`) recognise a version-1 user file. Before
merging, it converts every `{"dispatch": "<legacy string>"}` in the user's
overrides with a translation table (the spike's dispatcher table, held in
`lib/migrate-dispatch.jq`), writes the file back atomically with
`"version": 2`, keeps a backup `settings.json.v1`, and prints what it
converted. A string it can't translate is left as `{"dispatch": …}` and
reported by `check` as an error naming the bind; it is never dropped.
**Amended:** `exec [rules] cmd` is left unconverted too (`{exec}` has no place
for rules). The v1 defaults' two zoom commands (`hyprctl keyword
cursor:zoom_factor …`) are mapped, as exact strings, to their `fledge hypr`
forms. `check` (and the keybind editor's command field) reject any other
`exec`/`shell` command running legacy IPC (`hyprctl keyword`, `--batch`/`-b`,
`dispatch` + a legacy string), naming the bind; CI's
`cachyos/check-legacy-ipc.sh` fails on such calls in the code. The
shipped defaults are rewritten to version 2 by hand in this branch (89 binds,
24 dispatcher kinds), and the migration is tested against them: migrating the
old defaults must equal the new defaults.

### Generators

`gen-binds.jq`, `gen-monitors.jq`, `gen-workspaces.jq`, `gen-input.jq` emit
`binds.lua`, `monitors.lua`, `workspaces.lua`, `input.lua` into
`~/.local/state/mbm/hypr/` (old `*.conf` there are removed on apply). The
`mbm-record` submap becomes `hl.define_submap("mbm-record", …)` with the
SUPER+CTRL+ALT+Escape reset bind. After writing, `apply` reloads Hyprland
(`hyprctl reload`) as today when in a session.

### Settings window

The keybind editor's "Hyprland dispatcher" kind takes a short form,
`window.move workspace=3 follow=false` (name, then `key=value` pairs; a bare
word is the positional argument), parsed into `{dsp, args}` with inline
validation against the same name list. Existing binds display their
dispatcher in that short form.

## IPC helpers

### bash: `fledge`

New CLI `dot-local/share/fledge/bin/fledge`, on PATH like `mbm` (uwsm env and
fish/bash paths). Subcommands:

- `fledge hypr dispatch '<hl.dsp expr>'`, e.g. `'hl.dsp.focus({workspace = 3})'`
- `fledge hypr set '<hl.config table body>'`, e.g. `'input = { kb_layout = "gb" }'`,
  runs `hyprctl eval 'hl.config({ … })'`
- `fledge hypr eval '<lua>'`
- **Amended:** `fledge hypr quote '<text>'` prints a double-quoted Lua string
  literal (escaped like `lib/lua.jq`), for scripts that splice values
  (addresses, monitor names, command lines) into the three above.

Each checks `hyprctl`'s output for `error:` and exits non-zero with the
message on stderr (rc 0 from `hyprctl` is not trusted). **Amended:** also a
failure: hyprctl rc ≠ 0, and the three refusals the old `.conf` manager prints
with rc 0 and no `error:` (`only supported with the lua config manager`,
`Invalid dispatcher`, `non-legacy parsers`). Exit 1 = failed, 2 = usage.
Tested with a stub `hyprctl` on PATH.

### QML: `Hypr` singleton

`dot-config/quickshell/mbm/services/Hypr.qml`: `dispatch(expr)` (via
`Hyprland.dispatch`, which takes a Lua expression under a Lua config) and
`set(body)` / `eval(lua)` (via a `Process` running `hyprctl eval`), logging
failures with `console.warn`.

**Amended:** the API is `Hypr.dispatch(expr)`, `Hypr.set(body)`,
`Hypr.evalLua(code)` (QML forbids a method named `eval`) and `Hypr.lit(v)`
(a value as a Lua literal, for building `set`/`evalLua` strings). `dispatch`
runs `hyprctl dispatch` too: `Hyprland.dispatch` gives QML no failure result.
Calls run one at a time, each in its own `Process`, with the same failure
rules as `fledge hypr` and a 5 s watchdog. The installer's config gets the same file (a
symlink into `cachyos/iso/installer/services/`, resolved by `cp -rL`).

## Callers to change (from the spike)

| Where | Today | After |
|---|---|---|
| `KeyRecorder.qml:34,47` | `submap mbm-record` / `submap reset` | `Hypr.dispatch('hl.dsp.submap("…")')` |
| mbm `shell.qml:26,62` | `hyprctl dispatch submap reset`, … | `Hypr` |
| `Lock.qml:94,116`, `Idle.qml:51` | `dpms on/off` | `hl.dsp.dpms({action = "on"})` |
| installer `shell.qml:67` | `forcerendererreload` | `hl.dsp.force_renderer_reload()` |
| installer `Xkb.qml:37-38` | `hyprctl keyword input:kb_layout …` | `Hypr.set('input = { kb_layout = …, kb_variant = … }')` |
| `slievr-*` scripts | 24 dispatch, 12 keyword, 2 `--batch` | `fledge hypr dispatch\|set` |
| settings zoom binds | `hyprctl keyword cursor:zoom_factor` | `fledge hypr set 'cursor = { zoom_factor = … }'` |
| `bootstrap.sh:391` | `hyprctl keyword env SHELL,…` | `fledge hypr eval 'hl.env("SHELL", …)'` |
| `verify-shell.sh:61`, `vm.sh:92`, installer `dev/run.sh:16` | `hyprctl dispatch exec …` | `hyprctl dispatch 'hl.dsp.exec_cmd("…")'` |
| live ISO `etc/mbm-installer/hyprland.conf` | `.conf` + `dismissnotify` | `hyprland.lua`; exit via `hl.dsp.exit()` |

A repo-wide grep for `hyprctl dispatch`, `hyprctl keyword`, `--batch`,
`Hyprland.dispatch(` must come back clean (or only Lua forms) at the end.

## Theme

`cachyos/branding/render-theme.sh` also renders `theme/hyprland.lua`
returning `{ activeBorderColor = "rgb(f4af03)", … }` from the same template
values; `hyprland.lua` loads it with the guarded loader and applies the
colours to `general.col.active_border` and `group.col.border_active`. The
`.conf` theme file is no longer read by Hyprland (kept only if other tools use
it; checked during implementation). **Amended:** a theme may ship its own
`hyprland.lua` (returning the table, and calling `hl.config` for more); the
leftover Omarchy themes gruvu and pandora were removed instead of ported, so
made-by-moonlight (rendered from the template) is the only theme.
`slievr-theme-set-templates` finds the vendored templates without `$OMARCHY_PATH`.

## Side fix

`fledge/rules.lua` matches the settings window by its current title
(`fledge · settings`), so it floats and sizes again (broken on `main` since
the fledge rename).

## Existing installs

`bootstrap.sh` stows `hyprland.lua` and the modules, runs `mbm settings apply`
(which migrates the user file and writes the Lua fragments), and removes the
now-dangling `*.conf` links. The next login uses Lua.

**Amended:** a `.conf` session that finds `hyprland.conf` gone writes Hyprland's
stub `hyprland.conf` ("This config is a STUB!") back into `~/.config/hypr`,
which is the repo through the stow fold, and rewrites it whenever it is
removed while that session runs. So bootstrap removes it only when it is
untracked, carries the marker in its first 200 bytes and no `.conf` session is
running, and `fledge/autostart.lua` removes it (same marker check) at the
first Lua login. A user's own `hyprland.conf` is never touched.

**Amended:** the running `.conf` session does *not* keep working: the repo is
stow-folded, so `git pull` deletes `~/.config/hypr/hyprland.conf` at once, and
the session (autoreload on) loads that stub within seconds: Hyprland's stock
binds, rules and monitors. Bootstrap detects the `.conf` session (`fledge hypr
eval` refused with the `.conf` manager's message; any other failure is
reported as "could not tell") and ends by saying, on stdout and as a critical
notification, that the session is on Hyprland's fallback config and to log out
and back in now. It skips Hyprland's SHELL update there (the next login has
it). The upgrade instructions (README "Upgrade", AGENTS.md) are: `git pull`,
bootstrap, log out at once, or do both from a TTY. Verified in the VM: a
`.conf` session, the pull simulated, bootstrap, then a relogin to Lua with the
stub gone.

## Testing

- **Unit (VM):** generator output against expected `.lua` fixtures; migration
  of every legacy dispatcher kind in the old defaults (old defaults migrated =
  new defaults); `check.jq` rejects unknown `dsp` names and bad `args`;
  Lua-string escaping; `fledge hypr` against a stub `hyprctl`; Lua syntax check
  of every shipped and generated `.lua` with `luac -p` (Lua 5.5 if packaged,
  else the closest `luac`; add it to CI's tool list).
- **VM, desktop:** restow + `mbm settings apply` + relogin. `verify-shell.sh`
  gains: Hyprland log says "Using lua config", `hyprctl configerrors` empty, no
  ".conf format" or fledge notification, bind count and descriptions match
  settings, the `mbm-record` submap exists and `fledge hypr` enters and leaves
  it, `fledge hypr dispatch|set` work, the settings window floats at 960x680,
  the zoom binds' commands work, KeyRecorder records a key (a bare F-key typed
  with wtype), a manual lock turns the screens off (dpms) and unlock on. A
  broken `binds.lua` (on a reload and across a relogin) leaves only the
  safety-net binds, a fledge notification, and look and feel, input, monitors
  and workspace rules intact. **Amended:** `slievr-*` actions are not sampled
  beyond the night-light toggle; idle dpms is not exercised (it needs real
  idle time); every sized window rule (localsend 1100x700, PiP 600x338 pinned,
  floating-window 875x600, settings 960x680) was checked live once. Steam's
  size rules don't apply because a later rule tiles every Steam window, as on
  the `.conf` config.
- **ISO:** rebuild, boot (live session on Lua, no notice, live keyboard switch
  works), full install, `verify-install.sh`.
- **Amended (verified):** the migration table's less obvious mappings were
  checked live by effect: `moveintogroup d` → `window.move({into_group = d})`;
  `changegroupactive N` → `group.active({index = N})`, 1-based like the legacy
  form (1 = first window); `sendshortcut M, K, activewindow` →
  `send_shortcut({mods, key, window = "activewindow"})` (the three clipboard
  binds deliver CTRL+Insert, SHIFT+Insert, CTRL+X); `alter_zorder top` →
  `window.alter_zorder({mode = "top"})`.

## Open risks

- `hl.meta.lua` is an API in flux (0.56 is the first Lua release); 0.57 may
  rename things. Keep every Hyprland-specific name in the generator, the two
  helpers and `fledge/*.lua`, nowhere else.
- Unknown keys in dispatcher arg tables and bind options are silently ignored:
  `check.jq` validation and VM checks are the only guard.
- A syntax error in `hyprland.lua` = emergency mode. Keep it minimal, CI
  syntax-checks it.
- `size` in one window rule didn't apply in the spike (not chased). **Amended:**
  every sized rule was checked in the VM and applies, except Steam's, which a
  later rule tiles exactly as the old `.conf` order did (see Testing).
