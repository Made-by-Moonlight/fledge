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

# About screen (slievr-launch-about): plain block art, 54 columns wide.
python3 "$HERE/render-console.py" "$SVG" --cols 54 > "$ABOUT"

# Plymouth logo: the mark in white on transparent, 320 px wide.
sed 's/currentColor/#ffffff/g' "$SVG" \
  | rsvg-convert -w 320 -o "$LOGO"

echo "updated $ABOUT and $LOGO"
