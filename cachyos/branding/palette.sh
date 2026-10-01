# shellcheck shell=bash
# made by moonlight brand palette. Hex values for graphics; MBM_VT_PALETTE maps
# ANSI colour numbers (what gum and \e[3Xm use on the Linux console) to brand
# colours. The live ISO loads it with mbm_vt_palette.
# shellcheck disable=SC2034  # consumed by scripts that source this file
MBM_BG="#171e28"
MBM_SURFACE="#212a33"
MBM_LINE="#2f3640"
MBM_FG="#ffffff"
MBM_ACCENT="#f4af03"
MBM_MUTED="#6c7787"
MBM_ERROR="#e5626a"
MBM_OK="#8fcf8a"

MBM_VT_PALETTE=(
  "$MBM_BG"      # 0  background
  "$MBM_ERROR"   # 1  error
  "$MBM_OK"      # 2  success
  "$MBM_ACCENT"  # 3  accent (selection, buttons)
  "$MBM_LINE"    # 4  lines
  "$MBM_ACCENT"  # 5
  "$MBM_MUTED"   # 6
  "$MBM_FG"      # 7  text
  "$MBM_MUTED"   # 8  muted hints
  "$MBM_ERROR"   # 9
  "$MBM_OK"      # 10
  "$MBM_ACCENT"  # 11
  "$MBM_SURFACE" # 12 surface
  "$MBM_ACCENT"  # 13
  "$MBM_MUTED"   # 14
  "$MBM_FG"      # 15 the mark
)

# mbm_vt_palette  ->  escapes that load MBM_VT_PALETTE into the Linux console
mbm_vt_palette() {
  local i
  for i in "${!MBM_VT_PALETTE[@]}"; do
    printf '\e]P%X%s' "$i" "${MBM_VT_PALETTE[$i]#\#}"
  done
}
