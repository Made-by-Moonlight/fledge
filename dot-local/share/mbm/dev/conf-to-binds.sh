#!/usr/bin/env bash
# One-off migration: Hyprland bind lines -> the "binds" object of mbm settings.
#   conf-to-binds.sh Group=file.conf [Group=file.conf]...  > binds.json
# Files are read in the order Hyprland sources them: `unbind` drops an earlier
# bind on the same mods+key, `$var = value` lines are expanded, and several
# binds on one combo become one entry with a list of actions.
set -euo pipefail

declare -A vars=()
records=""

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
norm_mods() { trim "$1" | tr '[:lower:]' '[:upper:]' | tr -s ' '; }
expand() { local s="$1" k; for k in "${!vars[@]}"; do s="${s//\$$k/${vars[$k]}}"; done; printf '%s' "$s"; }

for spec in "$@"; do
  group="${spec%%=*}" file="${spec#*=}"
  while IFS= read -r line || [[ -n $line ]]; do
    line="$(trim "${line%%#*}")"
    [[ -z $line ]] && continue
    if [[ $line =~ ^\$([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      vars[${BASH_REMATCH[1]}]="$(trim "${BASH_REMATCH[2]}")"
    elif [[ $line =~ ^unbind[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      IFS=, read -r mods key _ <<<"${BASH_REMATCH[1]}"
      records+="$(jq -cn --arg m "$(norm_mods "$mods")" --arg k "$(trim "$key")" '{unbind: true, mods: $m, key: $k}')"$'\n'
    elif [[ $line =~ ^bind([a-z]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      flags="${BASH_REMATCH[1]}" body="$(expand "${BASH_REMATCH[2]}")"
      IFS=, read -r mods key rest <<<"$body"
      if [[ $flags == *d* ]]; then
        IFS=, read -r label disp args <<<"$rest"
      else
        IFS=, read -r disp args <<<"$rest"
        label="$(trim "$disp") $(trim "$args")"
      fi
      records+="$(jq -cn --arg g "$group" --arg m "$(norm_mods "$mods")" --arg k "$(trim "$key")" \
        --arg f "${flags//d/}" --arg l "$(trim "${label//,/}")" --arg d "$(trim "$disp")" --arg a "$(trim "$args")" \
        '{group: $g, mods: $m, key: $k, flags: $f, label: $l, dispatcher: $d, args: $a}')"$'\n'
    fi
  done <"$file"
done

printf '%s' "$records" | jq -s '
  def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-|-$"; "");
  def ckey: "\(.mods)|\(.key | ascii_downcase)|\(.flags)";
  def action: if .dispatcher == "exec" then {exec: .args}
              else {dispatch: ([.dispatcher, .args] | map(select(. != "")) | join(" "))} end;
  reduce .[] as $r ([];
    if $r.unbind then map(select((.mods == $r.mods and (.key | ascii_downcase) == ($r.key | ascii_downcase)) | not))
    else ($r | ckey) as $k | (map(ckey) | index($k)) as $i
      | if $i == null then . + [$r + {actions: [$r | action]}] else .[$i].actions += [$r | action] end
    end)
  | reduce .[] as $e ({};
      . as $acc
      | (($e.group | slug) + "." + ($e.label | slug)) as $base
      | first($base, (range(2; 1000) | "\($base)-\(.)") | select(. as $c | $acc | has($c) | not)) as $id
      | .[$id] = ({mods: $e.mods, key: $e.key, label: $e.label, group: $e.group,
                   action: (if ($e.actions | length) == 1 then $e.actions[0] else $e.actions end)}
                  + (if $e.flags != "" then {flags: $e.flags} else {} end)))'
