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

## Session lock findings (Task 14, VM)

- `WlSessionLock.locked` does not notify when the lock is released: after `locked = false`, a direct read gives `false` but no `lockStateChanged` fires, so a binding to it stays `true`. `secure` notifies both ways. The shell keeps its own `locked` flag and resyncs it on `secureChanged`. `WlSessionLock` has no callable `unlock()` from QML (TypeError).
- `PamContext.pamMessage` has no arguments: read `message`, `responseRequired`, `messageIsError` from the context. `completed(result: PamResult)`, `error(error: PamError)` with `PamError` = `StartFailed`, `TryAuthFailed`, `InternalError`. `start()` returns bool.
- Quickshell does not kill a `Process`'s children when the shell exits or is killed: a `systemd-inhibit … sleep infinity` outlived every restart and kept its delay inhibitor. Hold `cat` on a `stdinEnabled` pipe instead; it exits with the shell.
- `misc:allow_session_lock_restore` set with `hyprctl keyword` is lost on every config reload (restow, `mbm settings apply`). Without it, a restarted shell that tries to re-lock is killed by a fatal Wayland error and Hyprland shows its "lockscreen died" screen (the session stays locked). It must live in the config file (Task 18).
- The VM's PAM stack (`login` → `system-auth`) has `pam_faillock` with defaults (deny=3, unlock_time=600): three wrong passwords lock the account for 10 minutes, sudo included. Keep wrong-password tests to two in a row; a correct password resets the count.
- Suspend in the VM: `/sys/power/mem_sleep` is `[s2idle]`. `systemctl suspend` works and the delay inhibitor held until the lock was secure (~100 ms); `virsh dompmwakeup` does **not** wake it ("guest is not in suspended state"), a `virsh send-key` does. But virtio-gpu loses its virtqueues across the resume (QEMU shows all-zero vrings) and the next blocking modeset (here `dpms on`) hangs Hyprland in `virtio_gpu_queue_ctrl_sgs` for good. After a suspend test the VM needs a reboot; check lock-before-suspend on real hardware.

## Idle and polkit findings (Task 15, VM)

- `IdleMonitor.timeout` is in seconds (double). A monitor that is enabled with timeout 0 reports idle at once. A timeout change while the monitor is enabled is ignored and the monitor then never reports idle, even if it was enabled with timeout 0 and given one later. Change it in this order: disable, set the timeout, enable (`services/Idle.qml` `Timeout`). Disabling while idle reports `isIdle` false.
- `PolkitAgent` binds to the logind session of the process. A `qs` started from an SSH login serves that SSH session, so pkexec on the desktop finds no agent. `vm.sh shell` starts qs through `hyprctl dispatch exec`. Hyprland runs as a uwsm user unit, and polkit falls back to the user's graphical session for those, as it will for `mbm-shell.service`.
- If another agent (polkit-gnome) already holds the session, registration fails. The real log line is `failed to register listener: ... An authentication agent already exists for the given subject`, but `isRegistered` still reads true. Nothing may start a second agent.
- 0.3.2 can't queue requests (`agentimpl.cpp`: activation pops the queue, so a second request activates straight away and replaces `flow`). When the first request finishes, it deletes the second's flow while polkit still waits on it. If that caller then gives up, `qs` segfaults in `g_cancellable_cancel`. `PolkitDialog` refuses (cancels) any request that arrives while one is open.
- With `pam_faillock`, every cancelled polkit request counts as a failed attempt (`faillock` shows `SVC polkit-1`). Three cancels lock the account for 10 minutes, and that includes the lock screen. A correct password resets the count.
- After a crash, Quickshell's crash guard restarts the shell under a bare `/usr/bin/quickshell` cmdline. `vm.sh shell` now kills that too.
