# Vendored Omarchy theme templates

From Omarchy 3.8.2 (`default/themed/`), MIT licensed (see `LICENSE`).
`cachyos/branding/render-theme.sh` fills them from a theme's `colors.toml`
the same way `fledge theme set templates` does, so a theme can be rendered
without an Omarchy install. Update by copying a newer Omarchy's
`default/themed/*.tpl` over these and re-running render-theme.sh.

`hyprland.lua.tpl` is fledge's own: the colours fledge's Lua Hyprland config
reads from the current theme. It replaces Omarchy's `hyprland.conf.tpl`, which
Hyprland can't read under a Lua config, so it isn't kept here; don't copy it back.
