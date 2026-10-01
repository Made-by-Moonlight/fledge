# cachyos/branding/

made by moonlight brand source files.

| File | What |
| --- | --- |
| `owl.svg` | The mark: the owner's brow-and-beak owl logo, traced with potrace (brow + beak + both eyes; right eye rebuilt as a ring cut off by the brow). `fill="currentColor"`. |
| `palette.sh` | Brand colours and the 16-slot Linux-console palette (`mbm_vt_palette`). |
| `render-console.py` | SVG → console block art (`▀▄█`). |
| `build-assets.sh` | Regenerates committed assets: `dot-config/omarchy/branding/about.txt` and the Plymouth `logo.png`. |
| `test-branding.sh` | Tests for the above. |

The ISO build renders `owl.ansi` itself (`cachyos/iso/builder/build-iso.sh`).
Changing the mark: replace `owl.svg`, run `build-assets.sh`, commit.
