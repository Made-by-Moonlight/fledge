# Main monitor: design

Date: 2026-10-21. Branch: `main-monitor`. A follow-up to the fledge shell
(project A): one monitor is the main one, it carries the bar, and the other
monitors can go without.

## Why

On the user's desk (an ultrawide between two portrait BenQs) every monitor
draws the full bar and a frame round all four edges. The side monitors don't
need a bar: it repeats the clock, tray and cog, and costs vertical space on
screens that are already narrow. The frame round every edge also eats the
outer pixels of each screen for no use (the user's words: "I don't want the
frame on all edges on any monitor; the frame should only be on the top when a
bar is present").

Success: the bar shows on the monitors the person chooses, always on the main
one; screens without a bar are edge to edge; notifications, the OSD and quick
settings appear on the main monitor; workspaces on every monitor are visible
from the main bar.

## Goals

- **A main monitor**, chosen in Settings › Displays. It always has the bar.
- **A bar per monitor, switchable.** Any other monitor's bar can be turned
  off; by default every monitor keeps its bar (nothing changes until the
  person turns one off).
- **The frame only where there's a bar** (the user's call): the strip and its
  tabs along the bar edge, nothing down the sides or along the far edge. A
  monitor without a bar has no frame at all.
- **Notifications, OSD and quick settings on the main monitor** (the user's
  choice), instead of the focused one.
- **The main bar's workspace dots show every monitor's workspaces**, grouped
  by monitor (the user's choice), so a bar-less monitor's workspaces stay
  visible.

## Non-goals

- Different bar layouts per monitor (modules, position, height): every bar
  that shows is the same bar.
- Moving the launcher: it keeps opening on the focused monitor (the user
  didn't ask for it to move, and it's typed into wherever you're looking).
- Making a monitor the Hyprland "primary" in any other sense (cursor start,
  XWayland primary): this is the shell's notion only.

## What the person sees

- **Settings › Displays, the selected monitor's card** gains two controls:
  - **Show bar** (a toggle). On the main monitor it's on and greyed out, with
    "The main monitor always has the bar" beside it.
  - **Make main monitor** (a button), or the label **Main monitor** on the one
    that is.
- **The canvas** marks the main monitor (a small "main" tag in its box), so
  which one it is shows without selecting it.
- These two controls **take effect immediately**, like the wallpaper picks on
  the same page: they change the shell, not Hyprland's monitor layout, so
  they don't wait for Apply and its 15-second keep/revert countdown.
- **A monitor with a bar**: the strip along the bar edge with its tabs, and
  windows tile below the strip and tabs as today. The other three edges have
  no border; windows keep Hyprland's own `gaps_out`.
- **A monitor without a bar**: no strip, no frame, no reserved edge.
- **The hide-bar keybind** still hides every bar at once, as today.

## Settings

Stored in the bar section of `settings.json` (the defaults file carries
neither key):

- `bar.main`: the main monitor's key, the same key Displays uses
  (`desc:<description>`, else the connector; Layout.js `keyFor`). A value,
  not a path segment, so a description with quotes is safe here.
- `bar.hidden`: a list of keys whose bar is off. Absent or empty: every
  monitor has a bar.

`bar.main` wins over `bar.hidden`: a main monitor listed as hidden still shows
its bar (the list isn't edited when the main changes, so turning a monitor
back from main restores its own choice).

## Which monitor is main

- `bar.main` names a connected monitor: that one.
- Otherwise (unset, or that monitor unplugged or switched off): **the
  top-left monitor of the layout** (the user's choice). That's the smallest y,
  then the smallest x, of Hyprland's monitor positions, which is the canvas
  read top to bottom, left to right. Focus never moves it.
- Worked out in one place (a `MainScreen` helper, or a property on
  ShellState) that the bar, notifications, OSD and quick settings all read.

## Frame and reserved edges

- `Frame.qml` draws only the bar edge: the strip and each tab with its
  fillets. The side and far borders and the desktop's rounded corners go.
  Where a tab hangs from a screen corner it runs straight into the edge, as
  today.
- `Bar.qml` keeps one `Reserve` (the bar edge, `barHeight`) and drops the
  other three.
- A monitor without a bar creates no bar surface and no reserve at all.
- `Theme.popupSide` (`frame + gap`) becomes `gap`: popups no longer sit inside
  a side border. The section insets in `Bar.qml` (`frame + gap`) become
  `gap` too.
- This replaces the project A spec's "the same border runs down the other
  three edges, and the desktop area inside has rounded corners" (the user's
  call 2026-10-21).

## Workspaces on the main bar

- The main bar's Workspaces module lists every monitor's workspaces, grouped
  by monitor in layout order (left to right), with a gap between groups. The
  focused workspace is highlighted as today.
- Any other bar that shows keeps today's behaviour: its own monitor's
  workspaces only.

## Notifications, OSD, quick settings

- Notifications (`Popups.qml`) and the OSD (`Osd.qml`) take the main monitor
  instead of `ShellState.focusedScreen()`.
- Quick settings opens on the main monitor, under its bar's cog. The cog on
  any other bar that shows also opens it on the main monitor (one panel, one
  place).
- The launcher, the lock, the polkit dialog and the settings window are
  unchanged.

## Constraints

- Shell only: no Hyprland config generator changes, nothing written to
  Hyprland.
- The defaults file gets no layout or monitor keys (AGENTS.md).
- `fledge settings apply` doesn't need to run for these keys; the shell reads
  them live.

## Testing

- `cachyos/iso/test/verify-shell.sh` (VM). The checks that need two monitors
  run only when the VM has a second output, and are skipped otherwise
  (whether `provision-vm.sh` can add a second virtual head is the builder's
  to find out):
  - with one monitor: it is main and has a bar.
  - setting `bar.hidden` to a non-main monitor's key removes its bar surface
    (`hyprctl layers` has no `fledge-bar` on that output) and its reserve.
  - setting `bar.main` moves notifications to that output (a test
    notification's layer is on it).
- A QML test (`test/tst_*.qml`) for the main-monitor fallback: named and
  present, named and absent, unset; ties broken left to right.

## Left to the builder

- How the main bar draws the gap between monitors' workspace groups.
- The exact wording beside the greyed-out toggle.
- Whether the "main" tag on the canvas is text or a glyph.
