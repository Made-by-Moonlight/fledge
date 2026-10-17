#!/usr/bin/env bash
# Tests for `mbm dmenu` with a fake `qs` that answers like the shell would.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
MBM="$HERE/../bin/mbm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_RUNTIME_DIR="$T" FAKE_LOG="$T/calls"
mkdir -p "$T/bin"
# fake qs: `qs -c mbm ipc call dmenu open PROMPT OPTS RESULT SELECT INPUTONLY`
# with a "--" before the positionals, which is dropped here (args $1..$11; PROMPT is $7). Answers per $FAKE: pick (2nd option), cancel,
# typed, args, dead (shell not running).
cat >"$T/bin/qs" <<'EOS'
#!/bin/bash
[[ $FAKE == dead ]] && exit 1
[[ $5 == dmenu && $6 == open && $7 == -- ]] && set -- "${@:1:6}" "${@:8}"
echo "$*" >>"$FAKE_LOG"
[[ $5 == shell ]] && { echo pong; exit 0; }
[[ $5 == dmenu && $6 == close ]] && exit 0
opts="$8" result="$9"
case "$FAKE" in
  pick)   (printf '1\n%s\n' "$(sed -n 2p "$opts")" >"$result") >/dev/null 2>&1 & ;;
  cancel) (printf '0\n\n' >"$result") >/dev/null 2>&1 & ;;
  typed)  (printf '1\nfree text\n' >"$result") >/dev/null 2>&1 & ;;
  args)   (printf '1\n%s|%s|%s\n' "$7" "${10}" "${11}" >"$result") >/dev/null 2>&1 & ;;
esac
EOS
chmod +x "$T/bin/qs"
export PATH="$T/bin:$PATH"

check "dmenu: returns the chosen line" "beta"  "$(printf 'alpha\nbeta\ngamma\n' | FAKE=pick "$MBM" dmenu)"
printf 'a\nb\n' | FAKE=cancel "$MBM" dmenu >/dev/null; rc=$?
check "dmenu: cancel exits 1"          "1"     "$rc"
check "dmenu: input-only returns text" "free text" "$(FAKE=typed "$MBM" dmenu --input-only </dev/null)"
check "dmenu: passes prompt/select/input-only" "Power|3|false" "$(printf 'x\n' | FAKE=args "$MBM" dmenu --prompt Power --select 3)"
printf 'a\n' | FAKE=dead "$MBM" dmenu 2>"$T/err"; rc=$?
check "dmenu: shell not running exits 1" "1"   "$rc"
contains "dmenu: says why"             "isn't running" "$(cat "$T/err")"
"$MBM" dmenu --select x </dev/null 2>/dev/null; rc=$?
check "dmenu: bad --select exits 2"    "2"     "$rc"
check "dmenu: dash-leading prompt passes through" "-x|0|false" "$(printf 'x\n' | FAKE=args "$MBM" dmenu --prompt -x)"
check "dmenu: empty prompt is allowed" "|0|false" "$(printf 'x\n' | FAKE=args "$MBM" dmenu --prompt "")"
for bad in "--prompt" "--select" "--select abc"; do
  # shellcheck disable=SC2086 # word-split on purpose
  printf 'a\n' | FAKE=pick "$MBM" dmenu $bad >/dev/null 2>&1; rc=$?
  check "dmenu: '$bad' exits 2" "2" "$rc"
done
# Timeout: no answer; the stale dialog must be closed and rc is 1.
: >"$T/calls"
printf 'a\n' | FAKE=hang MBM_DMENU_TIMEOUT=1 "$MBM" dmenu >/dev/null 2>&1; rc=$?
check "dmenu: timeout exits 1" "1" "$rc"
contains "dmenu: timeout closes the dialog" "dmenu close" "$(cat "$T/calls")"
# A signalled caller cleans up and closes the dialog too.
for sig in TERM HUP; do
  : >"$T/calls"
  (printf 'a\n' | FAKE=hang "$MBM" dmenu >/dev/null 2>&1) &
  sleep 0.6
  pkill -"$sig" -f "$MBM dmenu"
  wait
  check "dmenu: $sig leaves no temp files" "" "$(find "$T" -maxdepth 1 -name 'mbm-dmenu.*')"
  contains "dmenu: $sig closes the dialog" "dmenu close" "$(cat "$T/calls")"
done
check "dmenu: temp files cleaned up"   ""      "$(find "$T" -maxdepth 1 -name 'mbm-dmenu.*')"
# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
