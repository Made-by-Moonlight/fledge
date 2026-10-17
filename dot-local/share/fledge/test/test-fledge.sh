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

# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
