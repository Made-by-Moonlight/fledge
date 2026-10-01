#!/usr/bin/env bash
# Tests for render-theme.sh (and, from Task 4, the committed theme render).
#   bash cachyos/branding/test-theme.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RENDER="$DIR/render-theme.sh"

# fixture theme: every key the templates use, distinctive values
mkdir -p "$T/theme"
cat > "$T/theme/colors.toml" <<'EOT'
accent = "#123456"
cursor = "#123457"
foreground = "#fedcba"
background = "#abcdef"
selection_foreground = "#111111"
selection_background = "#222222"
color0 = "#000000"
color1 = "#010101"
color2 = "#020202"
color3 = "#030303"
color4 = "#040404"
color5 = "#050505"
color6 = "#060606"
color7 = "#070707"
color8 = "#080808"
color9 = "#090909"
color10 = "#0a0a0a"
color11 = "#0b0b0b"
color12 = "#0c0c0c"
color13 = "#0d0d0d"
color14 = "#0e0e0e"
color15 = "#0f0f0f"
EOT
echo "theme-provided kitty" > "$T/theme/kitty.conf"

bash "$RENDER" "$T/theme" "$T/out" >/dev/null
check "render: every template rendered or provided" "17" \
  "$(cd "$REPO/dot-local/share/slievr-cachy/default/themed" && for f in *.tpl; do [[ -e "$T/out/${f%.tpl}" ]] && echo x; done | wc -l | tr -d ' ')"
check "render: no {{ placeholders left" "" "$(grep -rl '{{' "$T/out" || true)"
check "render: theme file wins over template" "theme-provided kitty" "$(cat "$T/out/kitty.conf")"
contains "render: _strip form (hyprland accent)" "rgb(123456)" "$(cat "$T/out/hyprland.conf")"
contains "render: _rgb form (hyprlock background)" "rgba(171,205,239" "$(tr -d ' ' < "$T/out/hyprlock.conf")"
contains "render: plain form (waybar background)" "#abcdef" "$(cat "$T/out/waybar.css")"
check "render: colors.toml copied" "yes" "$([[ -f "$T/out/colors.toml" ]] && echo yes || echo no)"

echo stale > "$T/out/stale.txt"
bash "$RENDER" "$T/theme" "$T/out" >/dev/null
check "render: output dir is rebuilt clean" "no" "$([[ -e "$T/out/stale.txt" ]] && echo yes || echo no)"
check "render: missing colors.toml is an error" "1" "$(bash "$RENDER" "$T/nope" "$T/out2" 2>/dev/null; echo $?)"

check "render: OUT == THEME is refused" "1" "$(bash "$RENDER" "$T/theme" "$T/theme" >/dev/null 2>&1; echo $?)"
check "render: OUT == THEME leaves theme intact" "yes" "$([[ -f "$T/theme/colors.toml" ]] && echo yes || echo no)"
check "render: OUT = parent of THEME is refused" "1" "$(bash "$RENDER" "$T/theme" "$T" >/dev/null 2>&1; echo $?)"
check "render: OUT = parent leaves fixture intact" "yes" "$([[ -f "$T/theme/colors.toml" ]] && echo yes || echo no)"
check "render: shared-prefix sibling OUT is allowed" "0:yes" \
  "$(bash "$RENDER" "$T/theme" "$T/theme-out" >/dev/null 2>&1; echo "$?:$([[ -f "$T/theme-out/waybar.css" ]] && echo yes || echo no)")"

exit $fail
