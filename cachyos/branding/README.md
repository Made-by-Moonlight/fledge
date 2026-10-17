# cachyos/branding/

made by moonlight brand source files.

| File | What |
| --- | --- |
| `owl.svg` | The mark: the owner's brow-and-beak owl logo, traced with potrace (brow + beak + both eyes; right eye rebuilt as a ring cut off by the brow). `fill="currentColor"`. |
| `palette.sh` | Brand colours and the 16-slot Linux-console palette (`fledge_vt_palette`). |
| `render-console.py` | SVG → console block art (`▀▄█`). |
| `build-assets.sh` | Regenerates committed assets (needs `rsvg-convert`, `magick`, `python3`): `dot-config/omarchy/branding/about.txt`, the Plymouth `logo.png`, the Moonrise wallpapers, `glow.png`, `owl.png`, the theme `preview.png`, the SDDM `logo.png`/`background.png`, and the fledge shell's copies in `dot-local/share/fledge/assets/`. Optional arg: output root. |
| `render-theme.sh` | Renders `dot-config/omarchy/themes/made-by-moonlight` into `dot-config/omarchy/current/theme` through the vendored templates. |
| `test-theme.sh` | Tests for `render-theme.sh`. |
| `test-branding.sh` | Tests for the above. |

The ISO build renders `owl.ansi` itself (`cachyos/iso/builder/build-iso.sh`).
Changing the mark: replace `owl.svg`, run `build-assets.sh`, commit.

## Changing the theme

Edit `colors.toml` (theme dir) or the mark (`owl.svg`) -> `build-assets.sh` -> `render-theme.sh` -> commit.
