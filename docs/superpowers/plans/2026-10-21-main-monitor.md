# Main monitor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One monitor is the main one and always has the bar; any other monitor's bar can be switched off; the frame is only the bar edge (strip and tabs); notifications, the OSD and quick settings open on the main monitor; the main bar's workspace dots list every monitor's workspaces, grouped.

**Architecture:** Two settings, `bar.main` (a monitor key) and `bar.hidden` (keys), validated by `lib/check.jq` and read by `Settings.qml`. A pure JS module (`services/Main.js`) picks the main monitor and says whether a monitor shows a bar; `ShellState` exposes `mainScreen` from it. `shell.qml` creates a `Bar` only where it shows; `Bar.qml` keeps one reserve; `Frame.qml` draws only the bar edge. Popups read `ShellState.mainScreen`. The Displays card gets the two controls.

**Tech Stack:** QML/Quickshell (Qt 6), `qmltestrunner`, jq, bash.

**Spec:** `docs/superpowers/specs/2026-10-21-main-monitor-design.md`

## Global Constraints

- **Everything that runs project code runs in the test VM** (`cachyos/vm/`, `cachyos-test`), unit tests included: `cachyos/vm/vm.sh sync` then `cachyos/vm/vm.sh run '…'`. Never on the host. The person's desktop runs the shell straight from this repo with file watching off, so nothing changes there until they restart it.
- Monitor keys are Layout.js `keyFor(m, connected)`: `desc:<description>`, else the connector.
- Main fallback: `bar.main` if that key is connected and enabled, else the monitor with the smallest `y`, then smallest `x`.
- `bar.main` beats `bar.hidden`. The hide-bar keybind (`ShellState.barVisible`) still hides every bar.
- Shell only: nothing written to Hyprland, no generator changes, no keys in the defaults file.
- Commit messages: `area: what changed and why` (`shell:`, `fledge:`, `docs:`, `test:`).

## Review Focus

1. **Main unplugged**: the bar moves to the fallback monitor, and comes back when it returns. → Task 2 tests `test_mainAbsent`, `test_mainBack`.
2. **Hiding the bar on the monitor that is main**: the toggle can't, and a hand-edited `bar.hidden` naming the main is ignored. → Task 2 `test_mainBeatsHidden`.
3. **Bar surfaces created and destroyed live** as settings change: no leaked reserve keeping windows pushed down. → Task 7 VM check.
4. **Workspaces grouped**: a workspace moved to another monitor moves group without a restart. → Task 4.

---

### Task 1: Settings: `bar.main` and `bar.hidden`

**Files:**
- Modify: `dot-local/share/fledge/lib/check.jq`
- Modify: `dot-local/share/fledge/test/test-settings.sh`
- Modify: `dot-config/quickshell/fledge/services/Settings.qml`

- [ ] **Step 1: Failing tests** in `test-settings.sh`, beside the other `bad` bar rows:

```bash
bad "bar main not text"          "bar.main must be text"                '{"bar":{"main":3}}'
bad "bar main quote"             "bar.main: monitor name can't contain" '{"bar":{"main":"DP-\"1"}}'
bad "bar hidden not a list"      "bar.hidden must be a list"            '{"bar":{"hidden":"DP-1"}}'
bad "bar hidden entry not text"  "bar.hidden must be a list"            '{"bar":{"hidden":[1]}}'
good "bar main and hidden"       '{"bar":{"main":"desc:Acer X34","hidden":["DP-3"]}}'
```

(Use the file's existing helper for a passing check if `good` is named differently.)

- [ ] **Step 2: Run, see them fail.** `cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/fledge/dot-local/share/fledge/test/test-settings.sh'`
- [ ] **Step 3: `check.jq`.** Add `"main", "hidden"` to the bar `unknown([...])` list, and rules: `main` must be a string with no `"` or `\`; `hidden` must be an array of such strings.
- [ ] **Step 4: `Settings.qml`.** `readonly property string barMain: get("bar", "main", "")` and `readonly property var barHidden: get("bar", "hidden", [])` (non-array → `[]`).
- [ ] **Step 5: Tests pass; commit** `fledge: settings check knows bar.main and bar.hidden`.

### Task 2: Which monitor is main (pure JS)

**Files:**
- Create: `dot-config/quickshell/fledge/services/Main.js`
- Create: `dot-config/quickshell/fledge/test/tst_main.qml`
- Modify: `cachyos/iso/test-shell-qml.sh` (run the new file)

**Interfaces:**
- `pick(mons, mainKey) -> key | ""`: `mons` = `[{key, x, y}]`, enabled monitors only.
- `showsBar(key, mainKey, hidden, mons) -> bool`: true for `pick(mons, mainKey)`, else `!hidden.includes(key)`.

- [ ] **Step 1: Failing tests** `tst_main.qml` (import `"../services/Main.js" as M`): `test_mainNamed`, `test_mainAbsent` (falls back to top-left), `test_mainUnset`, `test_topThenLeft` (a monitor higher up but further right beats one lower and left), `test_mainBeatsHidden`, `test_hiddenOthers`, `test_noMonitors` (`""`), `test_mainBack` (same inputs with the key present again pick it).
- [ ] **Step 2: Run, fail.** `cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test-shell-qml.sh'`
- [ ] **Step 3: Implement** `Main.js` (`.pragma library`).
- [ ] **Step 4: Pass; commit** `shell: pick the main monitor (named, else top-left)`.

### Task 3: Bars only where they show; frame only along the bar edge

**Files:**
- Modify: `dot-config/quickshell/fledge/services/ShellState.qml`
- Modify: `dot-config/quickshell/fledge/shell.qml`
- Modify: `dot-config/quickshell/fledge/bar/Bar.qml`
- Modify: `dot-config/quickshell/fledge/bar/Frame.qml`
- Modify: `dot-config/quickshell/fledge/theme/Theme.qml`

- [ ] **Step 1: `ShellState`.** Build `mons` from `Hyprland.monitors.values` (enabled, with `keyFor` from `../settings/Layout.js` over all connected monitors), then `readonly property string mainKey: Main.pick(...)`, `readonly property var mainScreen` (the `Quickshell.screens` entry whose name is that monitor's connector, else `focusedScreen()`), and `function showsBar(screen)`.
- [ ] **Step 2: `shell.qml`.** Wrap `Bar` in a `LazyLoader` (or `Loader`) with `active: ShellState.showsBar(perScreen.modelData)`, so a monitor without a bar has no bar surface and no reserve.
- [ ] **Step 3: `Bar.qml`.** Keep only the bar-edge `Reserve`. Section insets `Theme.frame + Theme.gap` → `Theme.gap`. Pass `main: ShellState.mainScreen === root.screen` down to `Section` (for Task 4).
- [ ] **Step 4: `Frame.qml`.** The path becomes the strip plus the tabs only: drop the side and far borders and the desktop's corner arcs. Keep the tab fillets, and the straight run where a tab hangs from a screen corner. Update the header comment.
- [ ] **Step 5: `Theme.qml`.** `popupSide: gap` and fix its comment (no side border now).
- [ ] **Step 6: VM check by eye.** `cachyos/vm/vm.sh restow && cachyos/vm/vm.sh shell`, then `cachyos/vm/vm.sh shot`: strip and tabs at the top only, windows to the side edges (bar position bottom too: `fledge settings set .bar.position '"bottom"'`, then reset).
- [ ] **Step 7: Commit** `shell: frame only along the bar edge, and a bar only on monitors that show one`.

### Task 4: The main bar lists every monitor's workspaces

**Files:**
- Modify: `dot-config/quickshell/fledge/bar/Section.qml` (pass `main` to Workspaces)
- Modify: `dot-config/quickshell/fledge/bar/modules/Workspaces.qml`

- [ ] **Step 1:** With `main: true`, group `Hyprland.workspaces` (id > 0) by monitor, monitors ordered by `x` then `y`, workspaces by id. Draw the groups in one `Row` with a separator (a short `Theme.surface` bar, `Theme.gap` either side) between non-empty groups. Without `main`, today's per-monitor filter.
- [ ] **Step 2: VM check.** Move a workspace to another output (`fledge hypr dispatch` with the move-workspace-to-monitor dispatcher) and see it change group with no restart (needs two outputs; see Task 7).
- [ ] **Step 3: Commit** `shell: the main bar's workspace dots cover every monitor, grouped`.

### Task 5: Notifications, OSD and quick settings on the main monitor

**Files:**
- Modify: `dot-config/quickshell/fledge/notifications/Popups.qml`
- Modify: `dot-config/quickshell/fledge/osd/Osd.qml`
- Modify: `dot-config/quickshell/fledge/quicksettings/QuickSettings.qml`

- [ ] **Step 1:** `ShellState.focusedScreen()` → `ShellState.mainScreen` in all three. In QuickSettings, `openScreen` is still fixed when the panel opens (the comment's reason holds).
- [ ] **Step 2: Commit** `shell: notifications, OSD and quick settings open on the main monitor`.

### Task 6: Displays card: Show bar and Make main monitor

**Files:**
- Modify: `dot-config/quickshell/fledge/settings/pages/Displays.qml`
- Modify: `dot-config/quickshell/fledge/settings/Arrange.qml`

- [ ] **Step 1: Card row** under Scale/Rotation, separated by a rule: a `Toggle` "Show bar" (checked = `ShellState.showsBar` for that key; disabled on the main with "Main monitor: it always has the bar." beside it), and a `Button` "Make main monitor" (hidden on the main, which shows a `main` tag instead). Writes go straight to settings, like `wallPick`: `Settings.set([[".bar.main", key]], false)`; the toggle adds or removes the key in `bar.hidden`. They don't touch `page.staged` or the Apply state.
- [ ] **Step 2: Canvas tag.** `Arrange` takes `mainKey` and draws a small `main` tag (accent background) at the top of that monitor's box.
- [ ] **Step 3: Check** that a write updates the shell live with `apply: false` (wallpaper does; if `merged` only refreshes on apply, pass `true`).
- [ ] **Step 4: Commit** `shell: Displays sets the main monitor and which monitors show a bar`.

### Task 7: VM checks and docs

**Files:**
- Modify: `cachyos/iso/test/verify-shell.sh`
- Modify (if a second head is possible): `cachyos/vm/provision-vm.sh`, `cachyos/vm/README.md`
- Modify: `docs/superpowers/specs/2026-10-10-mbm-shell-design.md` (a one-line pointer: the frame is now the bar edge only, see the main-monitor spec)

- [ ] **Step 1:** Find out whether the VM can have two outputs (a second virtio-gpu head, or `hyprctl output create headless`). Use the headless output if it works: it needs no reprovisioning.
- [ ] **Step 2: Checks** in `verify-shell.sh`: one monitor is main and has a `fledge-bar` layer; no `fledge-frame-reserve` layers other than the bar edge's; with two outputs, `bar.hidden` naming the second removes its `fledge-bar` layer, and `bar.main` naming it moves a test notification (`notify-send`) to it. Reset both keys at the end. Skip the two-output checks with a printed `SKIP` when there's one.
- [ ] **Step 3: Run** `cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-shell.sh'`; all pass.
- [ ] **Step 4: Commit** `test: verify-shell checks the main monitor and per-monitor bars`, then `docs: point the shell spec's frame at the main-monitor spec`.
