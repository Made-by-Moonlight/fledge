# shellcheck shell=bash
# mbm dmenu: options on stdin -> the shell's launcher in dmenu mode -> the
# choice on stdout. Exit 1 on cancel, timeout, or when the shell isn't running.
# The shell answers through a FIFO: "1\n<choice>\n" or "0\n\n".

dmenu_main() {
  local prompt="" select=0 input_only=false dir status="" choice=""
  while (($#)); do
    case "$1" in
      -p | --prompt) prompt="${2:?--prompt needs a value}"; shift ;;
      --select) select="${2:?--select needs a number}"; shift ;;
      --input-only) input_only=true ;;
      *) echo "mbm dmenu: unknown option $1" >&2; return 2 ;;
    esac
    shift
  done
  [[ $select =~ ^[0-9]+$ ]] || { echo "mbm dmenu: --select needs a number" >&2; return 2; }

  dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/mbm-dmenu.XXXXXX")"
  # shellcheck disable=SC2064 # expand $dir now: it's local
  trap "rm -rf '$dir'" RETURN
  if [[ $input_only == true ]]; then : >"$dir/options"; else cat >"$dir/options"; fi
  mkfifo "$dir/result"

  qs -c mbm ipc call dmenu open "$prompt" "$dir/options" "$dir/result" "$select" "$input_only" >/dev/null 2>&1 \
    || { echo "mbm dmenu: the mbm shell isn't running" >&2; return 1; }
  { IFS= read -r status && IFS= read -r choice; } < <(timeout 600 cat "$dir/result") || return 1
  [[ $status == 1 ]] || return 1
  printf '%s\n' "$choice"
}
