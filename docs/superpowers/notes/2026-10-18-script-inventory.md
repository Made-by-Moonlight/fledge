# Script inventory for the fledge rename

**Date:** 2026-10-18 · **Spec:** `docs/superpowers/specs/2026-10-18-fledge-rename-design.md` (Pruning) · **Status:** for the user's veto before anything is deleted.

`dot-local/share/slievr-cachy/bin/` holds **270** files: the `slievr` router and 269 `slievr-*` scripts.

| | count |
|---|---|
| kept | **105** (104 scripts + the `slievr` router, which the `fledge` dispatcher replaces) |
| dropped | **165** (158 that nothing reaches + 7 webapps) |
| of which webapps | 7 (2 of them are bound today: the binds go too) |

## How reachability was decided

Roots, then the transitive closure over script-to-script calls (non-comment lines only; literal names, path-qualified names, and `slievr <words>` router calls resolved by longest prefix, as the router does):

- **Binds / settings defaults**: every `exec` in `dot-local/share/mbm/defaults/settings.json` (the `shell` actions are shell IPC, none name a script). The v1 fixture `dot-local/share/mbm/test/fixtures/defaults-v1.json` has the same strings and is history, not a root.
- **Shell QML**: `SystemMode.qml` (`slievr-menu capture|toggle|hardware|share|setup`), `QuickSettings.qml` (`slievr-toggle-nightlight`), `Ipc.qml` (`slievr-brightness-keyboard-mute`). `Lock.qml` and `Brightness.qml` mention scripts in comments only.
- **Hyprland Lua**: `dot-config/hypr/fledge/autostart.lua` (`slievr-first-run`, `slievr-powerprofiles-init`, `slievr-hyprland-monitor-watch`, `slievr-hook post-boot`, and `~/.config/omarchy/scripts/nvidia-power.sh`, which runs `slievr-hw-display-gpu` by absolute path). The toggles' Lua files only name `slievr-hyprland-toggle` in comments. No Lua bind or rule calls a script.
- **Session env**: `dot-config/uwsm/env-hyprland` runs `slievr-hw-display-gpu` by absolute path.
- **Bootstrap / installer / firstboot / ISO airootfs / vm**: no calls (bootstrap only has comments; the installer, firstboot and `mbm-*` ISO helpers reference only `slievr-cachy` paths and `slievr-firstboot`).
- **Units / .desktop**: the only units are `mbm-shell.service` and `slievr-firstboot.service`; the only `.desktop` is the SDDM theme metadata. None call a script.
- **Tests**: `cachyos/branding/test-theme.sh` runs `slievr-theme-set-templates`; `verify-shell.sh` runs `slievr-toggle-nightlight` (already bound).
- **The menu**: not "everything `slievr-menu` contains", but what a user can actually reach. Its entry args used by binds and QML are `capture, toggle, hardware, share, setup, background, theme, reminder-set`; the main menu (`Apps, Trigger, Style, Setup, System`) is reachable too, because cancelling the Setup submenu falls through to `show_main_menu` (and AGENTS.md documents `slievr-menu › Setup › Config`). **The Install, Remove, Update and Learn submenus, and `about`, are reachable only as `slievr-menu install|remove|update|learn|about` by hand. Nothing in the repo opens them and the main menu doesn't list them**, so the scripts that only they reach are dropped (groups below). This is the biggest call for the veto.
- Not roots: READMEs, docs, comments, and the router's `--help` text (it names `slievr update`, `slievr theme list/set`, `slievr font list`, `slievr debug`).

The menu's own code that only the dropped submenus use (the `install*` / `aur_install*` helpers and the `show_install_*`, `show_remove_*`, `show_update_*` and `show_learn_menu` functions, plus their `go_to_menu` cases) goes in Task 2 along with the scripts.

## Kept (105)

"reached from" names the root or the kept caller. **Proposed name** is the mechanical mapping `slievr-<g>-<a…>` → `fledge <g> <a…>` (libexec `<g>-<a…>`), except where flagged.

| script | status | reached from | proposed name | notes |
|---|---|---|---|---|
| `slievr` | kept | bind (router) | `fledge` (dispatcher) | Command router. Replaced by the `fledge` dispatcher (Task 3), not moved to libexec. |
| `slievr-ac-present` | kept | `slievr-powerprofiles-init` | `fledge ac present` |  |
| `slievr-audio-output-switch` | kept | bind (settings defaults) | `fledge audio output switch` |  |
| `slievr-battery-capacity` | kept | `slievr-battery-status` | `fledge battery capacity` |  |
| `slievr-battery-present` | kept | `slievr-powerprofiles-init` | `fledge battery present` |  |
| `slievr-battery-remaining-time` | kept | `slievr-battery-status` | `fledge battery remaining time` |  |
| `slievr-battery-status` | kept | bind (settings defaults) | `fledge battery status` | Used inside `$(…)` in a bind. |
| `slievr-branding-about` | kept | menu: Style › About | `fledge branding about` | `reset` calls `$OMARCHY_PATH/icon.txt` (unset on fledge): broken branch. |
| `slievr-branding-screensaver` | kept | menu: Style › Screensaver | `fledge branding screensaver` |  |
| `slievr-brightness-keyboard` | kept | bind (settings defaults) | `fledge brightness keyboard` |  |
| `slievr-brightness-keyboard-mute` | kept | shell QML | `fledge brightness keyboard mute` | Ipc.qml calls it via `sh -c "command -v … && …"`. |
| `slievr-capture-screenrecording` | kept | menu: Capture › Screenrecord | `fledge capture screenrecording` | Signals waybar (harmless no-op). |
| `slievr-capture-screenshot` | kept | bind (settings defaults); menu: Capture | `fledge capture screenshot` | Bind calls it through the router: `slievr capture screenshot region copy`. |
| `slievr-capture-text-extraction` | kept | bind (settings defaults); menu: Capture | `fledge capture text extraction` |  |
| `slievr-cmd-missing` | kept | `slievr-toggle-hybrid-gpu`; `slievr-transcode-ascii` | `fledge cmd missing` |  |
| `slievr-cmd-present` | kept | menu: Hardware, Setup › Defaults (option probes) | `fledge cmd present` |  |
| `slievr-cmd-terminal-cwd` | kept | bind (settings defaults) | `fledge cmd terminal cwd` | Used inside `$(…)` in two terminal binds. |
| `slievr-config-direct-boot` | kept | menu: Toggle › Direct Boot | `fledge config direct boot` |  |
| `slievr-default-browser` | kept | menu: Setup › Defaults | `fledge default browser` |  |
| `slievr-default-editor` | kept | menu: Setup › Defaults | `fledge default editor` |  |
| `slievr-default-terminal` | kept | menu: Setup › Defaults | `fledge default terminal` |  |
| `slievr-first-run` | kept | Hyprland Lua autostart | `fledge first run` | Inert: runs only if `~/.local/state/omarchy/first-run.mode` exists, which nothing creates; the body calls `$OMARCHY_PATH/install/...` (not vendored). Kept because autostart calls it; candidate to drop with its autostart line. |
| `slievr-font-current` | kept | menu: Style › Font | `fledge font current` | Reads `~/.config/waybar/style.css` (waybar is gone): returns nothing. |
| `slievr-font-list` | kept | menu: Style › Font | `fledge font list` |  |
| `slievr-font-set` | kept | menu: Style › Font | `fledge font set` |  |
| `slievr-hibernation-available` | kept | menu: System, Setup › System Sleep | `fledge hibernation available` |  |
| `slievr-hibernation-remove` | kept | menu: Setup › System Sleep | `fledge hibernation remove` |  |
| `slievr-hibernation-setup` | kept | menu: Setup › System Sleep | `fledge hibernation setup` | Copies from `$OMARCHY_PATH/default/systemd/...` (broken step). |
| `slievr-hook` | kept | Hyprland Lua autostart | `fledge hook` | Runs `~/.config/omarchy/hooks/<name>` (+ `.d/`). Called with `post-boot` (autostart) and `font-set` (font-set). |
| `slievr-hook-install` | kept | `slievr-first-run` | `fledge hook install` | Only reached from the inert branch of first-run. |
| `slievr-hw-dell-xps-haptic-touchpad` | kept | menu: Hardware (probe) | `fledge hw dell xps haptic touchpad` |  |
| `slievr-hw-display-gpu` | kept | uwsm env-hyprland, ~/.config/omarchy/scripts/nvidia-power.sh (autostart) | `fledge hw display gpu` | Called by absolute path `~/.local/share/slievr-cachy/bin/slievr-hw-display-gpu`, not via PATH. |
| `slievr-hw-external-monitors` | kept | bind (settings defaults) | `fledge hw external monitors` | Bind: `slievr-hw-external-monitors && slievr-hyprland-monitor-internal off`. |
| `slievr-hw-hybrid-gpu` | kept | menu: Hardware (probe) | `fledge hw hybrid gpu` |  |
| `slievr-hw-match` | kept | `slievr-hw-dell-xps-haptic-touchpad` | `fledge hw match` |  |
| `slievr-hw-touchpad` | kept | menu: Hardware (probe) | `fledge hw touchpad` |  |
| `slievr-hw-touchscreen` | kept | menu: Hardware (probe) | `fledge hw touchscreen` |  |
| `slievr-hyprland-monitor-focused` | kept | `slievr-launch-screensaver` | `fledge hyprland monitor focused` |  |
| `slievr-hyprland-monitor-internal` | kept | bind (settings defaults); menu: Hardware | `fledge hyprland monitor internal` |  |
| `slievr-hyprland-monitor-internal-mirror` | kept | bind (settings defaults); menu: Hardware | `fledge hyprland monitor internal mirror` |  |
| `slievr-hyprland-monitor-scaling-cycle` | kept | bind (settings defaults); menu: Toggle | `fledge hyprland monitor scaling cycle` |  |
| `slievr-hyprland-monitor-watch` | kept | Hyprland Lua autostart | `fledge hyprland monitor watch` |  |
| `slievr-hyprland-toggle` | kept | `slievr-hyprland-monitor-internal`; `slievr-hyprland-monitor-internal-mirror`; `slievr-hyprland-window-gaps-toggle`; `slievr-hyprland-window-single-square-aspect-toggle` | `fledge hyprland toggle` | Copies `~/.config/hypr/fledge/toggles/<flag>.lua` into `~/.local/state/hypr-toggles/`. |
| `slievr-hyprland-toggle-disabled` | kept | `slievr-hyprland-monitor-internal`; `slievr-hyprland-monitor-internal-mirror` | `fledge hyprland toggle disabled` |  |
| `slievr-hyprland-toggle-enabled` | kept | `slievr-hyprland-monitor-internal`; `slievr-hyprland-monitor-internal-mirror` | `fledge hyprland toggle enabled` |  |
| `slievr-hyprland-window-close-all` | kept | bind (settings defaults) | `fledge hyprland window close all` |  |
| `slievr-hyprland-window-gaps-toggle` | kept | bind (settings defaults); menu: Toggle | `fledge hyprland window gaps toggle` |  |
| `slievr-hyprland-window-pop` | kept | bind (settings defaults) | `fledge hyprland window pop` |  |
| `slievr-hyprland-window-single-square-aspect-toggle` | kept | bind (settings defaults); menu: Toggle | `fledge hyprland window single square aspect toggle` |  |
| `slievr-hyprland-window-transparency-toggle` | kept | bind (settings defaults) | `fledge hyprland window transparency toggle` |  |
| `slievr-hyprland-workspace-layout-toggle` | kept | bind (settings defaults); menu: Toggle | `fledge hyprland workspace layout toggle` |  |
| `slievr-launch-about` | kept | `slievr-branding-about` | `fledge launch about` |  |
| `slievr-launch-browser` | kept | bind (settings defaults) | `fledge launch browser` |  |
| `slievr-launch-editor` | kept | bind (settings defaults); menu: Setup › Config (open_in_editor) | `fledge launch editor` |  |
| `slievr-launch-floating-terminal-with-presentation` | kept | menu: present_terminal helper | `fledge launch floating terminal with presentation` |  |
| `slievr-launch-or-focus` | kept | bind (settings defaults) | `fledge launch or focus` | Bind args: `thunar thunar`, `obsidian "uwsm-app -- obsidian"`. |
| `slievr-launch-or-focus-tui` | kept | bind (settings defaults) | `fledge launch or focus tui` |  |
| `slievr-launch-screensaver` | kept | menu: System › Screensaver | `fledge launch screensaver` | Uses `$OMARCHY_PATH/default/foot/screensaver.ini` for foot (broken branch). |
| `slievr-launch-tui` | kept | bind (settings defaults) | `fledge launch tui` |  |
| `slievr-launch-walker` | kept | menu: menu() picker for every submenu | mechanical `fledge launch walker`; misleading (walker is gone) — suggest its callers use `fledge dmenu` if `mbm dmenu` becomes a fledge built-in | Shim: walker is gone; `--dmenu` → `mbm dmenu`, `-m menus:*` → "not available" notice. |
| `slievr-menu` | kept | bind (settings defaults); shell QML | `fledge menu` | Entry args used: capture, toggle, hardware, share, setup, background, theme, reminder-set. The main menu is reached too: Setup›(cancel) falls through to `show_main_menu`. |
| `slievr-menu-file` | kept | `slievr-transcode`; `slievr-branding-about`; `slievr-branding-screensaver` | `fledge menu file` |  |
| `slievr-menu-input` | kept | menu: Trigger › Reminder › Set one | `fledge menu input` |  |
| `slievr-menu-select` | kept | `slievr-transcode` | `fledge menu select` |  |
| `slievr-menu-share` | kept | menu: Share | **suggest `fledge share`** (libexec `share`; also its own `slievr:group=share name=` metadata) | **Collision:** `fledge menu share` (bind + QML "Share…") would resolve to libexec `menu-share`, not `menu share`. Rename needed. |
| `slievr-notification-send` | kept | menu: reminder input error | `fledge notification send` |  |
| `slievr-pkg-add` | kept | `slievr-toggle-hybrid-gpu`; `slievr-setup-security-fingerprint`; `slievr-setup-security-fido2` | `fledge pkg add` |  |
| `slievr-pkg-missing` | kept | `slievr-pkg-add` | `fledge pkg missing` |  |
| `slievr-pkg-present` | kept | `slievr-setup-security-fingerprint` | `fledge pkg present` |  |
| `slievr-powerprofiles-init` | kept | Hyprland Lua autostart | `fledge powerprofiles init` |  |
| `slievr-powerprofiles-list` | kept | menu: Setup › Power Profile | `fledge powerprofiles list` |  |
| `slievr-powerprofiles-set` | kept | `slievr-powerprofiles-init` | `fledge powerprofiles set` |  |
| `slievr-reminder` | kept | bind (settings defaults); menu: Trigger › Reminder | `fledge reminder` |  |
| `slievr-restart-app` | kept | `slievr-restart-hyprsunset`; `slievr-restart-xcompose` | `fledge restart app` |  |
| `slievr-restart-hyprsunset` | kept | menu: Setup › Config › Hyprsunset | `fledge restart hyprsunset` |  |
| `slievr-restart-xcompose` | kept | menu: Setup › Config › XCompose | `fledge restart xcompose` |  |
| `slievr-screensaver` | kept | `slievr-launch-screensaver` | `fledge screensaver` |  |
| `slievr-setup-dns` | kept | menu: Setup › DNS | `fledge setup dns` |  |
| `slievr-setup-security-fido2` | kept | menu: Setup › Security | `fledge setup security fido2` |  |
| `slievr-setup-security-fingerprint` | kept | menu: Setup › Security | `fledge setup security fingerprint` |  |
| `slievr-show-done` | kept | `slievr-launch-floating-terminal-with-presentation` | `fledge show done` |  |
| `slievr-show-logo` | kept | `slievr-launch-floating-terminal-with-presentation` | `fledge show logo` |  |
| `slievr-state` | kept | `slievr-system-reboot`; `slievr-system-shutdown` | `fledge state` | Reached via system-reboot/shutdown. |
| `slievr-sudo-passwordless` | kept | menu: Toggle › Passwordless Sudo | `fledge sudo passwordless` |  |
| `slievr-swayosd-client` | kept | `slievr-audio-output-switch`; `slievr-toggle-touchpad`; `slievr-toggle-touchscreen` | **suggest `fledge osd`** (swayosd is gone; or point its 3 callers at `qs -c fledge ipc call osd popup` and drop it) | Shim: swayosd is gone; forwards to the shell OSD over IPC. |
| `slievr-system-lock` | kept | menu: System | `fledge system lock` |  |
| `slievr-system-logout` | kept | menu: System | `fledge system logout` |  |
| `slievr-system-reboot` | kept | menu: System | `fledge system reboot` |  |
| `slievr-system-shutdown` | kept | menu: System | `fledge system shutdown` |  |
| `slievr-theme-set-templates` | kept | cachyos/branding/test-theme.sh | `fledge theme set templates` | Only a test (test-theme.sh) runs it; theme-set (its menu caller) is unreachable. Kept: project C territory. |
| `slievr-toggle` | kept | `slievr-toggle-screensaver`; `slievr-toggle-suspend` | `fledge toggle` |  |
| `slievr-toggle-enabled` | kept | menu: System, Setup › System Sleep | `fledge toggle enabled` |  |
| `slievr-toggle-hybrid-gpu` | kept | menu: Hardware | `fledge toggle hybrid gpu` | Copies from `$OMARCHY_PATH/default/...` (broken step). |
| `slievr-toggle-idle` | kept | menu: Toggle | `fledge toggle idle` |  |
| `slievr-toggle-nightlight` | kept | bind (settings defaults); shell QML; menu: Toggle | `fledge toggle nightlight` |  |
| `slievr-toggle-notification-silencing` | kept | menu: Toggle | `fledge toggle notification silencing` |  |
| `slievr-toggle-screensaver` | kept | menu: Toggle | `fledge toggle screensaver` |  |
| `slievr-toggle-suspend` | kept | menu: Setup › System Sleep | `fledge toggle suspend` |  |
| `slievr-toggle-touchpad` | kept | bind (settings defaults); menu: Hardware | `fledge toggle touchpad` |  |
| `slievr-toggle-touchscreen` | kept | menu: Hardware | `fledge toggle touchscreen` |  |
| `slievr-toggle-waybar` | kept | menu: Toggle › Top Bar | **suggest `fledge toggle bar`** (waybar is gone) | Shim: toggles the mbm bar (waybar is gone). |
| `slievr-transcode` | kept | bind (settings defaults); menu: Trigger › Transcode | `fledge transcode` |  |
| `slievr-transcode-ascii` | kept | `slievr-branding-about`; `slievr-branding-screensaver` | `fledge transcode ascii` |  |
| `slievr-weather-icon` | kept | `slievr-weather-status` | `fledge weather icon` |  |
| `slievr-weather-status` | kept | bind (settings defaults) | `fledge weather status` | Used inside `$(…)` in a bind. |

## Dropped (165), grouped

Every drop is either unreachable from the roots above or reachable only through another dropped script or one of the menu's unopened submenus, except the webapps, which go whatever reaches them.

### Webapps (AGENTS.md rule 3: dropped regardless of reachability) — 7

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-launch-or-focus-webapp` | dropped | bind (`apps.youtube`) | **Bound:** `apps.youtube` (Super+Shift+Y) in settings defaults → remove the bind. |
| `slievr-launch-webapp` | dropped | bind via `dot-local/bin/yt-music`; `slievr-menu` (a submenu nothing opens); dropped: `slievr-install-gaming-xbox-cloud`, `slievr-launch-or-focus-webapp`, `slievr-webapp-handler-hey`, `slievr-webapp-handler-zoom`, `slievr-webapp-remove`, `slievr-webapp-remove-all` | **Bound indirectly:** `apps.youtube-music` (Super+Shift+M) runs `~/.local/bin/yt-music` (`dot-local/bin/yt-music`), which calls this → remove the bind and yt-music. Also the menu's Learn submenu (unreachable). |
| `slievr-webapp-handler-hey` | dropped | unreachable | Open HEY webmail and translate mailto links |
| `slievr-webapp-handler-zoom` | dropped | unreachable | Open Zoom web meetings from browser protocol links |
| `slievr-webapp-install` | dropped | `slievr-menu` (a submenu nothing opens); dropped: `slievr-install-gaming-xbox-cloud`, `slievr-install-tailscale` | Also called by install-tailscale and install-gaming-xbox-cloud (both dropped). |
| `slievr-webapp-remove` | dropped | `slievr-menu` (a submenu nothing opens); dropped: `slievr-remove-gaming-xbox-cloud` | Remove web app desktop launchers |
| `slievr-webapp-remove-all` | dropped | dropped: `slievr-remove-preinstalls` | Remove all web apps installed via slievr-webapp-install. |

### Optional-software installers (Omarchy's Install menu; only `slievr-menu install` opens it, and nothing does) — 30

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-install-browser` | dropped | `slievr-menu` (a submenu nothing opens) | Install a supported browser |
| `slievr-install-chromium-google-account` | dropped | `slievr-menu` (a submenu nothing opens); dropped: `slievr-refresh-chromium` | Allow Chromium to sign in to Google accounts by adding the required OAuth credentials |
| `slievr-install-dev-env` | dropped | `slievr-menu` (a submenu nothing opens) | Install a supported development environment |
| `slievr-install-docker-dbs` | dropped | `slievr-menu` (a submenu nothing opens) | Install one of the supported databases in a Docker container with the suitable development options. |
| `slievr-install-dropbox` | dropped | `slievr-menu` (a submenu nothing opens) | Install and start the Dropbox service. Must then be authenticated via the web. |
| `slievr-install-gaming-geforce-now` | dropped | `slievr-menu` (a submenu nothing opens) | Install and launch Geforce Now. |
| `slievr-install-gaming-gpu-lib32` | dropped | dropped: `slievr-install-gaming-heroic`, `slievr-install-gaming-lutris`, `slievr-install-gaming-steam` | Install lib32 graphics drivers (Vulkan + NVIDIA) for any detected GPUs. |
| `slievr-install-gaming-heroic` | dropped | `slievr-menu` (a submenu nothing opens) | Install Heroic Games Launcher (Epic, GOG, Amazon Prime Gaming) with graphics drivers. |
| `slievr-install-gaming-lutris` | dropped | `slievr-menu` (a submenu nothing opens) | Install Lutris with Wine + DXVK for running Windows games (Battle.net, EA, Ubisoft Connect, etc.) |
| `slievr-install-gaming-moonlight` | dropped | `slievr-menu` (a submenu nothing opens) | Install Moonlight (NVIDIA GameStream / Sunshine client) for streaming games to this PC. |
| `slievr-install-gaming-retroarch` | dropped | `slievr-menu` (a submenu nothing opens) | Install RetroArch with the full libretro core set plus FBNeo and a ~/Games ROM directory. |
| `slievr-install-gaming-steam` | dropped | `slievr-menu` (a submenu nothing opens) | Install Steam and graphics drivers selected for this system |
| `slievr-install-gaming-xbox-cloud` | dropped | `slievr-menu` (a submenu nothing opens) | Install Xbox Cloud Gaming as a web app and launch it. |
| `slievr-install-gaming-xbox-controllers` | dropped | `slievr-menu` (a submenu nothing opens) | Install support for using Xbox controllers with Steam/RetroArch/etc. |
| `slievr-install-helix` | dropped | `slievr-menu` (a submenu nothing opens) | Install Helix and configure it to use the current Omarchy theme |
| `slievr-install-nordvpn` | dropped | `slievr-menu` (a submenu nothing opens) | Install the NordVPN service with optional GUI. |
| `slievr-install-once` | dropped | `slievr-menu` (a submenu nothing opens) | Install the ONCE service, enable its background service, and launch the TUI. |
| `slievr-install-tailscale` | dropped | `slievr-menu` (a submenu nothing opens) | Install the Tailscale mesh VPN service and a web app for the Tailscale Admin Console. |
| `slievr-install-terminal` | dropped | `slievr-menu` (a submenu nothing opens) | Install one of the approved terminals and set it as the default for Omarchy (Super + Return etc). |
| `slievr-install-vscode` | dropped | `slievr-menu` (a submenu nothing opens) | Install VS Code and configure Omarchy defaults for secrets, updates, and theme |
| `slievr-install-zed` | dropped | `slievr-menu` (a submenu nothing opens) | Install Zed Editor and configure it with the current Omarchy theme |
| `slievr-pkg-aur-add` | dropped | `slievr-menu` (a submenu nothing opens); dropped: `slievr-install-browser`, `slievr-install-nordvpn` | Only the Install menu helpers and dropped installers call it. |
| `slievr-pkg-aur-install` | dropped | `slievr-menu` (a submenu nothing opens) | Show a fuzzy-finder TUI for picking new AUR packages to install. |
| `slievr-pkg-install` | dropped | `slievr-menu` (a submenu nothing opens) | Show a fuzzy-finder TUI for picking new Arch and OPR packages to install. |
| `slievr-sudo-keepalive` | dropped | dropped: `slievr-pkg-aur-install`, `slievr-pkg-install` | Only pkg-install/pkg-aur-install call it. |
| `slievr-theme-bg-install` | dropped | `slievr-menu` (a submenu nothing opens) | Open the current theme's user background folder |
| `slievr-theme-install` | dropped | `slievr-menu` (a submenu nothing opens) | Install a theme from a git repository |
| `slievr-tui-install` | dropped | `slievr-menu` (a submenu nothing opens) | Create a desktop launcher for a terminal UI app |
| `slievr-voxtype-install` | dropped | `slievr-menu` (a submenu nothing opens) | Install › AI › Dictation. |
| `slievr-windows-vm` | dropped | `slievr-menu` (a submenu nothing opens) | Install/Remove › Windows. |

### Removers (Omarchy's Remove menu; only `slievr-menu remove` opens it, and nothing does) — 20

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-pkg-drop` | dropped | dropped: `slievr-remove-browser`, `slievr-remove-gaming-heroic`, `slievr-remove-gaming-lutris`, `slievr-remove-gaming-minecraft`, `slievr-remove-gaming-moonlight`, `slievr-remove-gaming-retroarch`, `slievr-remove-gaming-steam`, `slievr-remove-gaming-xbox-controllers`, `slievr-remove-preinstalls`, `slievr-remove-security-fido2`, `slievr-remove-security-fingerprint`, `slievr-voxtype-remove` | Only removers call it. |
| `slievr-pkg-remove` | dropped | `slievr-menu` (a submenu nothing opens) | Show a fuzzy-finder TUI for picking packages installed on the system to be removed. |
| `slievr-remove-browser` | dropped | `slievr-menu` (a submenu nothing opens) | Remove a supported browser and clean up Omarchy browser defaults |
| `slievr-remove-dev-env` | dropped | `slievr-menu` (a submenu nothing opens) | Remove a development environment that was previously installed via slievr-install-dev-env. |
| `slievr-remove-gaming-geforce-now` | dropped | `slievr-menu` (a submenu nothing opens) | Remove the GeForce NOW Flatpak app and its data. |
| `slievr-remove-gaming-heroic` | dropped | `slievr-menu` (a submenu nothing opens) | Remove Heroic Games Launcher and its game libraries, configs, and caches. |
| `slievr-remove-gaming-lutris` | dropped | `slievr-menu` (a submenu nothing opens) | Remove Lutris, Wine, umu-launcher, and all their configs and caches. |
| `slievr-remove-gaming-minecraft` | dropped | `slievr-menu` (a submenu nothing opens) | Remove the Minecraft launcher along with its worlds, mods, and caches. |
| `slievr-remove-gaming-moonlight` | dropped | `slievr-menu` (a submenu nothing opens) | Remove Moonlight and its configs and caches. |
| `slievr-remove-gaming-retroarch` | dropped | `slievr-menu` (a submenu nothing opens) | Remove RetroArch, all libretro cores, and its config/saves. Leaves ~/Games/roms and ~/Games/bios alone. |
| `slievr-remove-gaming-steam` | dropped | `slievr-menu` (a submenu nothing opens) | Remove Steam and all of its game libraries, configs, and caches. |
| `slievr-remove-gaming-xbox-cloud` | dropped | `slievr-menu` (a submenu nothing opens) | Remove the Xbox Cloud Gaming web app. |
| `slievr-remove-gaming-xbox-controllers` | dropped | `slievr-menu` (a submenu nothing opens) | Remove the xpadneo Xbox controller driver and undo its module/blacklist config. |
| `slievr-remove-preinstalls` | dropped | `slievr-menu` (a submenu nothing opens) | Remove preinstalled Omarchy applications (web apps, TUIs, and selected packages). |
| `slievr-remove-security-fido2` | dropped | `slievr-menu` (a submenu nothing opens) | Remove FIDO2 authentication from sudo and polkit |
| `slievr-remove-security-fingerprint` | dropped | `slievr-menu` (a submenu nothing opens) | Remove fingerprint authentication from sudo, polkit, and lock screen |
| `slievr-theme-remove` | dropped | `slievr-menu` (a submenu nothing opens) | Remove a user-installed theme |
| `slievr-tui-remove` | dropped | `slievr-menu` (a submenu nothing opens) | Remove terminal UI desktop launchers |
| `slievr-tui-remove-all` | dropped | dropped: `slievr-remove-preinstalls` | Remove all TUIs installed via slievr-tui-install. |
| `slievr-voxtype-remove` | dropped | `slievr-menu` (a submenu nothing opens) | Remove Voxtype dictation and its configuration |

### Update menu and Omarchy self-management: update/channel/branch/reinstall/migrate/refresh-*/version/logs (most need an Omarchy git checkout at `$OMARCHY_PATH`), plus the Update menu's restart-audio/wifi/bluetooth/trackpad, firmware, timezone, time and drive-password items (only `slievr-menu update` opens that menu, and nothing does) — 50

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-branch-set` | dropped | dropped: `slievr-channel-set` | Set the branch for Omarchy's git repository. |
| `slievr-channel-set` | dropped | `slievr-menu` (a submenu nothing opens) | Set the Omarchy channel, which dictates what git branch and package repository is used. |
| `slievr-debug` | dropped | unreachable | Router help text mentions `slievr debug`; no caller. |
| `slievr-drive-info` | dropped | dropped: `slievr-drive-select` | Print drive information such as size, model, and mount details |
| `slievr-drive-password` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Password › Drive Encryption. Works without Omarchy; unreachable. |
| `slievr-drive-select` | dropped | dropped: `slievr-drive-password` | Select a drive from a list with info that includes space and brand. Used by slievr-drive-password. |
| `slievr-migrate` | dropped | dropped: `slievr-update-perform` | Run all pending migrations to bring the system in line with the installed version. |
| `slievr-pkg-aur-accessible` | dropped | dropped: `slievr-update-aur-pkgs` | Returns true if the AUR is up and available. |
| `slievr-refresh-applications` | dropped | unreachable | Ensure all default .desktop, web apps, TUIs, and npx wrappers are installed. |
| `slievr-refresh-chromium` | dropped | unreachable | Refresh the ~/.config/chromium-flags.conf file from the Omarchy defaults. |
| `slievr-refresh-config` | dropped | dropped: `slievr-refresh-chromium`, `slievr-refresh-fastfetch`, `slievr-refresh-hyprsunset`, `slievr-refresh-tmux` | Copies the named config from ~/.local/share/omarchy/config/X/Y/Z -> ~/.config/X/Y/Z. |
| `slievr-refresh-fastfetch` | dropped | unreachable | Overwrite the user config for fastfetch with the Omarchy default. |
| `slievr-refresh-hyprland` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Process › Hyprland. |
| `slievr-refresh-hyprsunset` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Config. Copies from `$OMARCHY_PATH/config`. |
| `slievr-refresh-limine` | dropped | dropped: `slievr-reinstall-configs` | Overwrite the user config for the Limine bootloader and rebuild it. |
| `slievr-refresh-pacman` | dropped | dropped: `slievr-channel-set`, `slievr-reinstall-pkgs` | Overwrite the package configuration for /etc/pacman with the Omarchy default of using its dedicated mirrors and repositories, then update all packages. |
| `slievr-refresh-plymouth` | dropped | `slievr-menu` (a submenu nothing opens); dropped: `slievr-reinstall-configs` | Update › Config. |
| `slievr-refresh-sddm` | dropped | dropped: `slievr-plymouth-reset` | Refresh the SDDM theme from default |
| `slievr-refresh-tmux` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Config. Copies from `$OMARCHY_PATH/config`. |
| `slievr-reinstall` | dropped | unreachable | Reinstall Omarchy packages and reset default configs |
| `slievr-reinstall-configs` | dropped | dropped: `slievr-reinstall` | Reset all Omarchy user configs to the defaults |
| `slievr-reinstall-git` | dropped | dropped: `slievr-reinstall` | Reinstall the Omarchy source directory from git |
| `slievr-reinstall-pkgs` | dropped | dropped: `slievr-reinstall` | Reinstall all default Omarchy packages from the stable channel |
| `slievr-restart-bluetooth` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Hardware › Bluetooth. Self-contained; same as above. |
| `slievr-restart-pipewire` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Hardware › Audio. Self-contained and works; drop because no menu path reaches it. |
| `slievr-restart-trackpad` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Hardware › Trackpad. Self-contained; same as above. |
| `slievr-restart-wifi` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Hardware › Wi-Fi. Self-contained; same as above. |
| `slievr-snapshot` | dropped | dropped: `slievr-update`, `slievr-update-branch` | Create or restore system snapshots with snapper |
| `slievr-tz-select` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Timezone. Works without Omarchy; unreachable. |
| `slievr-update` | dropped | `slievr-menu` (a submenu nothing opens); dropped: `slievr-channel-set`, `slievr-pkg-aur-accessible`, `slievr-snapshot`, `slievr-update-analyze-logs` | Router help text mentions `slievr update`; Update menu (unreachable). |
| `slievr-update-analyze-logs` | dropped | dropped: `slievr-update-perform` | Check the update log for known failure conditions |
| `slievr-update-aur-pkgs` | dropped | dropped: `slievr-update-perform` | Update AUR packages if any are installed |
| `slievr-update-available` | dropped | unreachable | Get remote tag |
| `slievr-update-available-reset` | dropped | dropped: `slievr-update-perform` | Ensure Waybar icon offering the available update is removed |
| `slievr-update-branch` | dropped | unreachable | Switch Omarchy branches and update from the selected branch |
| `slievr-update-confirm` | dropped | dropped: `slievr-update` | Prompt for confirmation before starting an update |
| `slievr-update-firmware` | dropped | `slievr-menu` (a submenu nothing opens) | Update › Firmware (fwupd). Works without Omarchy; unreachable. |
| `slievr-update-git` | dropped | dropped: `slievr-update` | Pull the latest Omarchy git changes |
| `slievr-update-keyring` | dropped | dropped: `slievr-update-perform` | Ensure the Omarchy and Arch keyring packages are installed and populated |
| `slievr-update-orphan-pkgs` | dropped | dropped: `slievr-update-perform` | Remove orphaned system packages after updates |
| `slievr-update-perform` | dropped | dropped: `slievr-update`, `slievr-update-branch` | Run the full Omarchy update pipeline |
| `slievr-update-restart` | dropped | dropped: `slievr-update-perform` | Prompt for required reboot or service restarts after updates |
| `slievr-update-system-pkgs` | dropped | dropped: `slievr-update-perform` | Update system packages with pacman |
| `slievr-update-time` | dropped | `slievr-menu` (a submenu nothing opens); dropped: `slievr-update-git` | Update › Time. Works without Omarchy; unreachable. |
| `slievr-update-without-idle` | dropped | unreachable | Documented no-op. |
| `slievr-upload-log` | dropped | unreachable | Upload logs to logs.omarchy.org |
| `slievr-version` | dropped | dropped: `slievr-snapshot` | Print the installed Omarchy version |
| `slievr-version-branch` | dropped | unreachable | Print the current Omarchy git branch |
| `slievr-version-channel` | dropped | unreachable | Print the active Omarchy mirror and package channel |
| `slievr-version-pkgs` | dropped | unreachable | Print when system packages were last upgraded |

### Theme switching and per-app theme pushers (`slievr-theme-set` chain; one theme ships, the theme/background pickers already say "not available"; project C replaces this) — 26

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-plymouth-preview` | dropped | unreachable | Preview a Plymouth boot screen with custom colors and logo |
| `slievr-plymouth-reset` | dropped | unreachable | Restore the default Omarchy Plymouth boot theme and SDDM login screen |
| `slievr-plymouth-set` | dropped | dropped: `slievr-plymouth-set-by-theme` | Set the Plymouth boot theme colors and logo |
| `slievr-plymouth-set-by-theme` | dropped | unreachable | Set the Plymouth boot theme from an Omarchy theme |
| `slievr-restart-btop` | dropped | dropped: `slievr-theme-set` | Reload btop configuration (used by the Omarchy theme switching). |
| `slievr-restart-helix` | dropped | dropped: `slievr-theme-set` | Reload Helix configuration |
| `slievr-restart-hyprctl` | dropped | dropped: `slievr-theme-set` | Reload hyprland configuration (used by the Omarchy theme switching). |
| `slievr-restart-opencode` | dropped | dropped: `slievr-theme-set` | Reload opencode configuration (used by the Omarchy theme switching). |
| `slievr-restart-terminal` | dropped | dropped: `slievr-theme-set` | Reload supported terminal emulators after config changes |
| `slievr-restart-tmux` | dropped | dropped: `slievr-refresh-tmux` | Restart tmux if running with the latest configuration |
| `slievr-theme-bg-next` | dropped | dropped: `slievr-theme-set` | Cycle to the next background for the current theme |
| `slievr-theme-bg-set` | dropped | unreachable | Set the current background image |
| `slievr-theme-colors-from-alacritty` | dropped | dropped: `slievr-theme-set` | Generate a theme's colors.toml from its alacritty.toml palette |
| `slievr-theme-current` | dropped | unreachable | Show current theme |
| `slievr-theme-list` | dropped | unreachable | Router help text mentions `slievr theme list`; no caller. |
| `slievr-theme-refresh` | dropped | dropped: `slievr-install-helix` | Refresh the current theme from its templates. |
| `slievr-theme-set` | dropped | dropped: `slievr-theme-install`, `slievr-theme-refresh` | Mentioned in a comment in test-theme.sh (the test runs theme-set-templates directly). |
| `slievr-theme-set-browser` | dropped | dropped: `slievr-install-browser`, `slievr-theme-set` | Apply the current theme color to Chromium, Chrome, Edge, and Brave |
| `slievr-theme-set-foot` | dropped | dropped: `slievr-theme-set` | Apply current Omarchy theme colors to running Foot terminals |
| `slievr-theme-set-gnome` | dropped | dropped: `slievr-theme-set` | Apply the current theme to GNOME color mode and icon settings |
| `slievr-theme-set-keyboard` | dropped | dropped: `slievr-theme-set` | Apply the current theme keyboard color to supported keyboards |
| `slievr-theme-set-keyboard-asus-rog` | dropped | dropped: `slievr-theme-set-keyboard` | Apply the current theme keyboard color to ASUS ROG keyboards |
| `slievr-theme-set-keyboard-f16` | dropped | dropped: `slievr-theme-set-keyboard` | Apply the current theme keyboard color to Framework Laptop 16 keyboards |
| `slievr-theme-set-obsidian` | dropped | dropped: `slievr-theme-set` | Sync Omarchy theme to all Obsidian vaults |
| `slievr-theme-set-vscode` | dropped | dropped: `slievr-install-vscode`, `slievr-theme-set` | Sync Omarchy theme to VS Code, VSCodium, and Cursor |
| `slievr-theme-update` | dropped | `slievr-menu` (a submenu nothing opens) | Update user-installed git themes |

### Replaced by the mbm shell or retired tools (mic mute/brightness OSD, wiremix/bluetui/nmtui launchers, mako, battery timer, idle wake) — 11

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-audio-input-mute` | dropped | unreachable | Settings bind uses the shell (`osd.mic mute`). |
| `slievr-battery-monitor` | dropped | unreachable | Omarchy ran it from a systemd timer; no unit ships here. Would call the `battery-low` hook. |
| `slievr-battery-remaining` | dropped | dropped: `slievr-battery-monitor` | Returns the battery percentage remaining as an integer. |
| `slievr-brightness-display` | dropped | dropped: `slievr-system-wake` | Shell `osd.brightness` replaced it (Brightness.qml mentions it in a comment only). |
| `slievr-brightness-display-apple` | dropped | dropped: `slievr-brightness-display` | Adjust the brightness on Apple Studio Displays and Apple XDR Displays using asdcontrol. |
| `slievr-hyprland-monitor-focused-apple` | dropped | dropped: `slievr-brightness-display` | Return success if the focused Hyprland monitor is an Apple display. |
| `slievr-launch-audio` | dropped | unreachable | Launch the Omarchy audio controls TUI (provided by wiremix). |
| `slievr-launch-bluetooth` | dropped | unreachable | Launch the Omarchy bluetooth controls TUI (provided by bluetui). |
| `slievr-launch-wifi` | dropped | unreachable | Launch wifi controls (nmtui — NetworkManager's own TUI). |
| `slievr-notification-dismiss` | dropped | unreachable | Dismiss a mako notification on the basis of its summary. Used by the first-run notifications to dismiss them after clicking for action. |
| `slievr-system-wake` | dropped | unreachable | Omarchy's hypridle on-resume; hypridle is retired (shell idle). |

### Hardware probes and quirks only Omarchy's installer/menus used — 12

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-hw-asus-expertbook-b9406` | dropped | unreachable | Detect ASUS ExpertBook B9406 series laptops on Intel Panther Lake. |
| `slievr-hw-asus-rog` | dropped | unreachable | theme-set-keyboard-asus-rog is its only consumer in Omarchy; here nothing calls it. |
| `slievr-hw-asus-zenbook-ux5406aa` | dropped | unreachable | Detect ASUS Zenbook UX5406AA series laptops on Intel Panther Lake. |
| `slievr-hw-dell-xps-oled` | dropped | unreachable | Match Dell XPS systems with LG OLED panel on Intel Panther Lake (Xe3) GPU. |
| `slievr-hw-framework16` | dropped | unreachable | Detect whether the computer is a Framework Laptop 16. |
| `slievr-hw-intel` | dropped | unreachable | Detect whether the computer has an Intel CPU. |
| `slievr-hw-intel-ptl` | dropped | dropped: `slievr-hw-asus-expertbook-b9406`, `slievr-hw-asus-zenbook-ux5406aa`, `slievr-hw-dell-xps-oled` | Only other dropped hw probes call it. |
| `slievr-hw-nvidia-gsp` | dropped | dropped: `slievr-install-gaming-gpu-lib32` | Only install-gaming-gpu-lib32. |
| `slievr-hw-nvidia-without-gsp` | dropped | dropped: `slievr-install-gaming-gpu-lib32` | Only install-gaming-gpu-lib32. |
| `slievr-hw-recover-internal-monitor` | dropped | unreachable | Ran by Omarchy's first-run installer step (not vendored); hyprland-monitor-watch does recovery now. |
| `slievr-hw-surface` | dropped | unreachable | Detect whether the computer is a Microsoft Surface device. |
| `slievr-hw-vulkan` | dropped | dropped: `slievr-voxtype-install` | Only voxtype-install. |

### Omarchy development tooling — 3

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-dev-add-migration` | dropped | unreachable | Creates a new Omarchy migration named after the unix timestamp of the last commit. |
| `slievr-dev-benchmark` | dropped | unreachable | Measure Omarchy CLI response times |
| `slievr-dev-bin-metadata` | dropped | unreachable | Show Omarchy bin metadata fields and defaults |

### Other unreferenced utilities — 6

| script | status | reached from | notes |
|---|---|---|---|
| `slievr-npx-install` | dropped | unreachable | Only refresh-applications (dropped) uses it. |
| `slievr-sudo-reset` | dropped | unreachable | Reset the sudo lockout/faillock for the current user. |
| `slievr-voxtype-config` | dropped | unreachable | Open the Voxtype configuration file |
| `slievr-voxtype-model` | dropped | unreachable | Open Voxtype AI model setup |
| `slievr-voxtype-status` | dropped | unreachable | Waybar module helper. |
| `slievr-wifi-powersave` | dropped | unreachable | Omarchy ran it from a power-profile/udev hook; none ships. |

## Every webapp script (all dropped)

`slievr-launch-webapp`, `slievr-launch-or-focus-webapp`, `slievr-webapp-handler-hey`, `slievr-webapp-handler-zoom`, `slievr-webapp-install`, `slievr-webapp-remove`, `slievr-webapp-remove-all`.

Things that reach them and must go with them in Task 2:

- settings default bind `apps.youtube` (Super+Shift+Y): `slievr-launch-or-focus-webapp YouTube "https://youtube.com/"`.
- settings default bind `apps.youtube-music` (Super+Shift+M): `~/.local/bin/yt-music`, i.e. `dot-local/bin/yt-music`, which focuses an existing window or calls `slievr-launch-webapp`. Drop the bind and the file (or keep the file without its webapp branch, which isn't worth it).
- `slievr-menu`: Learn submenu (every entry is a webapp), Install › Web App, Remove › Web App (all already unreachable).
- dropped `slievr-install-tailscale` and `slievr-install-gaming-xbox-cloud` (create webapps); dropped `slievr-remove-gaming-xbox-cloud`, `slievr-remove-preinstalls`.
- `defaults-v1.json` (the migration fixture) keeps both strings: it's history and Task 3 leaves it byte-identical. (`test-migrate.sh` has no expectations on these two binds.)

## Dynamic call sites (names built or resolved at runtime)

None of the scripts builds another script's name from a variable (searched: `slievr-$…`, `slievr-${…}`, `"slievr-"` concatenation in bash/QML/JS/Lua, `$OMARCHY_PATH/bin`, `$OMARCHY_BIN_DIR/…`). What is resolved at runtime:

| call site | form | can resolve to |
|---|---|---|
| settings `capture.*` bind | router: `slievr capture screenshot region copy` | longest prefix → `slievr-capture-screenshot region copy`. After the rename: `fledge capture screenshot region copy` (natural fit). |
| `slievr` router (`load_commands`, `resolve_direct_route`, `group_has_*`) | globs `$OMARCHY_BIN_DIR/slievr-*`, builds `slievr-<w1>-…-<wn>` from argv; `# slievr:group/name/aliases` metadata adds routes (`omarchy screenshot`, `omarchy logout`, …) | any script. Replaced by `fledge`; the metadata routes and `slievr:` headers become dead (filename-only resolution). |
| binds, QML `SystemMode.qml` `app("slievr-menu <x>")`, `slievr-menu "$1"` → `go_to_menu` | menu key, substring-matched (`*share*`, `*reminder-set*` before `*reminder*`, …) | used: capture, toggle, hardware, share, setup, background, theme, reminder-set. Accepted but unused: learn, trigger, style, power, screenrecord, install, remove, update, about, system, apps. |
| `slievr-menu` `present_terminal "<cmd string>"`, `install*()`, `terminal bash -c "…"` | command strings run in a terminal | literal script names inside the strings (all listed in the tables). |
| `slievr-menu` sources `~/.config/omarchy/extensions/menu.sh` | user extension | nothing ships one. |
| `slievr-launch-walker -m menus:<x>` (Style › Theme/Background/Unlock) | mode name | `notify-send "… isn't available"`; `--dmenu` → `mbm dmenu`. |
| `slievr-hook <name>` | runs `~/.config/omarchy/hooks/<name>` and `<name>.d/*` | called with `post-boot` (autostart), `font-set` (font-set); dropped callers used `theme-set`, `battery-low`, `post-update`. Repo ships `hooks/post-update` (only update-perform ran it) and `*.sample`s. |
| `slievr-hyprland-toggle <flag>` | copies `~/.config/hypr/fledge/toggles/<flag>.lua` → `~/.local/state/hypr-toggles/` | `window-no-gaps` (gaps-toggle), `single-window-aspect-ratio` (square-aspect toggle); monitor-internal/-mirror write their own flag files and use `hyprland-toggle-enabled/-disabled`. |
| `slievr-toggle <name>`, `slievr-toggle-enabled <name>` | state files `~/.local/state/omarchy/toggles/<name>` | `screensaver-off`, `suspend-off` (kept); `skip-*-theme-changes` (theme-set-vscode, dropped). |
| `slievr-restart-app <app>` | `pkill -x` + relaunch | `hyprsunset`, `xcompose` helpers (kept). |
| `slievr-launch-or-focus`, `-or-focus-tui`, `launch-tui`, `launch-editor` | arbitrary app/command | thunar, obsidian, btop, cliamp, lazydocker, `$EDITOR`. |
| `slievr-hw-match <pattern>` | DMI match | from `hw-dell-xps-haptic-touchpad` (kept). |
| `Ipc.qml` | `sh -c 'command -v slievr-brightness-keyboard-mute && slievr-brightness-keyboard-mute "$1"'` | literal; the `command -v` guard must be renamed too. |
| `env-hyprland`, `nvidia-power.sh` | absolute path `~/.local/share/slievr-cachy/bin/slievr-hw-display-gpu` | that script; becomes a libexec path or `fledge hw display gpu`. |
| `slievr-launch-screensaver` | `exec_cmd <terminal> … -e slievr-screensaver` | `slievr-screensaver` (kept). |
| `slievr-theme-set-templates` | `TEMPLATES_DIR="${OMARCHY_PATH:-<bin>/..}/default/themed"` | relative to the script: moves with `default/` in Task 3. |
| `slievr-reminder`, `slievr-sudo-passwordless`, `slievr-capture-screenrecording` | non-script names: `slievr-reminder-${minutes}m-…` systemd-run units, `/etc/sudoers.d/99-slievr-nopasswd-$USER` + `slievr-nopasswd-expire-$USER` timer, `/tmp/slievr-screenrecord*` | not scripts, but `slievr` strings for Task 3's rename/grep. Also `SLIEVR_SYSFS_DRM` in hw-display-gpu. |

## Naming: one collision and a few misleading names

- **Collision (must fix):** under longest-prefix resolution, `fledge menu share` (the bind `utilities.share`, the QML "Share…" entry, and `slievr-menu share` today) would run libexec `menu-share` instead of `menu` with argument `share`. Rename `menu-share` → `share` (`fledge share clipboard|file|folder`, which its own `slievr:group=share` metadata already routes as `slievr share`). No other call site's first argument plus the script name makes another script (checked all `slievr-x <word>` strings in the repo).
- **Misleading (suggested, optional):** `swayosd-client` → `osd` (swayosd is gone; it forwards to the shell OSD), `toggle-waybar` → `toggle-bar` (waybar is gone), `launch-walker` (walker is gone; could become `fledge dmenu` for its `--dmenu` path if `mbm dmenu` turns into a fledge built-in).
- **Fine as mechanical:** long names (`fledge hyprland window single square aspect toggle`, `fledge launch or focus tui`, `fledge launch floating terminal with presentation`) and one-off groups (`ac present`, `first run`, `state`, `screensaver`, `show done|logo`, `config direct boot`). `fledge hyprland …` next to the built-in `fledge hypr …` reads slightly oddly but isn't wrong.

## Notes for later tasks

- Kept scripts that are already partly broken (kept anyway: reachable, and fixing them is project B): `first-run` (inert: nothing creates `first-run.mode`; `$OMARCHY_PATH` body), `branding-about reset`, `launch-screensaver` (foot branch), `hibernation-setup`, `toggle-hybrid-gpu` (copy from `$OMARCHY_PATH/default/…`), `font-current` (reads waybar's CSS, so the font menu has no preselect), `capture-screenrecording` (signals waybar; harmless).
- The dispatcher rule "words must match `^[a-z0-9][a-z0-9_.]*$` or exit 2" must apply only to the words it tries to match, not to arguments: binds and scripts pass `suspend-off`, `--reverse`, `--private`, URLs and quoted commands (`obsidian "uwsm-app -- obsidian"`). A non-word token should end the scan, not fail it.
- `mbm dmenu` (used by `launch-walker`, so by every menu) isn't in the plan's built-in list (`hypr`, `settings`, `help`); it needs a home when `mbm` is folded into `fledge`.
