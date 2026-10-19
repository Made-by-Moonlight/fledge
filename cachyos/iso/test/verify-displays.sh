#!/usr/bin/env bash
# End-to-end checks for monitor arrangement, run inside the logged-in Hyprland
# session (headless outputs stand in for screens; no UI is driven):
#   cachyos/vm/vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-displays.sh'
# Writes displays settings the way Settings > Displays does and reads Hyprland
# back, then checks that a display-pending.json left by a dead shell is reverted
# when fledge-shell.service starts. Restores the user's settings file and removes
# the headless outputs on any exit. Restarts fledge-shell.service.
set -uo pipefail

# Over ssh the locale is "C", and qs prints a Qt locale warning on stdout.
export LC_ALL=C.UTF-8
bad=0
ok() { printf 'PASS  %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }
is() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got: $3)"; fi; }

user=~/.config/fledge/settings.json
pending=~/.local/state/fledge/display-pending.json
backup="$(mktemp)"
had_user=0
if [[ -e $user ]]; then cp -- "$user" "$backup"; had_user=1; fi
outputs=()

cleanup() {
  local o
  for o in "${outputs[@]}"; do hyprctl output remove "$o" >/dev/null 2>&1; done
  rm -f -- "$pending"
  if ((had_user)); then cp -- "$backup" "$user"; else rm -f -- "$user"; fi
  rm -f -- "$backup"
  fledge settings apply >/dev/null 2>&1
}
trap cleanup EXIT

# The key Settings > Displays gives a monitor: desc:<description> unless that is
# empty or has a comma, quote or backslash, then the connector name.
key_for() { # <name> <description>
  case "$2" in
    ''|*[,\"\\]*) printf '%s' "$1" ;;
    *) printf 'desc:%s' "$2" ;;
  esac
}
mon() { hyprctl monitors -j | jq -r --arg n "$1" ".[] | select(.name == \$n) | $2"; }

before="$(hyprctl monitors -j | jq -r '.[].name')"
hyprctl output create headless >/dev/null || { no "create headless output A"; exit 1; }
hyprctl output create headless >/dev/null || { no "create headless output B"; exit 1; }
sleep 1
for n in $(hyprctl monitors -j | jq -r '.[].name'); do
  grep -qxF -- "$n" <<<"$before" || outputs+=("$n")
done
is "two headless outputs created" 2 "${#outputs[@]}"
((${#outputs[@]} == 2)) || exit 1

a=${outputs[0]} b=${outputs[1]}
da="$(mon "$a" .description)"; db="$(mon "$b" .description)"
ka="$(key_for "$a" "$da")"; kb="$(key_for "$b" "$db")"
printf 'A=%s (%s) key=%s\nB=%s (%s) key=%s\n' "$a" "$da" "$ka" "$b" "$db" "$kb"
# Two outputs on one key would be one entry: the checks below need two.
[[ $ka != "$kb" ]] || { no "the two outputs have distinct keys"; exit 1; }
da_path() { printf '.displays["%s"]' "$1"; }

# --- an arrangement: B right of A, rotated -------------------------------------
wa="$(mon "$a" .width)"
fledge settings set "$(da_path "$ka")" '{"mode":"preferred","position":"0x0","scale":1,"transform":0}' \
                    "$(da_path "$kb")" "{\"mode\":\"preferred\",\"position\":\"${wa}x0\",\"scale\":1,\"transform\":1}" \
  && fledge settings apply >/dev/null 2>&1
is "settings set + apply succeed" 0 $?
sleep 1
is "A at 0x0"            "0x0"       "$(mon "$a" '"\(.x)x\(.y)"')"
is "A not rotated"       0           "$(mon "$a" .transform)"
is "B right of A"        "${wa}x0"   "$(mon "$b" '"\(.x)x\(.y)"')"
is "B rotated (transform 1)" 1       "$(mon "$b" .transform)"

# --- connector and desc: entries for the same monitor --------------------------
# The generator writes connector rules first and desc: rules after; Hyprland
# applies the later rule, so the description-keyed entry wins.
# The VM's own screen has a real description; the headless ones have none.
v=Virtual-1
dv="$(mon "$v" .description)"; kv="$(key_for "$v" "$dv")"
if [[ -n $dv && $kv == desc:* ]]; then
  fledge settings set "$(da_path "$v")" '{"mode":"preferred","position":"auto","scale":1,"transform":0}' \
                      "$(da_path "$kv")" '{"mode":"preferred","position":"auto","scale":2,"transform":0}' \
    && fledge settings apply >/dev/null 2>&1
  is "connector + desc: entries apply" 0 $?
  sleep 1
  is "the desc: entry's scale wins over the connector's" 2 "$(mon "$v" .scale)"
  fledge settings reset "$(da_path "$v")" "$(da_path "$kv")" >/dev/null && fledge settings apply >/dev/null 2>&1
else
  printf 'SKIP  connector + desc: precedence (%s has no usable description)\n' "$v"
fi

# --- a pending change left by a dead shell is reverted at start ----------------
wait_gone() { local _; for _ in $(seq 40); do [[ -e $pending ]] || return 0; sleep 0.5; done; return 1; }
# settings_is <path> <want>: polls briefly for the reverted value to land.
settings_is() { local _ got; for _ in $(seq 20); do got="$(fledge settings get "$1" | jq -c .)"; [[ $got == "$2" ]] && break; sleep 0.25; done; printf '%s' "$got"; }
restart_shell() { systemctl --user restart fledge-shell.service; }
old_a='{"mode":"preferred","position":"0x0","scale":1,"transform":0}'

# New format: A had an entry before, B had none (null).
fledge settings set "$(da_path "$ka")" '{"mode":"preferred","position":"0x0","scale":2,"transform":0}' \
                    "$(da_path "$kb")" '{"mode":"preferred","position":"1x1","scale":1,"transform":2}' >/dev/null
jq -n --arg a "$ka" --arg b "$kb" --argjson old "$old_a" \
  '{old: {($a): $old, ($b): null}, deadline: ((now + 15) * 1000 | floor)}' >"$pending"
restart_shell
wait_gone; is "new-format pending file is gone after the shell starts" 0 $?
is "new format: A back to its old entry" "$old_a" "$(settings_is ".displays[\"$ka\"]" "$old_a")"
is "new format: B (null) is reset"       null    "$(settings_is ".displays[\"$kb\"]" null)"

# Old format: {name, old}.
fledge settings set "$(da_path "$ka")" '{"mode":"preferred","position":"0x0","scale":2,"transform":0}' >/dev/null
jq -n --arg a "$ka" --argjson old "$old_a" '{name: $a, old: $old}' >"$pending"
restart_shell
wait_gone; is "old-format pending file is gone after the shell starts" 0 $?
is "old format: A back to its old entry" "$old_a" "$(settings_is ".displays[\"$ka\"]" "$old_a")"

exit "$bad"
