# Monitor Arrangement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings › Displays gets a drag-to-arrange canvas (physical size, snapping, rotation, no overlap, no floating), one page-wide Apply through confirm-or-revert, and monitors keyed by description.

**Architecture:** A pure JS layout module (`settings/Layout.js`, `.pragma library`) holds all geometry: mm/logical sizes, snapping, push-out, touch checks, and mm ↔ logical-pixel placement. A canvas component (`settings/Arrange.qml`) draws and drags rectangles using it. `Displays.qml` stages every edit, and its one Apply hands a map of entries to a multi-entry `DisplayConfirm`. The CLI side changes only validation, defaults and generator ordering.

**Tech Stack:** Quickshell 0.3.2 QML/JS, qmltestrunner (qt6-declarative), jq, bash, Hyprland 0.56 Lua config.

**Spec:** `docs/superpowers/specs/2026-10-19-monitor-arrangement-design.md` (read it first; it is the source of every decision below).

## Global Constraints

- Never run project code on the host. Every test runs in the VM: `cachyos/vm/vm.sh sync` then `cachyos/vm/vm.sh run '<cmd>'` (repo is at `~/proj/fledge` inside the VM).
- Branch `monitor-arrange` (already created from `origin/main`). Commit after each task, message `area: what changed and why` (`shell:`, `fledge:`, `docs:`).
- Settings stay `version` 2; a `displays` entry keeps exactly `mode`, `position`, `scale`, `transform`, `enabled`.
- Hyprland IPC only via `Hypr` / `fledge hypr …`; never `hyprctl keyword`. Queries (`hyprctl monitors -j`) are fine.
- Display keys: `desc:<description>` unless the description is empty or contains `,`, `"` or `\`, then the connector name (same rule as `Displays.qml` `monitorValue` + `wallKey`).
- Shell scripts: bash, `set -euo pipefail` (tests: `set -uo pipefail` like their neighbours), shellcheck-clean. QML/JS match `Displays.qml` density.
- Physical sizes come from `lastIpcObject.physicalWidth/physicalHeight` (mm, **unrotated panel**). Distrust when either is 0 or `|(mmW/mmH)/(pxW/pxH) − 1| > 0.1`; then use 96 dpi of the logical size (`25.4 / 96` mm per logical px).
- Transforms: odd values (1, 3, 5, 7) swap width and height. Rotate buttons keep the flip bit: `t = (t & 4) | ((t + d + 4) & 3)`, d = ±1.

## Review Focus

1. **Scale ≠ 1:** a scale-1.5 monitor beside a scale-1 one must touch exactly in logical pixels (`round(px / scale)`; Hyprland rejects scales that don't divide the mode, which is not our problem, but the logical size we compute must be the same integer Hyprland uses: `Math.round(px / scale)`). Test in Task 1.
2. **Monitors only touching at a corner** count as *not* touching (the cursor can't cross a corner). Test in Task 1.
3. **Hand-set layout with a gap or overlap already in place** (e.g. an old `position` typed by hand): the canvas still opens and shows it, and Apply is disabled with the problem named, rather than the page throwing. Test in Task 1 (`fromLogical` + `problems` on a gapped layout).
4. **A monitor unplugged while the page has staged edits**: staged edits for a key not connected are dropped at Apply, not written with a stale size. Covered in Task 4 step list.
5. **Enabling a monitor whose saved position now overlaps** (layout changed while it was off): it is pushed out and slid to touch. Test in Task 1 (`settle`).

---

## File Structure

- Create `dot-config/quickshell/fledge/settings/Layout.js`: all geometry, no Qt types.
- Create `dot-config/quickshell/fledge/test/tst_layout.qml`: its unit tests.
- Create `dot-config/quickshell/fledge/settings/Arrange.qml`: the canvas (draw, select, drag, rotate buttons).
- Modify `dot-config/quickshell/fledge/settings/pages/Displays.qml`: staging model, one Apply, disabled chips, desc keys.
- Modify `dot-config/quickshell/fledge/services/DisplayConfirm.qml`: multi-entry begin/revert.
- Modify `dot-config/quickshell/fledge/services/Settings.qml`: `setReset(pairs, paths, apply)`.
- Modify `dot-local/share/fledge/lib/check.jq`, `gen-monitors.jq`, `defaults/settings.json`, `test/test-settings.sh`, `test/fixtures/*`.
- Modify `cachyos/iso/test-shell-qml.sh`: run `tst_layout.qml` too.
- Create `cachyos/iso/test/verify-displays.sh`: VM end-to-end check.

---

### Task 1: Layout maths (`Layout.js`)

**Model:** opus. **Files:** create `settings/Layout.js`, `test/tst_layout.qml`; modify `cachyos/iso/test-shell-qml.sh`.

**Interfaces (Produces):**

A *monitor* (`mon`) is `{ key: string, px: [w, h], mm: [w, h], scale: number, transform: int }` (px = mode pixels, mm = reported, both unrotated). A *rect* is `{ key, x, y, w, h }` in mm (canvas space, y down).

- `logical(mon) -> [w, h]`: `Math.round(px / scale)`, swapped for odd transform.
- `physical(mon) -> [w, h]`: trusted mm (swapped for odd transform) or the 96 dpi fallback of `logical(mon)`.
- `trusted(mon) -> bool`: the trust rule from Global Constraints.
- `fromLogical(mons, pos) -> rects`: `pos` is `{key: [x, y]}` in logical px. Anchor = the monitor at `[0,0]`, else the first in `mons`. BFS over monitors that touch in logical px; each child's mm rect: along the shared edge, exactly touching the parent's mm edge; across it, `Δpx / ppm(parent)` where `ppm(m) = logical(m)[0] / physical(m)[0]`. Monitors touching nothing are converted on their own relative to the anchor with the anchor's ppm (so a broken layout still draws). The anchor's rect is first in the returned array (so `toLogical` keeps it at `0,0`).
- `toLogical(mons, rects) -> { ok: bool, pos: {key: [x, y]}, error: string }`: the inverse. Anchor = the key passed as `rects[0]` placed at `[0,0]`. BFS over mm-touching pairs; along the touching axis the child's logical coordinate is the parent's logical edge exactly; across, `Math.round(Δmm × ppm(parent))`. A child that also touches an already-placed monitor on the *other* axis takes that axis from it exactly. Then verify in logical px: no overlap, every monitor touches another, every mm-touching pair touches in px. On failure `ok: false` and a one-line `error` naming the monitors (e.g. `"DP-2 and DP-3 overlap"`, `"DP-1 doesn't touch another monitor"`, `"DP-2 can't line up with both DP-1 and DP-3"`).
- `drag(rects, key, x, y, snapMm) -> rects`: move `key` to `(x, y)`, snap (edges touching: L↔R, R↔L, T↔B, B↔T; alignment: L=L, R=R, T=T, B=B, centres) within `snapMm`, then push out of overlaps the shortest way (up to 4 passes). Returns new array, inputs untouched.
- `settle(rects, key) -> rects`: push `key` out of overlaps, then if it touches nothing slide it the shortest distance until it shares an edge segment (> 0 length) with the nearest monitor.
- `rotate(rects, key, w, h) -> rects`: replace `key`'s size with `w × h` about its centre, then `settle`.
- `touching(a, b) -> bool`: share an edge segment of length > `EPS` (0.5 mm in mm space; callers in px space pass `eps = 0`). Corner-only contact is false.
- `problems(rects) -> [string]`: overlap and floating messages (same wording as `toLogical` errors), empty when fine.
- `fit(rects, width, height, margin) -> { scale, ox, oy }`: canvas transform that fits all rects.

- [ ] **Step 1: Write `tst_layout.qml`** (pattern: `test/tst_dspshort.qml`, `import "../settings/Layout.js" as L`). Fixtures: `acer = {key:"desc:Acer", px:[3440,1440], mm:[800,350], scale:1, transform:0}`, `benqL = {key:"desc:BenqL", px:[2560,1440], mm:[600,340], scale:1, transform:1}`, `benqR = {…"desc:BenqR"…, transform:3}`. Tests:
  - `test_sizes`: `logical(benqL)` is `[1440,2560]`; `physical(benqL)` is `[340,600]`; `logical({px:[3840,2160],scale:1.5,transform:0,…})` is `[2560,1440]`; `trusted` false for `mm:[0,0]` and for `mm:[160,90]` on a 1440×2560 unrotated portrait panel; fallback `physical` of a 1920×1080 scale-1 untrusted monitor is `[508, 285.75]`.
  - `test_user_desk_round_trip`: `fromLogical([acer, benqL, benqR], {acer:[0,0], benqL:[-1440,-560], benqR:[3440,-560]})` then `toLogical` gives `ok` and positions within ±1 px of the input; transforms untouched.
  - `test_physical_alignment`: rects with acer at `(0,0)` and benqL right edge on acer's left edge, top 131 mm above → `toLogical` x for benqL is exactly `-1440`, y is `Math.round(-131 × 3440/800)` = `-563`.
  - `test_mixed_scale`: a 3840×2160 scale-1.5 600×340 mm monitor touching the right of a 1920×1080 scale-1 530×300 mm one: x of the right one equals `1920` exactly.
  - `test_corner_not_touching`: rects meeting only at a corner → `touching` false, `problems` names the floating one.
  - `test_overlap_pushout`: `drag` benqR onto the middle of acer → result doesn't overlap and touches acer.
  - `test_float_settles`: benqR dropped 200 mm away → `settle` → touches acer; `problems` empty.
  - `test_enable_into_overlap`: a saved rect overlapping acer → `settle` → no overlap, touching.
  - `test_rotate_about_centre`: rotating acer to `350×800` keeps its centre (before settle) and the result has no overlaps.
  - `test_grid_cycle`: four 1920×1080 530×300 mm monitors in a 2×2 grid → `toLogical` ok with `[0,0],[1920,0],[0,1080],[1920,1080]`.
  - `test_broken_layout_draws`: `fromLogical` with a 100 px gap returns 3 rects and `problems` is non-empty (no throw).
- [ ] **Step 2: Add the runner line** to `cachyos/iso/test-shell-qml.sh` (second `"$RUNNER" -input …/tst_layout.qml`, keep `set -e` failing on either) and update its header comment. Run in VM: `cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test-shell-qml.sh'`. Expected: tst_layout fails (no module).
- [ ] **Step 3: Implement `Layout.js`** with the interfaces above. Header comment states the units (mm canvas, logical px out) and the touching-edge rule.
- [ ] **Step 4: Run the same command.** Expected: all tests pass, tst_dspshort still passes.
- [ ] **Step 5: Commit** `shell: Layout.js works out monitor positions from a physical-size arrangement: …` (say why: exact edges, mm alignment).

### Task 2: Settings side (keys, defaults, generator, combined write)

**Model:** sonnet. **Files:** `lib/check.jq`, `lib/gen-monitors.jq`, `defaults/settings.json`, `test/test-settings.sh`, `test/fixtures/defaults.json` (only if its displays need a desc entry), `test/fixtures/expected-monitors.lua`, `services/Settings.qml`.

**Interfaces (Produces):** `Settings.setReset(pairs, paths, apply) -> int` (job id): one queued job running `fledge settings set <pairs…>`, then (if `paths` non-empty) `fledge settings reset <paths…>`, then `fledge settings apply` when `apply`; ends in exactly one `writeFinished`. Implement with the same `sh -c` approach as `run`; `set` alone when `paths` is empty.

- [ ] **Step 1: Failing tests in `test-settings.sh`:**
  - `bad "display key with a comma" "displays: monitor name can't contain a comma" '{"displays":{"desc:Acer X34, 1":{"mode":"preferred"}}}'`
  - `bad "empty display key" "displays: monitor name can't be empty" '{"displays":{"":{"mode":"preferred"}}}'`
  - `good "display by description" '{"displays":{"desc:Acer Technologies X34 GS 0x1240460A":{"mode":"3440x1440@180","position":"0x0","scale":1}}}'`
  - Generator order: with `displays` `{"desc:Z":{…}, "DP-1":{…}}`, `monitors.lua` lists the `DP-1` rule before the `desc:Z` rule, the catch-all last.
- [ ] **Step 2: Run in VM** `bash ~/proj/fledge/dot-local/share/fledge/test/test-settings.sh`. Expected: the new checks FAIL.
- [ ] **Step 3: Implement:** in `check.jq` a key check beside `check_display` (exact messages above); in `gen-monitors.jq` sort connector keys before `desc:` keys (each group by key), so a desc rule, written later, is the one Hyprland ends up with *if* Hyprland is last-wins: **verify in the VM** by applying both a `DP-1`/Virtual-1 rule and a `desc:` rule for the VM's monitor with different scales and reading `hyprctl monitors -j`; if Hyprland is first-match-wins instead, reverse the order and the test, and note it in the jq comment.
- [ ] **Step 4: Defaults:** set `displays` to `{}` in `defaults/settings.json`. Keep `test/fixtures/defaults.json` as is (it tests the generator, not the shipped defaults). Run `test-settings.sh` and `test-defaults.sh` in the VM. Expected: PASS.
- [ ] **Step 5: `Settings.setReset`** in `Settings.qml`, comment matching `set`/`reset`. (Exercised by Task 3/5.)
- [ ] **Step 6: Commit** `fledge: displays may be keyed by description (no comma), connector rules generate first …; the shipped defaults no longer carry one desk's layout`.

### Task 3: Multi-entry confirm-or-revert (`DisplayConfirm`)

**Model:** sonnet. **Files:** `services/DisplayConfirm.qml`.

**Interfaces:**
- Consumes: `Settings.setReset` (Task 2).
- Produces: `DisplayConfirm.begin(changes) -> bool` where `changes` is `{ set: {key: entry}, remove: [key] }`. `previous` becomes `{ old: {key: entry|undefined} }` covering every key in `set` and `remove`. Pending file: `{ old: {…}, deadline }`. `undo(p)` restores every key in one `setReset` (keys with an old entry → set; keys that had none → reset). `active`, `countdown`, `keep()`, `revert()` unchanged in meaning.
- Startup: a pending file with `old` is undone; an old-format file (`{name, old}`) is converted to `{old: {[name]: old}}` and undone (cheap, keeps the crash guarantee).

- [ ] **Step 1:** Rewrite `begin`/`undo`/`savePending`/startup per the interface; `path(key)` stays `'.displays["' + key + '"]'`. Keep the comment block explaining why it lives outside the page, updated for "a set of monitors".
- [ ] **Step 2: Verify in the VM** (covered end to end in Task 5; here, a smoke check): `cachyos/vm/vm.sh restow && cachyos/vm/vm.sh shell`, then `qs -c fledge ipc call` is not wired for this, so check `journalctl --user -u fledge-shell -n 50` shows no QML errors after opening Settings › Displays.
- [ ] **Step 3: Commit** `shell: DisplayConfirm keeps or reverts a set of monitors together …`.

### Task 4: Canvas and the reworked Displays page

**Model:** opus. **Files:** create `settings/Arrange.qml`; modify `settings/pages/Displays.qml`.

**Interfaces:**
- Consumes: `Layout.js` (Task 1), `DisplayConfirm.begin(changes)` (Task 3).
- `Arrange.qml` properties: `mons` (array of Layout monitors, enabled + connected only), `rects` (in/out, mm), `selected: string`; signals `moved(var rects)`, `picked(string key)`, `rotated(string key, int dir)`. Draws via `Layout.fit`; drag uses `Layout.drag` with `snapMm: 12`, release calls `Layout.settle`. Each rectangle: connector + model, rotated logical size `W×H`, rotation in degrees, and a small "size unknown" tag when `!Layout.trusted(mon)`. Rotate left / Rotate right `Button`s under the canvas act on `selected`. Theme colours/radius from `Theme`, components from `components/`.

`Displays.qml` model:
- `keyOf(m)`: the Global Constraints key rule (reuse `monitorValue` + the `wallKey` quote/backslash rule; one function).
- Saved entry for a monitor: `user/merged.displays[keyOf(m)] ?? merged.displays[m.name]` (connector fallback).
- `staged`: `{ key: {mode, scale, transform, enabled} }` edits, plus `rects` (mm) — initialised from `Layout.fromLogical` of the live monitors on page open and whenever the set of connected monitors changes with nothing staged.
- Card controls (mode chips, Scale, Rotation `Choice`, Enabled `Toggle`) only stage. Remove the per-card Apply/Reset and the `Position (XxY)` `Field`. Changing scale/mode/rotation re-sizes that rect via `Layout.rotate` (same call: new size about centre + settle).
- Disabled monitors (staged off, or saved off and unplugged) are dimmed chips in a row under the canvas; toggling one on returns it to `rects` at its saved position via `Layout.settle`. Switching off the last enabled one is refused with the existing message.
- One row of page buttons under the canvas: **Apply** (enabled when something is staged, `Layout.problems` is empty, `toLogical.ok`, and `!DisplayConfirm.active`; otherwise a one-line muted reason beside it) and **Discard** (clears staging, rebuilds rects).
- Apply builds `changes.set` for every enabled connected monitor: `{mode, scale, transform, position: "XxY" from toLogical, enabled: true}`, and for monitors switched off in this edit `{…saved, enabled: false}`. `changes.remove`: connector-keyed user entries (`Settings.user.displays[m.name]`) of any monitor written under a different key. Drop staged edits for keys no longer connected (Review Focus 4).
- `entries` (switched-off list) matches saved `desc:` keys to monitors by description, not name.
- The Workspaces and Wallpaper sections are unchanged.

- [ ] **Step 1: Build `Arrange.qml`.**
- [ ] **Step 2: Rework `Displays.qml`** per the model above.
- [ ] **Step 3: Check in the VM:** `cachyos/vm/vm.sh restow && cachyos/vm/vm.sh shell`, open Settings › Displays, `cachyos/vm/vm.sh shot displays`, look at the screenshot: canvas shows the VM's monitor; no QML warnings in `journalctl --user -u fledge-shell -n 100`. Then add two headless outputs (`hyprctl output create headless` twice), reopen the page, screenshot: three rects, the headless ones tagged "size unknown".
- [ ] **Step 4: Commit** `shell: Settings › Displays arranges monitors on a physical-size canvas …; one Apply for the page`.

### Task 5: VM end-to-end check

**Model:** sonnet. **Files:** create `cachyos/iso/test/verify-displays.sh`.

The script (pattern: `verify-shell.sh`'s `ok/no/is` helpers, header saying how to run it) drives the real path without the UI by writing settings the way the page does and reading Hyprland back:

- Create two headless outputs; read their names and descriptions from `hyprctl monitors -j`.
- Write a layout with `fledge settings set` under `desc:` keys (or connector, if the headless description fails the key rule; the script uses the same rule), positions from a hand-computed row (`0x0`, `<w0>x0`, …) and one with `transform 1`; `fledge settings apply`. Check `hyprctl monitors -j` positions and transforms match.
- A connector-keyed entry plus a `desc:` entry for the same monitor with different scales: check which wins matches the generator order decided in Task 2.
- Confirm-or-revert: call into the shell isn't scriptable, so check the pending-file path instead: write a `display-pending.json` in the new format with an `old` map, restart `fledge-shell.service`, check the user file's displays equal the `old` values and the pending file is gone. Repeat with the old `{name, old}` format.
- Clean up: remove the headless outputs (`hyprctl output remove`) and the test's settings entries (`fledge settings reset`), `fledge settings apply`.

- [ ] **Step 1: Write the script.**
- [ ] **Step 2: Run** `cachyos/vm/vm.sh sync && cachyos/vm/vm.sh restow && cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-displays.sh'`. Expected: all PASS, exit 0.
- [ ] **Step 3: Run the rest:** `test-shell-qml.sh`, `test-settings.sh`, `test-defaults.sh`, `verify-shell.sh` in the VM; shellcheck the new script. Expected: all pass.
- [ ] **Step 4: Commit** `shell: verify-displays.sh checks an arrangement reaches Hyprland and a pending change reverts after a crash`.

### Task 6: Docs

**Model:** sonnet. **Files:** `README.md` (if it describes Displays), `cachyos/vm/README.md` (headless outputs recipe), AGENTS.md only if a convention changed (display keys).

- [ ] **Step 1:** Update the docs that mention the Position box or connector-keyed displays (`grep -rn 'Position (XxY)\|displays' README.md cachyos/vm/README.md docs/ --include=*.md` outside `docs/superpowers/`).
- [ ] **Step 2: Commit** `docs: …`.
