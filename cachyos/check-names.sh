#!/usr/bin/env bash
# Fail if an old name is back. The product is fledge; these went in the rename
# (docs/superpowers/specs/2026-10-18-fledge-rename-design.md):
#   slievr             the user's handle, once the repo, scripts and themes
#   mbm, mbm-, mbm_    the shell, CLI and config dirs (MBM_* env vars too)
#   made-by-moonlight  the old theme name (the byline "made by moonlight",
#                      with spaces, is the brand and always fine)
# Checked case-insensitively in the contents and paths of the files git sees
# (tracked, plus untracked ones not ignored). A hit passes only through the
# allowlist below: a whole history file, or a file plus the exact text allowed
# there. That text is cut out of the line and the line is checked again, so a
# second, unallowed name on the same line still fails.
#   bash cachyos/check-names.sh [ROOT]   (CI runs it; ROOT defaults to this repo)
set -euo pipefail
cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}"

# Bash/git ERE over lowercased text, so `MBM_` and `Slievr` count. mbm is a
# whole word or a prefix (`mbm-shell`, `mbm_x`); `\b` alone would miss `mbm_`.
forbidden='slievr|(^|[^a-z0-9_])mbm([^a-z0-9_]|$)|mbm[-_]|made[-_]?by[-_]?moonlight'

# Whole files that keep old names on purpose.
whole_files=(
  cachyos/check-names.sh            # this guard: its patterns are the names
  cachyos/test-check-names.sh       # its test: every form, forbidden and allowed
  dot-local/share/fledge/test/fixtures/defaults-v1.json   # frozen v1 defaults (slievr-* binds)
  # The rename's own docs, which have to name what was renamed.
  docs/superpowers/specs/2026-10-18-fledge-rename-design.md
  docs/superpowers/plans/2026-10-18-fledge-rename.md
  docs/superpowers/notes/2026-10-18-script-inventory.md
)
# History: specs, plans and notes written before the rename keep their names
# (file names included) and are never edited to follow a rename.
history_re='^docs/superpowers/(specs|plans|notes)/([0-9]{4}-[0-9]{2}-[0-9]{2})-[^/]*$'
is_history() {
  [[ $1 =~ $history_re && ${BASH_REMATCH[2]} < 2026-10-18 ]]
}

# File glob <TAB> ERE (lowercase) of the text allowed in it.
rules=(
  # The default username stays slievr (the user's account, not the brand).
  $'cachyos/install/profile.sh\t^username="slievr"'
  $'cachyos/vm/vm.sh\t^vm_user="\\$\\{vm_user:-slievr\\}"'
  $'cachyos/vm/dev-up.sh\t^vm_user="slievr"'
  $'cachyos/vm/README.md\t~slievr/proj/|using `slievr` /'
  $'cachyos/iso/README.md\t"slievr@\\$ip'
  $'cachyos/iso/test/verify-install.sh\t"slievr@\\$ip|run as slievr '
  $'AGENTS.md\t`slievr` is the user\'s handle|the old names \\(`slievr`, `mbm`, `made-by-moonlight`\\)'
  # The test of the v1 -> v2 migration: the old strings it rewrites.
  $'dot-local/share/fledge/test/test-migrate.sh\tslievr|b970944:dot-local/share/mbm/'
  # The GitHub org (Made-by-Moonlight; GitHub matches it case-insensitively).
  $'*\tgithub\\.com/made-by-moonlight/'
)

mapfile -t files < <(git ls-files -co --exclude-standard)
excludes=()
fail=0
for f in "${files[@]}"; do
  # git still lists a tracked file deleted in the working tree.
  [[ -e $f || -L $f ]] || continue
  allowed=0
  if is_history "$f"; then
    allowed=1
    # Citing a history doc by its (old) name is fine anywhere.
    base="${f##*/}"
    [[ ${base,,} =~ $forbidden ]] && rules+=("*"$'\t'"${base//./\\.}")
  fi
  for w in "${whole_files[@]}"; do [[ $f == "$w" ]] && allowed=1; done
  if (( allowed )); then
    excludes+=(":(exclude,literal)$f")
  elif [[ ${f,,} =~ $forbidden ]]; then
    printf '%s: old name in the path\n' "$f"
    fail=1
  fi
done

# Cut every match of each rule that applies to <file> out of <text>.
strip_allowed() { # <file> <text>
  local f=$1 s=$2 r glob re
  for r in "${rules[@]}"; do
    glob=${r%%$'\t'*} re=${r#*$'\t'}
    # shellcheck disable=SC2053  # the rule's file is a glob on purpose
    [[ $f == $glob ]] || continue
    while [[ $s =~ $re && -n ${BASH_REMATCH[0]} ]]; do
      s=${s/"${BASH_REMATCH[0]}"/ }
    done
  done
  printf '%s' "$s"
}

while IFS= read -r hit; do
  f=${hit%%:*} rest=${hit#*:}
  text=${rest#*:}
  left="$(strip_allowed "$f" "${text,,}")"
  if [[ $left =~ $forbidden ]]; then
    printf '%s\n' "$hit"
    fail=1
  fi
done < <(git grep --untracked -nIiE "$forbidden" -- . "${excludes[@]}" || true)

if (( fail )); then
  echo "check-names: old names above (slievr, mbm, made-by-moonlight); use fledge, or allowlist a real exception in cachyos/check-names.sh" >&2
  exit 1
fi
echo "check-names: clean"
