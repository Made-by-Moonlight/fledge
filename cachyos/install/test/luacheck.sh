# shellcheck shell=bash
# Lua syntax check for the tests: source it, then `lua_syntax_ok <file>...`.
# Uses `luac -p` (parse only), so nothing in the file runs and no Hyprland is
# needed. Prints the compiler's message for each broken file.
lua_syntax_ok() {
  local luac f rc=0
  luac="$(command -v luac || command -v luac5.5 || command -v luac5.4)" || {
    echo "luac not found (pacman -S lua)" >&2; return 1; }
  for f in "$@"; do
    "$luac" -p "$f" || rc=1
  done
  return "$rc"
}
