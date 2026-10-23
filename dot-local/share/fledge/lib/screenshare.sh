# shellcheck shell=bash
# fledge screenshare pick [--allow-token]: xdg-desktop-portal-hyprland's custom
# picker (dot-config/hypr/xdph.conf). xdph passes the windows it can share in
# XDPH_WINDOW_SHARING_LIST and --allow-token when allow_token_by_default is on;
# the shell's share dialog picks, and the pick goes to stdout as xdph reads it:
# "[SELECTION]<flags>/<target>". Exit 1 on a refusal (cancel, busy, timeout, a
# malformed answer), 2 on bad usage. The shell answers through a FIFO:
# "1\n<flags>/<target>\n" or "0\n\n". When the dialog can't open (no shell, or
# one older than the dialog), xdph's own hyprland-share-picker picks instead:
# plainer, but sharing still works.
# FLEDGE_SCREENSHARE_TIMEOUT (seconds, default 120) bounds the wait, since the
# portal request waits on us.

screenshare_usage() { echo "usage: fledge screenshare pick [--allow-token]" >&2; }

screenshare_stock() { # <allow-token: true|false> <why>
  echo "fledge screenshare: $2; using hyprland-share-picker" >&2
  if [[ $1 == true ]]; then exec hyprland-share-picker --allow-token; else exec hyprland-share-picker; fi
}

screenshare_main() {
  local fd allow=false out status="" choice=""
  # Globals: the EXIT trap runs after this function has returned, when its locals are gone.
  screenshare_dir="" screenshare_reader=0 screenshare_open=false
  [[ ${1:-} == pick ]] || { screenshare_usage; return 2; }
  shift
  while (($#)); do
    case "$1" in
      --allow-token) allow=true ;;
      *) echo "fledge screenshare: unknown option $1" >&2; screenshare_usage; return 2 ;;
    esac
    shift
  done

  [[ "$(qs -c fledge ipc call shell ping 2>&1 | tail -n1)" == pong ]] || screenshare_stock "$allow" "the shell isn't running"

  # As in dmenu.sh: EXIT, not RETURN, so a signal still removes the FIFO and closes the dialog.
  screenshare_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/fledge-screenshare.XXXXXX")"
  screenshare_cleanup() {
    if ((screenshare_reader)); then kill "$screenshare_reader" 2>/dev/null || true; fi
    if [[ $screenshare_open == true ]]; then qs -c fledge ipc call screenshare close >/dev/null 2>&1 || true; fi
    rm -rf "$screenshare_dir"
    return 0
  }
  trap screenshare_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  mkfifo "$screenshare_dir/result"

  # "--" so a list starting with "-" isn't parsed as a qs option.
  # exec skips the EXIT trap: clean up first.
  if ! out="$(qs -c fledge ipc call screenshare open -- "${XDPH_WINDOW_SHARING_LIST:-}" "$screenshare_dir/result" "$allow" 2>&1)"; then
    screenshare_cleanup
    screenshare_stock "$allow" "could not open the dialog: $(printf '%s\n' "$out" | tail -n1)"
  fi
  # One request at a time: the shell refuses a second while its dialog is open.
  [[ "$(printf '%s\n' "$out" | tail -n1)" == ok ]] \
    || { echo "fledge screenshare: the share dialog is busy with another request" >&2; return 1; }
  screenshare_open=true

  exec {fd}< <(timeout "${FLEDGE_SCREENSHARE_TIMEOUT:-120}" cat "$screenshare_dir/result")
  screenshare_reader=$!
  # Timeout (or a dead reader) leaves screenshare_open=true so the exit trap closes the stale dialog.
  # Every 2 s, check the shell still holds this request: one restarted (or crashed) has lost the
  # dialog, and xdph runs one picker at a time, so every share would wait out the timeout.
  local rc
  while :; do
    IFS= read -r -t 2 status <&"$fd" && break
    rc=$?
    ((rc > 128)) || return 1 # EOF: the timeout fired
    [[ "$(qs -c fledge ipc call screenshare waiting -- "$screenshare_dir/result" 2>/dev/null | tail -n1)" == true ]] \
      || { echo "fledge screenshare: the shell lost the dialog (restarted?)" >&2; screenshare_open=false; return 1; }
  done
  IFS= read -r choice <&"$fd" || return 1
  exec {fd}<&-
  screenshare_open=false # the shell already closed its dialog when it answered
  [[ $status == 1 ]] || return 1
  # xdph parses whatever follows [SELECTION]: hand it only the two shapes the dialog makes.
  [[ $choice =~ ^r?/(screen|window):[^[:space:]/]+$ ]] \
    || { echo "fledge screenshare: malformed answer from the shell: $choice" >&2; return 1; }
  printf '[SELECTION]%s\n' "$choice"
}
