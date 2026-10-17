#!/usr/bin/env bash
# Every command the desktop runs by name resolves: run inside the logged-in
# session (it reads the merged settings through `fledge settings get`):
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-commands.sh'
# A rename that misses one caller fails only when someone presses that key or
# picks that menu entry, so this walks the callers instead:
#   - every string in the merged settings (bind execs, nested $(fledge ...)),
#     and every {shell: "target.fn"} action;
#   - the code lines (not comments) of libexec/, lib/, the stowed config
#     (Hyprland Lua, units, uwsm env, ...), the shell's QML and bootstrap.sh.
# `fledge w1 w2 ...` must resolve the way the dispatcher does: a built-in, or
# the longest leading run of command words naming an action `fledge help`
# lists. `qs -c fledge ipc call T F` (and {shell: "T.F"}) must name a function
# of an IpcHandler with target T in ipc/Ipc.qml. Calls built at run time
# (`fledge "$cmd"`, `fledge $1`) can't be checked here and are counted.
# VERBOSE=1 lists every call checked.
set -euo pipefail

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../.." && pwd)"
FLEDGE_DIR="$REPO/dot-local/share/fledge"
FLEDGE="$FLEDGE_DIR/bin/fledge"
QML="$REPO/dot-config/quickshell/fledge"
bad=0
ok() { printf 'PASS  %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }
is() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }

# --- What resolves, all from the dispatcher's own help --------------------
# `fledge help` lists the groups; `fledge help <group>` lists a libexec
# group's actions as "  fledge w1 w2  about". A group with no such rows is a
# built-in (hypr, settings, dmenu, help), whose help text names its
# subcommands ("fledge hypr dispatch ...", "| set <path>").
declare -A CMDS=() BUILTIN_SUBS=() BUILTIN=()
mapfile -t groups < <("$FLEDGE" help | sed -nE 's/^  ([a-z0-9][a-z0-9_.]*)( .*)?$/\1/p')
for g in "${groups[@]}"; do
  text="$("$FLEDGE" help "$g")"
  rows="$(sed -nE 's/^  fledge ([a-z0-9_. ]*[a-z0-9_.])  .*$/\1/p; s/^  fledge ([a-z0-9_. ]*[a-z0-9_.]) *$/\1/p' <<<"$text")"
  if [[ -n $rows ]]; then
    while IFS= read -r r; do CMDS[$r]=1; done <<<"$rows"
  else
    BUILTIN[$g]=1
    BUILTIN_SUBS[$g]="$({ grep -oE "(fledge $g|\\|) [a-z][a-z0-9_]*" <<<"$text" || true; } | awk '{print $NF}' | sort -u | tr '\n' ' ')"
  fi
done
is "fledge help lists the built-ins" "dmenu help hypr settings" "$(printf '%s\n' "${!BUILTIN[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
is "fledge help lists libexec actions" yes "$( (( ${#CMDS[@]} > 50 )) && echo yes || echo no)"

# resolves w1 w2 ...: the dispatcher's rule, against the lists above.
resolves() {
  local -a w=("$@"); local n
  if [[ -n ${BUILTIN[${w[0]}]:-} ]]; then
    # A built-in's second word, when it has subcommands, must be one of them.
    [[ -z ${BUILTIN_SUBS[${w[0]}]} || ${#w[@]} -lt 2 || " ${BUILTIN_SUBS[${w[0]}]} " == *" ${w[1]} "* ]]
    return
  fi
  for ((n = ${#w[@]}; n >= 1; n--)); do
    [[ -n ${CMDS["${w[*]:0:n}"]:-} ]] && return 0
  done
  return 1
}
# The walker must be able to fail: a made-up command and a bad built-in
# subcommand don't resolve, real ones do.
is "resolver rejects a made-up command" no "$(resolves no such thing && echo yes || echo no)"
is "resolver rejects a bad built-in subcommand" no "$(resolves hypr frobnicate && echo yes || echo no)"
is "resolver takes an action with arguments" yes "$(resolves capture screenshot region copy && echo yes || echo no)"
is "resolver takes a built-in" yes "$(resolves settings apply && echo yes || echo no)"

# IPC targets and functions: "target fn" lines from Ipc.qml's IpcHandlers.
# (A `target: Brightness` without quotes is a Connections block, not IPC.)
declare -A IPC=()
while IFS= read -r tf; do IPC[$tf]=1; done < <(awk '
  /target: *"[A-Za-z]+"/ { match($0, /"[A-Za-z]+"/); t = substr($0, RSTART + 1, RLENGTH - 2); next }
  /target: *[A-Za-z]/ { t = ""; next }
  t != "" && match($0, /function [A-Za-z]+\(/) { print t " " substr($0, RSTART + 9, RLENGTH - 10) }
' "$QML/ipc/Ipc.qml")
is "Ipc.qml has the shell ping" yes "$([[ -n ${IPC["shell ping"]:-} ]] && echo yes || echo no)"
is "Ipc.qml parse skips non-IPC blocks" no "$([[ -n ${IPC["Brightness onApplied"]:-} || -n ${IPC[" onApplied"]:-} ]] && echo yes || echo no)"

# --- Extraction -----------------------------------------------------------
# Reads "where<TAB>text" lines; prints "kind<TAB>where<TAB>call" for each
# call found in text: kind f (fledge words), d (dynamic fledge call), i (ipc).
# A fledge call is `fledge` in command position (line start; after a quote,
# ( ` ; | & or {; or after --, exec, then, do, else, sudo, setsid, nohup), so
# prose ("in the fledge shell") and `qs -c fledge` aren't calls; not part of a
# longer name (fledge-shell, ~/.config/fledge/, "fledge:"); its words are the leading run
# of command words, each ending at whitespace, a quote, ) ; | & } or the end.
# QML's Process arrays are the other form: ["fledge", "w1", ...] and
# [root.fledge, "w1", ...].
extract() {
  perl -ne '
    chomp; my ($where, $t) = split /\t/, $_, 2; next unless defined $t;
    my $w = qr/[a-z0-9][a-z0-9_.]*(?=[\s"\x27`);|&}]|$)/;
    while ($t =~ /(?:^\s*|[\x27"`(;|&{]\s*|(?:^|\s)(?:--|exec|then|do|else|sudo|setsid|nohup)\s+)fledge(?![\w\/.:-])((?:\s+$w)*)(\s+\S)?/g) {
      my ($words, $next) = ($1, $2);
      $words =~ s/^\s+//; $words =~ s/\s+/ /g;
      if ($words ne "") { print "f\t$where\t$words\n" }
      elsif (defined $next && $next =~ /[\$"\x27]$/) { print "d\t$where\tfledge$next...\n" }
    }
    while ($t =~ /\[\s*(?:"fledge"|\w+\.fledge)\s*((?:,\s*"[a-z0-9][a-z0-9_.]*"\s*)+)/g) {
      my @w = ($1 =~ /"([^"]+)"/g); print "f\t$where\t@w\n";
    }
    while ($t =~ /qs -c fledge ipc call ([^\s"\x27`;)]+) ([^\s"\x27`;)]+)/g) { print "i\t$where\t$1 $2\n" }
  '
}
# Code lines of a file as "path:line<TAB>text", comment lines dropped
# (# for shell, jq, units and env; -- for Lua; // for QML).
code_lines() { # <file>
  awk -v p="${1#"$REPO"/}" '
    /^[[:space:]]*(#|--|\/\/)/ { next }
    { printf "%s:%d\t%s\n", p, NR, $0 }' "$1"
}

calls="$(mktemp)"; trap 'rm -f "$calls"' EXIT
# The merged settings: every string, each with its JSON path, plus the shell actions.
settings="$("$FLEDGE" settings get .)"
jq -r 'paths(strings) as $p | "settings:\($p | map(tostring) | join("."))\t\(getpath($p))"' <<<"$settings" | extract >>"$calls"
jq -r 'paths(objects | select(has("shell"))) as $p | "s\tsettings:\($p | map(tostring) | join("."))\t\(getpath($p).shell)"' <<<"$settings" >>"$calls"
# The files the session runs from. The shell's QML tests are left out: they
# hold made-up commands on purpose.
while IFS= read -r -d '' f; do
  grep -Iq . "$f" || continue   # text files only
  code_lines "$f" | extract >>"$calls"
done < <(find "$FLEDGE_DIR/libexec" "$FLEDGE_DIR/lib" "$REPO/dot-config" "$REPO/cachyos/bootstrap.sh" \
            -path "$QML/test" -prune -o -type f -print0)

# --- Checks ---------------------------------------------------------------
declare -A seen=()
n_f=0 n_i=0 n_d=0 n_settings=0
while IFS=$'\t' read -r kind where call; do
  [[ $where == settings:* ]] && n_settings=$((n_settings + 1))
  [[ ${VERBOSE:-} ]] && printf '      %s %s: %s\n' "$kind" "$where" "$call"
  case "$kind" in
    f)
      n_f=$((n_f + 1))
      read -ra words <<<"$call"
      resolves "${words[@]}" || no "$where: fledge $call does not resolve"
      ;;
    i | s)
      n_i=$((n_i + 1))
      if [[ $kind == s ]]; then
        t="${call%%.*}"; fn="${call#*.}"; fn="${fn%% *}"
      else
        t="${call%% *}"; fn="${call#* }"
      fi
      if [[ ! $t =~ ^[A-Za-z]+$ || ! $fn =~ ^[A-Za-z]+$ ]]; then
        n_d=$((n_d + 1)); seen["dynamic ipc $where: $call"]=1
      elif [[ -z ${IPC["$t $fn"]:-} ]]; then
        no "$where: ipc call $t $fn: no such IPC function in Ipc.qml"
      fi
      ;;
    d) n_d=$((n_d + 1)); seen["dynamic $where: $call"]=1 ;;
  esac
done <"$calls"

# Enough of each kind that a broken extractor can't pass on nothing.
is "settings calls found" yes "$( (( n_settings > 50 )) && echo yes || echo no)"
is "fledge calls found"   yes "$( (( n_f > 100 )) && echo yes || echo no)"
is "ipc calls found"      yes "$( (( n_i > 20 )) && echo yes || echo no)"
((bad)) || ok "every fledge call resolves ($n_f) and every ipc call exists ($n_i)"
if ((n_d)); then
  printf 'NOTE  %d calls are built at run time and left unchecked:\n' "$n_d"
  printf '%s\n' "${!seen[@]}" | sort | sed 's/^/        /'
fi
exit $bad
