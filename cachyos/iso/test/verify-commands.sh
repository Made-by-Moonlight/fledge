#!/usr/bin/env bash
# Every command the desktop runs by name resolves: run inside the logged-in
# session (it reads the merged settings through `fledge settings get`):
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-commands.sh'
# A rename that misses one caller fails only when someone presses that key or
# picks that menu entry, so this walks the callers instead:
#   - every string in the merged settings (bind execs, nested $(fledge ...)),
#     and every {shell: "target.fn"} action;
#   - the code lines (not comments) of libexec/, lib/, the stowed config
#     (Hyprland Lua, units, uwsm env, ...), the shell's QML and bootstrap.sh;
#   - and, though they run where fledge isn't installed, the installer
#     (cachyos/install, the ISO's airootfs configs and its QML installer), so
#     a fledge call that creeps in there is checked too. Their tests, and
#     Markdown anywhere, are left out.
# The call head is `fledge`, a path ending in /bin/fledge, or a variable
# holding it ($fledge, "$_fledge", ${fledge}); QML Process arrays start with
# "fledge" or a .fledge property.
# `fledge w1 w2 ...` must resolve the way the dispatcher does: a built-in, or
# the longest leading run of command words naming an action `fledge help`
# lists. A first word that isn't a command word (Capture, audio-output) fails.
# Command words left over after the action are its word arguments
# (`fledge toggle touchpad on`); a typo there (`fledge toggle nightlite`)
# would resolve to a shorter script, so each (action, first word argument)
# pair must be in WORD_ARGS below. `qs -c fledge ipc call T F` (and
# {shell: "T.F"}) must name a function of an IpcHandler with target T in
# ipc/Ipc.qml. Calls built at run time (`fledge "$cmd"`, `fledge $1`) and the
# fledge binary handed to other code ("$1" hypr eval ...) can't be checked
# here and are counted. VERBOSE=1 lists every call checked.
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

# resolves w1 w2 ...: the dispatcher's rule, against the lists above. Sets
# RESOLVED to the action (w1-w2, empty for a built-in) and RESOLVED_N to the
# number of words it took.
ALL_GROUPS=" ${groups[*]} "
resolves() {
  local -a w=("$@"); local n
  RESOLVED="" RESOLVED_N=0
  if [[ -n ${BUILTIN[${w[0]}]:-} ]]; then
    ((${#w[@]} < 2)) && return 0
    # A built-in's second word, when it has subcommands, must be one of them;
    # help's is a group; dmenu takes only options (--prompt), no words.
    case "${w[0]}" in
      help) [[ $ALL_GROUPS == *" ${w[1]} "* ]] ;;
      *) [[ -n ${BUILTIN_SUBS[${w[0]}]} && " ${BUILTIN_SUBS[${w[0]}]} " == *" ${w[1]} "* ]] ;;
    esac
    return
  fi
  for ((n = ${#w[@]}; n >= 1; n--)); do
    if [[ -n ${CMDS["${w[*]:0:n}"]:-} ]]; then
      RESOLVED="$(IFS=-; echo "${w[*]:0:n}")" RESOLVED_N=$n
      return 0
    fi
  done
  return 1
}
# The walker must be able to fail: a made-up command and a bad built-in
# subcommand don't resolve, real ones do.
is "resolver rejects a made-up command" no "$(resolves no such thing && echo yes || echo no)"
is "resolver rejects a bad built-in subcommand" no "$(resolves hypr frobnicate && echo yes || echo no)"
is "resolver takes an action with arguments" yes "$(resolves capture screenshot region copy && echo yes || echo no)"
is "resolver takes a built-in" yes "$(resolves settings apply && echo yes || echo no)"
is "resolver rejects a bad settings subcommand" no "$(resolves settings frobnicate && echo yes || echo no)"
is "resolver rejects a word after dmenu" no "$(resolves dmenu frobnicate && echo yes || echo no)"
is "resolver rejects help for no group" no "$(resolves help frobnicate && echo yes || echo no)"
is "resolver takes help for a group" yes "$(resolves help capture && echo yes || echo no)"
is "resolver takes dmenu" yes "$(resolves dmenu && echo yes || echo no)"

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
# call found in text: kind f (fledge words), m (malformed first word),
# d (dynamic fledge call, or the binary handed on), i (ipc).
# A fledge call is a head in command position (line start; after a quote,
# ( ` ; | & { or !; after --, exec, then, do, else, if, while, until, sudo,
# setsid, nohup; then any VAR=value assignments), so prose ("in the fledge
# shell") and `qs -c fledge` aren't calls. The head is `fledge` (not part of a
# longer name: fledge-shell, ~/.config/fledge/, "fledge:", @@fledge), a path
# ending in /bin/fledge, or $fledge / $_fledge / ${fledge}, each optionally
# quoted. Its words are the leading run of command words, each ending at
# whitespace, a quote, ) ; | & } or the end. QML's Process arrays are the
# other form: ["fledge", "w1", ...] and [root.fledge, "w1", ...]. A fledge
# variable or .fledge property used any other way (not assigned, not tested
# with -x) hands the binary to code that calls it: counted as dynamic.
extract() {
  perl -ne '
    chomp; my ($where, $t) = split /\t/, $_, 2; next unless defined $t;
    my $w = qr/[a-z0-9][a-z0-9_.]*(?=[\s"\x27`);|&}]|$)/;
    my $var = qr/\$(?:\{_?fledge\}|_?fledge(?!\w))/i;
    my $head = qr/$var|[^\s"\x27`(;|&{]*\/bin\/fledge(?![\w\/.:-])|(?<![\w\/.@-])fledge(?![\w\/.:-])/;
    my %used;
    while ($t =~ /(?:^\s*|[\x27"`(;|&{!]\s*|(?:^|\s)(?:--|exec|then|do|else|if|while|until|sudo|setsid|nohup)\s+)(?:[A-Za-z_]\w*=\S*\s+)*["\x27]?($head)["\x27]?((?:\s+$w)*)(?=(\s+["\x27\$][^\s"\x27);|&]*|\s+[^\s"\x27`);|&}]+)?)/g) {
      my ($h, $words, $next, $at) = ($1, $2, $3, $-[1]);
      $words =~ s/^\s+//; $words =~ s/\s+/ /g;
      if ($words ne "") { print "f\t$where\t$words\n" }
      elsif (defined $next && $next =~ /^\s+["\x27\$]/) { print "d\t$where\t$h$next...\n" }
      elsif (defined $next && $next =~ /^\s+([A-Za-z0-9][A-Za-z0-9_.-]*)$/) { print "m\t$where\t$1\n" }
      else { next }
      $used{$at} = 1;
    }
    while ($t =~ /\[\s*(?:"fledge"|(\w+\.fledge))\s*((?:,\s*"[a-z0-9][a-z0-9_.]*"\s*)+)/g) {
      $used{$-[1]} = 1 if defined $1;
      my @w = ($2 =~ /"([^"]+)"/g); print "f\t$where\t@w\n";
    }
    while ($t =~ /($var|\b\w+\.fledge\b(?![\w.\/-]))/g) {
      my ($ref, $at) = ($1, $-[1]);
      next if $used{$at} || substr($t, 0, $at) =~ /-x\s+["\x27]?$/;
      print "d\t$where\t$ref handed on\n";
    }
    while ($t =~ /qs -c fledge ipc call ([^\s"\x27`;)]+) ([^\s"\x27`;)]+)/g) { print "i\t$where\t$1 $2\n" }
  '
}
# The extractor must find each call form and nothing in the non-calls.
xt() { printf 'x\t%s\n' "$1" | extract | cut -f1,3 | tr '\t' ' ' | paste -sd'|'; }
is "extract: bare head"           "f capture screenshot"   "$(xt 'fledge capture screenshot')"
is "extract: path head"           "f hw display gpu"       "$(xt '[[ "$(~/.local/share/fledge/bin/fledge hw display gpu)" == x ]]')"
is "extract: quoted variable head after an assignment" "f settings apply" "$(xt 'if ! FLEDGE_NO_RELOAD=1 "$fledge" settings apply; then')"
is "extract: braced variable head" "f help"                "$(xt '${_fledge} help')"
is "extract: QML array, property head" "f settings set"    "$(xt 'const args = [root.fledge, "settings", "set"];')"
is "extract: uppercase first word" "m Capture"             "$(xt 'fledge Capture screenshot')"
is "extract: dashed first word"   "m audio-output"         "$(xt 'exec fledge audio-output switch')"
is "extract: run-time command"    'd fledge "$cmd...'     "$(xt 'fledge "$cmd"')"
is "extract: binary handed on"    'd $fledge handed on'    "$(xt 'manager="$(hypr_manager "$fledge")"')"
is "extract: assignment and -x test aren't calls" ""      "$(xt '_fledge="$HOME/.local/share/fledge/bin/fledge"; [ -x "$_fledge" ]')"
is "extract: installer markers aren't calls" ""           "$(xt 'echo "@@fledge stage base Base system"')"
is "extract: prose isn't a call"  ""                       "$(xt 'echo "isnt available in the fledge shell yet"')"
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
# The files the session runs from, and the installer's. Tests are left out:
# they hold made-up commands on purpose. So are sysusers.d and sudoers.d,
# which name the live ISO's user, fledge ("fledge installer", fledge ALL=...).
INSTALLER="$REPO/cachyos/iso/installer"
while IFS= read -r -d '' f; do
  grep -Iq . "$f" || continue   # text files only
  code_lines "$f" | extract >>"$calls"
done < <(find "$FLEDGE_DIR/libexec" "$FLEDGE_DIR/lib" "$REPO/dot-config" "$REPO/cachyos/bootstrap.sh" \
            "$REPO/cachyos/install" "$REPO/cachyos/iso/configs" "$INSTALLER" \
            \( -path "$QML/test" -o -path "$INSTALLER/test" -o -path "$REPO/cachyos/install/test" \
               -o -path '*/etc/sysusers.d' -o -path '*/etc/sudoers.d' \) -prune -o \
            -type f ! -name '*.md' ! -name 'test-*.sh' ! -name 'tst_*.qml' -print0)

# --- Checks ---------------------------------------------------------------
# (action, first word argument) pairs the actions take: a word argument not
# listed here fails, since a typo in it would still resolve (to the action,
# with the typo as its argument). Add a pair when an action gains one; "*"
# is for actions whose argument is a program or package name.
WORD_ARGS="
brightness-keyboard up
brightness-keyboard down
brightness-keyboard cycle
capture-screenshot region
cmd-missing *
cmd-present *
hyprland-monitor-internal on
hyprland-monitor-internal off
hyprland-monitor-internal toggle
hyprland-monitor-internal recover
hyprland-monitor-internal-mirror toggle
hyprland-monitor-internal-mirror recover
launch-or-focus *
launch-or-focus-tui *
launch-tui *
menu background
menu capture
menu hardware
menu setup
menu share
menu theme
menu toggle
pkg-add *
pkg-present *
powerprofiles-set ac
powerprofiles-set battery
reminder clear
reminder show
restart-app *
share file
share folder
state clear
toggle-touchpad on
toggle-touchpad off
"
declare -A seen=() wargs=()
n_f=0 n_i=0 n_d=0 n_p=0 n_w=0 n_settings=0
while IFS=$'\t' read -r kind where call; do
  [[ $where == settings:* ]] && n_settings=$((n_settings + 1))
  [[ ${VERBOSE:-} ]] && printf '      %s %s: %s\n' "$kind" "$where" "$call"
  case "$kind" in
    f)
      n_f=$((n_f + 1))
      read -ra words <<<"$call"
      if ! resolves "${words[@]}"; then
        no "$where: fledge $call does not resolve"
      elif [[ -n $RESOLVED ]] && ((RESOLVED_N < ${#words[@]})); then
        n_w=$((n_w + 1)); arg="${words[RESOLVED_N]}"
        wargs["$RESOLVED $arg"]=1
        [[ $WORD_ARGS == *$'\n'"$RESOLVED $arg"$'\n'* || $WORD_ARGS == *$'\n'"$RESOLVED *"$'\n'* ]] ||
          no "$where: fledge $call: '$arg' is a word argument of $RESOLVED not in WORD_ARGS (a typo of a longer action?)"
      fi
      ;;
    m)
      # Capture, audio-output: a call whose first word isn't a command word,
      # when it starts like a group (or a built-in). Otherwise it's prose after
      # a quote ("fledge first-boot bootstrap"), listed but not failed.
      first="${call%%-*}"; first="${first,,}"
      if [[ $ALL_GROUPS == *" $first "* ]]; then
        no "$where: fledge $call ...: '$call' is not a command word (lowercase, no '-')"
      else
        n_p=$((n_p + 1)); seen["not a call $where: fledge $call"]=1
      fi
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
((bad)) || ok "every fledge call resolves ($n_f calls, $n_w with word arguments) and every ipc call exists ($n_i)"
[[ ${VERBOSE:-} ]] && printf '      word arguments: %s\n' "${!wargs[@]}" | sort
if ((n_d + n_p)); then
  printf 'NOTE  %d calls are built at run time or hand the binary on (unchecked); %d are prose after a quote:\n' "$n_d" "$n_p"
  printf '%s\n' "${!seen[@]}" | sort | sed 's/^/        /'
fi
exit $bad
