# shellcheck shell=bash
# fledge dmenu: options on stdin -> the shell's launcher in dmenu mode -> the
# choice on stdout. Exit 1 on cancel, timeout, or when the shell isn't running;
# 2 on bad usage. The shell answers through a FIFO: "1\n<choice>\n" or "0\n\n".
# MBM_DMENU_TIMEOUT (seconds, default 600) bounds the wait.

dmenu_usage() { echo "usage: fledge dmenu [--prompt P] [--select N] [--input-only]" >&2; }

dmenu_main() {
  local fd prompt="" select=0 input_only=false out status="" choice=""
  # Globals: the EXIT trap runs after this function has returned, when its locals are gone.
  dmenu_dir="" dmenu_reader=0 dmenu_open=false
  while (($#)); do
    case "$1" in
      -p | --prompt) (($# >= 2)) || { dmenu_usage; return 2; }; prompt="$2"; shift ;;
      --select) (($# >= 2)) || { dmenu_usage; return 2; }; select="$2"; shift ;;
      --input-only) input_only=true ;;
      *) echo "fledge dmenu: unknown option $1" >&2; dmenu_usage; return 2 ;;
    esac
    shift
  done
  [[ $select =~ ^[0-9]+$ ]] || { echo "fledge dmenu: --select needs a number" >&2; return 2; }

  # Not a RETURN trap: it doesn't run on INT/TERM/HUP, which would leak the FIFO and leave the
  # dialog open (and a shell writer waiting on it). EXIT does, once the signal traps exit.
  dmenu_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/fledge-dmenu.XXXXXX")"
  dmenu_cleanup() {
    if ((dmenu_reader)); then kill "$dmenu_reader" 2>/dev/null || true; fi
    if [[ $dmenu_open == true ]]; then qs -c mbm ipc call dmenu close >/dev/null 2>&1 || true; fi
    rm -rf "$dmenu_dir"
    return 0
  }
  trap dmenu_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  if [[ $input_only == true ]]; then : >"$dmenu_dir/options"; else cat >"$dmenu_dir/options"; fi
  mkfifo "$dmenu_dir/result"

  # Tell "not running" apart from a real qs error.
  [[ "$(qs -c mbm ipc call shell ping 2>&1 | tail -n1)" == pong ]] \
    || { echo "fledge dmenu: the shell isn't running" >&2; return 1; }
  # "--" so a prompt starting with "-" isn't parsed as a qs option.
  out="$(qs -c mbm ipc call dmenu open -- "$prompt" "$dmenu_dir/options" "$dmenu_dir/result" "$select" "$input_only" 2>&1)" \
    || { echo "fledge dmenu: could not open the dialog: $(printf '%s\n' "$out" | tail -n1)" >&2; return 1; }
  dmenu_open=true

  exec {fd}< <(timeout "${MBM_DMENU_TIMEOUT:-600}" cat "$dmenu_dir/result")
  dmenu_reader=$!
  # Timeout (or a dead reader) leaves dmenu_open=true so the exit trap closes the stale dialog.
  { IFS= read -r status && IFS= read -r choice; } <&"$fd" || return 1
  exec {fd}<&-
  dmenu_open=false # the shell already closed itself when it answered
  [[ $status == 1 ]] || return 1
  printf '%s\n' "$choice"
}
