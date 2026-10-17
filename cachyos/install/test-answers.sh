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

f="$(mk ok 600 $'# written by fledge-install\nDISK=/dev/disk/by-id/nvme-X\nDISK_CONFIRMED=yes\n\nHOSTNAME=glaux\nUSER_PASSWORD=pa=ss word\nLUKS_PASSPHRASE=luks\n')"
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

ok() { "$@" && echo yes || echo no; }
check "username: simple"             yes "$(ok valid_username ethan)"
check "username: digits, _ and -"    yes "$(ok valid_username e_b-2)"
check "username: leading underscore" yes "$(ok valid_username _svc)"
check "username: uppercase rejected"  no "$(ok valid_username Ethan)"
check "username: leading digit"       no "$(ok valid_username 2ethan)"
check "username: leading dash"        no "$(ok valid_username -ethan)"
check "username: slash rejected"      no "$(ok valid_username 'a/b')"
check "username: space rejected"      no "$(ok valid_username 'a b')"
check "username: empty rejected"      no "$(ok valid_username '')"
check "username: root rejected"       no "$(ok valid_username root)"
check "username: 32 chars ok"        yes "$(ok valid_username "$(printf 'a%.0s' {1..32})")"
check "username: 33 chars rejected"   no "$(ok valid_username "$(printf 'a%.0s' {1..33})")"
check "hostname: simple"            yes "$(ok valid_hostname glaux)"
check "hostname: digits and dash"   yes "$(ok valid_hostname ninox-2)"
check "hostname: uppercase rejected" no "$(ok valid_hostname Glaux)"
check "hostname: leading dash"       no "$(ok valid_hostname -glaux)"
check "hostname: trailing dash"      no "$(ok valid_hostname glaux-)"
check "hostname: dot rejected"       no "$(ok valid_hostname glaux.local)"
check "hostname: empty rejected"     no "$(ok valid_hostname '')"
check "hostname: 63 chars ok"       yes "$(ok valid_hostname "$(printf 'a%.0s' {1..63})")"
check "hostname: 64 chars rejected"  no "$(ok valid_hostname "$(printf 'a%.0s' {1..64})")"

f="$T/u.env"; printf 'USERNAME=ethan\n' > "$f"; chmod 600 "$f"
check "answers: USERNAME is an allowed key" "ethan" "$( load_answers "$f" && printf '%s' "$USERNAME" )"

FIX="$DIR/test/fixtures"
check "xkb: known layout"         yes "$(ok valid_xkb_layout gb "$FIX/base.lst")"
check "xkb: two layouts"          yes "$(ok valid_xkb_layout us,de "$FIX/base.lst")"
check "xkb: unknown layout"        no "$(ok valid_xkb_layout zz "$FIX/base.lst")"
check "xkb: variant is not a layout" no "$(ok valid_xkb_layout dvorak "$FIX/base.lst")"
check "xkb: injection refused"     no "$(ok valid_xkb_layout 'us;rm' "$FIX/base.lst")"
check "xkb: empty layout refused"  no "$(ok valid_xkb_layout '' "$FIX/base.lst")"
check "xkb variant: empty ok"     yes "$(ok valid_xkb_variant '')"
check "xkb variant: name"         yes "$(ok valid_xkb_variant dvorak)"
check "xkb variant: bad chars"     no "$(ok valid_xkb_variant 'a b')"

check "mount: under home"           yes "$(ok valid_mount_path /home/ethan/storage1)"
check "mount: own top-level dir"    yes "$(ok valid_mount_path /data)"
check "mount: under /mnt"           yes "$(ok valid_mount_path /mnt/games)"
check "mount: relative refused"      no "$(ok valid_mount_path storage1)"
# shellcheck disable=SC2088  # a literal ~ on purpose: callers expand it first
check "mount: tilde refused"         no "$(ok valid_mount_path '~/storage1')"
check "mount: root refused"          no "$(ok valid_mount_path /)"
check "mount: a home itself refused" no "$(ok valid_mount_path /home/ethan)"
check "mount: /home refused"         no "$(ok valid_mount_path /home)"
check "mount: /mnt refused"          no "$(ok valid_mount_path /mnt)"
check "mount: system tree refused"   no "$(ok valid_mount_path /var/lib/x)"
check "mount: /boot refused"         no "$(ok valid_mount_path /boot)"
check "mount: dotdot refused"        no "$(ok valid_mount_path /home/ethan/../root)"
check "mount: trailing slash refused" no "$(ok valid_mount_path /data/)"
check "mount: space refused"         no "$(ok valid_mount_path '/data/my disk')"
check "mount: comma refused"         no "$(ok valid_mount_path /data,x)"
check "mount: hidden dir refused"    no "$(ok valid_mount_path /home/ethan/.config)"
check "mount: inside hidden refused"  no "$(ok valid_mount_path /home/ethan/.local/share/x)"
check "mount: hidden top-level refused" no "$(ok valid_mount_path /.data)"
check "mount: dot inside a name ok"  yes "$(ok valid_mount_path /data/games.old)"
check "mount: ~/proj refused"         no "$(ok valid_mount_path /home/ethan/proj)"
check "mount: inside ~/proj refused"  no "$(ok valid_mount_path /home/ethan/proj/slievr-cachy)"
check "mount: ~/projects ok"         yes "$(ok valid_mount_path /home/ethan/projects)"
check "mount: deeper proj ok"        yes "$(ok valid_mount_path /home/ethan/storage1/proj)"
check "data mounts: ~/proj refused"  1 "$(parse_data_mounts 'a-1:/home/e/proj' >/dev/null; echo $?)"

check "data mounts: empty spec"  "" "$(parse_data_mounts '')"
check "data mounts: two entries" $'aaaa-1\t/home/e/s1\nBB-2\t/data' "$(parse_data_mounts 'aaaa-1:/home/e/s1,BB-2:/data')"
check "data mounts: duplicate path"  1 "$(parse_data_mounts 'a-1:/data,b-2:/data' >/dev/null; echo $?)"
check "data mounts: duplicate uuid"  1 "$(parse_data_mounts 'a-1:/data,a-1:/d2' >/dev/null; echo $?)"
check "data mounts: system path"     1 "$(parse_data_mounts 'a-1:/usr' >/dev/null; echo $?)"
check "data mounts: no colon"        1 "$(parse_data_mounts 'a-1' >/dev/null; echo $?)"
check "data mounts: bad uuid chars"  1 "$(parse_data_mounts 'a/1:/data' >/dev/null; echo $?)"

f="$(mk keys 600 $'XKB_LAYOUT=gb\nXKB_VARIANT=\nDATA_MOUNTS=a-1:/data\n')"
check "answers: new keys load" "gb||a-1:/data" "$( load_answers "$f" && printf '%s|%s|%s' "$XKB_LAYOUT" "$XKB_VARIANT" "$DATA_MOUNTS" )"

exit $fail
