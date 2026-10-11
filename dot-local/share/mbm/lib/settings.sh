# shellcheck shell=bash
# mbm settings: shipped defaults + the user's overrides -> one merged state
# file (read live by the shell) + generated Hyprland config. The merge and the
# validation live only here, so the shell and bootstrap can't disagree.
# Every path can be overridden from the environment (the tests use a temp HOME).

MBM_DEFAULTS="${MBM_DEFAULTS:-$MBM_ROOT/defaults/settings.json}"
MBM_CONFIG_DIR="${MBM_CONFIG_DIR:-$HOME/.config/mbm}"
MBM_STATE_DIR="${MBM_STATE_DIR:-$HOME/.local/state/mbm}"
MBM_HYPR_DIR="${MBM_HYPR_DIR:-$HOME/.config/hypr/mbm}"
MBM_USER="$MBM_CONFIG_DIR/settings.json"
MBM_MERGED="$MBM_STATE_DIR/settings.json"

die() { printf 'mbm: %s\n' "$*" >&2; exit 1; }

# atomic_write <file>: stdin -> temp file beside <file>, then mv, so readers
# (Hyprland, the shell's file watcher) never see a half-written file.
atomic_write() {
  local dest="$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "$dest.XXXXXX")"
  if cat >"$tmp"; then
    mv -f "$tmp" "$dest"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Only jq *paths* are accepted (.a.b, .a["id.with.dots"]), never arbitrary
# filters: the settings window passes these through.
valid_path() {
  local re='^(\.[A-Za-z_][A-Za-z0-9_]*|\["[^"\\]*"\])+$'
  [[ $1 =~ $re ]]
}

user_json() { # the overrides, or {} when there are none
  if [[ -f $MBM_USER ]]; then
    jq -e 'if type == "object" then . else error("not an object") end' "$MBM_USER" 2>/dev/null \
      || die "$MBM_USER is not a valid JSON object"
  else
    echo '{}'
  fi
}

# merge <user-json>: defaults * overrides; a bind or workspace overridden with null is removed.
merge() {
  jq -n --slurpfile d "$MBM_DEFAULTS" --argjson u "$1" \
    '($d[0] * $u) | .binds |= with_entries(select(.value != null))
     | if has("workspaces") then .workspaces |= with_entries(select(.value != null)) else . end'
}

merged_json() {
  local user
  user="$(user_json)" || exit 1
  merge "$user"
}

# check_json <merged-json>: 0 when valid; one problem per line on stderr.
check_json() {
  local errs
  errs="$(jq -r -f "$MBM_ROOT/lib/check.jq" <<<"$1")" || return 1
  [[ -z $errs ]] && return 0
  printf '%s\n' "$errs" >&2
  return 1
}

refresh_state() {
  local out
  out="$(merged_json)" || exit 1
  printf '%s\n' "$out" | atomic_write "$MBM_MERGED"
}

# write_user <new-user-json>: validate the merged result first; write nothing if it fails.
write_user() {
  local merged
  merged="$(merge "$1")" || die "could not merge settings"
  check_json "$merged" || die "change refused: the settings would be invalid"
  printf '%s\n' "$1" | atomic_write "$MBM_USER"
  printf '%s\n' "$merged" | atomic_write "$MBM_MERGED"
}

# get takes any jq filter, not just a path: it only reads, and callers (and
# the tests) want things like '.binds | has("x")'. Only set/reset write, so
# only they are restricted to plain paths.
settings_get() {
  local path="${1:-.}"
  local merged
  merged="$(merged_json)" || exit 1
  jq "$path" <<<"$merged"
}

settings_set() {
  (($# >= 2 && $# % 2 == 0)) || die "usage: mbm settings set <path> <json> [<path> <json>]..."
  local user filter='.' i=0 out
  local -a args=()
  user="$(user_json)" || exit 1
  while (($#)); do
    valid_path "$1" || die "bad settings path: $1"
    jq -n --argjson v "$2" 'true' >/dev/null 2>&1 || die "not JSON: $2"
    filter+=" | setpath(path($1); \$v$i)"
    args+=(--argjson "v$i" "$2")
    i=$((i + 1))
    shift 2
  done
  out="$(jq "${args[@]}" "$filter" <<<"$user")" || die "could not apply the change"
  write_user "$out"
}

settings_reset() {
  (($# >= 1)) || die "usage: mbm settings reset <path>..."
  local user filter='.' out p
  user="$(user_json)" || exit 1
  for p in "$@"; do
    valid_path "$p" || die "bad settings path: $p"
    filter+=" | delpaths([path($p)])"
  done
  out="$(jq "$filter" <<<"$user")" || die "could not reset"
  write_user "$out"
}

settings_check() {
  local merged
  merged="$(merged_json)" || exit 1
  check_json "$merged" || exit 1
}

settings_apply() {
  local merged binds monitors input workspaces
  merged="$(merged_json)" || exit 1
  check_json "$merged" || die "settings are invalid; nothing applied"
  # Render everything before writing anything, so a jq failure can't leave a mix.
  binds="$(jq -r -f "$MBM_ROOT/lib/gen-binds.jq" <<<"$merged")" || die "could not generate binds"
  monitors="$(jq -r -f "$MBM_ROOT/lib/gen-monitors.jq" <<<"$merged")" || die "could not generate monitors"
  input="$(jq -r -f "$MBM_ROOT/lib/gen-input.jq" <<<"$merged")" || die "could not generate input"
  workspaces="$(jq -r -f "$MBM_ROOT/lib/gen-workspaces.jq" <<<"$merged")" || die "could not generate workspaces"
  printf '%s\n' "$binds" | atomic_write "$MBM_HYPR_DIR/binds.conf"
  printf '%s\n' "$monitors" | atomic_write "$MBM_HYPR_DIR/monitors.conf"
  printf '%s\n' "$workspaces" | atomic_write "$MBM_HYPR_DIR/workspaces.conf"
  printf '%s\n' "$input" | atomic_write "$MBM_HYPR_DIR/input.conf"
  printf '%s\n' "$merged" | atomic_write "$MBM_MERGED"
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -z ${MBM_NO_RELOAD:-} ]]; then
    hyprctl reload >/dev/null
  fi
}

settings_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    get) settings_get "$@" ;;
    set) settings_set "$@" ;;
    reset) settings_reset "$@" ;;
    check) settings_check ;;
    apply) settings_apply ;;
    *) die "usage: mbm settings get|set|reset|check|apply" ;;
  esac
}
