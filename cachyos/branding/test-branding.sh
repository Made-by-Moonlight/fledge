#!/usr/bin/env bash
# Tests for the brand palette and console renderer. Needs python3, magick and rsvg-convert.
#   bash cachyos/branding/test-branding.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
# shellcheck source=SCRIPTDIR/palette.sh
source "$DIR/palette.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R=(python3 "$DIR/render-console.py")

# palette
check "palette has 16 VT slots" "16" "${#FLEDGE_VT_PALETTE[@]}"
esc="$(mbm_vt_palette)"
contains "VT slot 0 is the background" $'\e]P0171e28' "$esc"
contains "VT slot 3 is the accent"     $'\e]P3f4af03' "$esc"
contains "VT slot 15 is the mark"      $'\e]PFffffff' "$esc"

# renderer: a fully filled square -> 4 cols x 2 rows of full blocks
cat > "$T/full.svg" <<'EOT'
<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" fill="currentColor"/></svg>
EOT
check "full square renders as full blocks" $'████\n████' "$("${R[@]}" "$T/full.svg" --cols 4)"

# top quarter only -> one row of upper half blocks; trailing blank rows trimmed
cat > "$T/top.svg" <<'EOT'
<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><rect width="10" height="2.5" fill="currentColor"/></svg>
EOT
check "top quarter renders as upper halves" "▀▀▀▀" "$("${R[@]}" "$T/top.svg" --cols 4)"

check "--ansi wraps lines in the SGR colour" $'\e[97m████\e[0m\n\e[97m████\e[0m' \
  "$("${R[@]}" "$T/full.svg" --cols 4 --ansi)"

# the real mark
owl="$("${R[@]}" "$DIR/owl.svg" --cols 48)"
check "owl fits 48 columns" "yes" "$(awk 'length > 48 {bad=1} END {print bad ? "no" : "yes"}' <<<"$owl")"
check "owl uses only block characters" "" "$(tr -d ' ▀▄█\n' <<<"$owl")"
contains "owl has solid areas" "█" "$owl"

# committed generated assets match a fresh build (built into a temp root)
repo="$(cd "$DIR/../.." && pwd)"
bash "$DIR/build-assets.sh" "$T/assets" >/dev/null
check "about.txt is current" "$(cat "$repo/dot-config/omarchy/branding/about.txt")" \
  "$(cat "$T/assets/dot-config/omarchy/branding/about.txt")"
committed="$repo/cachyos/plymouth-theme/slievr-cachy/logo.png"
fresh="$T/assets/cachyos/plymouth-theme/slievr-cachy/logo.png"
check "plymouth logo is 320px wide" "320" "$(magick identify -format '%w' "$committed")"
ply_rel=cachyos/plymouth-theme/slievr-cachy
for f in entry.png bullet.png progress_box.png progress_bar.png; do
  check "plymouth $f is current" "0" \
    "$(magick compare -metric AE "$repo/$ply_rel/$f" "$T/assets/$ply_rel/$f" null: 2>&1 | awk '{print $1}')"
done
check "plymouth dot is amber" "F4AF03" "$(magick "$repo/$ply_rel/bullet.png" -format '%[hex:p{7,7}]' info: | cut -c1-6)"
check "plymouth field fill is #212a33" "212A33" "$(magick "$repo/$ply_rel/entry.png" -format '%[hex:p{143,24}]' info: | cut -c1-6)"
check "plymouth logo is current (0 differing pixels)" "0" \
  "$(magick compare -metric AE "$committed" "$fresh" null: 2>&1 | awk '{print $1}')"

# theme + SDDM images
theme_rel=dot-config/omarchy/themes/made-by-moonlight
sddm_rel=cachyos/sddm-theme/slievr-cachy
for spec in "backgrounds/1-moonrise-3440x1440.png 3440x1440" "backgrounds/2-moonrise-2560x1440.png 2560x1440" \
            "backgrounds/3-moonrise-1920x1080.png 1920x1080" "glow.png 1920x1080" "owl.png 520x520" "preview.png 1280x720"; do
  f="${spec% *}"; want="${spec#* }"
  check "theme $f is $want" "$want" "$(magick identify -format '%wx%h' "$T/assets/$theme_rel/$f" 2>/dev/null)"
  check "theme $f is current" "0" \
    "$(magick compare -metric AE "$repo/$theme_rel/$f" "$T/assets/$theme_rel/$f" null: 2>&1 | awk '{print $1}')"
done
check "sddm logo is 260px wide" "260" "$(magick identify -format '%w' "$T/assets/$sddm_rel/logo.png" 2>/dev/null)"
for f in logo.png background.png; do
  check "sddm $f is current" "0" \
    "$(magick compare -metric AE "$repo/$sddm_rel/$f" "$T/assets/$sddm_rel/$f" null: 2>&1 | awk '{print $1}')"
done
check "glow has no owl (centre pixel is background-ish)" "yes" \
  "$(magick "$T/assets/$theme_rel/glow.png" -format '%[fx:p{960,600}.r<0.2?1:0]' info: | sed 's/^1$/yes/;s/^0$/no/')"
check "moonrise has the owl (white near the centre)" "yes" \
  "$(magick "$T/assets/$theme_rel/backgrounds/3-moonrise-1920x1080.png" -crop 422x200+749+411 -format '%[fx:maxima.r>0.8?1:0]' info: | sed 's/^1$/yes/;s/^0$/no/')"

exit $fail
