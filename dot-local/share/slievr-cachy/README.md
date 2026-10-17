# Vendored & renamed Omarchy command scripts

`bin/` started as a vendored copy of `bin/` from
[basecamp/omarchy](https://github.com/basecamp/omarchy) (at the version
recorded in `VENDORED_VERSION`), MIT-licensed (see `LICENSE`), then had
every `omarchy-*` command renamed to `slievr-*` (and the `omarchy`
dispatcher to `slievr`) throughout this directory and every config that
calls them (then `dot-config/hypr/bindings.conf`, the vendored Hyprland
defaults, waybar, mako, walker, elephant; mbm settings and the Lua Hyprland
config replaced the Hyprland files, the mbm shell the last four). These are no longer updated from upstream
Omarchy — they're a permanent, independent fork under this project's own
naming, not a live sync.

The keybindings (`dot-local/share/mbm/defaults/settings.json`, generated into
Hyprland config by `mbm settings apply`) call several of these commands
(`slievr-launch-browser`, `slievr capture screenshot ...`, etc.). Rather
than installing the full Omarchy framework — which overrides the pacman
mirrorlist and makes broader system changes — only these self-contained
bash scripts are vendored here, giving the keybindings their expected
commands without installing Omarchy itself or touching CachyOS's repo
config.

Only the scripts something in the desktop reaches are kept (a bind, the
shell, Hyprland autostart, the menu's reachable submenus, or another kept
script). Omarchy's self-management commands (update, reinstall, migrate,
refresh, channels), its install/remove menus, theme switching and all web
app scripts were pruned: the inventory is in
`docs/superpowers/notes/2026-10-18-script-inventory.md`.
