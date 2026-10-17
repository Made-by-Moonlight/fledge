# fledge

*by made by moonlight*

A CachyOS + Hyprland desktop and the installer ISO that puts it on a machine:
boot the ISO, answer a few questions in its graphical installer, and
it installs unattended onto an encrypted btrfs disk, desktop included, then
reboots to the login screen.

The desktop is its own Quickshell shell (`fledge`): an attached bar with three
hanging tabs inside a rounded screen frame, a launcher (apps, clipboard,
emoji, system), notifications, OSD, lock screen, quick settings and a
settings window. Settings are one JSON file that generates the Hyprland
config. Hyprland runs a Lua config and doesn't reload on its own: after
hand-editing `~/.config/hypr`, run `hyprctl reload`. Pinning workspaces to
monitors is edited on the Displays page of the settings window. Wallpapers
live in `~/Pictures/Wallpapers` and are chosen (per monitor if you like) on
the Displays page. Audio is PipeWire (wireplumber, pipewire-pulse), and the
desktop ships an emoji font for the emoji picker.

![Desktop with btop and a terminal](docs/screenshots/06-desktop-apps.png)

## Install

Download the ISO and its `.sha256` from the
[latest release](https://github.com/Made-by-Moonlight/fledge/releases/latest),
check it, and write it to a USB stick (or copy it onto a Ventoy stick):

    sha256sum -c fledge-*.iso.sha256
    sudo dd if=fledge-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

Secure Boot must be off. The install needs an internet connection; the
installer can join Wi-Fi, and the network carries over to the installed system.

## Upgrade

An installed system keeps the repo in `~/proj/fledge`, stowed into `~`:

    git -C ~/proj/fledge pull && bash ~/proj/fledge/cachyos/bootstrap.sh

From a system still on Hyprland's old `.conf` config, log out and back in
straight after: the pull removes `~/.config/hypr/hyprland.conf` at once, the
running session falls back to Hyprland's stock config within seconds, and only
a new login starts the Lua config (bootstrap says so too). Or pull and run
bootstrap from a TTY (Ctrl+Alt+F2) and log in afterwards.

## Screenshots

| | |
|---|---|
| ![Installer welcome](docs/screenshots/01-installer.png) | ![Installer summary](docs/screenshots/02-installer-summary.png) |
| The installer | Everything asked up front, then unattended |
| ![Disk unlock](docs/screenshots/03-unlock.png) | ![Login](docs/screenshots/04-login.png) |
| Disk unlock (Plymouth) | Login (SDDM) |
| ![Desktop](docs/screenshots/05-desktop.png) | ![Launcher](docs/screenshots/07-launcher.png) |
| Desktop: bar tabs and screen frame | Launcher (apps, clipboard, emoji, system) |
| ![Lock screen](docs/screenshots/08-lock.png) | ![Quick settings](docs/screenshots/09-quick-settings.png) |
| Lock screen | Quick settings |
| ![Settings](docs/screenshots/10-settings.png) | |
| Settings (keybinds, displays, bar, idle, input) | |

## Repo layout

- `cachyos/iso/` — the installer ISO and its graphical installer (build, test, release)
- `cachyos/install/` — the installer itself and first-boot setup
- `cachyos/bootstrap.sh` — the desktop layer, run by the installer (or on first boot if that failed)
- `cachyos/branding/` — owl, palette and theme assets
- `dot-config/quickshell/fledge/` — the desktop shell (bar, launcher, notifications, lock, settings)
- `dot-config/hypr/` — the Hyprland config: `hyprland.lua` and its `fledge/*.lua` modules
- `dot-local/share/fledge/` — the `fledge` command: `fledge <group> <action>` over the scripts in `libexec/`, `fledge settings` (defaults + overrides → generated Hyprland Lua), `fledge hypr`, `fledge dmenu`
- `dot-config/`, `dot-local/` — dotfiles, stowed into `~` (`.stow-local-ignore` keeps the rest of the repo out)

The repo is [Made-by-Moonlight/fledge](https://github.com/Made-by-Moonlight/fledge).
Releases are built by GitHub Actions when a `v*` tag is pushed on `main`
(see `cachyos/iso/README.md`).
