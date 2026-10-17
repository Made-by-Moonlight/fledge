#!/usr/bin/env bash
# Tests for `fledge hypr dispatch|set|eval` with a stub hyprctl.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
FLEDGE="$HERE/../bin/fledge"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# stub: records argv one element per line; STUB_OUT is printed, STUB_RC returned
cat >"$T/hyprctl" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_ARGV"
printf '%s\n' "${STUB_OUT:-ok}"
exit "${STUB_RC:-0}"
EOS
chmod +x "$T/hyprctl"
export HYPRCTL="$T/hyprctl" STUB_ARGV="$T/argv"

run() { # <args...>; sets rc, err, argv
  err="$("$FLEDGE" "$@" 2>&1 >/dev/null)"; rc=$?
  argv="$(cat "$T/argv" 2>/dev/null)"; rm -f "$T/argv"
}

expr='hl.dsp.exec_cmd("kitty --title \"a b\"", {x={1}})'
run hypr dispatch "$expr"
check "dispatch rc" 0 "$rc"
check "dispatch argv is one element, unchanged" $'dispatch\n'"$expr" "$argv"

run hypr set 'input={kb_layout="gb"}'
check "set rc" 0 "$rc"
check "set wraps in hl.config" $'eval\nhl.config({ input={kb_layout="gb"} })' "$argv"

run hypr eval 'return 1+1'
check "eval rc" 0 "$rc"
check "eval passes through" $'eval\nreturn 1+1' "$argv"

STUB_OUT='error: bad thing' run hypr dispatch 'x'
check "error output with rc 0 -> exit 1" 1 "$rc"
contains "error message prefixed on stderr" 'fledge hypr: error: bad thing' "$err"

STUB_RC=7 STUB_OUT='nope' run hypr eval 'x'
check "hyprctl rc 7 -> exit 1" 1 "$rc"
contains "rc 7 output on stderr" 'fledge hypr: nope' "$err"

for msg in 'only supported with the lua config manager' 'Invalid dispatcher' 'non-legacy parsers'; do
  STUB_OUT="$msg" run hypr eval 'x'
  check "refusal [$msg] rc 0 -> exit 1" 1 "$rc"
  contains "refusal [$msg] on stderr" "fledge hypr: $msg" "$err"
done

STUB_RC=3 STUB_OUT='' run hypr eval 'x'
check "rc 3 with empty output -> exit 1" 1 "$rc"

out="$("$FLEDGE" hypr eval 'x' 2>/dev/null)"
check "bare ok is dropped" "" "$out"
out="$(STUB_OUT='42' "$FLEDGE" hypr eval 'x' 2>/dev/null)"
check "other output kept on stdout" "42" "$out"

# quote: a Lua string literal that reads back as the exact text.
rm -f "$T/argv"
check "quote: plain" '"address:0x55d0"' "$("$FLEDGE" hypr quote 'address:0x55d0')"
check "quote: escapes" '"a\\b \"c\" d\ne\009f\0011"' "$("$FLEDGE" hypr quote $'a\\b "c" d\ne\tf\0011' 2>/dev/null || true)"
for text in '' 'kitty --class=x -e sh -c "echo $HOME"' $'two\nlines\ttab' 'back\\slash \\" end\\' 'ünïcødé 󰍹' $'del\x7f' '#x ]]==] [[' "it's"; do
  got="$(lua -e "io.write($("$FLEDGE" hypr quote "$text"))")"
  check "quote round-trips through Lua: [$text]" "$text" "$got"
done
check "quote: hyprctl not called" "no" "$([[ -e $T/argv ]] && echo yes || echo no)"
run hypr quote
check "quote without args -> 2" 2 "$rc"

rm -f "$T/argv"
"$FLEDGE" hypr dispatch 2>/dev/null; "$FLEDGE" hypr bogus x 2>/dev/null; "$FLEDGE" bogus 2>/dev/null
check "stub not called on usage errors" "no" "$([[ -e $T/argv ]] && echo yes || echo no)"

run hypr dispatch
check "dispatch without args -> 2" 2 "$rc"
run hypr set
check "set without args -> 2" 2 "$rc"
run hypr eval
check "eval without args -> 2" 2 "$rc"
run hypr
check "hypr without subcommand -> 2" 2 "$rc"
run hypr bogus x
check "unknown hypr subcommand -> 2" 2 "$rc"
run bogus
check "unknown command -> 2" 2 "$rc"
run
check "no args -> 2" 2 "$rc"

# warning: lines (a dispatcher that found no target) go to stderr, still exit 0
out="$(STUB_OUT=$'warning: =[C]:-1: send_shortcut: window not found' "$FLEDGE" hypr dispatch x 2>"$T/err")"; rc=$?
check "warning -> exit 0" 0 "$rc"
check "warning -> nothing on stdout" "" "$out"
check "warning -> on stderr" "fledge hypr: warning: =[C]:-1: send_shortcut: window not found" "$(cat "$T/err")"
out="$(STUB_OUT=$'42\nwarning: w' "$FLEDGE" hypr eval x 2>"$T/err")"
check "warning beside a result: result on stdout" "42" "$out"
check "warning beside a result: warning on stderr" "fledge hypr: warning: w" "$(cat "$T/err")"

# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
