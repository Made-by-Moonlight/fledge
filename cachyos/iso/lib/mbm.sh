# shellcheck shell=bash
# Helpers for the made by moonlight live-ISO configurator. Pure where
# possible so test-mbm.sh can cover them without an ISO.

# valid_hostname <name>  ->  0 for a single RFC 1123 label in lowercase
valid_hostname() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

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

# mask_answers <file>  ->  the file with password values replaced by ********
mask_answers() {
  sed -E 's/^((USER_PASSWORD|LUKS_PASSPHRASE|ROOT_PASSWORD)=).*/\1********/' "$1"
}

# mbm_online  ->  0 if the CachyOS mirror answers (pacstrap needs it)
mbm_online() {
  curl -fsI --max-time 5 https://mirror.cachyos.org >/dev/null 2>&1
}

# Network names from `iwctl station DEV get-networks` on stdin, one per line.
# Rows are "[>] NAME  SECURITY  SIGNAL" padded with trailing spaces; names may
# contain spaces, so strip the known columns from the right, not by field count.
parse_networks() {
  sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | awk '
    NR <= 4 { next }                                  # title, rules, header
    {
      line = $0
      sub(/[ \t]+$/, "", line)                        # row padding
      sub(/^[ \t]*>?[ \t]*/, "", line)                # connected marker
      sub(/[ \t]+\*+$/, "", line)                     # signal stars
      if (!sub(/[ \t]+(open|psk|8021x|wep|owe|sae|wpa3-personal)$/, "", line)) next
      if (line != "") print line
    }'
}
