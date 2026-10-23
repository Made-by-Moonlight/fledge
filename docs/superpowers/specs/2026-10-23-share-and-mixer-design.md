# Screen sharing and per-app volume: design

Date: 2026-10-23. Branch: `share-and-mixer`. A follow-up to the fledge shell
(project A), in three parts: per-app volume in quick settings, a fledge
screen-share picker, and Vesktop in place of the official Discord client.

## Why

- **Screen sharing is broken.** `dot-config/hypr/xdph.conf` (from the initial
  import, originally Omarchy's) sets
  `custom_picker_binary = hyprland-preview-share-picker`, which nothing
  installs and no repo carries. xdg-desktop-portal-hyprland runs it, gets no
  answer, and every share request ends in `SHAREDATA returned selection -1`
  (seen in the portal's journal on the user's desktop, 2026-10-23). The portal,
  xdph and PipeWire are otherwise fine.
- **Shared audio.** The user wants a screen share to carry the audio of the
  shared window only. The official Discord client on Linux sends no
  screen-share audio at all.
- **Per-app volume.** Quick settings has one output slider; there is no way to
  turn one app down (the user asked for "a per application volume menu").

Success: Discord (Vesktop) can share a window or a screen through a fledge
picker, with that app's audio; quick settings lists each app playing audio
with its own slider and mute.

## Goals

- **Apps in the audio picker.** The `›` beside the volume slider opens the
  audio picker; it gains an **Apps** group under Output and Input.
- **A fledge share picker**: a shell dialog listing windows and screens with
  live thumbnails, which xdph uses as its custom picker. Themed like the rest
  of the shell.
- **Vesktop replaces Discord** (the user's choice): `vesktop-bin` from the
  CachyOS repo, with its per-app share audio (venmic).

## Non-goals

- Per-app microphone levels, moving an app to another output, remembering
  per-app volumes (WirePlumber already restores stream volumes).
- Region sharing: xdph supports `region:`, but nothing asked for it.
- Choosing the shared audio outside Vesktop: the portal protocol carries no
  audio, and Vesktop picks the audio source in its own share dialog.
- Keeping the official client installed alongside.
- Theming Vesktop. The theme ships `vencord.theme.css`, but linking it into
  `~/.config/vesktop/themes/` needs a stow guard for that directory and the
  theme is still switched on by hand in Vesktop; left for project C.

## Part 1: per-app volume

**What the person sees.** Under Output and Input in the audio picker, an
**Apps** heading, then one row per app playing audio: its icon, its name, a
mute glyph, a slider and the percentage, laid out like the volume row above.
"Nothing playing" when the list is empty. Rows come and go as apps start and
stop playing (an idle Discord has no stream, so no row).

**Service.** `services/Audio.qml` gains:

- `streams`: PipeWire nodes with `audio && isStream && isSink` (playback
  streams), in a stable order (by application name, then node id) so rows
  don't jump.
- the streams added to the `PwObjectTracker`, without which their volume and
  mute aren't live;
- `setStreamVolume(node, v)` and `toggleStreamMute(node)`, clamped like the
  sink's.

**Names and icons.** From the node's properties: `application.name`, else
`node.description`, else `node.name`; the icon from `application.icon-name`,
else the app's desktop entry looked up by `application.process.binary`, else
a generic speaker glyph. Two streams from one app (a browser with two tabs)
are two rows; each row's subtitle is `media.name` when it differs from the
app name.

## Part 2: the fledge share picker

The stock fix came first (dropping the missing `custom_picker_binary`, so xdph
ran its bundled `hyprland-share-picker`), and sharing worked. The user then
saw that picker (an unstyled Qt list of `class: title` rows) and asked for the
fledge one back: "that's so very ugly". So the picker is ours.

**What the person sees.** An app asks to share its screen. A centered dialog
on the focused monitor, styled like the polkit dialog: two tabs, **Windows**
and **Screens**. Windows shows each open window as a card with a live
thumbnail, its icon and title; Screens shows each monitor's thumbnail and
name. Click (or arrows and Enter) picks; Escape or Cancel refuses, and the app
is told so. A **Remember this choice** toggle maps to xdph's restore token; it
starts on when xdph passes `--allow-token` (`allow_token_by_default`, kept on
as before).

**The protocol** (read from xdph 1.4.1 and its bundled picker, confirmed in
the VM). xdph runs `custom_picker_binary` as one program name, looked up on
`PATH` (a value with spaces is not split into arguments: `fledge screenshare
pick` there fails every request), with `--allow-token` when
`allow_token_by_default` is set and `XDPH_WINDOW_SHARING_LIST` in the
environment: entries `<handle>[HC>]<class>[HT>]<title>[HE>]<address>[HA>]`,
repeated. Handle and address are decimal; the address is the window's
Hyprland address (`94252854480848` for Hyprland's `55b8f3e90fd0`). The picker prints `[SELECTION]<flags>/<target>`, where `<flags>` is
`r` to allow a restore token or empty, and `<target>` is
`screen:<output name>` or `window:<handle>`. Anything else (no output,
non-zero exit) is a refusal. The session's `PATH` has
`~/.local/share/fledge/bin` (`uwsm/env-hyprland`), so the config names a
wrapper there.

**Pieces.**

- `fledge screenshare pick [--allow-token]`, a built-in (`lib/screenshare.sh`)
  shaped like `fledge dmenu`: a FIFO in `$XDG_RUNTIME_DIR`, the shell asked
  to open the dialog over IPC, a bounded wait on the FIFO for `1\n<flags>/<target>`
  or `0\n`, then `[SELECTION]…` on stdout. Not `fledge share`: that group is
  the LocalSend scripts, and a built-in would shadow them.
  - Shell not running: it runs `hyprland-share-picker` with the same
    arguments, so sharing still works without the shell (ugly, not broken).
  - Timeout (`FLEDGE_SCREENSHARE_TIMEOUT`, default 120 s): refuses and closes
    the dialog, so a forgotten dialog can't hang the portal.
  - Signals and exit clean up the FIFO and close the dialog, as dmenu does.
  - A shell that restarts while the dialog is open has lost it, and xdph runs
    one picker at a time, so every share would stall until the timeout. The
    helper asks every 2 s (`screenshare waiting <fifo>`) and refuses as soon
    as the shell no longer holds its request (seen in the VM: 2 s).
- `share/SharePicker.qml`: the dialog. Windows come from the sharing list,
  matched to Hyprland toplevels by address for the thumbnail
  (`ScreencopyView` on the toplevel) and icon; a window it can't match still
  shows, with its class and title and no thumbnail. Screens come from
  `Quickshell.screens`. It answers by writing the FIFO, bounded like
  `dmenuFinish`.
- An `IpcHandler` target `screenshare` in `ipc/Ipc.qml`: `open(list, result,
  allowToken)` answers `ok` or `busy`, `close()`, and `waiting(result)`. `shell state` reports
  `screenshare`.
- `ShellState.shareOpen`: like `polkitOpen`, no popup opens over the dialog
  (it holds the keyboard), and opening it closes open popups.
- `fledge-share-picker` (beside `fledge` in `~/.local/share/fledge/bin`): a
  one-line wrapper for `fledge screenshare pick "$@"`, since the config can't
  carry arguments. `dot-config/hypr/xdph.conf`:
  `custom_picker_binary = fledge-share-picker`.
- `Hyprland.toplevels` fills lazily: opening the dialog calls
  `refreshToplevels()`, or windows have no thumbnails.

**One request at a time**, like polkit: a request while the dialog is open
gets `busy` and is refused. Under the session lock the dialog doesn't show;
the request waits and the dialog appears after unlock (the timeout still
runs). The polkit dialog wins over it: while polkit is open the share dialog
stays hidden.

## Part 3: Vesktop

- `bootstrap.sh`: `vesktop-bin` replaces `discord` in `PACMAN_PACKAGES`, and
  `discord` joins `RETIRED_PKGS` so upgrades drop it.
- `fledge/rules.lua`: the workspace-9 and opacity rules match Vesktop's
  window class (checked in the VM; expected `vesktop`).
- `dot-config/vesktop-flags.conf`: `--ozone-platform=wayland`, read by the
  package's launcher. Vesktop ignores `ELECTRON_OZONE_PLATFORM_HINT` and would
  otherwise run under XWayland, where screen sharing bypasses the portal.
- Shared audio is Vesktop's: its share dialog lists audio sources (venmic)
  and can follow the shared app. Nothing for us to build beyond installing
  it; the VM check confirms the audio choice appears.

## Testing

All in the `cachyos-test` VM.

- `verify-shell.sh` gains: with `pw-play` (or `speaker-test`) running, the
  audio picker shows one app row and its slider moves the stream's volume
  (`wpctl get-volume <id>`).
- `test-screenshare.sh` (with a fake `qs`, like `test-dmenu.sh`): the
  `[SELECTION]` line for a pick, `--allow-token` passed through, refusal on
  cancel, `busy` and timeout (which closes the dialog), the fallback to
  `hyprland-share-picker` when the shell isn't running, a malformed answer
  refused.
- `verify-shell.sh`: `fledge screenshare pick` with a sharing list opens the
  dialog (`shell state`), a picked screen comes back as
  `[SELECTION]/screen:<name>`, Escape refuses.
- `verify-shell.sh` also makes a real portal request
  (`cachyos/iso/test/portal-screencast.py`, the ScreenCast calls an app
  makes): the dialog opens, and a pick gives the app a PipeWire stream.
- By hand: a window share from Vesktop through the fledge picker starts the
  stream, with the app's audio; cancelling gives a refusal, not a hang.
- Vesktop: launches on workspace 9, and a window share offers that app's
  audio.
