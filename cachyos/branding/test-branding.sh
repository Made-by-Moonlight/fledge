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
check "palette has 16 VT slots" "16" "${#MBM_VT_PALETTE[@]}"
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
check "plymouth logo is current (0 differing pixels)" "0" \
  "$(magick compare -metric AE "$committed" "$fresh" null: 2>&1 | awk '{print $1}')"

exit $fail
