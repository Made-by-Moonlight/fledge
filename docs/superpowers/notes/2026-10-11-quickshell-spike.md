# Quickshell spike (VM, 2026-10-11)

Installed in the VM: **Quickshell 0.3.2** (Arch package; the plan said 0.3.1). Hyprland 0.56.2.

| Question | Answer |
| --- | --- |
| `qs` subcommands available | `log`, `list`, `kill`, `ipc`, `msg` (deprecated, use `ipc call`). Flags: `-c/--config`, `-p/--path`, `-n/--no-duplicate`, `-d/--daemonize`. |
| `pragma Singleton` in a directory imported by relative path (`import "services"`) works | Yes: `Probe.hello` returned `singleton-ok`. |
| IPC: typed args (string with spaces, int, bool) and string return | `qs -c spike ipc call spike echo "a b" 3 true` -> `a b\|3\|true`. |
| `UPower.displayDevice.percentage` range (0-1 or 0-100) | Not observable: the VM has no battery; `displayDevice` exists but reports `pct: 0`, `isLaptopBattery: false`. Treat range as unverified; guard on `isLaptopBattery` and check on real hardware (Quickshell shells conventionally treat it as 0-1). |
| `PowerProfiles.profile` value for balanced | `1` (enum PowerProfile: PowerSaver=0, Balanced=1, Performance=2). |
| `Networking.backend` / device types seen | `backend: 1` (enum NetworkBackendType: None=0, NetworkManager=1). One device `enp1s0`, `type: 2`, `connected: true` (ethernet; wifi type value not observed). |
| `Bluetooth.defaultAdapter` in the VM | `null` (log: `Failed to create DBusObjectManagerInterface for org.bluez` WARN; no bluetoothd/adapter). |
| `Quickshell.iconPath(name, true)` for a known icon | `image://icon/kitty` (an image-provider URL, not a filesystem path; use as `Image.source`). kitty icon exists in the VM theme. |
| `/etc/pam.d/hyprlock` contents (copy for mbm-lock) | `# PAM configuration file for hyprlock` / `# the 'login' configuration file (see /etc/pam.d/login)` / blank / `auth        include     login` |
| `gdbus` / `systemd-inhibit` present | Yes: `/usr/bin/gdbus`, `/usr/bin/systemd-inhibit`. Session is `Type=wayland`, `Active=yes`; `InhibitDelayMaxSec` is default (5s); `gdbus monitor` on login1 prints `Monitoring signals on object /org/freedesktop/login1 ...`. |
| Anything that contradicts the plan | See below. |

## Contradictions / caveats for later tasks

- Version is 0.3.2, not 0.3.1; all imports in the spike (Hyprland, Networking, Bluetooth, Pipewire, UPower, Notifications, Io) resolved, so the 0.3.1 API extract still holds.
- Models are populated asynchronously: immediately after start (3s) `Hyprland.workspaces` was `[]` and `DesktopEntries.applications` was 0; a few seconds later workspaces `[11]` and 24 apps. Never read these once at startup; bind reactively.
- The VM's only workspace id is 11 (not 1); do not assume workspace 1 exists.
- Hyprland.activeToplevel and `Pipewire.defaultAudioSink` were null (no windows, no audio sink in the VM); `?.` guards are required.
- Every `qs` invocation prints a locale WARN ("C" encoding) in the SSH session; not an error, but filter it when parsing output of `qs ipc call` (it goes to stderr in the spike's merged output).
- `UPower.displayDevice` is non-null even without a battery; test `isLaptopBattery`, not null-ness.
- Networking `type` and `PowerProfiles.profile` are numeric enums, not strings.
