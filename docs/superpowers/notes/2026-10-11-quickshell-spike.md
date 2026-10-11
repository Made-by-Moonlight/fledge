# Quickshell spike (VM, 2026-10-11)

Installed in the VM: **Quickshell 0.3.2** (Arch package; the plan said 0.3.1). Hyprland 0.56.2.

| Question | Answer |
| --- | --- |
| `qs` subcommands available | `log`, `list`, `kill`, `ipc`, `msg` (deprecated, use `ipc call`). Flags: `-c/--config`, `-p/--path`, `-n/--no-duplicate`, `-d/--daemonize`. |
| `pragma Singleton` in a directory imported by relative path (`import "services"`) works | Yes: `Probe.hello` returned `singleton-ok`. |
| IPC: typed args (string with spaces, int, bool) and string return | `qs -c spike ipc call spike echo "a b" 3 true` -> `a b\|3\|true`. |
| `UPower.displayDevice.percentage` range (0-1 or 0-100) | **Undetermined.** The `.qmltypes` declare it as `double`, read-only, with no doc comment or range (`Services/UPower/quickshell-service-upower.qmltypes:217`). The VM has no battery: `upower -d` DisplayDevice shows `percentage: 0%` and Quickshell reports `0`, so both scales read the same. Do not assume a range; derive the fraction from `energy / energyCapacity` (both `double`, read-only) or verify on real hardware before relying on `percentage`. |
| `PowerProfiles.profile` value for balanced | Observed `1`. Enum `PowerProfile` (`Services/UPower/quickshell-service-upower.qmltypes:48`): `values: ["PowerSaver", "Balanced", "Performance"]`. The qmltypes list names in order without explicit numbers; the observed `1` for balanced matches index 1. Use `PowerProfile.Balanced`, not `1`. |
| `Networking.backend` / device types seen | `backend: 1` = `NetworkBackendType.NetworkManager` (`Networking/quickshell-network.qmltypes:212`: `["None", "NetworkManager"]`). One device `enp1s0`, `type: 2`, `connected: true` = `DeviceType.Wired` (`:82`: `["None", "Wifi", "Wired"]`; so Wifi = 1). Use `DeviceType.Wifi` / `DeviceType.Wired` (there is no `Ethernet`). |
| `Bluetooth.defaultAdapter` in the VM | `null` (log: `Failed to create DBusObjectManagerInterface for org.bluez` WARN; no bluetoothd/adapter). |
| `Quickshell.iconPath(name, true)` for a known icon | `image://icon/kitty` (an image-provider URL, not a filesystem path; use as `Image.source`). The URL is returned for the name given; it does not by itself prove the icon resolves. `kitty.png`/`kitty.svg` were found under `/usr/share/icons/*/*/apps/` in the VM. |
| `/etc/pam.d/hyprlock` contents (copy for mbm-lock) | `# PAM configuration file for hyprlock` / `# the 'login' configuration file (see /etc/pam.d/login)` / blank / `auth        include     login` |
| `gdbus` / `systemd-inhibit` present | Yes: `/usr/bin/gdbus`, `/usr/bin/systemd-inhibit`. Session is `Type=wayland`, `Active=yes`; `InhibitDelayMaxSec` is default (5s); `gdbus monitor` on login1 prints `Monitoring signals on object /org/freedesktop/login1 ...`. |
| Anything that contradicts the plan | See below. |

## Contradictions / caveats for later tasks

- Version is 0.3.2, not 0.3.1; all imports in the spike (Hyprland, Networking, Bluetooth, Pipewire, UPower, Notifications, Io) resolved, so the 0.3.1 API extract still holds.
- Models are populated asynchronously: immediately after start (3s) `Hyprland.workspaces` was `[]` and `DesktopEntries.applications` was 0; a few seconds later workspaces `[11]` and 24 apps. Never read these once at startup; bind reactively.
- The VM's only workspace id is 11 (not 1); do not assume workspace 1 exists.
- Hyprland.activeToplevel and `Pipewire.defaultAudioSink` were null (no windows, no audio sink in the VM); `?.` guards are required.
- Every `qs` invocation prints a locale WARN ("C" encoding) in the SSH session. It is not an error and is on stderr, but `vm.sh run` merges stderr into the output, so filter it when parsing `qs ipc call` results.
- `UPower.displayDevice` is non-null even without a battery; test `isLaptopBattery`, not null-ness.
- Networking `type`, `backend` and `PowerProfiles.profile` are numeric enums, not strings. Compare against enum names, never raw numbers. Enum names confirmed in the VM's 0.3.2 `.qmltypes` (paths under `/usr/lib/qt6/qml/Quickshell/`; each qmltypes `Enum` lists names in order):

| Singleton (import) | Enum names | Source |
| --- | --- | --- |
| `PowerProfile` (Services.UPower) | `PowerSaver`, `Balanced`, `Performance` | `Services/UPower/quickshell-service-upower.qmltypes:48` |
| `UPowerDeviceState` (Services.UPower) | `Unknown`, `Charging`, `Discharging`, `Empty`, `FullyCharged`, `PendingCharge`, `PendingDischarge` | same file, `UPowerDeviceState` Component at line 341 |
| `NotificationUrgency` (Services.Notifications) | `Low`, `Normal`, `Critical` | `Services/Notifications/quickshell-service-notifications.qmltypes:432` |
| `PamResult` (Services.Pam) | `Success`, `Failed`, `Error`, `MaxTries` | `Services/Pam/quickshell-service-pam.qmltypes:172` |
| `WifiSecurityType` (Networking) | `Wpa3SuiteB192`, `Sae`, `Wpa2Eap`, `Wpa2Psk`, `WpaEap`, `WpaPsk`, `StaticWep`, `DynamicWep`, `Leap`, `Owe`, `Open`, `Unknown` | `Networking/quickshell-network.qmltypes:540-` (Enum at 544) |
| `DeviceType` (Networking) | `None`, `Wifi`, `Wired` | `Networking/quickshell-network.qmltypes:82` |
| `NetworkBackendType` (Networking) | `None`, `NetworkManager` | `Networking/quickshell-network.qmltypes:212` |
| `WlrKeyboardFocus` (exported as `Quickshell.Wayland._WlrLayerShell/WlrKeyboardFocus`; used via `WlrLayershell.keyboardFocus`) | `None`, `Exclusive`, `OnDemand` | `Wayland/_WlrLayerShell/quickshell-wayland-layershell.qmltypes:21` |

Note `PamResult` has no `Cancelled`, and `NotificationUrgency` is `Low/Normal/Critical` (not `Urgent`).
