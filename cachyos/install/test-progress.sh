#!/usr/bin/env bash
# Unit tests for lib/progress.sh. No VM state touched.
#   bash cachyos/install/test-progress.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/progress.sh
source "$DIR/lib/progress.sh"

check "silent without FLEDGE_PROGRESS" "" "$(unset FLEDGE_PROGRESS; progress_stage base 'Base system'; progress_fail; progress_done)"
export FLEDGE_PROGRESS=1
check "stage marker"   "@@fledge stage base Base system" "$(progress_stage base 'Base system')"
check "fail uses current stage" "@@fledge fail disk" "$(progress_stage disk Disk >/dev/null; progress_fail)"
check "fail explicit"  "@@fledge fail desktop" "$(progress_fail desktop)"
check "done marker"    "@@fledge done" "$(progress_done)"

in=$'( 1/245) installing base\n:: Running post-transaction hooks...\n(245/245) upgrading zstd\nwarning: ( 3/4) is not a count'
check "filter adds counts after install lines" \
  $'( 1/245) installing base\n@@fledge count 1 245\n:: Running post-transaction hooks...\n(245/245) upgrading zstd\n@@fledge count 245 245\nwarning: ( 3/4) is not a count' \
  "$(progress_filter <<<"$in")"
piped=$'Packages (3) a-1  b-1  c-1\n\ninstalling a...\nOptional dependencies for a\n    x: y [installed]\nupgrading b...\ninstalling c...\ninstalling d...'
check "filter counts piped pacman output against its Packages line" \
  $'Packages (3) a-1  b-1  c-1\n\ninstalling a...\n@@fledge count 1 3\nOptional dependencies for a\n    x: y [installed]\nupgrading b...\n@@fledge count 2 3\ninstalling c...\n@@fledge count 3 3\ninstalling d...' \
  "$(progress_filter <<<"$piped")"
check "filter: each transaction restarts the count (VerbosePkgLists header too)" \
  $'Packages (2) a-1  b-1\ninstalling a...\n@@fledge count 1 2\ninstalling b...\n@@fledge count 2 2\nPackage (1)  New Version\ninstalling z...\n@@fledge count 1 1' \
  "$(progress_filter <<<$'Packages (2) a-1  b-1\ninstalling a...\ninstalling b...\nPackage (1)  New Version\ninstalling z...')"
check "filter: no count before a Packages line" "installing a..." "$(progress_filter <<<'installing a...')"
check "filter strips colour codes" "WARN:  the desktop layer failed" "$(progress_filter <<<$'\e[33mWARN:\e[0m  the desktop layer failed')"
check "filter strips private-mode codes" "done" "$(progress_filter <<<$'\e[?25ldone\e[?25h')"
check "filter passes markers through" "@@fledge stage x X" "$(progress_filter <<<'@@fledge stage x X')"

exit $fail
