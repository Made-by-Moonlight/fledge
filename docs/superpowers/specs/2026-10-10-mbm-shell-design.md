# mbm shell v1 — design

**Date:** 2026-10-10
**Status:** approved design, amended during planning (2026-10-11)
**Branch:** `mbm-shell` (off `main` @ 4abc949)
**Mockups:** visual-companion screens in `.superpowers/brainstorm/` (gitignored):
`bar-style-v2.html`, `launcher-style.html`, `quick-settings.html`, `settings-window.html`

## Problem

The desktop's UI layer is still Omarchy's: waybar (bar), walker + elephant
(launcher, clipboard, emoji, dmenu for `slievr-menu`), mako (notifications),
swayosd (OSD), swaybg (wallpaper), hyprlock (lock), hypridle (idle),
polkit-gnome, plus ~283 vendored Omarchy scripts renamed `slievr-*`. Keybinds
and settings are hand-edited Hyprland `.conf` files. None of it is ours, and
none of it can be changed from a UI.

## The roadmap this is part of

"Make it our own" is four projects, each with its own spec, plan and branch.
After each one merges, the desktop works end to end.

| # | Project | Delivers | Retires |
|---|---|---|---|
| **A** | **mbm shell v1** (this spec) | Quickshell bar, launcher, notifications, OSD, lock, wallpaper, quick settings, settings window; `mbm settings` generator | waybar, walker, elephant, mako, swayosd, swaybg, hyprlock, hypridle, polkit-gnome, their configs and the scripts that only served them |
| B | `mbm` CLI | Owned commands for the remaining actions (screenshot/record, launch-or-focus, toggles, power profiles, hardware helpers). **No webapps.** | the vendored `slievr-*` tree, Omarchy LICENSE/README |
| C | mbm theme | Palette in mbm settings, our own app-theme renderer | `dot-config/omarchy/`, Omarchy `.tpl` templates |
| D | Graphical installer | Quickshell installer on the ISO (cage/Hyprland), reusing A + C | the `gum` configurator |

## Goals

- One Quickshell config, `mbm`, replaces every UI component listed under A.
- A settings window edits keybinds, displays, bar, idle & lock, and input.
  Changes apply live.
- Settings live in our own JSON. Hyprland config for them is **generated**,
  so Hyprland 0.57's `.conf` removal only touches the generator.
- Branded made by moonlight (palette in `dot-config/omarchy/current/theme/colors.toml`
  for now: `#171e28` background, `#f4af03` amber accent, JetBrains Mono).
- **Developed and tested only in the VM.** Nothing in this project is run,
  stowed or installed on the host machine.

## Non-goals (v1)

- Replacing `slievr-*` action scripts other than those that only served the
  retired tools (project B).
- Theme/palette editing or re-theming other apps (project C).
- Webapps, ever.
- SDDM → greetd (Quickshell ships a Greetd module; later, possibly with D).

## Decisions

| Topic | Decision |
| --- | --- |
| Toolkit | `quickshell` 0.3.1 from `extra` (built with PAM, PipeWire). Modules used: Hyprland, Io, Wayland (`WlSessionLock`, `IdleMonitor`, `IdleInhibitor`), Networking (NetworkManager), Bluetooth, Services.{Pipewire, UPower, Mpris, Notifications, SystemTray, Pam, Polkit}, Widgets. |
| Architecture | Quickshell renders and interacts. Anything that writes system config goes through the bash + `jq` CLI `mbm settings …`. |
| Process | One `quickshell -c mbm` instance (bar, popups, lock, settings window), started by uwsm, restarted on crash. |
| Bar | **Floating islands**: three detached pills (left: workspaces + focused title; centre: clock/date; right: status glyphs + tray + settings cog). |
| Launcher | Four modes: Apps, Clipboard, Emoji, System. Tabs + prefixes (`>` system, `:` emoji, `v` clipboard). **Position is a setting:** `centre` (palette) or `anchored` (drops from the left island). Default `centre`. Plus a **dmenu mode** for scripts. |
| Quick settings | Opened by the right island's cog (its visibility/position set on the Bar page), a settable bind, and a launcher "Settings" entry. Wi-Fi, Bluetooth, DND and night-light tiles; volume, mic and brightness sliders; power-profile switch; notification history; Settings and Power buttons. `›` expands in-panel pickers (networks, BT devices, audio sinks/sources). |
| Notifications | Pop-ups **top-right** by default (corner is a setting). Hidden while quick settings is open. DND holds pop-ups but still records them in history. |
| OSD | Bottom-centre: volume, brightness, mic mute. |
| Settings window | **Sidebar layout**: Keybinds, Displays, Bar, Idle & lock, Input. Keybinds is a grouped, filterable list; click a row to record keys; clashes flagged inline; "edited" tag on changed rows; right-click resets to default; "+ Add bind". |
| Lock + wallpaper | Port the approved made-by-moonlight design unchanged: Moonrise wallpaper per monitor; lock = glow background, owl, wordmark, clock, amber password field. Assets come from `cachyos/branding/` output, not `omarchy/current/`. |
| Idle | In-shell `IdleMonitor`, timeouts from settings (dim / lock / screen off / suspend). hypridle retired. Defaults keep today's behaviour: no idle timeouts (today's hypridle.conf has no listeners), lock before sleep on. |
| Lock semantics | Same as today's `slievr-system-lock`: locking also locks 1Password (`1password --lock` when running). **Lock before suspend:** the shell holds a logind delay inhibitor (`systemd-inhibit --what=sleep --mode=delay`, via `Process`), watches `PrepareForSleep` (`gdbus monitor --system`), locks, then releases it. On wake it turns displays back on (`hyprctl dispatch dpms on`), replacing `slievr-system-wake`. |
| Polkit | In-shell agent (`Services.Polkit`) styled like the lock prompt. polkit-gnome retired. |
| Naming | `mbm` (made by moonlight): `~/.config/quickshell/mbm/`, `~/.config/mbm/`, `~/.local/share/mbm/`, `mbm` CLI. |

## Repo layout

```
dot-config/quickshell/mbm/         -> ~/.config/quickshell/mbm/   (qs -c mbm)
  shell.qml                        entry; per-screen bar/wallpaper via Variants
  theme/Theme.qml                  singleton: palette, fonts, radii, spacing, durations
  services/                        thin singletons over Quickshell services
    Settings.qml                   FileView + JsonAdapter on ~/.config/mbm/settings.json,
                                   merged over defaults; exposes typed properties
    Audio Network Bluetooth Battery Brightness Notifs Clipboard Idle Power Media
  components/                      Pill Slider Toggle Tile List KeyRecorder Icon …
  bar/                             Bar.qml + modules/ (Workspaces Title Clock Tray Glyphs Cog)
  launcher/                        Launcher.qml + modes/ (Apps Clipboard Emoji System Dmenu)
  quicksettings/                   Panel, tiles, sliders, pickers/, NotificationHistory
  notifications/                   Popups.qml
  osd/                             Osd.qml
  lock/                            Lock.qml (WlSessionLock + Pam)
  polkit/                          Agent.qml
  wallpaper/                       Wallpaper.qml
  settings/                        Window.qml + pages/ (Keybinds Displays Bar Idle Input)
  ipc/                             Ipc.qml (IpcHandler targets)

dot-local/share/mbm/               -> ~/.local/share/mbm/   (bin/ on session PATH via ~/.config/uwsm/env)
  bin/mbm                          dispatcher: mbm settings …, mbm dmenu
  lib/settings.sh                  merge, validate, generate
  lib/dmenu.sh
  defaults/settings.json           every shipped default
  test/test-settings.sh            + fixtures/
```

`dot-config` / `dot-local` are GNU stow `--dotfiles` names (→ `.config`,
`.local`), unchanged from today.

## Settings

### Files

- `~/.local/share/mbm/defaults/settings.json`: shipped defaults, read-only (stowed from the repo).
- `~/.config/mbm/settings.json`: **user overrides only**. "Reset to default"
  deletes the key. New defaults from the repo reach the user on update.
- `~/.local/state/mbm/settings.json`: the **merged** settings (defaults + overrides),
  rewritten by every `set`/`reset`/`apply`. The shell reads only this file (plus the
  user file, to mark edited rows), so the merge lives in one place: the CLI.
- `~/.config/hypr/mbm/*.conf`: generated. `hyprland.conf` sources
  `~/.config/hypr/mbm/*.conf`. Never hand-edited (header comment says so).

### Schema (top level)

```jsonc
{
  "version": 1,
  "binds": {                                   // keyed by stable action id
    "apps.terminal":   { "mods": "SUPER", "key": "RETURN", "label": "Terminal", "group": "Apps",
                         "action": { "exec": "uwsm app -- $TERMINAL --dir=\"$(slievr-cmd-terminal-cwd)\"" } },
    "utilities.launch-apps": { "mods": "SUPER", "key": "SPACE", "label": "Launch apps", "group": "Utilities",
                         "action": { "shell": "launcher.toggle" } },
    "windows.focus-on-next-window": { "mods": "ALT", "key": "TAB", "label": "Focus on next window", "group": "Windows",
                         "action": [ { "dispatch": "cyclenext" }, { "dispatch": "bringactivetotop" } ] },
    "media.volume-up": { "mods": "", "key": "XF86AudioRaiseVolume", "flags": "el", "label": "Volume up", "group": "Media",
                         "action": { "shell": "osd.volume +5" } }
    // user-added binds use ids "custom.<n>"; a default bind set to null is removed
  },
  "displays":      { "<connector or desc:…>": { "mode": "2560x1440@165", "scale": 1.25, "position": "0x0", "enabled": true } },
  "bar":           { "position": "top", "left": ["workspaces","title"], "centre": ["clock"],
                     "right": ["tray","glyphs","cog"], "glyphs": ["network","battery"] },
  "launcher":      { "position": "centre" },             // centre | anchored
  "notifications": { "corner": "top-right", "timeoutMs": 5000 },
  "idle": { "dimSec": 0, "lockSec": 0, "screenOffSec": 0, "suspendSec": 0, "lockOnSleep": true }
  "input":         { "kbLayout": "us", "kbOptions": "compose:caps", "repeatRate": 40, "repeatDelay": 600,
                     "numlock": true, "touchpad": { "scrollFactor": 0.4, "naturalScroll": false, "tapToClick": true },
                     "sensitivity": 0 }
}
```

`mods` (space-separated, from SUPER SHIFT CTRL ALT MOD2 MOD3 MOD5, may be empty)
and `key` (any Hyprland key: `RETURN`, `code:10`, `mouse:272`, `XF86AudioMute`,
`switch:on:Lid Switch`) are separate fields, because many real keys can't be
written as a `MOD+KEY` string. `action` is one action or a list of them
(Hyprland runs several binds on one combo; `ALT+TAB` does). Each action is
exactly one of `{shell: "<target>.<fn> [args]"}` (→ `exec, qs -c mbm ipc call …`),
`{dispatch: "<dispatcher> [args]"}` or `{exec: "<command>"}`. `flags` maps to
Hyprland bind flags (`e l r n m t i s p`; `d` is always added). Labels can't
contain commas. A clash is two different bind ids on the same mods+key+flags.
Real defaults are migrated from today's config (see Cutover), not invented.

### CLI

| Command | Does |
| --- | --- |
| `mbm settings get <path>` | merged value (jq path) |
| `mbm settings set <path> <json> [<path> <json>]…` | write overrides atomically; refuses (writes nothing) if the result fails `check`. Paths are jq paths such as `.launcher.position` or `.binds["apps.terminal"].key` |
| `mbm settings reset <path>` | delete override |
| `mbm settings check` | validate merged settings; non-zero + message on failure |
| `mbm settings apply` | `check`, then generate `binds.conf`, `monitors.conf`, `input.conf` into `~/.config/hypr/mbm/`, then `hyprctl reload` if Hyprland is running |
| `mbm dmenu [--prompt P]` | options on stdin → shell's launcher in dmenu mode → choice on stdout (exit 1 on cancel) |

### Validation (`check`)

Bad JSON; unknown top-level or per-section keys; `version` mismatch; key combo
not matching `MOD(+MOD)*+KEY` with known modifiers; **two binds with the same
combo + flags**; action with zero or more than one of shell/dispatch/exec;
display mode not `WxH@R`; idle timeouts not non-negative integers (and
`lock ≥ dim` when both are set). `apply` writes nothing if `check` fails.

### Write safety

Every write (user JSON, each generated `.conf`) goes to a temp file in the same
directory, then `mv`. A failed `apply` leaves the previous generated files intact.

### Live vs generated

- **Generated (needs `apply`):** binds, displays, input.
- **Live in the shell (the `Settings` singleton watches the file):** bar layout,
  launcher position, notification corner and timeout, idle timeouts.

The settings window writes through `mbm settings set` and then runs `mbm settings apply`
when a generated section changed, showing any `check` error inline.

## Shell ↔ Hyprland

- Binds that drive the shell call `qs -c mbm ipc call <target> <fn>`. IPC targets:
  `launcher` (toggle, open <mode>), `quicksettings` (toggle, open [picker]), `settings`
  (open [page]), `lock` (lock), `osd` (volume ±n, brightness ±n, mic-mute),
  `notifications` (dismiss, dismiss-all, dnd-toggle), `dmenu` (used by `mbm dmenu`).
- Workspaces, focused title and monitors come from `Quickshell.Hyprland`.
- `misc:allow_session_lock_restore = true`, so a restarted shell can lock again.
- The Keybinds page records keys inside an empty Hyprland submap (mbm-record, generated with binds.conf) so compositor binds don't fire while recording; SUPER+CTRL+ALT+Escape always leaves it.

## Cutover (all in this branch)

**Hyprland config**
- `autostart.conf` (+ `hypr-defaults/hypr/autostart.conf`): remove mako,
  waybar, swaybg, hypridle, polkit-gnome. The shell runs as the user unit mbm-shell.service (Restart=on-failure, WantedBy graphical-session.target, enabled by a stowed .wants link like elephant was).
- `hyprland.conf` sources `~/.config/hypr/mbm/*.conf`. It stops sourcing
  `bindings.conf`, `hypr-defaults/hypr/bindings/*`, `monitors.conf` and
  `input.conf`, whose contents migrate into `defaults/settings.json` and which
  are then deleted.
- Remove walker/waybar/mako layer rules from `hypr-defaults/hypr/apps/`.

**Bind remaps (deliberate changes)**
- `Super+Space` → launcher apps; `Super+Ctrl+V` → clipboard; `Super+Ctrl+E` → emoji.
- `Super+Escape`, `XF86PowerOff`, `Super+Alt+Space` → launcher System mode.
- `Super+Ctrl+L` → `lock.lock`. `Super+Ctrl+I` → idle-lock toggle (shell).
- `Super+K` → settings window, Keybinds page.
- `Super+Shift+Space` (toggle bar) → shell bar toggle.
- `Super+,` / `Super+Shift+,` → notifications dismiss / dismiss-all.
- Media/brightness keys → `osd.*` (shell does the change and shows the OSD).
- Quick settings: new bind `Super+A` (free today; `Super+S` / `Super+Alt+S` stay scratchpad).
- `Super+Ctrl+W` / `Super+Ctrl+B` / `Super+Ctrl+A` (today: nmtui, bluetui, wiremix) →
  quick settings opened with the Wi-Fi / Bluetooth / audio picker expanded
  (`quicksettings.open wifi|bluetooth|audio`). `bluetui` and `wiremix` leave the package list.
- Webapp binds (e.g. `Super+Shift+Y`) are left alone in A and decided in B.

**slievr-menu**
Callers keep working through compat shims that B deletes: `slievr-launch-walker`
(dmenu → `mbm dmenu`, modes → launcher), `slievr-swayosd-client` (→ `osd.show`),
`slievr-system-lock`, `slievr-toggle-waybar`, `slievr-toggle-idle`,
`slievr-toggle-notification-silencing`, `slievr-notification-dismiss` (→ IPC).
`slievr-menu-keybindings` and the restart/refresh scripts of retired tools are deleted,
and their slievr-menu entries removed.

**Packages (`bootstrap.sh`)**
- Add: `quickshell cliphist wl-clipboard jq ttf-jetbrains-mono` and an emoji
  dataset (`unicode-emoji`, read by the Emoji mode).
- Remove: `waybar walker elephant* mako swayosd swaybg hyprlock hypridle polkit-gnome bluetui wiremix`.
- Install `/etc/pam.d/mbm-lock` (`auth include login`), separate from the real login stack.
- Run `mbm settings apply` after stow.

**Files deleted**
`dot-config/{waybar,walker,elephant,mako,swayosd}`, `dot-config/hypr/{hyprlock,hypridle}.conf`,
the elephant unit under `dot-config/systemd/user/`, and `slievr-*` scripts whose
only purpose was a retired tool (`*-walker`, `*-waybar`, `*swayosd*`,
`slievr-system-lock`, `slievr-toggle-idle`, etc.). The plan lists each one,
found by grepping callers.

## Failure handling

| Failure | Behaviour |
| --- | --- |
| Shell crashes | uwsm unit restarts it; with `allow_session_lock_restore` a locked session comes back locked, not "lockscreen died" |
| Bad settings | `check` blocks `apply`; the shell uses the default for any key it can't read and logs it |
| Missing hardware (no battery/BT/backlight/Wi-Fi, e.g. the VM) | that tile/glyph is hidden |
| Service down (NM, BlueZ, power-profiles-daemon) | tile shows "unavailable"; the rest works |
| Suspend before lock is drawn | the delay inhibitor holds sleep until the lock surface is up (logind caps the delay at `InhibitDelayMaxSec`, 5 s by default) |
| PAM | dedicated `mbm-lock` service; a mistake there can't break real login |
| `mbm dmenu` with shell not running | exits 1 with a message (callers already treat cancel as no-op) |

## Testing (everything runs in the VM)

The host is never used to run, stow or install anything from this project.
Iterate with `cachyos/vm/dev-up.sh`, sync the branch into the VM, re-run
`bootstrap.sh` there.

1. **Generator unit tests: `dot-local/share/mbm/test/test-settings.sh`**,
   in the repo's `test/lib.sh` style (`check`/`contains`), temp `HOME`. Covers:
   defaults → expected `.conf` files; override replaces a bind; reset deletes
   a key; duplicate combo → `check` fails and `apply` writes nothing; malformed
   JSON; unknown key; invalid combo; failed apply leaves previous files intact.
2. **Migration parity:** in the VM before cutover, capture `hyprctl binds -j`
   from the hand-written config; after cutover, compare with the generated
   config. The only differences allowed are the deliberate remaps listed above.
3. **`qmllint`** over `dot-config/quickshell/mbm/` (in the VM).
4. **`cachyos/iso/test/verify-shell.sh`** (sibling of `verify-install.sh`, over SSH):
   `qs` running and none of the retired daemons; each IPC target answers;
   `mbm settings check` passes and generated files exist; `mbm settings set`
   a bind + `apply` → visible in `hyprctl binds`; lock then PAM unlock (via
   `virsh send-key`); `systemctl suspend` then resume → session is locked; kill `qs` while locked → restarts locked; `mbm dmenu`
   round-trip.
5. **Screenshots** (`grim` in the VM, copied to the host) of bar, launcher
   (both positions, each mode), quick settings, a notification, OSD, lock,
   each settings page. Compared against the mockups.
6. **Manual pass** in the VM viewer: keyboard navigation, key recording, animations.

## Open risks

- Quickshell 0.3 API details (Networking especially) are newer and less
  documented. The plan starts with a spike in the VM to confirm each service
  works before building UI on it.
- Hyprland 0.57 drops `.conf`. The generator is the only place that has to
  change, but that work isn't in this spec.
