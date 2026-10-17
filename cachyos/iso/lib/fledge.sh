# shellcheck shell=bash
# Helpers for the live ISO's installer scripts (fledge-probe, fledge-install). Pure where
# possible so test-iso-lib.sh can cover them without an ISO. (valid_hostname lives in
# cachyos/install/lib/answers.sh, where install-cachyos.sh checks the answers.)

# write_answers <file> KEY=value...  ->  mode-600 answers file for
# install-cachyos.sh --answers (one KEY=value per line, unquoted). Refuses,
# and removes the file, if any argument contains a newline.
write_answers() {
  local file="$1" kv; shift
  ( umask 077; : > "$file" )
  chmod 600 "$file"
  for kv in "$@"; do
    if [[ "$kv" == *$'\n'* ]]; then
      echo "write_answers: a value contains a newline" >&2
      rm -f -- "$file"; return 1
    fi
    printf '%s\n' "$kv" >> "$file"
  done
}

# fledge_online  ->  0 if the CachyOS mirror answers (pacstrap needs it)
fledge_online() {
  curl -fsI --max-time 5 https://mirror.cachyos.org >/dev/null 2>&1
}
