#!/usr/bin/env bash
# Compare two `hyprctl binds -j` dumps (before/after the cutover), bind by bind.
#   bind-parity.sh BEFORE.json AFTER.json
# Binds are keyed on (modmask, key/keycode, submap). The key sets must be
# identical except combos listed `add`/`remove` in parity-allowed.txt. For a
# combo on both sides the actions (a multiset, so ALT+TAB's two binds work)
# and their flags must be identical, except an action may be replaced by one
# matching a `replace` pattern there. Exits 1 and prints each violation with
# its combo otherwise.
set -euo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
ALLOWED="${PARITY_ALLOWED:-$HERE/parity-allowed.txt}"

if [[ $# -ne 2 ]]; then
  echo "usage: bind-parity.sh BEFORE.json AFTER.json" >&2
  exit 2
fi

# parity-allowed.txt -> {add: [combo], remove: [combo], replace: [ere]}
allowed="$(sed 's/[[:space:]]*#.*$//' "$ALLOWED" | jq -Rn '
  [inputs | select(test("\\S"))] as $l
  | def combo: split(" ") | map(select(. != "")) | "\(.[0])|\(.[1])|\(.[2] // "")";
    {add: [$l[] | select(startswith("add ")) | ltrimstr("add ") | combo],
     remove: [$l[] | select(startswith("remove ")) | ltrimstr("remove ") | combo],
     replace: [$l[] | select(startswith("replace ")) | ltrimstr("replace ")]}')"

# Cosmetic in `hyprctl binds -j`, so ignored by name: the description text and
# has_description (the `d` flag). Every other field is compared.
jq -rn --slurpfile b "$1" --slurpfile a "$2" --argjson ok "$allowed" '
  def combo: "\(.modmask)|\(if .key == "" then "#\(.keycode)" else (.key | ascii_downcase) end)|\(.submap // "")";
  def flags: [.locked, .mouse, .release, .repeat, .longPress, .non_consuming, .auto_consuming,
              .catch_all, .allow_input_capture, .submap_universal] | map(tostring) | join(",");
  def act: "[\(flags)] \(.dispatcher) \(.arg)";
  def group: reduce .[] as $x ({}; .[$x | combo] += [$x | act]) | map_values(sort);
  def show: split("|") | "mod \(.[0]) key \(.[1])" + (if .[2] != "" then " submap \(.[2])" else "" end);
  ($b[0] | group) as $B | ($a[0] | group) as $A
  | ([$B, $A | keys[]] | unique) as $all
  | $all[] as $c
  | if ($B | has($c)) and ($A | has($c) | not) then
      (if $ok.remove | index($c) then empty else "\($c | show): bind dropped (\($B[$c] | join("; ")))" end)
    elif ($B | has($c) | not) then
      (if $ok.add | index($c) then empty else "\($c | show): bind added but not allowed (\($A[$c] | join("; ")))" end)
    elif $B[$c] == $A[$c] then empty
    else
      # multiset difference, per side
      ($B[$c] as $x | $A[$c] as $y
       | (reduce $x[] as $e ($y; (index([$e]) // null) as $i | if $i == null then . else del(.[$i]) end)) as $new
       | (reduce $y[] as $e ($x; (index([$e]) // null) as $i | if $i == null then . else del(.[$i]) end)) as $old
       | if ($new | length) != ($old | length) then "\($c | show): action count changed (\($x | join("; ")) -> \($y | join("; ")))"
         else $new[] as $n
           | if any($ok.replace[]; . as $re | $n | sub("^\\[[^]]*\\] "; "") | test($re)) then empty
             else "\($c | show): action changed to \($n) (was \($old | join("; ")))" end
         end)
    end' >"${TMPDIR:-/tmp}/bind-parity.$$"
trap 'rm -f "${TMPDIR:-/tmp}/bind-parity.$$"' EXIT
if [[ -s "${TMPDIR:-/tmp}/bind-parity.$$" ]]; then
  cat "${TMPDIR:-/tmp}/bind-parity.$$" >&2
  exit 1
fi
