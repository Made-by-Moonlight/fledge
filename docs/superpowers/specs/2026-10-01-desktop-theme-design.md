# made by moonlight desktop theme — design

**Date:** 2026-10-01
**Status:** implemented (see plan)
**Builds on:** `2026-10-01-custom-iso-design.md` (branch `custom-iso`)
**Mockups:** https://claude.ai/artifact/FvBp7ejtFWAdXRkffAYeBT

## Problem

The ISO run showed the installed system carries almost none of the brand: the
login screen is still the "SLIEVR" SDDM theme, the desktop is Omarchy's
"pandora" theme, and the lock screen is pandora's. The previous spec scoped
branding to the ISO, the boot splash and the about screen only.

The same VM run found defects to fix alongside:

1. `bootstrap.sh` stows into a fresh account before `~/.config` exists, so
   stow folds the whole directory: `~/.config` becomes a symlink into the repo
   and every app writes its settings into git.
2. `verify-install.sh` counts the `journalctl --list-boots` header as a boot.
3. The test VM has no TPM, so four TPM measurement units fail (real hardware
   has one).
4. Installer cosmetics: the welcome owl scrolls off the top of the 25-row
   console; the "Install made by moonlight on this machine?" prompt is nearly
   invisible.
5. `virt-install`'s first boot powers the VM off at the post-install reboot
   instead of restarting it.

## Decisions

| Topic | Decision |
| --- | --- |
| Approach | A real Omarchy theme `made-by-moonlight` with `colors.toml` as the source of truth, rendered into the committed `dot-config/omarchy/current/theme/` so fresh installs boot branded. |
| Templates | Omarchy 3.8.2's `default/themed/*.tpl` (17 files) vendored into `dot-local/share/slievr-cachy/default/themed/`; the render does not depend on an Omarchy install. |
| Wallpaper | **Moonrise**: small white owl (22% of width, 90% opacity) horizontally centred, top edge at 38% of the height under a faint radial glow (`#222c39` → `#171e28`) from the top. 3440×1440, 2560×1440, 1920×1080. |
| Focus | **Amber** (`accent`): focused window, launcher, notifications. |
| Login + lock | One layout: owl, "made by moonlight" wordmark (JetBrains Mono, letter-spaced, lowercase), amber password field; lock adds a clock. Background is a **glow-only** image (no owl) so the owl never appears twice. |
| Terminal | 16 colours as approved (table below). |
| Out of scope | Apps without an Omarchy template (neovim, VS Code, browsers, Discord, Steam, GTK/Qt): keep pandora's files, carried into the theme unchanged. `slievr-theme-set` on fresh installs (it still needs Omarchy's own directories). Renaming internal `slievr-cachy` theme directories. |

### `colors.toml`

```toml
accent = "#f4af03"
cursor = "#f4af03"
foreground = "#ffffff"
background = "#171e28"
selection_foreground = "#171e28"
selection_background = "#f4af03"

color0 = "#2f3640"
color1 = "#e5626a"
color2 = "#8fcf8a"
color3 = "#f4af03"
color4 = "#6fa8dc"
color5 = "#c38fd6"
color6 = "#5fc4c0"
color7 = "#c8ced8"
color8 = "#6c7787"
color9 = "#f08a90"
color10 = "#ade0a9"
color11 = "#ffc53d"
color12 = "#93c0ea"
color13 = "#d6aee4"
color14 = "#86d8d4"
color15 = "#ffffff"
```

## Components

- `dot-config/omarchy/themes/made-by-moonlight/`: `colors.toml`,
  `backgrounds/1-moonrise-3440x1440.png`, `2-moonrise-2560x1440.png`,
  `3-moonrise-1920x1080.png`, `glow.png` (1920×1080, no owl), `owl.png`
  (white, 520 px wide), `preview.png`, plus pandora's non-templated files
  copied unchanged.
- `cachyos/branding/build-assets.sh`: additionally generates the wallpapers,
  `glow.png`, `owl.png`, and the SDDM `logo.png` (owl, 260 px) +
  `background.png` (= glow). Welcome-screen owl for the ISO drops to 40 cols.
- `cachyos/branding/render-theme.sh [THEME_DIR] [OUT_DIR]`: clean `OUT_DIR`,
  copy the theme, render every vendored template whose output the theme
  doesn't already provide (same substitution rules as
  `slievr-theme-set-templates`: `{{ key }}`, `{{ key_strip }}`,
  `{{ key_rgb }}`). Defaults render into `dot-config/omarchy/current/theme/`.
- `dot-config/omarchy/current/`: re-rendered; `theme.name` =
  `made-by-moonlight`; `background` → the 3440×1440 Moonrise wallpaper.
- `dot-config/hypr/hyprlock.conf`: background = theme `glow.png` blurred;
  clock label; owl image; amber input field; theme colours via the rendered
  `hyprlock.conf`.
- `cachyos/sddm-theme/slievr-cachy/Main.qml`: `#171e28` + `background.png`,
  owl `logo.png`, wordmark, username, `#212a33` field with `#2f3640` border
  (`#e5626a` on failure) and amber dot bullets; login logic unchanged.
- Fixes 1–5 above, in `bootstrap.sh`, `verify-install.sh`,
  `provision-vm.sh` (`--tpm emulator`), `mbm-configurator`
  (`GUM_CONFIRM_PROMPT_FOREGROUND=7`), `build-iso.sh` (owl cols), and
  `slievr-iso-boot` (wait for power-off after install, then start the VM).

## Testing

- `test-theme.sh`: rendering into a temp dir leaves no `{{` anywhere; every
  rendered template contains a palette value (hex or rgb form); the committed
  `current/theme` equals a fresh render (no drift).
- `test-branding.sh`: wallpapers exist at the three sizes, `glow.png` and
  `owl.png` exist, SDDM assets match a fresh build.
- `verify-install.sh`: `~/.config` is a real directory; boot count fixed.
- ISO rebuild + VM run: Claude screenshots the unlock screen, SDDM, the
  desktop and the lock screen via `virsh screenshot` and compares them with
  the mockups; the user types passwords. `verify-install.sh` must pass
  (no TPM failures with the emulated TPM).
