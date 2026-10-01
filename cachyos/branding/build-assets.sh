#!/usr/bin/env bash
# Regenerate the committed brand assets from owl.svg. Run after changing the
# mark, then commit the results.
#   cachyos/branding/build-assets.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SVG="$HERE/owl.svg"

# About screen (slievr-launch-about): plain block art, 54 columns wide.
python3 "$HERE/render-console.py" "$SVG" --cols 54 > "$REPO/dot-config/omarchy/branding/about.txt"

# Plymouth logo: the mark in white on transparent, 320 px wide.
sed 's/currentColor/#ffffff/g' "$SVG" \
  | rsvg-convert -w 320 -o "$REPO/cachyos/plymouth-theme/slievr-cachy/logo.png"

echo "updated dot-config/omarchy/branding/about.txt and cachyos/plymouth-theme/slievr-cachy/logo.png"
