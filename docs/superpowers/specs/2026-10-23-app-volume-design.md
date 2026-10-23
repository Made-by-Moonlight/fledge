# Per-app volume in Settings › Apps: design

Date: 2026-10-23. Branch: `app-volume`, on top of `app-rules` (PR #19). Builds
on the per-app volume rows in quick settings
(`2026-10-23-share-and-mixer-design.md`) and Settings › Apps
(`2026-10-23-app-rules-design.md`).

## Why

The user: "the app sound settings should be moved to apps as well". Their
choices:

- **Both places.** Quick settings keeps its per-app rows for what's playing;
  each app's row in Settings › Apps also gets its sound.
- **Live and remembered.** The Apps row shows the app's live volume and mute
  while it plays, and can hold a volume that the app's new streams start at,
  instead of WirePlumber's last-used one.

Success: an app's row in Settings › Apps shows a Sound section while it
plays, with a slider and mute that move all of its streams; a "Starts at"
volume, once set, is what the app's next stream begins at.

## Which app a stream belongs to

Settings › Apps is keyed by window class; PipeWire streams aren't. Seen on the
user's desktop (2026-10-23):

| Stream | `application.name` | `application.process.binary` | process | window |
|---|---|---|---|---|
| Zen tab | Zen | zen-bin | 2335 | zen, pid 2335 |
| Vesktop | vesktop | vesktop | 83008 | vesktop, pid 81805 (83008's parent) |

So, in order, the first that answers:

1. **By name:** the stream's `application.process.binary` or
   `application.name`, ignoring case, is a known class (an open window's or a
   configured app's). This goes first so a command-line player started in a
   terminal (`mpv`, `pw-play`) counts as itself, not as the terminal.
2. **By process:** the stream's `application.process.id`, or the nearest
   ancestor of it, owns a window (`hyprctl clients -j` pids, parents from
   `/proc/<pid>/status`): Zen (the same process) and Electron apps such as
   Vesktop (an audio child process).
3. Otherwise it belongs to no app: it still shows in quick settings, not in
   Settings › Apps.

Where the process id is: apps that go through pipewire-pulse (browsers,
Electron) carry `application.process.id` on the stream node; native PipeWire
clients (`pw-cat`, mpv's PipeWire output) only on their client object (seen in
the VM). So the walk reads both from one `pw-dump`.

The walk runs once per new stream, for all waiting streams in one small shell
command, not per change. Its answers (and the starting-volume bookkeeping) are
keyed by node id **and** `object.serial`: PipeWire reuses node ids, and in the
VM a new stream on an old id inherited the old stream's app until this was
fixed. A miss ("no window") is retried when the open windows change, since a
stream can start before its window maps.

## Settings

`apps.<class>.volume`: the volume the app's new streams start at, 0 to 1. No
entry means WirePlumber's own restore (the last volume used). It's read live
by the shell: no apply, nothing generated.

## Applying a remembered volume

When a stream first appears, is ready, and maps to an app with a `volume`,
the shell sets that stream's volume once (WirePlumber has restored its own
value by then; ours lands after: checked in the VM, still 0.30 seconds later).
Streams still waiting on either are retried every 250 ms. Mute isn't remembered. A stream's volume isn't set
again after that, so a change during playback (quick settings, the app's
own slider) sticks for that stream.

## The page

In an app's expanded row, under Opens on:

```
 Sound   (shown while it plays, or when it has a starting volume)
   󰕾 ━━━━━━━━━━━━━━━━━━━━━━━━○──────  64%      ← live: all its streams
   Starts at  ( Last used | Fixed )
     ━━━━━━━━━━━━━━━━━━━━━━○────────  60%      ← apps.<class>.volume
```

- **Live:** the app's streams together. The slider shows the loudest one and
  sets them all; the glyph mutes or unmutes them all. Not shown when nothing
  is playing.
- **Starts at:** Last used (no `volume`: WirePlumber's restore) or Fixed, with
  its slider, which saves 400 ms after the last move like the opacity ones.
  Choosing Fixed starts it at the live volume when the app is playing, else
  100 %.
- The row summary adds "♪ 60%" when a starting volume is set, and the row
  shows a speaker glyph while the app plays.

Quick settings is unchanged except for the row name: an app's row there uses
the same name the Apps page does when the stream maps to an app.

## Non-goals

- Remembering mute, or a volume per stream (tab) rather than per app.
- Routing an app to an output.
- Recording streams (per-app microphone).

## Testing

All in the `cachyos-test` VM.

- `test-settings.sh`: `volume` 0–1 accepted, out of range or text refused;
  `apps.lua` unaffected by it.
- `verify-shell.sh`:
  - a stream named like a configured class maps to it (`shell streams`
    reports the class), and starts at the app's `volume`;
  - a stream from a process inside a window (`kitty --class X -e pw-cat`)
    maps to that window's class;
  - with no `volume`, the stream keeps WirePlumber's;
  - `settings app <class>` while it plays shows the Sound section
    (screenshot).
