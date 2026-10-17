#!/usr/bin/env bash
# Regenerate the committed brand assets from owl.svg. Run after changing the
# mark, then commit the results.
#   cachyos/branding/build-assets.sh [OUTPUT_ROOT]   (default: the repo root)
# Needs python3, magick and rsvg-convert.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SVG="$HERE/owl.svg"
OUT="${1:-$REPO}"
ABOUT="$OUT/dot-config/omarchy/branding/about.txt"
LOGO="$OUT/cachyos/plymouth-theme/slievr-cachy/logo.png"
mkdir -p "$(dirname "$ABOUT")" "$(dirname "$LOGO")"

# About screen (fledge launch about): plain block art, 54 columns wide.
python3 "$HERE/render-console.py" "$SVG" --cols 54 > "$ABOUT"

# Plymouth logo: the mark in white on transparent, 320 px wide.
sed 's/currentColor/#ffffff/g' "$SVG" \
  | rsvg-convert -w 320 -o "$LOGO"

# Plymouth unlock field, dots and progress bar in the brand palette
# (same look as the SDDM field). Sizes match what slievr-cachy.script expects.
PLY_DIR="$(dirname "$LOGO")"
magick -size 286x48 xc:'#2f3640' -fill '#212a33' -draw 'rectangle 2,2 283,45' "PNG32:$PLY_DIR/entry.png"
magick -size 14x14 xc:none -fill '#f4af03' -draw 'circle 7,7 7,2' "PNG32:$PLY_DIR/bullet.png"
magick -size 300x10 xc:'#2f3640' "PNG32:$PLY_DIR/progress_box.png"
magick -size 300x10 xc:'#f4af03' "PNG32:$PLY_DIR/progress_bar.png"

# Desktop theme + SDDM images (spec: Moonrise wallpaper, glow, owl).
THEME_DIR="$OUT/dot-config/omarchy/themes/made-by-moonlight"
SDDM_DIR="$OUT/cachyos/sddm-theme/slievr-cachy"
mkdir -p "$THEME_DIR/backgrounds" "$SDDM_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

white_owl() { # <width> <out.png>
  sed 's/currentColor/#ffffff/g' "$SVG" | rsvg-convert -w "$1" -o "$2"
}
glow() { # <w> <h> <out.png>: #171e28 with a faint radial glow from the top
  local w=$1 h=$2
  magick -size "${w}x${h}" xc:'#171e28' \
    \( -size "$((w * 7 / 5))x$((h * 2))" radial-gradient:'#222c39'-'#171e28' \) \
    -gravity north -geometry "+0-${h}" -composite "$3"
}
moonrise() { # <w> <h> <out.png>: glow + white owl, 22% wide, 90% opacity, top at 38%
  local w=$1 h=$2
  glow "$w" "$h" "$TMP/glow-$w.png"
  white_owl "$((w * 22 / 100))" "$TMP/owl-$w.png"
  magick "$TMP/glow-$w.png" \( "$TMP/owl-$w.png" -channel A -evaluate multiply 0.9 +channel \) \
    -gravity north -geometry "-$((w * 22 * 117 / 100000))+$((h * 38 / 100))" -composite "$3"
}

moonrise 3440 1440 "$THEME_DIR/backgrounds/1-moonrise-3440x1440.png"
moonrise 2560 1440 "$THEME_DIR/backgrounds/2-moonrise-2560x1440.png"
moonrise 1920 1080 "$THEME_DIR/backgrounds/3-moonrise-1920x1080.png"
magick "$THEME_DIR/backgrounds/3-moonrise-1920x1080.png" -resize 1280x720 "$THEME_DIR/preview.png"
glow 1920 1080 "$THEME_DIR/glow.png"
white_owl 520 "$TMP/owl-520.png"
magick -size 520x520 xc:none "$TMP/owl-520.png" -gravity center -composite "PNG32:$THEME_DIR/owl.png"
white_owl 260 "$SDDM_DIR/logo.png"
cp "$THEME_DIR/glow.png" "$SDDM_DIR/background.png"
# The fledge shell's own copies (wallpaper, lock background, owl), so the shell
# doesn't depend on the Omarchy theme tree that project C retires.
FLEDGE_ASSETS="$OUT/dot-local/share/fledge/assets"
mkdir -p "$FLEDGE_ASSETS"
cp "$THEME_DIR/backgrounds/1-moonrise-3440x1440.png" "$FLEDGE_ASSETS/moonrise-3440x1440.png"
cp "$THEME_DIR/backgrounds/2-moonrise-2560x1440.png" "$FLEDGE_ASSETS/moonrise-2560x1440.png"
cp "$THEME_DIR/backgrounds/3-moonrise-1920x1080.png" "$FLEDGE_ASSETS/moonrise-1920x1080.png"
cp "$THEME_DIR/glow.png" "$THEME_DIR/owl.png" "$FLEDGE_ASSETS/"

echo "updated about.txt, the Plymouth logo, the theme images and the SDDM images under $OUT"
