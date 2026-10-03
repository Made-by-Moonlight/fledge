# shellcheck shell=bash
# Unattended-install answers. The ISO configurator (mbm-configurator) writes a
# root-only file under /run with one KEY=value per line (value = everything
# after the first '=', unquoted). It is parsed, never sourced, so a value can
# never run as code.

ANSWER_KEYS=(DISK DISK_CONFIRMED HOSTNAME TIMEZONE USERNAME USER_PASSWORD LUKS_PASSPHRASE ROOT_PASSWORD)

# valid_username <name>  ->  0 for a safe login name: lowercase, starts with a
# letter or '_', then letters, digits, '_' or '-', at most 32; not a name the
# base system already uses.
valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  case "$1" in
    root|bin|daemon|mail|ftp|http|nobody|dbus|polkitd|systemd-*|git|sddm) return 1 ;;
  esac
}

# load_answers <file>  ->  sets the ANSWER_KEYS globals present in the file,
# then deletes it. Returns 1 (file kept) on any problem. Never echoes a value.
load_answers() {
  local file="$1" line key value mode n=0
  [[ -f "$file" ]] || { echo "answers: file not found: $file" >&2; return 1; }
  mode="$(stat -c '%a' "$file")"
  [[ "$mode" == 600 || "$mode" == 400 ]] \
    || { echo "answers: $file must be mode 600 (is $mode)" >&2; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || { echo "answers: line $n is not KEY=value" >&2; return 1; }
    key="${line%%=*}"; value="${line#*=}"
    if [[ " ${ANSWER_KEYS[*]} " != *" $key "* ]]; then
      echo "answers: unknown key on line $n" >&2; return 1
    fi
    printf -v "$key" '%s' "$value"
  done < "$file"
  rm -f -- "$file"
}
