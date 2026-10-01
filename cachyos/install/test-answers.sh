#!/usr/bin/env bash
# Unit tests for lib/answers.sh. No VM.
#   bash cachyos/install/test-answers.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
# shellcheck source=SCRIPTDIR/lib/answers.sh
source "$DIR/lib/answers.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mk() { # <name> <mode> <content>
  printf '%s' "$3" > "$T/$1"; chmod "$2" "$T/$1"; echo "$T/$1"
}

f="$(mk ok 600 $'# written by mbm-configurator\nDISK=/dev/disk/by-id/nvme-X\nDISK_CONFIRMED=yes\n\nHOSTNAME=glaux\nUSER_PASSWORD=pa=ss word\nLUKS_PASSPHRASE=luks\n')"
out="$( load_answers "$f" && printf '%s|%s|%s|%s|%s' "$DISK" "$DISK_CONFIRMED" "$HOSTNAME" "$USER_PASSWORD" "$LUKS_PASSPHRASE" )"
check "answers: loads keys, keeps '=' and spaces in values" \
  "/dev/disk/by-id/nvme-X|yes|glaux|pa=ss word|luks" "$out"
check "answers: file deleted after load" "gone" "$([[ -e "$f" ]] && echo present || echo gone)"

f="$(mk unknown 600 $'DISK=/dev/x\nEVIL=1\n')"
check "answers: unknown key rejected" "1" "$( load_answers "$f" 2>/dev/null; echo $? )"
check "answers: rejected file kept"   "present" "$([[ -e "$f" ]] && echo present || echo gone)"

f="$(mk loose 644 $'DISK=/dev/x\n')"
check "answers: world-readable file rejected" "1" "$( load_answers "$f" 2>/dev/null; echo $? )"

f="$(mk bad 600 $'USER_PASSWORD secret\n')"
err="$( load_answers "$f" 2>&1 )"; rc=$?
check "answers: malformed line rejected" "1" "$rc"
check "answers: errors never echo values" "" "$(grep -o 'secret' <<<"$err")"

check "answers: missing file rejected" "1" "$( load_answers "$T/nope" 2>/dev/null; echo $? )"

exit $fail
