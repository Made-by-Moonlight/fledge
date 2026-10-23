#!/usr/bin/env bash
# Tests for `fledge screenshare pick` with a fake `qs` that answers like the shell would.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
FLEDGE="$HERE/../bin/fledge"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_RUNTIME_DIR="$T" FAKE_LOG="$T/calls"
mkdir -p "$T/bin"
# fake qs: `qs -c fledge ipc call screenshare open -- LIST RESULT ALLOW` (the "--" is
# dropped here, so LIST is $7). Answers per $FAKE: window, screen, cancel, args (echoes
# LIST and ALLOW back as a screen name), bad (a malformed answer), busy, hang, dead (no
# shell), old (a shell without the screenshare target), lost (a shell that restarted and
# no longer holds the request).
cat >"$T/bin/qs" <<'EOS'
#!/bin/bash
[[ $FAKE == dead ]] && exit 1
[[ $5 == screenshare && $6 == open && $7 == -- ]] && set -- "${@:1:6}" "${@:8}"
echo "$*" >>"$FAKE_LOG"
[[ $5 == shell ]] && { echo pong; exit 0; }
[[ $5 == screenshare && $6 == close ]] && exit 0
[[ $5 == screenshare && $6 == waiting ]] && { [[ $FAKE == lost ]] && echo false || echo true; exit 0; }
[[ $FAKE == old ]] && { echo "No target screenshare"; exit 1; }
[[ $FAKE == busy ]] && { echo busy; exit 0; }
echo ok
result="$8"
case "$FAKE" in
  window) (printf '1\nr/window:42\n' >"$result") >/dev/null 2>&1 & ;;
  screen) (printf '1\n/screen:DP-1\n' >"$result") >/dev/null 2>&1 & ;;
  cancel) (printf '0\n\n' >"$result") >/dev/null 2>&1 & ;;
  args)   (printf '1\n/screen:%s-%s\n' "$7" "$9" >"$result") >/dev/null 2>&1 & ;;
  bad)    (printf '1\n/screen:DP-1 window:7\n' >"$result") >/dev/null 2>&1 & ;;
esac
EOS
# fake hyprland-share-picker: the fallback, says it ran and with what.
cat >"$T/bin/hyprland-share-picker" <<'EOS'
#!/bin/bash
echo "stock picker $* list=$XDPH_WINDOW_SHARING_LIST"
EOS
chmod +x "$T/bin/qs" "$T/bin/hyprland-share-picker"
export PATH="$T/bin:$PATH"
pick() { "$FLEDGE" screenshare pick "$@"; }

check "screenshare: a window pick"   "[SELECTION]r/window:42"  "$(FAKE=window pick)"
check "screenshare: a screen pick"   "[SELECTION]/screen:DP-1" "$(FAKE=screen pick)"
check "screenshare: passes the list and --allow-token" "[SELECTION]/screen:7[HC>]x[HT>]t[HE>]9[HA>]-true" \
  "$(XDPH_WINDOW_SHARING_LIST='7[HC>]x[HT>]t[HE>]9[HA>]' FAKE=args pick --allow-token)"
check "screenshare: no --allow-token passes false" "[SELECTION]/screen:-false" "$(XDPH_WINDOW_SHARING_LIST='' FAKE=args pick)"
out="$(FAKE=cancel pick)"; rc=$?
check "screenshare: cancel exits 1"       "1" "$rc"
check "screenshare: cancel prints nothing" "" "$out"
out="$(FAKE=bad pick 2>"$T/err")"; rc=$?
check "screenshare: malformed answer exits 1" "1" "$rc"
check "screenshare: malformed answer prints nothing" "" "$out"
contains "screenshare: says why" "malformed" "$(cat "$T/err")"
FAKE=busy pick >/dev/null 2>"$T/err"; rc=$?
check "screenshare: busy exits 1" "1" "$rc"
contains "screenshare: says busy" "busy" "$(cat "$T/err")"
check "screenshare: shell not running falls back to the stock picker" "stock picker --allow-token list=L" \
  "$(XDPH_WINDOW_SHARING_LIST=L FAKE=dead pick --allow-token 2>/dev/null)"
check "screenshare: fallback without --allow-token" "stock picker  list=" \
  "$(XDPH_WINDOW_SHARING_LIST='' FAKE=dead pick 2>/dev/null)"
check "screenshare: a shell without the dialog falls back too" "stock picker  list=L" \
  "$(XDPH_WINDOW_SHARING_LIST=L FAKE=old pick 2>/dev/null)"
check "screenshare: fallback leaves no temp files" "" "$(find "$T" -maxdepth 1 -name 'fledge-screenshare.*')"
for bad in "" "pick --nope" "open"; do
  # shellcheck disable=SC2086 # word-split on purpose
  FAKE=window "$FLEDGE" screenshare $bad >/dev/null 2>&1; rc=$?
  check "screenshare: '$bad' exits 2" "2" "$rc"
done
# Timeout: no answer; the stale dialog must be closed and rc is 1.
: >"$T/calls"
FAKE=hang FLEDGE_SCREENSHARE_TIMEOUT=1 pick >/dev/null 2>&1; rc=$?
check "screenshare: timeout exits 1" "1" "$rc"
contains "screenshare: timeout closes the dialog" "screenshare close" "$(cat "$T/calls")"
# A shell that lost the dialog: refused at the next check, not at the timeout.
start=$SECONDS
FAKE=lost FLEDGE_SCREENSHARE_TIMEOUT=30 pick >/dev/null 2>"$T/err"; rc=$?
check "screenshare: a lost dialog exits 1" "1" "$rc"
check "screenshare: a lost dialog is refused within seconds" yes "$( ((SECONDS - start < 10)) && echo yes || echo no)"
contains "screenshare: says the dialog was lost" "lost the dialog" "$(cat "$T/err")"
# A dialog that's still there waits on past the first checks, until the timeout.
start=$SECONDS
FAKE=hang FLEDGE_SCREENSHARE_TIMEOUT=5 pick >/dev/null 2>&1; rc=$?
check "screenshare: a live dialog times out with 1" "1" "$rc"
check "screenshare: a live dialog waits until the timeout" yes "$( ((SECONDS - start >= 4)) && echo yes || echo no)"
# A signalled caller (the portal giving up) cleans up and closes the dialog too.
for sig in TERM HUP; do
  : >"$T/calls"
  (FAKE=hang pick >/dev/null 2>&1) &
  sleep 0.6
  pkill -"$sig" -f "$FLEDGE screenshare"
  wait
  check "screenshare: $sig leaves no temp files" "" "$(find "$T" -maxdepth 1 -name 'fledge-screenshare.*')"
  contains "screenshare: $sig closes the dialog" "screenshare close" "$(cat "$T/calls")"
done
check "screenshare: temp files cleaned up" "" "$(find "$T" -maxdepth 1 -name 'fledge-screenshare.*')"
# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
