#!/usr/bin/env bash
# Render an Omarchy-style theme (colors.toml + files) into a theme directory,
# filling the vendored Omarchy templates the way slievr-theme-set-templates
# does. Files the theme provides win over templates.
#   cachyos/branding/render-theme.sh [THEME_DIR] [OUT_DIR]
# Defaults: dot-config/omarchy/themes/made-by-moonlight -> dot-config/omarchy/current/theme
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
THEME="${1:-$REPO/dot-config/omarchy/themes/made-by-moonlight}"
OUT="${2:-$REPO/dot-config/omarchy/current/theme}"
TEMPLATES="$REPO/dot-local/share/slievr-cachy/default/themed"
COLORS="$THEME/colors.toml"
die() { echo "render-theme: $*" >&2; exit 1; }

[[ -f "$COLORS" ]] || die "no colors.toml in $THEME"
[[ -n "$OUT" ]] || die "empty output directory"
OUT_R="$(realpath -m -- "$OUT")"
THEME_R="$(realpath -m -- "$THEME")"
if [[ "$OUT_R" == / || "$OUT_R" == "$HOME" || "$OUT_R" == "$REPO" || "$OUT_R" == "$THEME_R" ||
  "$THEME_R" == "$OUT_R"/* || "$REPO" == "$OUT_R"/* || "$HOME" == "$OUT_R"/* ]]; then
  die "refusing to use '$OUT' as the output directory (it is, or contains, the theme, repo or home)"
fi

hex_to_rgb() { local hex="${1#\#}"; printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"; }

sed_script="$(mktemp)"
trap 'rm -f "$sed_script"' EXIT
while IFS='=' read -r key value; do
  key="${key//[\"\' ]/}"
  [[ -n "$key" && "$key" != \#* ]] || continue
  value="${value#*[\"\']}"; value="${value%%[\"\']*}"
  printf 's|{{ %s }}|%s|g\n' "$key" "$value"
  printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}"
  if [[ "$value" == \#* ]]; then
    printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$(hex_to_rgb "$value")"
  fi
done < "$COLORS" > "$sed_script"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -aL "$THEME/." "$OUT/"
shopt -s nullglob
for tpl in "$TEMPLATES"/*.tpl; do
  name="$(basename "$tpl" .tpl)"
  [[ -e "$OUT/$name" ]] || sed -f "$sed_script" "$tpl" > "$OUT/$name"
done
echo "rendered ${THEME#"$REPO"/} -> ${OUT#"$REPO"/}"
