#!/usr/bin/env bash
# Tests for dev/conf-to-binds.sh (the one-off Hyprland bind -> settings migration).
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
CONV="$HERE/../dev/conf-to-binds.sh"

out="$("$CONV" "Test=$HERE/fixtures/sample-binds.conf")"
check "converter: matches fixture" "$(jq -S . "$HERE/fixtures/sample-binds.json")" "$(jq -S . <<<"$out")"
check "converter: unbind removed PRINT" "false" "$(jq 'has("test.screenshot")' <<<"$out")"
exit $fail
