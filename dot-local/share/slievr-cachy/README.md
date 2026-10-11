# Vendored & renamed Omarchy command scripts

`bin/` started as a vendored copy of `bin/` from
[basecamp/omarchy](https://github.com/basecamp/omarchy) (at the version
recorded in `VENDORED_VERSION`), MIT-licensed (see `LICENSE`), then had
every `omarchy-*` command renamed to `slievr-*` (and the `omarchy`
dispatcher to `slievr`) throughout this directory and every config that
calls them (then `dot-config/hypr/bindings.conf`, `hypr-defaults/`, waybar,
mako, walker, elephant; the mbm shell replaced the last four). These are no longer updated from upstream
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

Most scripts work standalone. A subset of Omarchy's own self-management
commands (`slievr-update*`, `slievr-reinstall*`, `slievr-migrate`,
`slievr-refresh-pacman/sddm/plymouth`, `slievr-theme-set` and other
theme-catalog browsing, `slievr-install-*`) still reference
`$OMARCHY_PATH`, which assumed a live git checkout of the upstream
Omarchy repo (`install/`, `config/`, `migrations/`, `themes/` trees) that
isn't vendored here. Nothing in the active desktop config calls these —
they're inert unless manually invoked, in which case they'll error. Not
worth reimplementing since there's no upstream to sync from or reinstall
against anymore.
