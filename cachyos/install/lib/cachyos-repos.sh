# shellcheck shell=bash
# CachyOS repo sections for the target's /etc/pacman.conf. Sourced by
# chroot-setup.sh (inside the chroot) and the unit tests; pure functions only.
#
# Replaces CachyOS's cachyos-repo.sh, which pins package URLs (keyring,
# mirrorlists, its own pacman) that go 404 whenever the mirror moves on. The
# keyring and mirrorlists come from pacstrap instead, resolved from the live
# ISO's [cachyos] repo, so they are always current; this only writes the
# sections. Same repo choice as upstream: the most specific level the CPU runs.

# <`/lib/ld-linux-x86-64.so.2 --help` output> <cpuinfo file>
# -> znver4 | v4 | v3, or nothing when the CPU is below x86-64-v3 (generic
# [cachyos] only). glibc lists the x86-64-vN levels it will load as
# "(supported, searched)". znver4 is AMD Zen 4/5; upstream asks
# `gcc -march=native`, which isn't in the target, so read cpuinfo: family 25
# is Zen 3 or 4, and only Zen 4 has AVX-512; family 26 is Zen 5.
cachyos_repo_level() {
  local ld="$1" cpuinfo="$2" vendor family flags
  if [[ $ld == *"x86-64-v4 (supported, searched)"* ]]; then
    vendor="$(awk -F': *' '/^vendor_id/ {print $2; exit}' "$cpuinfo")"
    family="$(awk -F': *' '/^cpu family/ {print $2; exit}' "$cpuinfo")"
    flags="$(awk -F': *' '/^flags/ {print $2; exit}' "$cpuinfo")"
    if [[ $vendor == AuthenticAMD ]] \
      && { [[ $family == 26 ]] || [[ $family == 25 && " $flags " == *" avx512f "* ]]; }; then
      echo znver4
    else
      echo v4
    fi
  elif [[ $ld == *"x86-64-v3 (supported, searched)"* ]]; then
    echo v3
  fi
}

# <level> -> the repo sections for pacman.conf, most specific first. The
# optimised repos take priority over [cachyos], which takes priority over Arch.
cachyos_repo_sections() {
  local level="$1" list repo
  case "$level" in
    v3) list=cachyos-v3-mirrorlist ;;
    v4 | znver4) list=cachyos-v4-mirrorlist ;;   # znver4 is served from the v4 mirrors
    "") ;;
    *) echo "cachyos_repo_sections: unknown level '$level'" >&2; return 1 ;;
  esac
  if [[ -n $level ]]; then
    for repo in "cachyos-$level" "cachyos-core-$level" "cachyos-extra-$level"; do
      printf '[%s]\nInclude = /etc/pacman.d/%s\n\n' "$repo" "$list"
    done
  fi
  printf '[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n\n'
}

# <pacman.conf> <level>: put the sections above the first repo (so they win
# over [core]) and set `Architecture = auto`, which CachyOS's pacman expands to
# the x86_64_v3/v4 package architectures. Idempotent: a config with any
# [cachyos*] section is left as it is.
add_cachyos_repos() {
  local conf="$1" level="$2" sections tmp
  [[ -f $conf ]] || { echo "add_cachyos_repos: no $conf" >&2; return 1; }
  sections="$(cachyos_repo_sections "$level")" || return 1
  grep -qE '^\[cachyos(-[a-z0-9]+)*\]' "$conf" && return 0
  tmp="$(mktemp)"
  SECTIONS="$sections" awk '
    function insert() {
      if (!arch) print "Architecture = auto\n"
      print ENVIRON["SECTIONS"] "\n"
      done = 1
    }
    /^\[/ && sect == "[options]" && $0 != "[options]" && !done { insert() }
    /^\[/ { sect = $0 }
    sect == "[options]" && /^Architecture[ \t]*=/ { print "Architecture = auto"; arch = 1; next }
    { print }
    END { if (!done) { print ""; insert() } }
  ' "$conf" >"$tmp" || { rm -f "$tmp"; return 1; }
  # Written back over the original so its owner and mode stay.
  cat "$tmp" >"$conf"
  rm -f "$tmp"
}
