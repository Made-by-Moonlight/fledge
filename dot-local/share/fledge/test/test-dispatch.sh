#!/usr/bin/env bash
# Tests for the `fledge` dispatcher: longest-prefix resolution into libexec/,
# arguments passed through untouched, built-ins first, help, unknown commands
# and command words that could escape libexec/. Runs against a temp libexec
# (FLEDGE_LIBEXEC) of stubs that print their name and argv.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
FLEDGE="$HERE/../bin/fledge"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
L="$T/libexec"; mkdir -p "$L"
export FLEDGE_LIBEXEC="$L"

stub() { # <name> [first comment line]: prints "<name>" then one line per argument
  printf '#!/usr/bin/env bash\n\n# %s\nprintf "%%s\\n" %q "$@"\nexit "${STUB_RC:-0}"\n' "${2:-stub $1}" "$1" >"$L/$1"
  chmod +x "$L/$1"
}
for n in a a-b a-b-c capture-screenshot capture-screenrecording hypr-quote settings help dmenu menu; do stub "$n"; done
stub capture-screenshot "Take a screenshot"
stub capture-screenrecording "Record the screen"
printf 'not executable\n' >"$L/a-b-x"
mkdir -p "$L/c"; stub c/d; stub A
printf '#!/bin/sh\necho ESCAPED\n' >"$T/x"; chmod +x "$T/x"

run() { # <args...>: sets out, err, rc
  out="$("$FLEDGE" "$@" 2>"$T/err")"; rc=$?; err="$(cat "$T/err")"
}
has_line() { # <description> <ERE for a whole line> <text>
  if grep -qxE -- "$2" <<<"$3"; then check "$1" ok ok; else check "$1" "a line like /$2/" "$3"; fi
}

# --- longest match wins -----------------------------------------------------------
run a b c d
check "a b c d -> a-b-c with d" $'a-b-c\nd' "$out"
run a b x y
check "a b x y -> a-b with x y (a-b-x isn't executable)" $'a-b\nx\ny' "$out"
run a x
check "a x -> a with x" $'a\nx' "$out"
run a
check "a alone -> a, no args" "a" "$out"
run capture screenshot region copy
check "capture screenshot region copy" $'capture-screenshot\nregion\ncopy' "$out"
STUB_RC=5 run a b
check "the script's exit status comes back" 5 "$rc"

# --- arguments pass through verbatim; only command words are checked --------------
run a b 'x y' '"q"' "it's" '' '$HOME' '--reverse' 'suspend-off' 'https://e.x/a?b=1&c' '*'
check "args verbatim (spaces, quotes, empty, \$, flags, hyphens, URLs, globs)" \
  "$(printf '%s\n' a-b 'x y' '"q"' "it's" '' '$HOME' '--reverse' 'suspend-off' 'https://e.x/a?b=1&c' '*')" "$out"
run a ../x b
check "a non-word token ends the scan, it isn't a command word" $'a\n../x\nb' "$out"
run a b A c
check "an uppercase argument after a match passes through" $'a-b\nA\nc' "$out"

# --- command words that could leave libexec/ are refused -------------------------
for bad in ../x a/b c/d A -x . .. .hidden 'a b' ''; do
  run "$bad"
  check "command word [$bad] -> exit 2" 2 "$rc"
  check "command word [$bad] -> nothing ran" "" "$out"
done
contains "a refused word is named" "not a command word" "$(run ../x; echo "$err")"
run a..b
check "a word with .. -> exit 2" 2 "$rc"

# --- built-ins come first ---------------------------------------------------------
check "hypr is built in (libexec/hypr-quote not run)" '"x"' "$("$FLEDGE" hypr quote x)"
run settings
check "settings is built in -> its usage, exit 1" 1 "$rc"
contains "settings usage" "usage: fledge settings get|set|reset|check|apply" "$err"
check "settings: libexec/settings not run" "" "$out"
run dmenu --select x
check "dmenu is built in -> its own usage error, exit 2" 2 "$rc"
contains "dmenu: its own message" "fledge dmenu: --select needs a number" "$err"
run help
check "help is built in -> exit 0" 0 "$rc"
check "help: libexec/help not run" "no" "$(grep -qx help <<<"$out" && echo yes || echo no)"

# --- help ---------------------------------------------------------------------------
has_line "help lists the libexec groups" '  capture +Screenshots and screen recording' "$out"
has_line "help lists a group without a description" '  a' "$out"
has_line "help lists built-in settings" '  settings +.+' "$out"
has_line "help lists built-in hypr" '  hypr +.+' "$out"
check "help lists each group once" 1 "$(grep -cE '^  capture( |$)' <<<"$out")"
run help capture
check "help capture -> exit 0" 0 "$rc"
has_line "help capture: screenshot and its comment" '  fledge capture screenshot +Take a screenshot' "$out"
has_line "help capture: screenrecording and its comment" '  fledge capture screenrecording +Record the screen' "$out"
check "help capture: only capture actions" 2 "$(grep -c '^  fledge ' <<<"$out")"
run help a
has_line "help a: the group's own script" '  fledge a +stub a' "$out"
has_line "help a: a-b-c" '  fledge a b c +stub a-b-c' "$out"
check "help a: non-executable a-b-x left out" 0 "$(grep -c 'a b x' <<<"$out")"
run help hypr
check "help hypr -> exit 0" 0 "$rc"
contains "help hypr: the hypr usage" "fledge hypr dispatch" "$out$err"
run help nope
check "help for an unknown group -> exit 2" 2 "$rc"
run --help
check "--help -> exit 0" 0 "$rc"
contains "--help is the group list" "  capture" "$out"

# --- unknown commands -----------------------------------------------------------------
run captur
check "unknown -> exit 2" 2 "$rc"
contains "unknown: says so" "fledge: unknown command: captur" "$err"
contains "unknown: did you mean (prefix)" "did you mean" "$err"
contains "unknown: suggests capture screenshot" "fledge capture screenshot" "$err"
run capture bogus
check "known group, unknown action -> exit 2" 2 "$rc"
contains "known group: suggests its actions" "fledge capture screenrecording" "$err"
run zzz
check "nothing near -> exit 2" 2 "$rc"
check "nothing near -> no suggestion" 0 "$(grep -c 'did you mean' <<<"$err")"
run c
check "a directory in libexec isn't a command -> exit 2" 2 "$rc"
contains "a directory: unknown command" "fledge: unknown command: c" "$err"
run
check "no args -> exit 2" 2 "$rc"
check "the stray outside libexec never ran" 0 "$(grep -c ESCAPED <<<"$out$err")"

# The real libexec: every script name is reachable as words (lowercase word
# runs joined by -), and no script name is the group of a built-in.
real="$HERE/../libexec"
bad_names="$(cd "$real" && for f in *; do [[ $f =~ ^[a-z0-9][a-z0-9_.]*(-[a-z0-9][a-z0-9_.]*)*$ ]] || echo "$f"; done)"
check "real libexec: every name is a run of command words" "" "$bad_names"
check "real libexec: no script shadows a built-in" "" "$(cd "$real" && ls -d hypr settings dmenu help hypr-* settings-* dmenu-* help-* 2>/dev/null)"
check "real libexec: every script is executable" "" "$(find "$real" -type f ! -perm -u+x)"


# Longest-prefix collisions: `fledge menu <name>` must reach menu's own
# go_to_menu, so no submenu name may also be a menu-<name> script.
menus="$(sed -n '/^go_to_menu() {/,/^}/p' "$real/menu" | grep -oE '^ *\*[a-z0-9_.-]+\*\)' | tr -d ' *)')"
check "menu: go_to_menu has its submenus" yes "$(grep -qx setup <<<"$menus" && grep -qx trigger <<<"$menus" && echo yes || echo no)"
check "menu: no submenu name is a menu-* script" "" "$(for m in $menus; do [[ -e $real/menu-$m ]] && echo "menu-$m"; done)"

# `fledge toggle <flag>` must reach the generic toggle, so its flags carry a
# '-' (not a command word) and none is the name of a toggle-* script. Flags:
# toggle-enabled's argument, and the last word of a `fledge toggle \` call.
flags="$( { grep -rhoE 'fledge toggle enabled [a-z0-9_.-]+' "$real" | awk '{print $4}'
           for f in "$real"/*; do awk '/fledge toggle \\$/{c=1;next} c&&/\\$/{next} c{print $NF;c=0}' "$f"; done; } | sort -u)"
check "toggle: flags found" yes "$(grep -qx suspend-off <<<"$flags" && echo yes || echo no)"
check "toggle: every flag has a '-'" "" "$(grep -v -- - <<<"$flags")"
check "toggle: no flag is a toggle-* script name" "" "$(for f in $flags; do [[ -e $real/toggle-$f ]] && echo "toggle-$f"; done)"
check "toggle: no toggle-* name is a dash-free flag" "" "$(cd "$real" && for t in toggle-*; do grep -qx -- "${t#toggle-}" <<<"$flags" && echo "$t"; done)"
# The header: the leading run of comment and blank lines, however long it grows.
contains "toggle: the header says why flags carry a '-'" "must contain a '-'" "$(awk '!/^(#|$)/{exit} 1' "$real/toggle")"

# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
