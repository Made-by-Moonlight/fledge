# made by moonlight

A CachyOS + Hyprland desktop and the installer ISO that puts it on a machine:
boot the ISO, answer a few questions, and it installs unattended onto an
encrypted btrfs disk, then sets up the desktop on first boot.

![Desktop with btop and a terminal](docs/screenshots/06-desktop-apps.png)

## Install

Download the ISO and its `.sha256` from the
[latest release](https://github.com/slievr/slievr-cachy/releases/latest),
check it, and write it to a USB stick (or copy it onto a Ventoy stick):

    sha256sum -c made-by-moonlight-*.iso.sha256
    sudo dd if=made-by-moonlight-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

Secure Boot must be off. The install needs an internet connection; the
installer can join Wi-Fi, and the network carries over to the installed system.

## Screenshots

| | |
|---|---|
| ![Installer welcome](docs/screenshots/01-installer.png) | ![Installer summary](docs/screenshots/02-installer-summary.png) |
| The installer | Everything asked up front, then unattended |
| ![Disk unlock](docs/screenshots/03-unlock.png) | ![Login](docs/screenshots/04-login.png) |
| Disk unlock (Plymouth) | Login (SDDM) |
| ![Desktop](docs/screenshots/05-desktop.png) | ![Launcher](docs/screenshots/07-launcher.png) |
| Desktop | Launcher (Walker) |
| ![Lock screen](docs/screenshots/08-lock.png) | |
| Lock screen (hyprlock) | |

## Repo layout

- `cachyos/iso/` — the installer ISO (build, test, release)
- `cachyos/install/` — the installer itself and first-boot setup
- `cachyos/bootstrap.sh` — the desktop layer, run on first boot
- `cachyos/branding/` — owl, palette and theme assets
- `dot-config/`, `dot-local/` — dotfiles, stowed into `~`

Releases are built by GitHub Actions when a `v*` tag is pushed on `main`
(see `cachyos/iso/README.md`).
