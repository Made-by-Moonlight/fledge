# shellcheck shell=bash
# fledge update [--yes]: snapshot /, update packages (pacman, then the AUR
# through paru), move fledge to its newest release tag and re-run bootstrap,
# update firmware, then say whether to reboot. Only the parts with something
# pending run. A failing step stops the run and names the snapshot to boot.
# fledge update check [--json]: what's pending; no root, changes nothing (the
# bar runs it). A part that can't be checked (offline, a tool missing) is
# reported, counts 0, and doesn't fail the check.
# fledge version: the release this checkout is at (git describe).
#
# fledge moves only a release checkout: on main, no uncommitted changes, and
# HEAD an ancestor of the new tag. Anything else is a dev checkout (a feature
# branch, local commits) and is never moved; packages and firmware still are.
# FLEDGE_REPO (the checkout) and FLEDGE_MODULES_DIR (/usr/lib/modules) are for tests.

update_usage() { echo "usage: fledge update [--yes] | fledge update check [--json]" >&2; }

update_repo() { printf '%s\n' "${FLEDGE_REPO:-$(cd "$FLEDGE_ROOT/../../.." && pwd)}"; }

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

# Sets U_FROM, U_TO (the tag to move to, or ""), U_DEV, U_PKG, U_AUR, U_FW, U_ERRORS.
update_check() {
  local repo out err rc newest
  repo="$(update_repo)"
  U_FROM="" U_TO="" U_DEV="" U_PKG=0 U_AUR=0 U_FW=0 U_ERRORS=()
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
  fi

  # checkupdates: 0 = updates listed, 2 = none, anything else = couldn't check.
  if ! command -v checkupdates >/dev/null; then
    U_ERRORS+=("packages: checkupdates is missing (pacman-contrib)")
  else
    rc=0; out="$(checkupdates 2>"$err")" || rc=$?
    case $rc in
      0) U_PKG="$(grep -c . <<<"$out")" ;;
      2) ;;
      *) U_ERRORS+=("packages: $(tail -n1 "$err")") ;;
    esac
  fi

  # paru -Qua exits 1 both when nothing is out of date and on errors; only stderr tells them apart.
  if ! command -v paru >/dev/null; then
    U_ERRORS+=("AUR: paru is missing")
  else
    out="$(paru -Qua 2>"$err")" || true
    if [[ -n $out ]]; then U_AUR="$(grep -c . <<<"$out")"
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

update_total() { echo $((U_PKG + U_AUR + U_FW + (${#U_TO} > 0 ? 1 : 0))); }

update_print() {
  local e
  if [[ -n $U_DEV ]]; then printf '  %-9s skipped: %s\n' fledge "$U_DEV"
  elif [[ -n $U_TO ]]; then printf '  %-9s %s → %s\n' fledge "$U_FROM" "$U_TO"
  else printf '  %-9s %s (newest)\n' fledge "$U_FROM"; fi
  printf '  %-9s %s\n' packages "$U_PKG" AUR "$U_AUR" firmware "$U_FW"
  for e in "${U_ERRORS[@]}"; do printf '  couldn'\''t check %s\n' "$e"; done
}

update_json() {
  jq -n --arg from "$U_FROM" --arg to "$U_TO" --arg dev "$U_DEV" \
    --argjson pkg "$U_PKG" --argjson aur "$U_AUR" --argjson fw "$U_FW" \
    '{fledge: (if $to == "" then null else {from: $from, to: $to} end),
      packages: $pkg, aur: $aur, firmware: $fw,
      dev: ($dev != ""), devReason: $dev, errors: $ARGS.positional}' --args "${U_ERRORS[@]}"
}

update_snapshot="" # the pre snapshot's number, once taken

update_fail() { # <step>
  echo >&2
  echo "fledge update: $1 failed; the steps after it didn't run." >&2
  if [[ -n $update_snapshot ]]; then
    echo "To go back to before the update: boot Snapshots › $update_snapshot in the Limine menu," >&2
    echo "or run: sudo snapper -c root undochange $update_snapshot..0" >&2
  fi
  exit 1
}

update_step() { # <name> <command...>
  printf '\n\e[1m==> %s\e[0m\n' "$1"
  "${@:2}" || update_fail "$1"
}

update_run() { # <yes: true|false>
  local yes=$1 repo answer
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

  # No root config: / isn't btrfs, or bootstrap hasn't set snapshots up yet.
  if sudo snapper -c root get-config >/dev/null 2>&1; then
    update_snapshot="$(sudo snapper -c root create --type pre --cleanup-algorithm number \
      --print-number --description "fledge update")" || update_fail "the snapshot"
    echo "Snapshot $update_snapshot taken (Limine › Snapshots)."
  else
    echo "No snapper config for /: updating without a snapshot." >&2
  fi

  ((U_PKG)) && update_step "Packages" sudo pacman -Syu "${noconfirm[@]}"
  ((U_AUR)) && update_step "AUR packages" paru -Sua "${noconfirm[@]}"
  # After the packages, so bootstrap's installs go against a synced database.
  if [[ -n $U_TO ]]; then
    update_step "fledge $U_TO" git -C "$repo" merge --ff-only --quiet "$U_TO"
    update_step "Bootstrap ($U_TO)" bash "$repo/cachyos/bootstrap.sh"
  fi
  if ((U_FW)); then
    if [[ $yes == true ]]; then update_step "Firmware" fwupdmgr update --assume-yes --no-reboot-check
    else update_step "Firmware" fwupdmgr update; fi
  fi

  if [[ -n $update_snapshot ]]; then
    sudo snapper -c root create --type post --pre-number "$update_snapshot" --cleanup-algorithm number \
      --description "fledge update" || echo "fledge update: couldn't take the post-update snapshot" >&2
  fi

  echo
  # The kernel package removes the running kernel's modules when it upgrades it.
  if [[ ! -d "${FLEDGE_MODULES_DIR:-/usr/lib/modules}/$(uname -r)" ]]; then
    echo "Updated. The kernel changed: reboot to use it (until then, new USB devices and modules won't load)."
    if [[ $yes != true ]]; then
      read -r -p "Reboot now? [y/N] " answer || answer=n
      [[ $answer =~ ^[Yy] ]] && systemctl reboot
    fi
  else
    echo "Updated."
  fi
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
    "") update_run false ;;
    --yes | -y) (($# == 1)) || { update_usage; return 2; }; update_run true ;;
    *) update_usage; return 2 ;;
  esac
}
