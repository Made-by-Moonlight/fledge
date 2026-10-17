#!/usr/bin/env bash
# Fail if stow would link anything but the dot-* trees into ~. .stow-local-ignore
# names the project's top-level entries one by one (a negative pattern would
# hide dot-config too, see its comment), so a new top-level entry lands in ~
# until someone adds it there. This asks stow itself, in a dry run into an
# empty target, rather than re-implementing its ignore rules.
#   bash cachyos/check-stow-ignore.sh [ROOT]   (CI runs it; ROOT defaults to this repo)
set -euo pipefail
root="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
command -v stow >/dev/null || { echo "check-stow-ignore: needs stow" >&2; exit 2; }
target="$(mktemp -d)"; trap 'rm -rf "$target"' EXIT

# Same invocation as bootstrap.sh and vm.sh restow; -n -v prints
# "LINK: <name> => <relative path to the source>" and changes nothing. Into an
# empty target every top-level entry folds to one link.
out="$(cd "$root" && stow --dotfiles -n -v -t "$target" . 2>&1)" || {
  printf '%s\n' "$out" >&2; echo "check-stow-ignore: stow failed" >&2; exit 2; }

# The source's top-level entry in the repo, whether stow folded it to one link
# or linked the files inside it (it can't fold a dot-* dir on some versions).
bad=()
while IFS= read -r line; do
  [[ $line == LINK:*' => '* ]] || continue
  name="${line#LINK: }"; name="${name%% => *}"
  src="$(realpath -m "$target/$(dirname "$name")/${line##* => }")"
  top="${src#"$root"/}"; top="${top%%/*}"
  [[ $top == dot-* ]] || bad+=("$top")
done <<<"$out"
mapfile -t bad < <(printf '%s\n' "${bad[@]}" | sort -u | grep .)

if ((${#bad[@]})); then
  printf 'check-stow-ignore: stow would link %s into ~; add a ^/<name> line to .stow-local-ignore\n' "${bad[@]}" >&2
  exit 1
fi
echo "check-stow-ignore: clean"
