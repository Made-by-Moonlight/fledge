# shellcheck shell=bash
# made by moonlight brand palette. Hex values for graphics; FLEDGE_VT_PALETTE maps
# ANSI colour numbers (what gum and \e[3Xm use on the Linux console) to brand
# colours. The live ISO loads it with fledge_vt_palette.
# shellcheck disable=SC2034  # consumed by scripts that source this file
FLEDGE_BG="#171e28"
FLEDGE_SURFACE="#212a33"
FLEDGE_LINE="#2f3640"
FLEDGE_FG="#ffffff"
FLEDGE_ACCENT="#f4af03"
FLEDGE_MUTED="#6c7787"
FLEDGE_ERROR="#e5626a"
FLEDGE_OK="#8fcf8a"

FLEDGE_VT_PALETTE=(
  "$FLEDGE_BG"      # 0  background
  "$FLEDGE_ERROR"   # 1  error
  "$FLEDGE_OK"      # 2  success
  "$FLEDGE_ACCENT"  # 3  accent (selection, buttons)
  "$FLEDGE_LINE"    # 4  lines
  "$FLEDGE_ACCENT"  # 5
  "$FLEDGE_MUTED"   # 6
  "$FLEDGE_FG"      # 7  text
  "$FLEDGE_MUTED"   # 8  muted hints
  "$FLEDGE_ERROR"   # 9
  "$FLEDGE_OK"      # 10
  "$FLEDGE_ACCENT"  # 11
  "$FLEDGE_SURFACE" # 12 surface
  "$FLEDGE_ACCENT"  # 13
  "$FLEDGE_MUTED"   # 14
  "$FLEDGE_FG"      # 15 the mark
)

# fledge_vt_palette  ->  escapes that load FLEDGE_VT_PALETTE into the Linux console
fledge_vt_palette() {
  local i
  for i in "${!FLEDGE_VT_PALETTE[@]}"; do
    printf '\e]P%X%s' "$i" "${FLEDGE_VT_PALETTE[$i]#\#}"
  done
}
