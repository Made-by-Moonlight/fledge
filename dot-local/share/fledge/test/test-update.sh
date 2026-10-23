#!/usr/bin/env bash
# Tests for `fledge update` and `fledge version`, with stubs for the package tools,
# snapper and sudo, and a scratch checkout whose origin carries release tags.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
FLEDGE="$HERE/../bin/fledge"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export LOG="$T/calls" FLEDGE_REPO="$T/checkout" FLEDGE_MODULES_DIR="$T/modules"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$T/bin" "$T/modules/6.0-test"

# Stubs log "<name> <args>" and answer from FAKE_* variables.
stub() { printf '#!/bin/bash\necho "%s $*" >>"$LOG"\n%s\n' "$1" "$2" >"$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub sudo 'exec "$@"'
stub checkupdates 'printf "%s" "${FAKE_CU:-}"; [[ -n ${FAKE_CU_ERR:-} ]] && { echo "$FAKE_CU_ERR" >&2; exit 1; }; [[ -n ${FAKE_CU:-} ]] || exit 2'
stub paru 'if [[ $1 == -Qua ]]; then printf "%s" "${FAKE_AUR:-}"; [[ -n ${FAKE_AUR_ERR:-} ]] && echo "$FAKE_AUR_ERR" >&2; exit 1; fi'
stub fwupdmgr '[[ $1 == get-updates ]] && echo "${FAKE_FW:-{\"Devices\":[]\}}"; exit 0'
stub pacman 'exit ${FAKE_PACMAN_RC:-0}'
stub snapper '[[ $3 == get-config ]] && exit ${FAKE_NOSNAP:-0}; [[ $3 == create && $5 == pre ]] && echo 7; exit 0'
stub uname 'echo 6.0-test'
stub systemctl 'exit 0'
stub qs 'exit 0'
export PATH="$T/bin:$PATH"

# origin: v1 → v2 on main; the checkout starts at v1, tracking origin/main.
git init -q -b main "$T/src"
( cd "$T/src" && mkdir cachyos && printf '#!/bin/bash\necho "bootstrap $(git -C "$(dirname "$0")/.." describe --tags)" >>"$LOG"\n' >cachyos/bootstrap.sh \
  && git add . && git commit -qm one && git tag v2026.10.01 \
  && echo two >f && git add f && git commit -qm two && git tag v2026.10.02 \
  && echo three >g && git add g && git commit -qm three )
git clone -q --bare "$T/src" "$T/origin.git"
fresh() { # <ref>: a release checkout at <ref>
  rm -rf "$FLEDGE_REPO"; git clone -q "$T/origin.git" "$FLEDGE_REPO"
  git -C "$FLEDGE_REPO" reset -q --hard "$1"
}
json() { "$FLEDGE" update check --json 2>/dev/null | jq -c "$1"; }
jsonr() { "$FLEDGE" update check --json 2>/dev/null | jq -r "$1"; }

# --- check ---
fresh v2026.10.01
check "a release behind the newest tag offers it" '{"from":"v2026.10.01","to":"v2026.10.02"}' "$(json .fledge)"
check "version is the tag" v2026.10.01 "$("$FLEDGE" version)"
check "no packages pending" "0 0 0" "$(jsonr '"\(.packages) \(.aur) \(.firmware)"')"
check "counts packages, AUR and firmware" "2 1 1" "$(FAKE_CU=$'a 1 -> 2\nb 1 -> 2\n' FAKE_AUR=$'zen 1 -> 2\n' \
  FAKE_FW='{"Devices":[{"Releases":[{}]},{"Releases":[]}]}' jsonr '"\(.packages) \(.aur) \(.firmware)"')"
check "a part that can't be checked is an error, not a failure" '["packages: no network"] 0' \
  "$(FAKE_CU_ERR="no network" jsonr '"\(.errors|tojson) \(.packages)"')"
check "paru's 'nothing' exit isn't an error" '[]' "$(json .errors)"
check "an AUR error is reported" '["AUR: error: rpc down"]' "$(FAKE_AUR_ERR="error: rpc down" json .errors)"

fresh v2026.10.02
check "at the newest tag: nothing for fledge" null "$(json .fledge)"
git -C "$FLEDGE_REPO" switch -q -c feature
check "a feature branch is a dev checkout" '"on branch feature, not main"' "$(json .devReason)"
fresh v2026.10.01; echo x >>"$FLEDGE_REPO/cachyos/bootstrap.sh"
check "uncommitted changes are a dev checkout" '"uncommitted changes"' "$(json .devReason)"
fresh v2026.10.01; touch "$FLEDGE_REPO/untracked"
check "an untracked file isn't" false "$(json .dev)"
fresh origin/main
check "ahead of the newest tag is a dev checkout" '"main is ahead of v2026.10.02"' "$(json .devReason)"
fresh v2026.10.01; ( cd "$FLEDGE_REPO" && echo local >l && git add l && git commit -qm local )
check "local commits: diverged, never rewound" '"main has diverged from v2026.10.02"' "$(json .devReason)"
check "and fledge isn't offered" null "$(json .fledge)"

# --- the run ---
fresh v2026.10.02
: >"$LOG"
out="$("$FLEDGE" update --yes 2>&1)"; rc=$?
check "nothing pending: exit 0" 0 "$rc"
contains "nothing pending: says so" "Everything is up to date." "$out"
check "nothing pending: no snapshot, no pacman" "" "$(grep -E '^(snapper -c root create|pacman)' "$LOG")"

fresh v2026.10.01
: >"$LOG"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_AUR=$'zen 1 -> 2\n' "$FLEDGE" update --yes 2>&1)"; rc=$?
check "full run: exit 0" 0 "$rc"
check "full run: the steps, in order" \
"snapper -c root create --type pre
pacman -Syu --noconfirm
paru -Sua --noconfirm
bootstrap v2026.10.02
snapper -c root create --type post --pre-number 7" \
  "$(grep -E '^(snapper -c root create|pacman|paru -S|bootstrap)' "$LOG" | sed 's/ --cleanup-algorithm.*--pre-number/ --pre-number/; s/ --cleanup-algorithm.*//')"
contains "full run: asks the bar to recheck" "qs -c fledge ipc call shell recheck" "$(cat "$LOG")"
check "fledge moved to the tag, still on main" "main v2026.10.02" \
  "$(git -C "$FLEDGE_REPO" branch --show-current) $(git -C "$FLEDGE_REPO" describe --tags)"
contains "kernel unchanged: no reboot" "Updated." "$out"

fresh v2026.10.02
: >"$LOG"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 FAKE_AUR=$'zen 1 -> 2\n' "$FLEDGE" update --yes 2>&1)"; rc=$?
check "a failing step: exit 1" 1 "$rc"
contains "a failing step: names it" "Packages failed" "$out"
contains "a failing step: names the snapshot" "Snapshots › 7" "$out"
check "a failing step: nothing after it runs" "" "$(grep -E '^(paru -S|snapper .*post)' "$LOG")"

fresh v2026.10.02
: >"$LOG"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_NOSNAP=1 "$FLEDGE" update --yes 2>&1)"; rc=$?
check "no snapper config: still updates" 0 "$rc"
contains "no snapper config: says so" "without a snapshot" "$out"
check "no snapper config: no snapshot taken" "" "$(grep 'snapper -c root create' "$LOG")"

rmdir "$T/modules/6.0-test"
out="$(FAKE_CU=$'a 1 -> 2\n' "$FLEDGE" update --yes 2>&1)"
contains "kernel upgraded: says reboot" "reboot to use it" "$out"
mkdir "$T/modules/6.0-test"

out="$(FAKE_CU=$'a 1 -> 2\n' "$FLEDGE" update <<<n 2>&1)"; rc=$?
check "declined: exit 0" 0 "$rc"
contains "declined: nothing changed" "Nothing changed." "$out"

# --- dispatch ---
"$FLEDGE" update bogus >/dev/null 2>&1; check "unknown update action: usage" 2 "$?"
"$FLEDGE" update check --bogus >/dev/null 2>&1; check "unknown check option: usage" 2 "$?"
contains "help update lists the builtin and libexec actions" "fledge update check" "$("$FLEDGE" help update)"
contains "help update still lists firmware" "fledge update firmware" "$("$FLEDGE" help update)"
mkdir -p "$T/libexec"; printf '#!/bin/bash\necho "firmware ran $*"\n' >"$T/libexec/update-firmware"; chmod +x "$T/libexec/update-firmware"
check "update firmware still runs libexec" "firmware ran " "$(FLEDGE_LIBEXEC="$T/libexec" "$FLEDGE" update firmware)"

# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
