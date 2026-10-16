#!/usr/bin/env bash
# Unit tests for lib/cachyos-repos.sh, run against fixtures (cpuinfo, ld.so
# --help output, a stock pacman.conf). Edits only temporary copies.
#   bash cachyos/install/test-cachyos-repos.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cachyos-repos.sh
source "$DIR/lib/cachyos-repos.sh"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
FIX="$DIR/test/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ld_v4="$(cat "$FIX/ldso-help-v4")"
ld_v3="$(cat "$FIX/ldso-help-v3")"
ld_v2="$(cat "$FIX/ldso-help-v2")"

# --- level ---------------------------------------------------------------
check "level zen4 + v4"          znver4 "$(cachyos_repo_level "$ld_v4" "$FIX/cpuinfo-zen4")"
check "level zen5 + v4"          znver4 "$(cachyos_repo_level "$ld_v4" "$FIX/cpuinfo-zen5")"
check "level zen3 (no avx512f)"  v3     "$(cachyos_repo_level "$ld_v3" "$FIX/cpuinfo-zen3")"
check "level zen4, v4 masked"    v3     "$(cachyos_repo_level "$ld_v3" "$FIX/cpuinfo-zen4")"
check "level intel avx512 + v4"  v4     "$(cachyos_repo_level "$ld_v4" "$FIX/cpuinfo-intel-avx512")"
check "level intel v3"           v3     "$(cachyos_repo_level "$ld_v3" "$FIX/cpuinfo-intel")"
check "level v2 only: none"      ""     "$(cachyos_repo_level "$ld_v2" "$FIX/cpuinfo-intel")"
check "level zen4, v2 only"      ""     "$(cachyos_repo_level "$ld_v2" "$FIX/cpuinfo-zen4")"
check "level empty ld text"      ""     "$(cachyos_repo_level "" "$FIX/cpuinfo-zen4")"

# --- sections ------------------------------------------------------------
headers() { grep -E '^\[' | tr '\n' ' '; }
check "sections v3 headers" "[cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3] [cachyos] " \
  "$(cachyos_repo_sections v3 | headers)"
check "sections v4 headers" "[cachyos-v4] [cachyos-core-v4] [cachyos-extra-v4] [cachyos] " \
  "$(cachyos_repo_sections v4 | headers)"
check "sections znver4 headers" "[cachyos-znver4] [cachyos-core-znver4] [cachyos-extra-znver4] [cachyos] " \
  "$(cachyos_repo_sections znver4 | headers)"
check "sections none headers" "[cachyos] " "$(cachyos_repo_sections "" | headers)"

v3="$(cachyos_repo_sections v3)"
contains "v3 core uses the v3 list" $'[cachyos-core-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist' "$v3"
contains "v3 generic uses the plain list" $'[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist' "$v3"
check "v3: three v3-list includes" 3 "$(grep -c 'cachyos-v3-mirrorlist$' <<<"$v3")"
check "v4: three v4-list includes" 3 "$(cachyos_repo_sections v4 | grep -c 'cachyos-v4-mirrorlist$')"
check "znver4: three v4-list includes" 3 "$(cachyos_repo_sections znver4 | grep -c 'cachyos-v4-mirrorlist$')"
check "none: one plain include" "Include = /etc/pacman.d/cachyos-mirrorlist" \
  "$(cachyos_repo_sections "" | grep '^Include')"
check "unknown level rejected" 1 "$(cachyos_repo_sections v5 >/dev/null 2>&1; echo $?)"

# --- add to pacman.conf --------------------------------------------------
conf="$TMP/pacman.conf"
cp "$FIX/pacman.conf-stock" "$conf"
add_cachyos_repos "$conf" znver4
check "add: rc 0" 0 "$?"
check "add: repo order" "[options] [cachyos-znver4] [cachyos-core-znver4] [cachyos-extra-znver4] [cachyos] [core] [extra] " \
  "$(headers <"$conf")"
check "add: Architecture = auto, once" "Architecture = auto" "$(grep '^Architecture' "$conf")"
check "add: Architecture stays in [options]" "[options]" \
  "$(awk '/^\[/ {s=$0} /^Architecture/ {print s}' "$conf")"
check "add: rest of the file untouched" "" \
  "$(diff <(grep -v '^Architecture' "$FIX/pacman.conf-stock") <(grep -v '^Architecture' "$conf") | grep '^<')"
contains "add: commented repos kept" "#[multilib]" "$(cat "$conf")"
contains "add: blank line before [core]" $'cachyos-mirrorlist\n\n' "$(cat "$conf")"

cp "$conf" "$TMP/once"
add_cachyos_repos "$conf" znver4
check "add twice: unchanged" "" "$(diff "$TMP/once" "$conf")"
add_cachyos_repos "$conf" v3
check "add other level: unchanged (any cachyos section counts)" "" "$(diff "$TMP/once" "$conf")"

# A config that already has the generic [cachyos] (e.g. CachyOS's own) is left alone.
cp "$FIX/pacman.conf-stock" "$TMP/generic"
printf '[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n' >>"$TMP/generic"
cp "$TMP/generic" "$TMP/generic.orig"
add_cachyos_repos "$TMP/generic" v3
check "existing [cachyos]: unchanged" "" "$(diff "$TMP/generic.orig" "$TMP/generic")"

# No Architecture line (only a commented one): one is added inside [options].
grep -v '^Architecture' "$FIX/pacman.conf-stock" | sed 's/^#CleanMethod.*/&\n#Architecture = auto/' >"$TMP/noarch"
add_cachyos_repos "$TMP/noarch" v3
check "no Architecture: added once" "Architecture = auto" "$(grep '^Architecture' "$TMP/noarch")"
check "no Architecture: added in [options]" "[options]" \
  "$(awk '/^\[/ {s=$0} /^Architecture/ {print s}' "$TMP/noarch")"
check "no Architecture: v3 order" "[options] [cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3] [cachyos] [core] [extra] " \
  "$(headers <"$TMP/noarch")"

# Level none: only [cachyos], still above [core].
cp "$FIX/pacman.conf-stock" "$TMP/none"
add_cachyos_repos "$TMP/none" ""
check "none: order" "[options] [cachyos] [core] [extra] " "$(headers <"$TMP/none")"

# Mode is kept (the file is rewritten in place, not replaced).
cp "$FIX/pacman.conf-stock" "$TMP/mode"; chmod 640 "$TMP/mode"
add_cachyos_repos "$TMP/mode" v4
check "mode kept" 640 "$(stat -c %a "$TMP/mode")"

check "missing file fails" 1 "$(add_cachyos_repos "$TMP/nope" v3 2>/dev/null; echo $?)"
check "unknown level fails, file untouched" "1 " \
  "$(cp "$FIX/pacman.conf-stock" "$TMP/bad"; add_cachyos_repos "$TMP/bad" v5 2>/dev/null; echo "$? $(diff "$FIX/pacman.conf-stock" "$TMP/bad")")"

exit $fail
