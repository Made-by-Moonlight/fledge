# Installer Tab focus, one-password boot, bar height: design

Date: 2026-10-18. Branch: `installer-tab-autologin`. Three small follow-ups
queued after the graphical installer (D) and the fledge rename, shipped
together on one branch.

## 1. One password at boot (autologin after disk unlock)

**Why.** Today a fresh install asks for two passwords on every boot: the LUKS
passphrase, then the SDDM login. When the person ticked "Use the same password
to unlock the disk at boot" on the Account step they have typed the same
secret twice for nothing; the disk unlock already proves who they are.

**Decision (the user's).** Choosing the same password *is* the autologin
choice. There is no separate toggle. Same password ⇒ boot asks for the disk
passphrase once and lands on the desktop. Different passwords ⇒ unchanged:
disk passphrase, then the SDDM greeter.

Behaviour:

- The session starts unlocked (no lock screen at login). After that the lock
  screen works as today (idle, lid, the lock bind). *(My call, from the user's
  "if you choose the same password it should autologin".)*
- Logging out shows the normal SDDM greeter, not an instant re-login
  (SDDM's `Relogin=false`, the default).
- The Account toggle's label says so, e.g. "Use the same password to unlock
  the disk, and log in automatically after unlocking". Exact wording is the
  builder's call; it must say both effects.

Mechanism:

- No new answers key: `install-cachyos.sh` turns autologin on exactly when
  the LUKS passphrase equals the user password. The graphical installer's
  answers already send the user password as `LUKS_PASSPHRASE` when the
  passwords are shared; the text installer gets the same rule from what was
  typed at its two prompts. One rule, both paths, nothing for an answers file
  to get wrong. *(My call; replaces an `AUTOLOGIN` key.)*
- The installer writes `/etc/sddm.conf.d/autologin.conf` on the target:
  `[Autologin]` `User=<username>` `Session=hyprland-uwsm.desktop`. A separate
  file from bootstrap's `default-session.conf`, so a `bootstrap.sh` re-run
  (the upgrade path) rewrites its own file and never removes autologin. The
  sddm.conf.d files merge alphabetically; `autologin.conf` and
  `default-session.conf` both set `Session=` to the same value, so order
  doesn't matter.
- `bootstrap.sh`'s comment that "real hardware/VM testing should still see a
  real password prompt" is updated: that is now true only when autologin is
  off.
- The install script writes the file before the Desktop stage, so the
  `--desktop-only` retry (which has no passwords) can't lose it. *(My call.)*
- Turning autologin off later: deleting the file. No settings UI on this
  branch (non-goal).

Tests: unit test that the install lib writes the file (content checked) and
writes nothing when not asked to; the rule "autologin iff passphrase equals
password" is checked in `test-desktop.sh`. VM end to end: install with
same password, boot, type only the LUKS passphrase, the desktop comes up
(`vm.sh` already types into the console); install with different passwords
still shows the greeter.

## 2. Tab / Shift+Tab in the installer

**Why.** The installer (`cachyos/iso/installer/`) only moves focus on
Return between some text fields; nothing moves on Tab, and toggles and
buttons are mouse-only.

Behaviour:

- On every step, Tab moves focus forward and Shift+Tab backward through
  that step's inputs, toggles, choices and buttons, including the footer's
  Back / Next, in visual order (left to right, top to bottom). Hidden
  controls (e.g. the disk passphrase row when the passwords are shared) are
  skipped.
- The focused control shows a focus ring in `Theme.accent`, like a focused
  `Input`'s border today.
- Space toggles a focused Toggle; Space or Return activates a focused
  Button / Choice / Tile. Return in a text field keeps its current meaning
  (next field or `Installer.next()`).
- Arrow keys keep whatever they do now in lists (`SearchList`, Disk).
- Focus wraps from the last control to the first.
- The rail's terminal button stays out of the Tab order. *(My call.)*

How: Qt Quick's `activeFocusOnTab` + `KeyNavigation` or a focus chain, the
builder's call, applied in the shared `components/` and `ui/` so the steps
need little or no per-field wiring. The live ISO and the dev runner
(`installer/dev`) both get it.

`components/` is shared with the desktop shell (the installer's
`components/` and `theme/` are symlinks to `dot-config/quickshell/fledge/`),
so the shell's Settings window and quick settings get Tab focus and rings
too. **The user wants that.** Check them in the VM for regressions: a focused
control must not swallow Space / Return / Escape that a page or popup already
handles (key recorder, launcher, quick settings closing on Escape).

Tests: an installer test (existing `installer/test/` style) that sends Tab /
Shift+Tab on the Account step and checks focus order, including the skip of
the hidden passphrase row; a VM screenshot of a focused toggle and button in
the installer and in the shell's Settings window.

## 3. Bar height slider

**Why.** The bar is a fixed 32 px; on a large or very small screen that's
wrong, and it should be a setting like the rest of the bar.

Behaviour:

- New setting `bar.height`, integer px, default 32, range 20–48, in
  `dot-local/share/fledge/defaults/settings.json`.
- Settings › Bar gets a slider (the existing `components/Slider.qml`) for it,
  applied live with no "apply", like the rest of that page.
- `Theme` is shared with the installer (symlinked), which has no Settings
  service, so `Theme.barHeight` becomes a writable property, default 32,
  that the shell binds to `bar.height`. *(My call.)* It follows the setting, so everything derived from it
  (`popupTop`, `osdBottom`, the reserved band at the bar edge) follows too.
  The bar's font size scales with the height so text stays proportionate at
  20 and 48 (the ratio is the builder's call; at 32 it must equal today's).
- `lib/check.jq` rejects a non-integer or out-of-range `bar.height`, with a
  message naming the range.
- No settings `version` bump: a missing key means the default.

Tests: `test-settings.sh` cases for in-range, 19, 49 and a string; VM
screenshots of the bar at 20, 32 and 48.

## Non-goals

- A settings UI to toggle autologin after install.
- Autologin without disk encryption, or with different passwords.
- Keyboard navigation in the shell beyond what the shared components give
  (no per-page focus wiring in Settings, nothing in the bar or launcher).
- Black frames between SDDM and Hyprland (separate, low-priority follow-up).
