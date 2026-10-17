# shellcheck shell=bash
# fledge settings: shipped defaults + the user's overrides -> one merged state
# file (read live by the shell) + generated Hyprland config. The merge and the
# validation live only here, so the shell and bootstrap can't disagree.
# Every path can be overridden from the environment (the tests use a temp HOME).

FLEDGE_DEFAULTS="${FLEDGE_DEFAULTS:-$FLEDGE_ROOT/defaults/settings.json}"
FLEDGE_CONFIG_DIR="${FLEDGE_CONFIG_DIR:-$HOME/.config/fledge}"
FLEDGE_STATE_DIR="${FLEDGE_STATE_DIR:-$HOME/.local/state/fledge}"
FLEDGE_HYPR_DIR="${FLEDGE_HYPR_DIR:-$HOME/.local/state/fledge/hypr}"
FLEDGE_USER="$FLEDGE_CONFIG_DIR/settings.json"
FLEDGE_MERGED="$FLEDGE_STATE_DIR/settings.json"

die() { printf 'fledge settings: %s\n' "$*" >&2; exit 1; }

# atomic_write <file>: stdin -> temp file beside <file>, then mv, so readers
# (Hyprland, the shell's file watcher) never see a half-written file. An
# existing file keeps its mode (mktemp alone would make it 0600).
atomic_write() {
  local dest="$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "$dest.XXXXXX")"
  if cat >"$tmp" && { [[ ! -e $dest ]] || chmod --reference="$dest" "$tmp"; }; then
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

# Set by the commands that write the user file (set, reset, apply): only they
# write a migrated file back, and they hold the settings lock while doing it.
FLEDGE_WRITE_MIGRATION=""

user_json() { # the overrides as settings v2, or {} when there are none
  # A missing, empty or whitespace-only file means no overrides (a user who empties
  # the file must not break every later write).
  local raw="" content
  if [[ -f $FLEDGE_USER ]]; then
    raw="$(<"$FLEDGE_USER")" || die "cannot read $FLEDGE_USER"
  fi
  if [[ -n ${raw//[[:space:]]/} ]]; then
    content="$(jq -e 'if type == "object" then . else error("not an object") end' <<<"$raw" 2>/dev/null)" \
      || die "$FLEDGE_USER is not a valid JSON object"
    migrate_user_file "$content" "$raw"
  else
    echo '{}'
  fi
}

# migrate_user_file <user-json> <file-content>: prints the overrides as settings
# v2. A v1 file (legacy {"dispatch": "…"} strings, which Hyprland's Lua config
# can't run) is converted; get and check do it in memory only, so a read never
# races a writer or needs a writable config dir. set/reset/apply write the result
# back, keeping what was read as settings.json.v1. An existing backup is never
# replaced: the first one holds the user's real original. Whatever the table
# can't convert stays as {dispatch}; `check` names it.
migrate_user_file() {
  local lib="$FLEDGE_ROOT/lib" out backup="$FLEDGE_USER.v1" kept="backup"
  if [[ $(jq -L "$lib" 'include "migrate-dispatch"; needs_migration' <<<"$1") != true ]]; then
    printf '%s\n' "$1"
    return
  fi
  out="$(jq -L "$lib" 'include "migrate-dispatch"; migrate_user' <<<"$1")" || die "could not migrate $FLEDGE_USER"
  if [[ -n $FLEDGE_WRITE_MIGRATION ]]; then
    if [[ -e $backup ]]; then
      kept="earlier backup kept"
    else
      printf '%s\n' "$2" | atomic_write "$backup" && chmod --reference="$FLEDGE_USER" "$backup" \
        || die "could not back up $FLEDGE_USER"
    fi
    jq '.settings' <<<"$out" | atomic_write "$FLEDGE_USER" || die "could not write $FLEDGE_USER"
    printf 'fledge settings: migrated %s binds to settings v2, %s could not be converted (%s: %s)\n' \
      "$(jq .count <<<"$out")" "$(jq .unconverted <<<"$out")" "$kept" "$backup" >&2
  fi
  jq '.settings' <<<"$out"
}

# lock_settings: hold the settings lock until the command exits, so concurrent
# writers (the settings window, a script, a migration) serialise their
# read-modify-write of the user file instead of losing each other's changes.
# The wait is bounded: env-hyprland runs apply at login, and a hung holder must
# not stall the session start.
lock_settings() {
  local lock="$FLEDGE_CONFIG_DIR/.lock" wait="${FLEDGE_LOCK_TIMEOUT:-10}"
  # flock reads a bad -w as "wait for ever" or fails with its own puzzling message.
  [[ $wait =~ ^[0-9]+$ ]] || die "FLEDGE_LOCK_TIMEOUT must be a whole number of seconds (got \"$wait\")"
  mkdir -p "$FLEDGE_CONFIG_DIR" || die "cannot create $FLEDGE_CONFIG_DIR"
  exec 9>"$lock" || die "cannot open $lock"
  flock -w "$wait" 9 || die "settings are busy: another fledge settings command holds $lock (waited ${wait}s)"
  FLEDGE_WRITE_MIGRATION=1
}

# merge <user-json>: defaults * overrides; a bind or workspace overridden with null
# is removed, and a bind's action is replaced, not merged.
merge() {
  jq -n --slurpfile d "$FLEDGE_DEFAULTS" --argjson u "$1" \
    '($d[0] * $u)
     # An overridden action replaces the default one whole: a deep merge would mix
     # the args of two dispatchers (e.g. {direction, workspace} on one focus).
     | reduce ($u.binds | objects | to_entries[] | select(.value | type == "object" and has("action"))) as $e
         (.; .binds[$e.key].action = $e.value.action)
     | .binds |= with_entries(select(.value != null))
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
  errs="$(jq -r --slurpfile dsp "$FLEDGE_ROOT/lib/dsp-names.json" -f "$FLEDGE_ROOT/lib/check.jq" <<<"$1")" || return 1
  [[ -z $errs ]] && return 0
  printf '%s\n' "$errs" >&2
  return 1
}

refresh_state() {
  local out
  out="$(merged_json)" || exit 1
  printf '%s\n' "$out" | atomic_write "$FLEDGE_MERGED"
}

# write_user <new-user-json>: validate the merged result first; write nothing if it fails.
write_user() {
  local merged
  merged="$(merge "$1")" || die "could not merge settings"
  check_json "$merged" || die "change refused: the settings would be invalid"
  printf '%s\n' "$1" | atomic_write "$FLEDGE_USER"
  printf '%s\n' "$merged" | atomic_write "$FLEDGE_MERGED"
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
  (($# >= 2 && $# % 2 == 0)) || die "usage: fledge settings set <path> <json> [<path> <json>]..."
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
  (($# >= 1)) || die "usage: fledge settings reset <path>..."
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
  local merged binds monitors input workspaces f lib="$FLEDGE_ROOT/lib"
  merged="$(merged_json)" || exit 1
  check_json "$merged" || die "settings are invalid; nothing applied"
  # Render everything before writing anything, so a jq failure can't leave a mix.
  binds="$(jq -r -L "$lib" -f "$lib/gen-binds.jq" <<<"$merged")" || die "could not generate binds"
  monitors="$(jq -r -L "$lib" -f "$lib/gen-monitors.jq" <<<"$merged")" || die "could not generate monitors"
  input="$(jq -r -L "$lib" -f "$lib/gen-input.jq" <<<"$merged")" || die "could not generate input"
  workspaces="$(jq -r -L "$lib" -f "$lib/gen-workspaces.jq" <<<"$merged")" || die "could not generate workspaces"
  printf '%s\n' "$binds" | atomic_write "$FLEDGE_HYPR_DIR/binds.lua"
  printf '%s\n' "$monitors" | atomic_write "$FLEDGE_HYPR_DIR/monitors.lua"
  printf '%s\n' "$workspaces" | atomic_write "$FLEDGE_HYPR_DIR/workspaces.lua"
  printf '%s\n' "$input" | atomic_write "$FLEDGE_HYPR_DIR/input.lua"
  # The .conf fragments from before the Lua config: nothing loads them now, and a
  # stale one would only mislead. Only the names apply ever wrote are removed.
  for f in binds monitors workspaces input; do
    rm -f "$FLEDGE_HYPR_DIR/$f.conf"
  done
  printf '%s\n' "$merged" | atomic_write "$FLEDGE_MERGED"
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -z ${FLEDGE_NO_RELOAD:-} ]]; then
    hyprctl reload >/dev/null
  fi
}

settings_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    get) settings_get "$@" ;;
    set) lock_settings; settings_set "$@" ;;
    reset) lock_settings; settings_reset "$@" ;;
    check) settings_check ;;
    apply) lock_settings; settings_apply ;;
    *) die "usage: fledge settings get|set|reset|check|apply" ;;
  esac
}
