# shellcheck shell=bash
# fledge update [--yes]: snapshot /, update packages (pacman, then the AUR
# through paru), move fledge to its newest release tag and re-run bootstrap,
# update firmware, then say whether to reboot. Only the parts with something
# pending run. A failing or interrupted step stops the run, and (without --yes)
# a guide offers to try again or to go back to the snapshot.
# fledge update check [--json]: what's pending; no root, changes nothing (the
# bar runs it). A part that can't be checked (offline, a tool missing) is
# reported, counts 0, and doesn't fail the check.
# fledge update recover: the guide on demand. Booted into a snapshot, it
# restores it (limine-snapper-restore); otherwise it picks up the last run
# that didn't finish, or says how to boot a snapshot.
# fledge version: the release this checkout is at (git describe).
#
# fledge moves only a release checkout: on main, no uncommitted changes, and
# HEAD an ancestor of the new tag. Anything else is a dev checkout (a feature
# branch, local commits) and is never moved; packages and firmware still are.
# Going back is never `snapper undochange` on the running system: /boot (the
# ESP) isn't in the snapshot, so that leaves the new kernel over the old
# modules. A snapshot's Limine entry carries its own kernel.
# Test hooks: FLEDGE_REPO (the checkout), FLEDGE_MODULES_DIR (/usr/lib/modules),
# FLEDGE_STATE (~/.local/state/fledge), FLEDGE_CMDLINE (/proc/cmdline).

update_usage() { echo "usage: fledge update [--yes] | fledge update check [--json] | fledge update recover" >&2; }

update_repo() { printf '%s\n' "${FLEDGE_REPO:-$(cd "$FLEDGE_ROOT/../../.." && pwd)}"; }
update_state() { printf '%s\n' "${FLEDGE_STATE:-$HOME/.local/state/fledge}"; }
# What bootstrap.sh records when it finishes, in the same form.
update_describe() { git -C "$(update_repo)" describe --tags --always --dirty 2>/dev/null; }

update_version() {
  git -C "$(update_repo)" describe --tags --match 'v*' --dirty 2>/dev/null || { echo "fledge: not a release checkout" >&2; return 1; }
}

# Why this checkout is a dev one, or nothing when fledge may move it.
update_dev_reason() { # <repo>
  local branch
  branch="$(git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null)" || { echo "not on a branch"; return; }
  [[ $branch == main ]] || { echo "on branch $branch, not main"; return; }
  # Untracked files don't block a fast-forward that doesn't touch them, so only tracked changes count.
  [[ -z "$(git -C "$1" status --porcelain --untracked-files=no)" ]] || echo "uncommitted changes"
}

# Packages that only take effect at boot: kernels, firmware files, microcode, NVIDIA's driver.
update_needs_boot() { # <package name>
  case $1 in
    linux-api-headers | linux*-headers | linux*-docs) return 1 ;;
    linux | linux-* | *-ucode | nvidia* | lib32-nvidia*) return 0 ;;
  esac
  return 1
}

# Sets U_FROM, U_TO (the tag to move to, or ""), U_BOOT (bootstrap didn't finish), U_DEV,
# U_PKG, U_AUR, U_FW, U_BOOTPKGS (pending packages that need a reboot), U_ERRORS.
update_check() {
  local repo out err rc newest finished
  repo="$(update_repo)"
  U_FROM="" U_TO="" U_BOOT=false U_DEV="" U_PKG=0 U_AUR=0 U_FW=0 U_BOOTPKGS=() U_ERRORS=()
  err="$(mktemp)"

  U_FROM="$(git -C "$repo" describe --tags --match 'v*' 2>/dev/null || git -C "$repo" rev-parse --short HEAD 2>/dev/null || true)"
  U_DEV="$(update_dev_reason "$repo")"
  # A dev checkout isn't fetched: nothing would come of it.
  if [[ -z $U_DEV ]]; then
    if ! git -C "$repo" fetch --quiet --tags origin 2>"$err"; then
      U_ERRORS+=("fledge: couldn't fetch: $(tail -n1 "$err")")
    elif newest="$(git -C "$repo" tag -l 'v*' --sort=-v:refname | head -n1)" && [[ -n $newest ]]; then
      if [[ "$(git -C "$repo" rev-parse "$newest^{commit}")" == "$(git -C "$repo" rev-parse HEAD)" ]]; then
        :
      elif git -C "$repo" merge-base --is-ancestor HEAD "$newest"; then
        U_TO="$newest"
      elif git -C "$repo" merge-base --is-ancestor "$newest" HEAD; then
        U_DEV="main is ahead of $newest"
      else
        U_DEV="main has diverged from $newest"
      fi
    fi
    # A bootstrap that failed (or was stopped) partway: the checkout moved but the machine
    # didn't follow. No record at all is an install from before this, and isn't flagged.
    if [[ -z $U_DEV && -z $U_TO && -f "$(update_state)/bootstrapped" ]]; then
      finished="$(<"$(update_state)/bootstrapped")"
      [[ $finished == "$(update_describe)" ]] || U_BOOT=true
    fi
  fi

  # checkupdates: 0 = updates listed, 2 = none, anything else = couldn't check.
  if ! command -v checkupdates >/dev/null; then
    U_ERRORS+=("packages: checkupdates is missing (pacman-contrib)")
  else
    rc=0; out="$(checkupdates 2>"$err")" || rc=$?
    case $rc in
      0) U_PKG="$(grep -c . <<<"$out")"; update_collect_boot "$out" ;;
      2) ;;
      *) U_ERRORS+=("packages: $(tail -n1 "$err")") ;;
    esac
  fi

  # paru -Qua exits 1 both when nothing is out of date and on errors; only stderr tells them apart.
  if ! command -v paru >/dev/null; then
    U_ERRORS+=("AUR: paru is missing")
  else
    out="$(paru -Qua 2>"$err")" || true
    if [[ -n $out ]]; then U_AUR="$(grep -c . <<<"$out")"; update_collect_boot "$out"
    elif [[ -s $err ]]; then U_ERRORS+=("AUR: $(tail -n1 "$err")"); fi
  fi

  # No fwupd, or nothing it can update (a VM), is simply no firmware updates.
  if command -v fwupdmgr >/dev/null; then
    fwupdmgr refresh >/dev/null 2>&1 || true
    if out="$(fwupdmgr get-updates --json 2>"$err")"; then
      U_FW="$(jq '[.Devices[]? | select((.Releases // []) | length > 0)] | length' <<<"$out" 2>/dev/null || echo 0)"
    elif ! printf '%s\n' "$out" | cat - "$err" | grep -qiE 'no updat|no (supported|updatable) devices'; then
      U_ERRORS+=("firmware: $(tail -n1 "$err")")
    fi
  fi
  rm -f "$err"
}

# "name old -> new" lines (checkupdates, paru -Qua): the names that need a reboot.
update_collect_boot() { # <lines>
  local name _
  while read -r name _; do
    if [[ -n $name ]] && update_needs_boot "$name"; then U_BOOTPKGS+=("$name"); fi
  done <<<"$1"
}

update_total() {
  local fledge=0
  [[ -n $U_TO || $U_BOOT == true ]] && fledge=1
  echo $((U_PKG + U_AUR + U_FW + fledge))
}

update_print() {
  local e
  if [[ -n $U_DEV ]]; then printf '  %-9s skipped: %s\n' fledge "$U_DEV"
  elif [[ -n $U_TO ]]; then printf '  %-9s %s → %s\n' fledge "$U_FROM" "$U_TO"
  elif [[ $U_BOOT == true ]]; then printf '  %-9s %s (its bootstrap didn'\''t finish: it runs again)\n' fledge "$U_FROM"
  else printf '  %-9s %s (newest)\n' fledge "$U_FROM"; fi
  printf '  %-9s %s\n' packages "$U_PKG" AUR "$U_AUR" firmware "$U_FW"
  for e in "${U_ERRORS[@]}"; do printf '  couldn'\''t check %s\n' "$e"; done
}

update_json() {
  jq -n --arg from "$U_FROM" --arg to "$U_TO" --arg dev "$U_DEV" --argjson boot "$U_BOOT" \
    --argjson pkg "$U_PKG" --argjson aur "$U_AUR" --argjson fw "$U_FW" \
    '{fledge: (if $to == "" then null else {from: $from, to: $to} end), bootstrap: $boot,
      packages: $pkg, aur: $aur, firmware: $fw,
      dev: ($dev != ""), devReason: $dev, errors: $ARGS.positional}' --args "${U_ERRORS[@]}"
}

# --- The run's record (update.json, in /home: a booted snapshot still sees it) ---
# {runs: [{snapshot, date, result}]}, newest last, the last 10. result: running, ok,
# "failed: <step>", "interrupted: <step>". date is snapper's, as Limine's menu shows it.

# With a date it's a new snapshot: any older record under the same number goes (numbers start
# over when snapper's config is made again). Without one, it updates that run's result.
update_record() { # <snapshot> <result> [date]
  local f tmp
  f="$(update_state)/update.json"; mkdir -p "$(update_state)"
  tmp="$(mktemp "$f.XXXXXX")"
  { cat "$f" 2>/dev/null || echo '{}'; } | jq --argjson n "$1" --arg r "$2" --arg d "${3:-}" '
    .runs = ((.runs // []) | if $d != "" then map(select(.snapshot != $n)) + [{snapshot: $n, date: $d, result: $r}]
                             else map(if .snapshot == $n then .result = $r else . end) end | .[-10:])' >"$tmp" && mv "$tmp" "$f"
}

# A recorded result as a sentence ends: "failed (AUR packages)", "didn't finish", …
update_how() { # <result>
  case $1 in
    ok) echo "finished" ;;
    running) echo "didn't finish" ;;
    failed:*) echo "failed (${1#failed: })" ;;
    interrupted:*) echo "was stopped (${1#interrupted: })" ;;
    *) echo "$1" ;;
  esac
}

update_runs() { jq -c '.runs // [] | reverse | .[]' "$(update_state)/update.json" 2>/dev/null || true; }

# "7 │ 2026-10-23 21:24:26", as the Snapshots menu lists it.
update_label() { # <snapshot>
  local d
  # No record (a snapshot taken by hand, or before fledge recorded them) is just the number.
  d="$(jq -r --argjson n "$1" '[.runs[]? | select(.snapshot == $n)][0].date // ""' "$(update_state)/update.json" 2>/dev/null || true)"
  if [[ -n $d ]]; then printf '%s │ %s\n' "$1" "$d"; else printf '%s\n' "$1"; fi
}

# The snapshot this boot runs from, or nothing.
update_booted() {
  if [[ "$(cat "${FLEDGE_CMDLINE:-/proc/cmdline}" 2>/dev/null)" =~ subvol=/?@/\.snapshots/([0-9]+)/snapshot ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# --- The guide ---

update_explain_boot() { # <snapshot>
  cat <<EOF

To go back to before the update:
  1. Reboot. In the boot menu (it waits 3 seconds: press an arrow key to stop it),
     open Snapshots and boot  $(update_label "$1")
  2. Log in. fledge says you're running the snapshot and offers to restore it,
     which makes it your system again (the current one is kept as a backup).
Your files in /home aren't touched either way.

EOF
  local answer
  read -r -p "Reboot now? [y/N] " answer || answer=n
  if [[ $answer =~ ^[Yy] ]]; then systemctl reboot; fi
}

update_guide() { # <snapshot or "">
  local answer
  echo
  echo "What now?"
  echo "  1  Try again"
  if [[ -n $1 ]]; then echo "  2  Go back to before the update"; fi
  echo "  3  Leave it for now (to come back here later: fledge update recover)"
  read -r -p "Choice: " answer || answer=3
  case $answer in
    1) exec "$FLEDGE_ROOT/bin/fledge" update ;;
    2) if [[ -n $1 ]]; then update_explain_boot "$1"; fi ;;
    *) echo "Left as it is. To come back here later: fledge update recover" ;;
  esac
}

update_snapshot="" update_current="" update_yes=false

update_fail() { # <step> [failed|interrupted]
  local how=${2:-failed}
  trap - INT TERM
  echo >&2
  echo "fledge update: $1 $how; the steps after it didn't run." >&2
  if [[ -n $update_snapshot ]]; then
    update_record "$update_snapshot" "$how: $1"
    echo "A snapshot from before the update is in the boot menu: Snapshots › $(update_label "$update_snapshot")." >&2
  fi
  [[ $update_yes == true ]] || update_guide "$update_snapshot"
  exit 1
}

update_step() { # <name> <command...>
  update_current=$1
  printf '\n\e[1m==> %s\e[0m\n' "$1"
  "${@:2}" || update_fail "$1"
}

update_bootstrap() { # <repo> <release>
  # Marked unfinished first, so a bootstrap that dies partway runs again next time.
  mkdir -p "$(update_state)" && echo unfinished >"$(update_state)/bootstrapped"
  update_step "Bootstrap ($2)" bash "$1/cachyos/bootstrap.sh"
}

update_run() { # <yes: true|false>
  local yes=$1 repo answer date
  update_yes=$yes
  # However the run ends, the bar's count is stale now (no shell is fine).
  trap 'qs -c fledge ipc call shell recheck >/dev/null 2>&1 || true' EXIT
  local -a noconfirm=()
  [[ $yes == true ]] && noconfirm=(--noconfirm)
  repo="$(update_repo)"

  echo "Checking for updates…"
  update_check
  update_print
  if (($(update_total) == 0)); then echo; echo "Everything is up to date."; return 0; fi
  if [[ $yes != true ]]; then
    read -r -p $'\nUpdate now? [Y/n] ' answer || answer=n
    [[ $answer =~ ^[Nn] ]] && { echo "Nothing changed."; return 0; }
  fi
  # From here on Ctrl+C is a stopped update: the guide, and exit 1 (130 would close the terminal).
  trap 'update_fail "${update_current:-The update}" interrupted' INT TERM

  # No root config: / isn't btrfs, or bootstrap hasn't set snapshots up yet.
  if sudo snapper -c root get-config >/dev/null 2>&1; then
    update_current="The snapshot"
    update_snapshot="$(sudo snapper -c root create --type pre --cleanup-algorithm number \
      --print-number --description "fledge update")" || update_fail "The snapshot"
    date="$(sudo snapper -c root --jsonout list 2>/dev/null | jq -r --argjson n "$update_snapshot" '.root[] | select(.number == $n) | .date' 2>/dev/null)"
    update_record "$update_snapshot" running "$date"
    echo "Snapshot $update_snapshot taken (boot menu › Snapshots)."
  else
    echo "No snapper config for /: updating without a snapshot." >&2
  fi

  ((U_PKG)) && update_step "Packages" sudo pacman -Syu "${noconfirm[@]}"
  ((U_AUR)) && update_step "AUR packages" paru -Sua "${noconfirm[@]}"
  # After the packages, so bootstrap's installs go against a synced database.
  if [[ -n $U_TO ]]; then
    update_step "fledge $U_TO" git -C "$repo" merge --ff-only --quiet "$U_TO"
    update_bootstrap "$repo" "$U_TO"
  elif [[ $U_BOOT == true ]]; then
    update_bootstrap "$repo" "$U_FROM"
  fi
  if ((U_FW)); then
    if [[ $yes == true ]]; then update_step "Firmware" fwupdmgr update --assume-yes --no-reboot-check
    else update_step "Firmware" fwupdmgr update; fi
  fi
  trap - INT TERM

  if [[ -n $update_snapshot ]]; then
    update_record "$update_snapshot" ok
    sudo snapper -c root create --type post --pre-number "$update_snapshot" --cleanup-algorithm number \
      --description "fledge update" || echo "fledge update: couldn't take the post-update snapshot" >&2
  fi

  echo
  # The kernel package removes the running kernel's modules when it upgrades it; that also
  # catches a kernel the boot list doesn't know (an AUR one).
  if [[ ! -d "${FLEDGE_MODULES_DIR:-/usr/lib/modules}/$(uname -r)" ]] && ! printf '%s\n' "${U_BOOTPKGS[@]}" | grep -qx 'linux.*'; then
    U_BOOTPKGS=("the kernel" "${U_BOOTPKGS[@]}")
  fi
  if ((${#U_BOOTPKGS[@]})); then
    echo "Updated. Reboot to start using: $(printf '%s, ' "${U_BOOTPKGS[@]}" | sed 's/, $//')."
    if [[ $yes != true ]]; then
      read -r -p "Reboot now? [y/N] " answer || answer=n
      if [[ $answer =~ ^[Yy] ]]; then systemctl reboot; fi
    fi
  else
    echo "Updated."
  fi
  return 0
}

update_recover() {
  local n run result answer lock=/run/lock/limine-snapper-restore.lock
  n="$(update_booted)"
  if [[ -n $n ]]; then
    result="$(jq -r --argjson n "$n" '[.runs[]? | select(.snapshot == $n)][0].result // ""' "$(update_state)/update.json" 2>/dev/null || true)"
    cat <<EOF
You're running snapshot $(update_label "$n")${result:+, taken before an update that $(update_how "$result")}.
The system here isn't kept until it's restored; your files in /home are your current ones.

Restoring makes this snapshot your system again. The system you booted away from is kept
as a backup snapshot, so this can be undone too.
EOF
    read -r -p $'\nRestore it now? [y/N] ' answer || answer=n
    [[ $answer =~ ^[Yy] ]] || { echo "Nothing changed. Rebooting normally goes back to the current system."; return 0; }
    # A restore that was killed leaves its lock behind (until a reboot), and every later one refuses.
    if [[ -e $lock ]] && ! pgrep -f 'limine-snapper-sync --restore' >/dev/null; then sudo rm -f "$lock"; fi
    echo
    cat <<'EOF'
limine-snapper-restore asks three things:
  - to confirm: press r, then Enter;
  - a description for the backup of the current system: a few words, or just Enter;
  - whether to reboot: Enter (the restored system starts with the reboot).
EOF
    echo
    sudo limine-snapper-restore
    return
  fi

  # The newest run that didn't end well ("running" is one that never got to say).
  run="$(update_runs | jq -c 'select(.result != "ok")' | head -n1)"
  if [[ -n $run ]] && [[ "$(update_runs | head -n1)" == "$run" ]]; then
    n="$(jq -r .snapshot <<<"$run")"
    result="$(jq -r .result <<<"$run")"
    echo "The last update (snapshot $(update_label "$n")) $(update_how "$result")."
    update_snapshot=$n
    update_guide "$n"
    return 0
  fi
  if [[ -z "$(update_runs)" ]]; then
    echo "No fledge update has taken a snapshot yet: there's nothing to go back to."
    return 0
  fi
  echo "The last update finished. Snapshots from before each update, newest first:"
  while read -r run; do
    printf '  %s │ %s  (%s)\n' "$(jq -r .snapshot <<<"$run")" "$(jq -r .date <<<"$run")" "$(update_how "$(jq -r .result <<<"$run")")"
  done < <(update_runs)
  n="$(update_runs | head -n1 | jq -r .snapshot)"
  update_explain_boot "$n"
}

update_main() {
  case "${1:-}" in
    check)
      shift
      case "${1:-}" in
        "") update_check; update_print ;;
        --json) update_check; update_json ;;
        *) update_usage; return 2 ;;
      esac
      ;;
    recover) (($# == 1)) || { update_usage; return 2; }; update_recover ;;
    "") update_run false ;;
    --yes | -y) (($# == 1)) || { update_usage; return 2; }; update_run true ;;
    *) update_usage; return 2 ;;
  esac
}
