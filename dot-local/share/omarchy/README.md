# Vendored Omarchy command scripts

`bin/` is vendored from [basecamp/omarchy](https://github.com/basecamp/omarchy)
(`bin/` subdirectory only, at the version recorded in `VENDORED_VERSION`),
MIT-licensed (see `LICENSE`).

`dot-config/hypr/bindings.conf` calls several `omarchy-*` commands
(`omarchy-launch-browser`, `omarchy capture screenshot ...`, etc.). Rather
than installing the full Omarchy framework — which overrides the pacman
mirrorlist and makes broader system changes — only these self-contained
bash scripts are vendored here, giving the keybindings their expected
commands without installing Omarchy itself or touching CachyOS's repo
config.

Not modified from upstream. To refresh: replace `bin/` with a newer
checkout's `bin/` directory and update `VENDORED_VERSION`.
