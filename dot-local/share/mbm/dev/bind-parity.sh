#!/usr/bin/env bash
# Compare two `hyprctl binds -j` dumps (before/after the cutover). Prints each
# bind only one side has; exits 1 if any of them isn't explained by
# parity-allowed.txt (the deliberate remaps).
set -euo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
norm() { jq -r '.[] | "\(.modmask) \(.key | ascii_downcase) \(.submap // "") :: \(.dispatcher) \(.arg)"' "$1" | sort; }
diffs="$(comm -3 <(norm "$1") <(norm "$2") | sed 's/^\t/+ /; t; s/^/- /')"
printf '%s\n' "$diffs"
unexplained="$(grep -vEf "$HERE/parity-allowed.txt" <<<"$diffs" | grep . || true)"
if [[ -n $unexplained ]]; then
  printf '\nUnexplained differences:\n%s\n' "$unexplained" >&2
  exit 1
fi
