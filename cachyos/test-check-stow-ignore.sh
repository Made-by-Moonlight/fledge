#!/usr/bin/env bash
# Tests for check-stow-ignore.sh: the repo passes, and a copy of its top level
# with one new, unlisted entry fails and names it.
#   bash cachyos/test-check-stow-ignore.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/install/test/lib.sh
source "$DIR/install/test/lib.sh"
GUARD="$DIR/check-stow-ignore.sh"
REPO="$(dirname "$DIR")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

out="$(bash "$GUARD" "$REPO" 2>&1)"; rc=$?
check "repo passes" 0 "$rc"
contains "repo reports clean" "check-stow-ignore: clean" "$out"

# A small tree shaped like the repo: the real ignore file, each tracked
# top-level entry as an empty file or dir, plus dot-* trees.
mk_tree() { # <dir>
  local d=$1 e
  mkdir -p "$d/dot-config/app" "$d/dot-local/share"
  : >"$d/dot-config/app/x"; : >"$d/dot-mise.toml"
  cp "$REPO/.stow-local-ignore" "$d/"
  while IFS= read -r e; do
    [[ $e == dot-* || -e $d/$e ]] && continue
    if [[ -d $REPO/$e ]]; then mkdir -p "$d/$e"; : >"$d/$e/f"; else : >"$d/$e"; fi
  done < <(git -C "$REPO" ls-files | cut -d/ -f1 | sort -u)
}

mk_tree "$T/ok"
out="$(bash "$GUARD" "$T/ok" 2>&1)"; rc=$?
check "copy of the top level passes" 0 "$rc"

mk_tree "$T/newdir"; mkdir "$T/newdir/tools"; : >"$T/newdir/tools/x"
out="$(bash "$GUARD" "$T/newdir" 2>&1)"; rc=$?
check "new top-level dir fails" 1 "$rc"
contains "new top-level dir is named" "would link tools into ~" "$out"

mk_tree "$T/newfile"; : >"$T/newfile/CONTRIBUTING.md"
out="$(bash "$GUARD" "$T/newfile" 2>&1)"; rc=$?
check "new top-level file fails" 1 "$rc"
contains "new top-level file is named" "would link CONTRIBUTING.md into ~" "$out"

# .github is not covered by stow's \.git default (segments match whole names).
mk_tree "$T/nogithub"; sed -i '/^\^\/\\\.github$/d' "$T/nogithub/.stow-local-ignore"
out="$(bash "$GUARD" "$T/nogithub" 2>&1)"; rc=$?
check "dropping the .github line fails" 1 "$rc"
contains "dropped .github is named" "would link .github into ~" "$out"

exit $fail
