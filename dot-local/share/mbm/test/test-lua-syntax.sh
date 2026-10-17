#!/usr/bin/env bash
# Every shipped Lua file (Hyprland config, installer Hyprland config) must parse.
# Hyprland falls back to an error screen on a syntax error, so catch it here.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
# shellcheck source=../../../../cachyos/install/test/luacheck.sh
source "$REPO/cachyos/install/test/luacheck.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# The checker itself: it must reject broken Lua, or the repo check proves nothing.
printf 'local x = 1\nreturn x\n' > "$T/good.lua"
printf 'local x = = 1\nif then\n' > "$T/bad.lua"
lua_syntax_ok "$T/good.lua" 2>/dev/null; check "accepts valid Lua" 0 "$?"
lua_syntax_ok "$T/bad.lua" 2>/dev/null; check "rejects broken Lua" 1 "$?"
lua_syntax_ok "$T/good.lua" "$T/bad.lua" 2>/dev/null; check "rejects when any file is broken" 1 "$?"

# Dirs may not exist yet (the Lua config lands in a later change).
files=()
for d in "$REPO/dot-config/hypr" "$REPO/cachyos/iso/configs/airootfs/etc/mbm-installer"; do
  [[ -d "$d" ]] && while IFS= read -r f; do files+=("$f"); done < <(find "$d" -name '*.lua' | sort)
done
for f in "${files[@]}"; do
  lua_syntax_ok "$f"; check "parses ${f#"$REPO"/}" 0 "$?"
done
printf '%d repo Lua file(s) checked\n' "${#files[@]}"
# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
