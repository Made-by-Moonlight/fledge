# Monitor arrangement: design

Date: 2026-10-19. Branch: `monitor-arrange`. A follow-up to the fledge shell
(project A): Settings › Displays gets a picture of the monitors you drag into
place, instead of typed pixel offsets.

## Why

The user's desk has an ultrawide (Acer X34 GS, 3440×1440) between two
2560×1440 BenQs turned to portrait, one rotated 90°, the other 270°. For the
cursor to cross each edge at the height where the screens physically line up,
each BenQ needs a hand-worked offset (`-1440x-560`, `3440x-560`): a rotated
monitor swaps width and height, and the vertical offset has to be worked out
from where the screens actually sit. **Rotation and alignment** are the two
fiddly parts (the user's words). Today's Displays page has a typed
`Position (XxY)` box and a Rotation dropdown per monitor, which leaves all of
that arithmetic to the person.

Success: someone with rotated, offset monitors arranges them by dragging a
picture that matches their desk, and the cursor crosses where the screens
physically meet, with no numbers typed.

## Goals

- An **arrangement canvas** at the top of Settings › Displays: every connected,
  enabled monitor drawn as a rectangle at its **physical size**, dragged into
  place.
- **Physical alignment** (the user's choice over "centre is good enough"): the
  vertical (or, for stacked monitors, horizontal) offset between neighbours
  comes from real-world millimetres, so the cursor crosses at the same physical
  height.
- **Rotation** from the canvas: rotate left / rotate right on the selected
  monitor, turning about its centre.
- **No overlap** (the user's rule): a monitor can never cover another.
- **No floating monitors** (the user's rule): every monitor touches at least
  one other, so the cursor can reach every screen.
- Fix the two traps found while looking (my calls, see "Identity" and
  "Defaults").

## Non-goals

- Layout profiles (different arrangements per set of connected monitors,
  docking). Not asked for; the user is on a desktop.
- Mirroring, HDR, VRR, colour management, 10-bit: not part of this.
- Changing how mode, scale and enabled are edited (the cards stay).
- Migration code for old settings: entries keyed by connector keep working as
  they are (see Identity), so nothing needs migrating.

## Anti-goals

- A cursor that hits an invisible wall or jumps at a border after arranging.
  That is the failure this exists to remove; a layout that "looks right" but
  leaves a 1 px gap or overlap in Hyprland's coordinates is broken.
- An arrangement that applies with no way back: it must go through
  confirm-or-revert like other display changes today.

## What the person sees

Prototyped in the brainstorm (draggable mockup with the user's three
monitors); the user approved the shape.

- A canvas at the top of the Displays page, above the per-monitor cards. Each
  enabled, connected monitor is a rectangle at physical scale, labelled with its
  connector/model, its rotated pixel size and its rotation. The canvas fits the
  whole arrangement, whatever its extent.
- **Click** selects a monitor (highlighted; only its card is shown below, the
  one being edited). **Drag** moves it.
- While dragging, the monitor **snaps** to other monitors' edges (touching left,
  right, top or bottom) and to alignment lines (tops, bottoms, centres level;
  for stacked monitors, lefts, rights, centres). The snap threshold is the
  builder's call (about 12 mm worked well in the mockup).
- **No overlap:** a monitor dragged onto another is pushed out the shortest way.
- **No floating:** dropped in empty space, it slides to the nearest position
  where it touches another monitor. The exact rule (nearest edge by distance) is
  the builder's call.
- **Rotate left / Rotate right** buttons act on the selected monitor and turn it
  about its centre; the result is then pushed out of overlaps / back to touching
  like a drop.
- **One Apply for the whole page** (the user's decision), then the existing
  15-second Keep / revert countdown covering everything. The cards lose their
  own Apply and Reset buttons. Card edits (mode, scale, rotation, enabled) only
  stage changes, and the canvas updates straight away. The overlap, floating
  and exact-edge checks run once over the whole staged layout at Apply. A page
  Reset (or Discard) throws away the staged changes; a "reset this monitor to
  defaults" action, if kept, also just stages (builder's call).
- The per-monitor cards keep mode, scale and enabled. The typed
  `Position (XxY)` box goes (the canvas replaces it; my call). The Rotation
  dropdown stays on the card and stays in sync with the canvas (my call: two
  ways to the same value, both obvious).
- Scale, mode and rotation edits on a card change the rectangle's pixel size
  label immediately; its physical size only changes with rotation.
- **Disabling monitors** (the user asked for this explicitly; the Enabled
  toggle exists today and stays, and switching off the only enabled monitor is
  still refused). A disabled monitor leaves the canvas and shows as a dimmed
  chip in a row under it, as do saved monitors that are switched off and
  unplugged (my call). Disabling one can leave the others floating (switch off
  the Acer and the BenQs no longer touch): the canvas shows the problem and
  Apply stays disabled with a one-line reason until the user drags them
  together (my call: no automatic re-packing, so nothing moves that the user
  didn't move). Turning a monitor back on puts it at its saved position, then
  pushes it out of overlaps and slides it to touch, as a drop does.

## How positions are worked out

Hyprland positions monitors in **logical pixels**: a monitor occupies
`(pixel size after rotation) / scale`. The canvas works in millimetres. The
two must agree exactly where monitors touch, or the cursor hits a gap.

The rule (my call, prototyped):

- **Along the shared edge**, positions are exact in logical pixels: two
  monitors side by side touch exactly (right edge of one = left edge of the
  next, in logical pixels), whatever their densities.
- **Across it**, the offset comes from millimetres: the BenQ's top sits
  `Δmm × (logical px per mm of the monitor it's measured against)` above the
  Acer's. For the user's desk that gives about `-560`, matching today's
  hand-worked value.
- A practical way to get there: pick an anchor monitor at `0x0` (the one
  holding workspace 1, or the first; builder's call), walk the touching
  relationships outward from it (a tree), and place each monitor from its
  parent: the touching axis from the parent's logical edge, the other axis from
  the mm offset converted with the parent's density. Round to whole pixels.
  Every shared edge must be exact in logical pixels (the anti-goal wins; my
  call). A monitor touching two already-placed neighbours (a 2×2 grid) takes
  each axis from the neighbour it touches on that axis; if the two disagree by
  a rounding pixel or two, it snaps to them; if they can't both be met, the
  layout is refused with a message.
- Final check before writing: no two monitors overlap in logical pixels,
  every monitor touches another, and every edge the canvas shows as shared is
  shared exactly. If not, refuse with a message rather than
  write a broken layout.
- The canvas is rebuilt from the **current** positions when the page opens:
  logical-pixel positions are converted back to mm with the same rule, so a
  layout set by hand (or by an older fledge) shows up where it really is.

**The user's real numbers** (read-only `hyprctl monitors -j` on their desk,
2026-10-19): BenQ EX2780Q ×2: 2560×1440 px, 600×340 mm, transforms 1 and 3,
positions `-1440x-560` and `3440x-560`; Acer X34 GS: 3440×1440 px, 800×350 mm,
transform 0, `0x0`; all scale 1. Hyprland reports `physicalWidth/Height` for
the **unrotated** panel (the rotated BenQs still say 600×340), so the layout
code swaps mm with the transform just as it swaps pixels. The unit test for
this desk uses these values; the expected y-offset is whatever they give
(about −560), not exactly −560.

**Physical size missing or nonsense.** Hyprland reports `physicalWidth` /
`physicalHeight` in mm (in `lastIpcObject` for each Quickshell monitor). Some
displays report 0 (virtual outputs, many projectors) or values that don't fit
the pixel aspect ratio (TVs). If either is 0, or the mm aspect ratio differs
from the pixel aspect ratio by more than ~10%, that monitor is drawn at a
nominal density of 96 dpi (≈3.78 px/mm) of its logical size instead. The
threshold is the builder's call. Nothing tells the user unless it's cheap to
show a small "size unknown" note on the rectangle (builder's call).

## Identity: monitors by description, not port (my call)

Settings stores `displays` by connector today (`DP-1`…), and the shipped
defaults contain the user's layout under connector names. On the user's
machine right now `DP-1` is the right BenQ and `DP-3` is the Acer, so those
defaults would put the ultrawide's mode on a BenQ. The user's own Hyprland
config and fledge's workspace pins and per-monitor wallpaper already key by
`desc:<description>`, which follows the screen across cables.

- The Displays page writes entries keyed `desc:<description>`, using the same
  rule as `monitorValue`/`wallKey` today: fall back to the connector when the
  description is empty, contains a comma, or contains a quote or backslash.
- An existing connector-keyed entry still works (Hyprland's `hl.monitor`
  accepts either as `output`), so nothing is migrated. When the page writes a
  monitor that also has a connector-keyed user entry, it removes that entry in
  the same job, so one monitor never has two rules. One job means one queued
  `Settings.run` that does the `settings set` and `settings reset` and then a
  single `settings apply` (extend `Settings` with a combined call; no CLI change
  needed; my call). The pending file records removed connector entries too, and
  revert restores them.
- `gen-monitors.jq`: ordering of rules must not let a leftover connector entry
  and a `desc:` entry fight. Desc entries after connector ones, or the builder's
  check that Hyprland's precedence is what we want; verify in the VM.
- `check.jq`: a display key must be a non-empty string without a comma; the
  rest of `check_display` is unchanged.
- The "switched off" monitors list (`entries` in `Displays.qml`) matches saved
  `desc:` keys against Hyprland's monitors by description, not name.

## Defaults (my call)

The user's three-monitor layout comes out of
`dot-local/share/fledge/defaults/settings.json` (`displays` becomes `{}`), and
the user's own layout goes in their `~/.config/fledge/settings.json` (they set
it with the new page, on their machine, when they choose to). A fresh install
starts with Hyprland's automatic placement (the catch-all `hl.monitor` rule).
The default workspace pins to the user's monitors by description stay as they
are; they are harmless on other hardware (a pin to a missing monitor is
ignored). Test fixtures that copy the defaults are updated to match.

## Applying (confirm-or-revert for several monitors)

`DisplayConfirm` today confirms one monitor's entry. Arranging moves several at
once, so it needs to take a set of entries: `begin` with a map of
key → new entry (and the keys to remove), save all their previous user entries
in the pending file, write them in one `Settings.set` (one apply, one
`hyprctl reload`), and revert all of them together on timeout, refusal or a
crash. The page's one Apply is its only caller. The
pending file's format changes; an old-format pending file at startup is still
reverted (it holds one `{name, old}`), or simply discarded: builder's call,
since one can only exist if the shell died mid-countdown across an upgrade.

The arrangement's Apply writes `position` and `transform` for every enabled,
connected monitor (all of them, since the anchor and the walk can shift any),
merged with each one's mode, scale and enabled as the cards have them.
Monitors switched off in this edit get `enabled: false` (their saved position
kept for when they come back); other disabled and disconnected monitors'
entries are left alone.

## Constraints

- Never run project code on the host (AGENTS.md hard rule 1). All testing is in
  the `cachyos-test` VM.
- Hyprland 0.56 Lua config; displays are generated into
  `~/.local/state/fledge/hypr/monitors.lua` by `fledge settings apply`. Don't
  hand-edit generated files.
- Settings stay `version` 2: the `displays` entry shape (`mode`, `position`,
  `scale`, `transform`, `enabled`) doesn't change, so no schema bump.
- QML, matching `Displays.qml`'s density and idiom; reuse `components/`
  (`Button`, `Choice`, `Stepper`, `Toggle`, `Pill`, `Glyph`) and `Theme`.
- The layout maths (mm ↔ logical px, snapping, overlap push-out, touch rule,
  placement walk) should live in a plain JS module or a QML singleton with no
  UI, so it can be unit-tested headless in the VM.

## Testing

- Unit tests for the layout maths: the user's desk (expect `-1440x-560`,
  `3440x-560` give or take rounding, transforms 1 and 3); mixed densities
  (a 4K 27" next to a 1080p 24" at scale 1.5); a monitor with 0×0 mm; overlap
  push-out; a dropped floating monitor snapping to the nearest; rotation about
  the centre; round trip px → mm → px is stable.
- Generator / check tests in `dot-local/share/fledge/test/test-settings.sh` for
  `desc:` keys and the comma rule.
- VM end to end: the VM has one virtual output. Extra heads come from
  `hyprctl output create headless` (they report 0 mm, which exercises the
  fallback) or from more virtio heads in the VM definition (builder's call).
  A `verify-*.sh` check applies an arrangement through the IPC or settings
  path, then reads `hyprctl monitors -j` for the expected positions and
  transforms, and checks a revert restores the old ones.

## Left to the builder

Snap threshold; the floating-drop rule's details; the aspect-ratio tolerance
for distrusting physical size; whether a "size unknown" note shows; the anchor
choice; old-format pending file handling; how extra heads are made in the VM;
the canvas's exact look within the existing theme.
