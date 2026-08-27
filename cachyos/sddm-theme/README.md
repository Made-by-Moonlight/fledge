# Vendored SDDM theme

`slievr-cachy/` is adapted from Omarchy's default SDDM theme
(`~/.local/share/omarchy/default/sddm/omarchy/` on a host with Omarchy
installed — part of [basecamp/omarchy](https://github.com/basecamp/omarchy),
MIT-licensed), with `logo.png` regenerated to read "SLIEVR" instead of
"OMARCHY" (same pixelated style/color, `#A8CD76`) and `metadata.desktop`
relabeled. `Main.qml` and the other assets (bullet/entry/lock PNGs) are
unmodified.

Not stow-managed — `bootstrap.sh` copies it to
`/usr/share/sddm/themes/slievr-cachy` directly, since SDDM reads themes
from a system path, not `$HOME`.
