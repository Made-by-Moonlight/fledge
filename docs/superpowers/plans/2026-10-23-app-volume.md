# Per-app volume in Settings › Apps: plan

Spec: `docs/superpowers/specs/2026-10-23-app-volume-design.md`.
Branch: `app-volume`, on `app-rules` (PR #19). Everything runs in the VM.

- [x] Spike on the desktop (read-only `pw-dump`, `/proc`): Zen plays from its
      window's process, Vesktop from a child of it.
- [x] `check.jq`: `apps.<class>.volume`, 0–1; tests (and that it generates
      no Hyprland rule).
- [x] `Audio.qml`: stream → class (name, then process walk via `pw-dump` and
      `/proc`, keyed by id + serial); `streamsOf`, `appVolume`, `appMuted`,
      `setAppVolume`, `toggleAppMute`; starting volumes, retried until ready.
      Quick settings rows use the app's name when a stream maps to one.
- [x] `Apps.qml`: Sound section (live slider and mute; Starts at Last used /
      Fixed with a debounced slider), the playing glyph, "♪" in the summary.
- [x] `shell streams` reports each stream's app.
- [x] `verify-shell.sh`: by name, by process, starting volume; full run.
