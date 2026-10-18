# Installer Tab focus, one-password boot, bar height: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Same disk and login password ⇒ one password at boot, then the desktop; Tab / Shift+Tab through every installer control (and the shell's settings controls, which share the components); a `bar.height` slider.

**Architecture:** Autologin is an SDDM drop-in that `install-cachyos.sh` writes when the LUKS passphrase equals the user password. Keyboard focus is added once, in the shared `dot-config/quickshell/fledge/components/` (symlinked into the installer) and the installer's `ui/`, using Qt Quick's own tab chain (`activeFocusOnTab`). The bar height is a new setting the shell binds into a now-writable `Theme.barHeight`.

**Tech Stack:** bash (shellcheck-clean, `set -euo pipefail`), Quickshell / Qt 6 QML, jq (`check.jq`), the `cachyos/vm/` test VM.

**Spec:** `docs/superpowers/specs/2026-10-18-installer-tab-autologin-design.md`

## Global Constraints

- Never run project code on the host (AGENTS.md rule 1). Unit tests, the shell, the installer dev runner and installs run in the VM `cachyos-test`: `cachyos/vm/vm.sh sync` then `cachyos/vm/vm.sh run '…'`. Host-side `vm.sh key/type/shot` calls drive the VM and are fine.
- Names: `fledge` everywhere; `cachyos/check-names.sh` must pass.
- Shell scripts: bash, `set -euo pipefail`, shellcheck-clean; comments say *why*; match surrounding density.
- Tests: `test-*.sh` with `cachyos/install/test/lib.sh` (`check` / `contains`, `exit $fail`).
- Commit messages: `area: what changed and why` (`install:`, `iso:`, `shell:`, `fledge:`, `docs:`). Commit per task on branch `installer-tab-autologin`; don't push.
- Autologin file: `/etc/sddm.conf.d/autologin.conf`, exactly `[Autologin]` / `User=<username>` / `Session=hyprland-uwsm.desktop`. Bootstrap's `default-session.conf` is untouched.
- `bar.height`: integer, default 32, range 20–48; at 32 every bar size equals today's.
- No settings `version` bump; no migration code.

## Review Focus

1. A password containing spaces, `=`, quotes or a trailing newline-free paste must compare correctly for the autologin rule (plain `[[ "$a" == "$b" ]]`, never word-split) — Task 1 test.
2. `--desktop-only` retry after a failed Desktop stage must keep autologin (file written before the Desktop stage, retry never touches it) — Task 1 test.
3. A disabled Next button must not be reachable by Tab, and Return on a focused Back must go back, not forward (Frame's Return handler must not also fire) — Task 2 VM check.
4. Tab inside the shell's key recorder (Settings › Keybinds, while recording) must still record Tab, not move focus — Task 2 VM check.
5. A user file with `"bar": {"height": 32.5}` or `"48"` must fail `fledge settings check` and the shell must fall back to 32, not lay out a fractional or string height — Task 3 tests.

---

### Task 1: Autologin when the disk and login passwords match

**Files:**
- Modify: `cachyos/install/lib/desktop.sh` (new function)
- Modify: `cachyos/install/lib/disk.sh:40-58` (`luks_format_open` keeps the prompted passphrase)
- Modify: `cachyos/install/install-cachyos.sh` (call after `seed_user_settings`, ~line 300; final message ~line 343)
- Modify: `cachyos/bootstrap.sh:299-301` (comment only)
- Modify: `cachyos/iso/installer/steps/Account.qml:47` (toggle label)
- Modify: `cachyos/iso/test/verify-install.sh` (one check)
- Test: `cachyos/install/test-desktop.sh`

**Interfaces:**
- Produces: `write_autologin <user> <user password> <luks passphrase>` in `lib/desktop.sh` → writes `$FLEDGE_TARGET/etc/sddm.conf.d/autologin.conf` (mode 644, dir created) when the two secrets are equal and non-empty; otherwise removes that file if present. Always returns 0. Never echoes either secret.
- Produces: after `luks_format_open`, the global `LUKS_PASSPHRASE` holds the passphrase actually used (prompted or from answers).

- [ ] **Step 1: Write the failing tests** in `test-desktop.sh` (after the `seed_user_settings` checks):

```bash
al="$FLEDGE_TARGET/etc/sddm.conf.d/autologin.conf"
write_autologin ethan 'pa=ss word' 'pa=ss word'
check "autologin: same password writes the drop-in" \
  $'[Autologin]\nUser=ethan\nSession=hyprland-uwsm.desktop' "$(cat "$al" 2>/dev/null)"
check "autologin: drop-in is 644" 644 "$(stat -c %a "$al" 2>/dev/null)"
write_autologin ethan 'pa=ss word' 'pa=ss word '
check "autologin: different passwords, no drop-in" no "$([[ -e $al ]] && echo yes || echo no)"
write_autologin ethan '' ''
check "autologin: empty passwords, no drop-in" no "$([[ -e $al ]] && echo yes || echo no)"
out="$(write_autologin ethan 's3cret*' 's3cret*' 2>&1)"
check "autologin: never echoes the password" "" "$(grep -o 's3cret' <<<"$out")"
```

Plus a source-order check (the retry path can't lose it): `write_autologin` is called in `install-cachyos.sh` before the last `desktop_and_finish` call and not inside `desktop_and_finish`:

```bash
src="$DIR/install-cachyos.sh"
check "autologin: written before the Desktop stage" yes \
  "$(awk '/^desktop_and_finish\(\)/,/^}/{next} /write_autologin/{w=NR} /^desktop_and_finish$/{d=NR} END{print (w && d && w<d) ? "yes" : "no"}' "$src")"
```

- [ ] **Step 2: Run, expect FAIL** (`write_autologin: command not found`):
`cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/install/test-desktop.sh'`

- [ ] **Step 3: Implement.**
  - `write_autologin` in `lib/desktop.sh`, comment explaining why a separate file (bootstrap re-runs rewrite `default-session.conf`) and why equality is the rule (spec §1).
  - `luks_format_open`: after prompting, `LUKS_PASSPHRASE="$p1"` so the caller can compare (comment: read by the autologin rule).
  - `install-cachyos.sh`: `write_autologin "$USERNAME" "$USER_PASSWORD" "$LUKS_PASSPHRASE"` right after `seed_user_settings …`. Final message: "On reboot, unlock the disk; the desktop starts when the passwords are the same, otherwise log in." (wording yours, both cases).
  - `bootstrap.sh:299-301`: the comment now says the greeter's password prompt shows unless the installer set up autologin (`autologin.conf`).
  - `Account.qml` toggle label: "Same password for the disk; log in automatically after unlocking it".
  - `verify-install.sh`: when `VERIFY_AUTOLOGIN` is set, `is "autologin drop-in" "User=$USER" "$(grep '^User=' /etc/sddm.conf.d/autologin.conf 2>/dev/null)"`; when it is unset, `is "no autologin" no "$([[ -e /etc/sddm.conf.d/autologin.conf ]] && echo yes || echo no)"`. Add `VERIFY_AUTOLOGIN=1` to the usage comment and `cachyos/iso/README.md:54`.

- [ ] **Step 4: Run, expect PASS**, plus shellcheck:
`cachyos/vm/vm.sh run 'cd ~/proj/fledge && bash cachyos/install/test-desktop.sh && shellcheck cachyos/install/lib/*.sh cachyos/install/install-cachyos.sh cachyos/iso/test/verify-install.sh'`

- [ ] **Step 5: Commit** — `install: log in automatically after the disk unlock when the disk and login passwords are the same (sddm autologin.conf, written before the Desktop stage so a retry keeps it)`

### Task 2: Tab / Shift+Tab focus in the shared components and the installer

**Files:**
- Modify: `dot-config/quickshell/fledge/components/{Button,Toggle,Choice,Tile,Slider,Field}.qml` (`Stepper` is two Buttons: nothing to do)
- Modify: `cachyos/iso/installer/ui/{Input,Rail}.qml`
- Modify: `cachyos/iso/installer/shell.qml` (IPC `focused()`)
- Create: `cachyos/iso/test/verify-installer-focus.sh` (host-side, drives the VM)

**Interfaces:**
- Produces: every focusable component has `activeFocusOnTab` and a ring: `border.width: activeFocus ? 2 : 0`, `border.color: Theme.accent` on the component's visible box (Toggle: its track; Choice: its outer pill; Input/Field: keep the existing accent border).
- Produces: each component's `objectName` defaults to its label text (`Button.text`, `Toggle.label`, `Choice.label`, `Tile.title`, `Input.label`, `Field.label`), so the focus can be named over IPC.
- Produces: installer IPC `focused(): string` on target `installer` → `objectName` of the window's `activeFocusItem` or its nearest ancestor with a non-empty `objectName`, `""` if none.
- Produces: `Slider` emits `stepped(-1|1)` on Left/Right (Task 3's bar slider relies on this).

Keys (spec §2):
- Button / Tile: Space, Return, Enter → `clicked()`, event accepted (so Frame's Return-forward doesn't also fire). A disabled Button has `activeFocusOnTab: false`.
- Toggle: Space → `toggled(!checked)`. Return is **not** accepted (falls through to Frame → next step, as today).
- Choice: Left/Right → `picked()` the previous/next option value (clamped, no wrap). *(Spec left Choice keys open; arrows are the natural fit for a segmented control.)*
- Slider: Left/Right → `stepped(∓1/±1)`.
- `Input`'s and `Field`'s `TextInput`: `activeFocusOnTab: true`. Input keeps its Return handling.
- Rail's terminal Button instance: `activeFocusOnTab: false` (spec: out of the Tab order).
- Hidden controls are skipped by Qt's tab chain already; the chain wraps by default. Nothing per step except where the VM check shows a step's own `FocusScope` traps Tab.

- [ ] **Step 1: Write the failing VM check** `cachyos/iso/test/verify-installer-focus.sh` (runs on the host, drives the VM; header comment says so and gives the usage). It: `vm.sh sync`, starts the dev installer (`vm.sh run 'bash ~/proj/fledge/cachyos/iso/installer/dev/run.sh'`), `go account`, `set sameLuks true`, focuses the username field, then sends `vm.sh key KEY_TAB` and records `qs -p /tmp/fledge-installer ipc call installer focused` after each press. Asserts (with `check` from `cachyos/install/test/lib.sh`):

```bash
check "tab order, shared passwords" \
  "Computer name|Password|Password again|Same password for the disk; log in automatically after unlocking it|Back|Next|Username" "$order"
# Shift+Tab from Username goes back to Next
check "shift+tab wraps backwards" "Next" "$after_shift_tab"
# Hidden passphrase row joins the chain once the toggle is off (Tab from "Password again")
check "tab order, separate passphrase" \
  "Same password for the disk; log in automatically after unlocking it|Disk passphrase|Disk passphrase again|Back|Next" "$order2"
# Space on the focused toggle flips it
check "space toggles" false "$(ipc_get sameLuks)"
# Return on a focused Back goes back one step, not forward
check "return on back" network "$(ipc current)"
```

(Fill the exact Next/Back order from what the Footer renders; Back is left of Next. `ipc_get` may need a tiny `get(key)` IPC beside `set`; add it if so.) Also: on Welcome, with an invalid Account, Tab never lands on a disabled Next.

- [ ] **Step 2: Run, expect FAIL** (`focused` is not an IPC function): `bash cachyos/iso/test/verify-installer-focus.sh`

- [ ] **Step 3: Implement** the Interfaces and Keys above.

- [ ] **Step 4: Run, expect PASS**: `bash cachyos/iso/test/verify-installer-focus.sh`, and the existing `cachyos/vm/vm.sh run 'cd ~/proj/fledge && bash cachyos/iso/test-installer-qml.sh && bash cachyos/iso/test-shell-qml.sh'`.

- [ ] **Step 5: Shell regression pass in the VM** (`vm.sh restow && vm.sh shell`, open Settings via `qs -c fledge ipc call` per `ipc/Ipc.qml`): Tab moves through a Settings page's controls with a visible ring; Escape still closes quick settings with a control focused; in Settings › Keybinds, while recording, Tab is recorded as a key (fix `KeyRecorder.qml` to accept Tab/Backtab while recording if not); the launcher and lock screen are unchanged. Screenshots: `vm.sh shot installer-focus-toggle`, `installer-focus-button`, `settings-focus`.

- [ ] **Step 6: Commit** — `shell: Tab / Shift+Tab focus with an accent ring in the shared controls (installer and settings), Space/Return activate; installer IPC focused() for the VM check`

### Task 3: `bar.height` setting and slider

**Files:**
- Modify: `dot-local/share/fledge/defaults/settings.json` (`bar.height: 32`)
- Modify: `dot-local/share/fledge/lib/check.jq:118-124`
- Modify: `dot-config/quickshell/fledge/services/Settings.qml:62` area
- Modify: `dot-config/quickshell/fledge/theme/Theme.qml`
- Modify: `dot-config/quickshell/fledge/shell.qml` (binding)
- Modify: `dot-config/quickshell/fledge/bar/**` (font sizes)
- Modify: `dot-config/quickshell/fledge/settings/pages/Bar.qml`
- Test: `dot-local/share/fledge/test/test-settings.sh`

**Interfaces:**
- Consumes: `Slider.stepped(dir)` on Left/Right (Task 2).
- Produces: `Settings.barHeight: int` — the merged `bar.height` when it is an integer in 20–48, else 32.
- Produces: `Theme.barHeight` writable `property int`, default 32 (the installer, which shares Theme and has no Settings, keeps 32). `Theme.barFont: Math.round(fontSize * barHeight / 32)`, `Theme.barFontLarge: Math.round(fontLarge * barHeight / 32)` (13 and 16 at 32).

- [ ] **Step 1: Write the failing tests** in `test-settings.sh`, in its existing style (set a user value, then `settings check`):

```bash
check "bar.height: default"           32  "$("$FLEDGE" settings get .bar.height)"
for v in 20 48; do  # in range
  "$FLEDGE" settings set .bar.height "$v" >/dev/null
  check "bar.height $v accepted" "" "$("$FLEDGE" settings check 2>&1)"
done
for v in 19 49 32.5 '"32"'; do  # out of range, fractional, string
  write_user "{\"bar\":{\"height\":$v}}"       # however the file seeds a raw user file
  check "bar.height $v rejected" "bar.height must be a whole number from 20 to 48" "$("$FLEDGE" settings check 2>&1)"
done
```

- [ ] **Step 2: Run, expect FAIL**: `cachyos/vm/vm.sh sync && cachyos/vm/vm.sh run 'bash ~/proj/fledge/dot-local/share/fledge/test/test-settings.sh'`

- [ ] **Step 3: Implement.**
  - defaults `"height": 32` in `bar`; `check.jq`: add `"height"` to the `unknown([...]; "bar")` list and `(if (.height // 32 | isint and . >= 20 and . <= 48) then empty else "bar.height must be a whole number from 20 to 48" end)`.
  - `Settings.barHeight` (validated fallback to 32, as in Interfaces).
  - `Theme.qml`: `barHeight` becomes writable with the comment that the shell binds it to `bar.height` and the installer keeps the default; add `barFont` / `barFontLarge`.
  - `shell.qml`: `Binding { target: Theme; property: "barHeight"; value: Settings.barHeight }`.
  - `bar/`: every `Glyph`/`Text` that used the default `Theme.fontSize` sets `font.pixelSize: Theme.barFont`; `Theme.fontLarge` → `Theme.barFontLarge`; `Theme.fontSmall` → `Math.round(Theme.fontSmall * Theme.barHeight / 32)` inline, or a `barFontSmall` if more than one use. Popups that hang off the bar (quick settings, calendar) keep the normal font sizes.
  - `Bar.qml` settings page: a row "Bar height" + current value (`"32 px"`) + `Slider` 200 px wide. `value: (Settings.barHeight - 20) / 28`; `onMoved: v => { const h = Math.round(20 + v * 28); if (h !== Settings.barHeight) Settings.set([[".bar.height", h]], false); }`; `onStepped: d => { const h = Math.max(20, Math.min(48, Settings.barHeight + d)); if (h !== Settings.barHeight) Settings.set([[".bar.height", h]], false); }`. Live, no apply (the page's existing rule).

- [ ] **Step 4: Run, expect PASS**: `test-settings.sh` as in Step 2; then `vm.sh restow && vm.sh shell`, set 20, 32 and 48 through the slider (or `fledge settings set .bar.height N` in the VM), and `vm.sh shot bar-20`, `bar-32`, `bar-48`. Check at each: text vertically centred and unclipped, windows start below the bar (reserved band follows), quick settings hangs one gap below the bar, the OSD clears a bottom bar. `verify-shell.sh` passes.

- [ ] **Step 5: Commit** — `shell: bar.height setting (20-48 px, default 32) with a live slider in Settings › Bar; Theme.barHeight and the bar's font sizes follow it`

### Task 4: End-to-end install in the VM

**Files:** none new (fixes go to the owning task's files, committed as follow-up commits).

- [ ] **Step 1:** Build the ISO and install into `cachyos-test` per `cachyos/iso/README.md`, with the **same** password for the disk. Drive the Account step with Tab only (no mouse) as a manual check of Task 2 on the real ISO.
- [ ] **Step 2:** Reboot. Type only the LUKS passphrase (`vm.sh type`). Expected: the desktop comes up with no greeter (`vm.sh shot autologin-desktop`); `VERIFY_AUTOLOGIN=1` `verify-install.sh` passes (README invocation, `ssh -t`).
- [ ] **Step 3:** `vm.sh relogin`. Expected: after logout the SDDM greeter shows (screenshot), typing the password logs in ("logged in").
- [ ] **Step 4:** Reinstall with **different** passwords. Expected: after the LUKS prompt the greeter shows; `verify-install.sh` without `VERIFY_AUTOLOGIN` passes.
- [ ] **Step 5:** Leave the VM installed with the same-password setup (the dev loop expects a working desktop; `dev-up.sh`'s LUKS unlock and `vm.sh relogin` both still work with autologin). Commit any fixes found: `iso: …` / `install: …`.
