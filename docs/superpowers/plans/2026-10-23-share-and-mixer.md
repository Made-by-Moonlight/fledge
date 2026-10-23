# Screen sharing and per-app volume: plan

Spec: `docs/superpowers/specs/2026-10-23-share-and-mixer-design.md`.
Branch: `share-and-mixer`. Everything runs in the `cachyos-test` VM.

## 1. Screen sharing: the fledge picker

- [x] Stock fix first: `xdph.conf` without the missing picker; sharing works
      on the user's desktop with `hyprland-share-picker`.
- [x] `lib/screenshare.sh` + `fledge screenshare pick` built-in (help text,
      `GROUPS_ABOUT`), modelled on `lib/dmenu.sh`.
- [x] `test-screenshare.sh` with a fake `qs` (cases in the spec's Testing).
- [x] VM spike: run xdph's list through a logging picker to see real
      handle/address values (hex or decimal, `0x` or not).
- [x] `share/SharePicker.qml`, `ShellState.shareOpen` (gates popups like
      `polkitOpen`), IPC target `screenshare`, wired in `shell.qml`.
- [x] `xdph.conf`: `custom_picker_binary = fledge-share-picker`, a wrapper
      (the VM showed xdph won't take arguments in that setting).
- [x] `verify-shell.sh` checks; screenshot the dialog.

## 2. Vesktop

- [x] `bootstrap.sh`: `vesktop-bin` replaces `discord` in `PACMAN_PACKAGES`;
      `discord` added to `RETIRED_PKGS` on its own line.
- [x] VM: install `vesktop-bin`, launch it, read its class from
      `hyprctl clients -j`; `fledge/rules.lua` matches that class
      (workspace 9, opacity override).
- [x] `dot-config/vesktop-flags.conf`: `--ozone-platform=wayland` (the VM
      showed Vesktop otherwise starts on X11).
- [ ] By hand on the desktop (needs a Discord login): a window share in
      Vesktop offers that app's audio (venmic).

## 3. Per-app volume

- [x] VM spike: play a raw stream (`pw-cat --playback`) and read its
      `isSink` / `type` from Quickshell, to settle which way round a
      playback stream is.
- [x] `services/Audio.qml`: `streams` (playback streams, sorted by app name
      then id), tracked; `appName`, `appIcon`, `setStreamVolume`,
      `stepStreamVolume`, `toggleStreamMute`.
- [x] `quicksettings/pickers/AudioPicker.qml`: **Apps** group with icon,
      name (· media name), mute, slider, percentage; "Nothing playing".
- [x] `ipc/Ipc.qml`: `shell streams` reports the rows (for the test).
- [x] `verify-shell.sh`: with a stream playing, it's listed by name, and a
      `wpctl set-volume` on it shows up in `shell streams`.
- [x] Screenshot the picker with two streams playing.

## 4. Finish

- [x] shellcheck, `check-names.sh`, `check-stow-ignore.sh`.
- [x] Full `verify-shell.sh` run in the VM.
