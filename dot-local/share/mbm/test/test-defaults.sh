#!/usr/bin/env bash
# The shipped defaults/settings.json must pass `mbm settings check`. Since the
# cutover it is the source of truth for binds, monitors, workspaces and input.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
DEF="$HERE/../defaults/settings.json"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

out="$(HOME="$T" XDG_CONFIG_HOME="$T/.config" MBM_DEFAULTS="$DEF" "$HERE/../bin/mbm" settings check 2>&1)"
check "defaults: settings check rc 0" 0 "$?"
check "defaults: settings check prints nothing" "" "$out"
exit $fail
