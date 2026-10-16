#!/usr/bin/env bash
# Unit tests for lib/progress.sh. No VM state touched.
#   bash cachyos/install/test-progress.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/progress.sh
source "$DIR/lib/progress.sh"

check "silent without MBM_PROGRESS" "" "$(unset MBM_PROGRESS; progress_stage base 'Base system'; progress_fail; progress_done)"
export MBM_PROGRESS=1
check "stage marker"   "@@mbm stage base Base system" "$(progress_stage base 'Base system')"
check "fail uses current stage" "@@mbm fail disk" "$(progress_stage disk Disk >/dev/null; progress_fail)"
check "fail explicit"  "@@mbm fail desktop" "$(progress_fail desktop)"
check "done marker"    "@@mbm done" "$(progress_done)"

in=$'( 1/245) installing base\n:: Running post-transaction hooks...\n(245/245) upgrading zstd\nwarning: ( 3/4) is not a count'
check "filter adds counts after install lines" \
  $'( 1/245) installing base\n@@mbm count 1 245\n:: Running post-transaction hooks...\n(245/245) upgrading zstd\n@@mbm count 245 245\nwarning: ( 3/4) is not a count' \
  "$(progress_filter <<<"$in")"
check "filter passes markers through" "@@mbm stage x X" "$(progress_filter <<<'@@mbm stage x X')"

exit $fail
