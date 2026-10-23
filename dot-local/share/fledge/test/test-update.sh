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
export LOG="$T/calls" FLEDGE_REPO="$T/checkout" FLEDGE_MODULES_DIR="$T/modules" FLEDGE_STATE="$T/state" FLEDGE_CMDLINE="$T/cmdline"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$T/bin" "$T/modules/6.0-test"

# Stubs log "<name> <args>" and answer from FAKE_* variables.
stub() { printf '#!/bin/bash\necho "%s $*" >>"$LOG"\n%s\n' "$1" "$2" >"$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub sudo 'exec "$@"'
stub checkupdates 'printf "%s" "${FAKE_CU:-}"; [[ -n ${FAKE_CU_ERR:-} ]] && { echo "$FAKE_CU_ERR" >&2; exit 1; }; [[ -n ${FAKE_CU:-} ]] || exit 2'
stub paru 'if [[ $1 == -Qua ]]; then printf "%s" "${FAKE_AUR:-}"; [[ -n ${FAKE_AUR_ERR:-} ]] && echo "$FAKE_AUR_ERR" >&2; exit 1; fi'
stub fwupdmgr '[[ $1 == get-updates ]] && echo "${FAKE_FW:-{\"Devices\":[]\}}"; exit 0'
# FAKE_PACMAN_INT: Ctrl+C during pacman (its parent is the update: sudo is exec'd).
stub pacman '[[ -n ${FAKE_PACMAN_INT:-} ]] && kill -INT $PPID; exit ${FAKE_PACMAN_RC:-0}'
stub snapper '[[ $3 == get-config ]] && exit ${FAKE_NOSNAP:-0}; [[ $3 == create && $5 == pre ]] && echo 7
[[ $3 == --jsonout ]] && echo "{\"root\":[{\"number\":7,\"date\":\"2026-10-23 21:24:26\"}]}"; exit 0'
stub uname 'echo 6.0-test'
stub systemctl 'exit 0'
stub qs 'exit 0'
stub limine-snapper-restore 'exit 0'
echo "root=/dev/mapper/root rootflags=subvol=@ rw" >"$T/cmdline"
export PATH="$T/bin:$PATH"

# origin: v1 → v2 on main; the checkout starts at v1, tracking origin/main.
git init -q -b main "$T/src"
# Its bootstrap logs, fails under FAKE_BOOT_FAIL, and records what finished like the real one.
mkdir -p "$T/src/cachyos" "$T/state"
cat >"$T/src/cachyos/bootstrap.sh" <<'EOS'
#!/bin/bash
repo="$(dirname "$0")/.."
echo "bootstrap $(git -C "$repo" describe --tags)" >>"$LOG"
[[ -n ${FAKE_BOOT_FAIL:-} ]] && exit 1
git -C "$repo" describe --tags --always --dirty >"$FLEDGE_STATE/bootstrapped"
EOS
( cd "$T/src" && git add . && git commit -qm one && git tag v2026.10.01 \
  && echo two >f && git add f && git commit -qm two && git tag v2026.10.02 \
  && echo three >g && git add g && git commit -qm three )
git clone -q --bare "$T/src" "$T/origin.git"
fresh() { # <ref>: a release checkout at <ref>
  rm -rf "$FLEDGE_REPO" "$FLEDGE_STATE"; mkdir -p "$FLEDGE_STATE"; git clone -q "$T/origin.git" "$FLEDGE_REPO"
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
contains "kernel's modules gone: says reboot" "Reboot to start using: the kernel." "$out"
mkdir "$T/modules/6.0-test"

out="$(FAKE_CU=$'a 1 -> 2\n' "$FLEDGE" update <<<n 2>&1)"; rc=$?
check "declined: exit 0" 0 "$rc"
contains "declined: nothing changed" "Nothing changed." "$out"

# --- reboot ---
fresh v2026.10.02
out="$(FAKE_CU=$'mesa 1 -> 2\n' "$FLEDGE" update --yes 2>&1)"
contains "mesa alone: no reboot" "Updated." "$out"
check "mesa alone: no reboot (really)" "" "$(grep -o 'Reboot to' <<<"$out")"
out="$(FAKE_CU=$'linux-cachyos 1 -> 2\nlinux-cachyos-headers 1 -> 2\nmesa 1 -> 2\nlinux-firmware-amdgpu 1 -> 2\n' \
  FAKE_AUR=$'nvidia-beta 1 -> 2\n' "$FLEDGE" update --yes 2>&1)"
contains "kernel, firmware, nvidia: named (headers aren't)" \
  "Reboot to start using: linux-cachyos, linux-firmware-amdgpu, nvidia-beta." "$out"
out="$(FAKE_CU=$'amd-ucode 1 -> 2\n' "$FLEDGE" update <<<$'y\ny' 2>&1)"
contains "microcode: asks to reboot" "Reboot to start using: amd-ucode." "$out"
check "and reboots on yes" "systemctl reboot" "$(grep '^systemctl' "$LOG" | tail -n1)"

# --- the run's record ---
fresh v2026.10.02
FAKE_CU=$'a 1 -> 2\n' "$FLEDGE" update --yes >/dev/null 2>&1
check "a finished run is recorded" '[{"snapshot":7,"date":"2026-10-23 21:24:26","result":"ok"}]' "$(jq -c .runs "$FLEDGE_STATE/update.json")"
FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 "$FLEDGE" update --yes >/dev/null 2>&1
check "a failed one too, by step" '"failed: Packages"' "$(jq -c '.runs[-1].result' "$FLEDGE_STATE/update.json")"
check "a snapshot number used again replaces the old record" 1 "$(jq '[.runs[] | select(.snapshot == 7)] | length' "$FLEDGE_STATE/update.json")"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 "$FLEDGE" update --yes 2>&1)"
contains "the failure names the snapshot as the boot menu does" "Snapshots › 7 │ 2026-10-23 21:24:26" "$out"
check "never undochange (really)" "" "$(grep -o undochange <<<"$out")"

# --- Ctrl+C ---
fresh v2026.10.02
: >"$LOG"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_AUR=$'zen 1 -> 2\n' FAKE_PACMAN_INT=1 "$FLEDGE" update --yes 2>&1)"; rc=$?
check "interrupted: exit 1, not 130 (the terminal stays open)" 1 "$rc"
contains "interrupted: says so" "Packages interrupted" "$out"
check "interrupted: recorded" '"interrupted: Packages"' "$(jq -c '.runs[-1].result' "$FLEDGE_STATE/update.json")"
check "interrupted: nothing after it ran" "" "$(grep -E '^(paru -S|snapper .*post)' "$LOG")"

# --- the guide ---
fresh v2026.10.02
: >"$LOG"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 "$FLEDGE" update <<<$'y\n3' 2>&1)"; rc=$?
check "guide, leave it: exit 1" 1 "$rc"
contains "guide offers going back" "2  Go back to before the update" "$out"
contains "guide, leave it: points at recover" "To come back here later: fledge update recover" "$out"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 "$FLEDGE" update <<<$'y\n2\ny' 2>&1)"
contains "guide, go back: names the entry" "boot  7 │ 2026-10-23 21:24:26" "$out"
check "guide, go back: reboots on yes" "systemctl reboot" "$(grep '^systemctl' "$LOG" | tail -n1)"
: >"$LOG"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 "$FLEDGE" update <<<$'y\n1' 2>&1)"
check "guide, try again: runs the update again" 2 "$(grep -c '^checkupdates' "$LOG")"
out="$(FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 FAKE_NOSNAP=1 "$FLEDGE" update <<<$'y\n3' 2>&1)"
check "no snapshot: no going back offered" "" "$(grep -o 'Go back' <<<"$out")"

# --- an unfinished bootstrap ---
fresh v2026.10.01
: >"$LOG"
FAKE_BOOT_FAIL=1 "$FLEDGE" update --yes >/dev/null 2>&1
check "bootstrap failed: marked unfinished" unfinished "$(cat "$FLEDGE_STATE/bootstrapped")"
check "the next check offers it again" "true null" "$(jsonr '"\(.bootstrap) \(.fledge)"')"
"$FLEDGE" update --yes >/dev/null 2>&1
check "the next run runs it" "bootstrap v2026.10.02
bootstrap v2026.10.02" "$(grep '^bootstrap' "$LOG")"
check "and then it's done" false "$(json .bootstrap)"
rm "$FLEDGE_STATE/bootstrapped"
check "no record (an older install): not offered" false "$(json .bootstrap)"

# --- recover ---
fresh v2026.10.02
out="$("$FLEDGE" update recover </dev/null 2>&1)"
contains "recover, no runs: nothing to go back to" "nothing to go back to" "$out"
FAKE_CU=$'a 1 -> 2\n' FAKE_PACMAN_RC=1 "$FLEDGE" update --yes >/dev/null 2>&1
out="$("$FLEDGE" update recover <<<3 2>&1)"
contains "recover after a failure: names it" "The last update (snapshot 7 │ 2026-10-23 21:24:26) failed (Packages)." "$out"
contains "recover after a failure: the guide" "1  Try again" "$out"
FAKE_CU=$'a 1 -> 2\n' "$FLEDGE" update --yes >/dev/null 2>&1
out="$("$FLEDGE" update recover <<<n 2>&1)"
contains "recover after a good run: lists the snapshots" "7 │ 2026-10-23 21:24:26  (finished)" "$out"
echo "root=/dev/mapper/root rootflags=subvol=/@/.snapshots/7/snapshot rw" >"$T/cmdline"
: >"$LOG"
out="$("$FLEDGE" update recover <<<n 2>&1)"
contains "booted into a snapshot: says which" "You're running snapshot 7 │ 2026-10-23 21:24:26" "$out"
check "declined: no restore" "" "$(grep limine-snapper-restore "$LOG")"
"$FLEDGE" update recover <<<y >/dev/null 2>&1
check "accepted: restores, as root" "sudo limine-snapper-restore" "$(grep "^sudo limine-snapper-restore" "$LOG")"
rm "$FLEDGE_STATE/update.json"
out="$("$FLEDGE" update recover <<<n 2>&1)"
contains "a snapshot fledge has no record of: still guided" "You're running snapshot 7." "$out"
echo "root=/dev/mapper/root rootflags=subvol=@ rw" >"$T/cmdline"

# --- dispatch ---
"$FLEDGE" update bogus >/dev/null 2>&1; check "unknown update action: usage" 2 "$?"
"$FLEDGE" update check --bogus >/dev/null 2>&1; check "unknown check option: usage" 2 "$?"
"$FLEDGE" update recover now >/dev/null 2>&1; check "recover takes no arguments" 2 "$?"
contains "help update lists the builtin and libexec actions" "fledge update check" "$("$FLEDGE" help update)"
contains "help update still lists firmware" "fledge update firmware" "$("$FLEDGE" help update)"
mkdir -p "$T/libexec"; printf '#!/bin/bash\necho "firmware ran $*"\n' >"$T/libexec/update-firmware"; chmod +x "$T/libexec/update-firmware"
check "update firmware still runs libexec" "firmware ran " "$(FLEDGE_LIBEXEC="$T/libexec" "$FLEDGE" update firmware)"

# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
