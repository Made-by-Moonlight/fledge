#!/usr/bin/env bash
# Fail if code still uses Hyprland IPC that its Lua config refuses, mostly with
# exit 0 (so nothing else would notice): `hyprctl keyword`, `hyprctl --batch`/`-b`,
# `hyprctl dispatch <legacy string>` and QML's `Hyprland.dispatch(`. Use
# `fledge hypr dispatch|set|eval` or the QML `Hypr` singleton (AGENTS.md).
# Comment lines are skipped, and so are the places that hold these strings on
# purpose: docs, tests and their fixtures, and the v1 migration table.
#   bash cachyos/check-legacy-ipc.sh   (CI runs it)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

pattern='\bhyprctl\s+(?:-\S+\s+)*?(?:keyword(?:\s|$)|--batch(?:\s|$)|-b(?:\s|$)|dispatch\s+(?![\x27"]|hl\.)[a-z])|\bHyprland\.dispatch\('
hits="$(git grep -nIP "$pattern" -- . ':!docs' ':!*.md' ':!**/test/**' ':!**/test-*.sh' \
  ':!**/tst_*.qml' ':!dot-local/share/mbm/lib/migrate-dispatch.jq' ':!cachyos/check-legacy-ipc.sh' |
  grep -vP '^[^:]+:\d+:\s*(#|//|--)' || true)"
if [[ -n $hits ]]; then
  printf '%s\n' "$hits"
  echo "check-legacy-ipc: legacy Hyprland IPC above; use fledge hypr / Hypr instead" >&2
  exit 1
fi
echo "check-legacy-ipc: clean"
