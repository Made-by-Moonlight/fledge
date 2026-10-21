# shellcheck shell=bash
# Unattended-install answers. The ISO's fledge-install writes a root-only file
# under /run with one KEY=value per line (value = everything after the first
# '=', unquoted). It is parsed, never sourced, so a value can never run as code.

ANSWER_KEYS=(DISK DISK_CONFIRMED HOSTNAME TIMEZONE USERNAME USER_PASSWORD LUKS_PASSPHRASE ROOT_PASSWORD
             XKB_LAYOUT XKB_VARIANT DATA_MOUNTS DATA_WIPES)

# valid_username <name>  ->  0 for a safe login name: lowercase, starts with a
# letter or '_', then letters, digits, '_' or '-', at most 32; not a name the
# base system already uses.
valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  case "$1" in
    root|bin|daemon|mail|ftp|http|nobody|dbus|polkitd|systemd-*|git|sddm) return 1 ;;
  esac
}

# valid_hostname <name>  ->  0 for a single RFC 1123 label in lowercase
valid_hostname() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
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

# valid_xkb_layout <layouts> [base.lst]  ->  0 when every comma-separated
# layout is listed in the "! layout" section of xkeyboard-config's rules.
# The charset check first: the value reaches vconsole.conf and settings JSON.
valid_xkb_layout() {
  local spec="$1" lst="${2:-/usr/share/X11/xkb/rules/base.lst}" known l parts
  [[ "$spec" =~ ^[a-z0-9_]+(,[a-z0-9_]+)*$ ]] || return 1
  known="$(awk '/^! /{s = $2; next} s == "layout" && NF {print $1}' "$lst" 2>/dev/null)" || return 1
  IFS=, read -ra parts <<<"$spec"
  for l in "${parts[@]}"; do
    grep -qxF -- "$l" <<<"$known" || return 1
  done
}

# valid_xkb_variant <variant>  ->  0 for empty or plain xkb variant names
valid_xkb_variant() {
  [[ "$1" =~ ^[a-z0-9_-]*(,[a-z0-9_-]*)*$ ]]
}

# valid_mount_path <path>  ->  0 for an absolute, clean path that is safe to
# mount a data disk on: not a system tree, not a whole home, not /home or /mnt
# themselves, not hidden, not ~/proj. Mirrored in cachyos/iso/installer/lib/Validate.js.
valid_mount_path() {
  local p="$1" parts
  [[ "$p" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
  [[ "$p" == *//* || "$p" == */ || "$p/" == *"/./"* || "$p/" == *"/../"* ]] && return 1
  # Hidden folders (~/.config, ~/.local …) belong to the desktop, not to data.
  [[ "$p" == */.* ]] && return 1
  IFS=/ read -ra parts <<<"${p#/}"
  case "${parts[0]}" in
    boot|efi|usr|var|etc|bin|sbin|lib|lib64|root|run|proc|sys|dev|tmp|swap) return 1 ;;
    # ~/proj holds the staged repo the dotfile symlinks point into: a disk
    # mounted on it or inside it would hide it. Its ancestors (/home, a whole
    # home) are refused by the length check.
    home) (( ${#parts[@]} >= 3 )) || return 1
          [[ "${parts[2]}" != proj ]] || return 1 ;;
    mnt|srv|media|opt) (( ${#parts[@]} >= 2 )) || return 1 ;;
  esac
  return 0
}

# parse_data_mounts <"uuid:/path,uuid:/path">  ->  "uuid<TAB>path" lines.
# Empty spec -> nothing. Returns 1 (callers die) on a malformed entry, a path
# valid_mount_path refuses, or a uuid or path used twice.
parse_data_mounts() {
  local spec="$1" e uuid path seen=$'\n' entries
  [[ -n "$spec" ]] || return 0
  IFS=, read -ra entries <<<"$spec"
  for e in "${entries[@]}"; do
    [[ "$e" == *:* ]] || return 1
    uuid="${e%%:*}"; path="${e#*:}"
    [[ "$uuid" =~ ^[A-Za-z0-9-]+$ ]] || return 1
    valid_mount_path "$path" || return 1
    [[ "$seen" == *$'\n'"u:$uuid"$'\n'* || "$seen" == *$'\n'"p:$path"$'\n'* ]] && return 1
    seen+="u:$uuid"$'\n'"p:$path"$'\n'
    printf '%s\t%s\n' "$uuid" "$path"
  done
}

# valid_data_label <label>  ->  0 for a label a wiped data disk can carry: 1 to
# 16 bytes of printable ASCII, no edge space, no ':' or ',' (they separate the
# fields of DATA_WIPES). Bytes, not characters: the label becomes a filesystem
# label, and filesystem labels have a byte limit.
valid_data_label() {
  local LC_ALL=C l="$1" re='^[ -~]+$'
  (( ${#l} >= 1 && ${#l} <= 16 )) || return 1
  [[ "$l" =~ $re ]] || return 1
  [[ "$l" != " "* && "$l" != *" " ]] || return 1
  [[ "$l" != *[:,]* ]]
}

# parse_data_wipes <"label:folder:disk,label:folder:disk">  ->
# "disk<TAB>folder<TAB>label" lines. Empty spec -> nothing. The label is up to
# the first ':', the folder up to the second, the disk is the rest (a
# /dev/disk/by-id name can hold a ':'). Returns 1 (callers die) on a malformed
# entry, a label valid_data_label refuses, a folder valid_mount_path refuses, a
# disk that is not a /dev node, or a disk, folder or label (lowercased) used twice.
# Output is held back until every entry checks out, so a failure prints nothing.
parse_data_wipes() {
  local spec="$1" e label lc path disk rest seen=$'\n' entries out=""
  [[ -n "$spec" ]] || return 0
  IFS=, read -ra entries <<<"$spec"
  for e in "${entries[@]}"; do
    [[ "$e" == *:*:* ]] || return 1
    label="${e%%:*}"; rest="${e#*:}"; path="${rest%%:*}"; disk="${rest#*:}"
    valid_data_label "$label" || return 1
    valid_mount_path "$path" || return 1
    [[ "$disk" =~ ^/dev/[^,[:space:]]+$ ]] || return 1
    lc="${label,,}"
    [[ "$seen" == *$'\n'"l:$lc"$'\n'* || "$seen" == *$'\n'"p:$path"$'\n'* \
       || "$seen" == *$'\n'"d:$disk"$'\n'* ]] && return 1
    seen+="l:$lc"$'\n'"p:$path"$'\n'"d:$disk"$'\n'
    out+="$disk"$'\t'"$path"$'\t'"$label"$'\n'
  done
  printf '%s' "$out"
}
