#!/usr/bin/env bash
# Hardware-adaptive CachyOS installer. Run as root in the stock CachyOS live ISO.
#   sudo /path/to/cachyos/install/install-cachyos.sh [--allow-usb] [--answers FILE] [--desktop-only USER]
#
# See ./README.md and ../../docs/superpowers/specs/2026-08-28-bare-metal-install-design.md
set -euo pipefail

HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"     # the fledge checkout being run from
MIRROR_CHECK_HOST="mirror.cachyos.org"

# shellcheck source=profile.sh
source "$HERE/profile.sh"
# shellcheck source=lib/detect.sh
source "$HERE/lib/detect.sh"
# shellcheck source=lib/disk.sh
source "$HERE/lib/disk.sh"
# shellcheck source=lib/answers.sh
source "$HERE/lib/answers.sh"
# shellcheck source=lib/network.sh
source "$HERE/lib/network.sh"
# shellcheck source=lib/progress.sh
source "$HERE/lib/progress.sh"
# shellcheck source=lib/desktop.sh
source "$HERE/lib/desktop.sh"

die()  { printf '\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\e[33mWARN:\e[0m  %s\n' "$*" >&2; }
rule() { printf '\n\e[1m== %s ==\e[0m\n' "$*"; }

# Any non-zero exit marks the running stage as failed for the graphical
# installer (no-op without FLEDGE_PROGRESS). die() lands here too.
# It also removes the temporary NOPASSWD sudoers drop-in of the Desktop stage;
# INT/TERM become exits so Ctrl-C or a GUI cancel run this trap too.
trap 'rc=$?; remove_install_sudoers; if (( rc != 0 )); then progress_fail; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The last two stages. Also the whole of --desktop-only, which the graphical
# installer's "Retry desktop" runs against the still-mounted target.
desktop_and_finish() {
  rule "Desktop (bootstrap.sh in the new system)"
  progress_stage desktop "Desktop"
  if ! run_desktop_stage "$USERNAME"; then
    warn "the desktop layer failed. The system is installed; /mnt is still mounted."
    warn "Retry with --desktop-only $USERNAME, or reboot: firstboot runs it on first boot."
    exit 3
  fi
  rule "Finish"
  progress_stage finish "Finish"
  finish_install
  progress_done
}

ALLOW_USB=0
ANSWERS=""
DESKTOP_ONLY=""
while (( $# )); do
  case "$1" in
    --allow-usb) ALLOW_USB=1 ;;
    --answers)   ANSWERS="${2:?--answers needs a file}"; shift ;;
    --desktop-only) DESKTOP_ONLY="${2:?--desktop-only needs a user}"; shift ;;
    *)           die "unknown argument: $1" ;;
  esac
  shift
done
if [[ -n "$DESKTOP_ONLY" ]]; then
  FLEDGE_STAGE=desktop   # a guard failure below is a Desktop failure, not Prepare
  valid_username "$DESKTOP_ONLY" || die "--desktop-only: not a valid user name: $DESKTOP_ONLY"
  [[ $EUID -eq 0 ]] || die "must run as root"
  mountpoint -q /mnt || die "--desktop-only: the target isn't mounted at /mnt"
  [[ -d "/mnt/home/$DESKTOP_ONLY/proj/fledge" ]] || die "--desktop-only: no staged repo for $DESKTOP_ONLY in /mnt"
  USERNAME="$DESKTOP_ONLY"
  desktop_and_finish
  exit 0
fi
XKB_LAYOUT="us"
XKB_VARIANT=""
DATA_MOUNTS=""
DATA_WIPES=""        # only the answers file can ask for wipes
DATA_WIPES_TSV=""
if [[ -n "$ANSWERS" ]]; then
  load_answers "$ANSWERS" || die "unusable answers file: $ANSWERS"
  for k in DISK HOSTNAME USER_PASSWORD LUKS_PASSPHRASE; do
    [[ -n "${!k:-}" ]] || die "answers file is missing $k"
  done
  if [[ -n "${TIMEZONE:-}" ]]; then
    [[ "$TIMEZONE" != *..* && -f "/usr/share/zoneinfo/$TIMEZONE" ]] \
      || die "answers TIMEZONE is not a valid zone: $TIMEZONE"
  fi
  XKB_LAYOUT="${XKB_LAYOUT:-us}"
  valid_xkb_layout "$XKB_LAYOUT"   || die "answers XKB_LAYOUT is not a known xkb layout: $XKB_LAYOUT"
  valid_xkb_variant "$XKB_VARIANT" || die "answers XKB_VARIANT is malformed: $XKB_VARIANT"
  DATA_MOUNTS_TSV="$(parse_data_mounts "$DATA_MOUNTS")" \
    || die "answers DATA_MOUNTS is malformed, repeats a disk or folder, or uses a system path"
  DATA_WIPES_TSV="$(parse_data_wipes "$DATA_WIPES")" \
    || die "answers DATA_WIPES is malformed, repeats a disk, folder or label, or uses a system path"
  ROOT_PASSWORD="${ROOT_PASSWORD:-}"     # empty -> root locked (chroot-setup.sh)
  # USERNAME is optional (profile.sh has the default) but always re-checked:
  # it reaches useradd, paths and a sed expression.
  valid_username "$USERNAME" || die "answers USERNAME is not a valid login name: $USERNAME"
  # The UI checks it too, but an answers file is the last word: it reaches
  # /etc/hostname and /etc/hosts.
  valid_hostname "$HOSTNAME" || die "answers HOSTNAME is not a valid host name: $HOSTNAME"
fi
progress_stage prepare "Prepare"

########################################################################
rule "Preflight"
########################################################################
[[ $EUID -eq 0 ]]        || die "must run as root"
[[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode (no /sys/firmware/efi)"

missing=()
for c in pacstrap genfstab arch-chroot cryptsetup sgdisk wipefs partprobe \
         mkfs.btrfs mkfs.ext4 mkfs.fat efibootmgr blkid lsblk findmnt lspci; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
(( ${#missing[@]} == 0 )) || die "missing tools in the live env: ${missing[*]}"

grep -qiE 'archiso|cachyos|miso' /proc/cmdline \
  || warn "this doesn't look like a live ISO ( /proc/cmdline has no archiso/cachyos )"
ping -c1 -W2 "$MIRROR_CHECK_HOST" >/dev/null 2>&1 \
  || warn "can't reach $MIRROR_CHECK_HOST - pacstrap will fail without network"
pacman -Sy --noconfirm >/dev/null || die "couldn't sync package databases"
KERNEL_VER="$(pacman -Si "$KERNEL" 2>/dev/null | awk '/^Version/ {print $3; exit}')"
[[ -n "$KERNEL_VER" ]] || die "$KERNEL is not in the configured repos"
(( $(vercmp "$KERNEL_VER" "$MIN_KERNEL") >= 0 )) \
  || die "$KERNEL $KERNEL_VER is older than the required $MIN_KERNEL"

########################################################################
rule "Hardware detection"
########################################################################
UCODE="$(detect_ucode /proc/cpuinfo)" || warn "unknown CPU vendor, defaulting to $UCODE"
LSPCI="$(lspci -nn)"
GPU_PKGS="$(detect_gpu_pkgs "$LSPCI")"
GPU_CMDLINE="$(detect_gpu_cmdline "$LSPCI")"
GPU_MODULES="$(detect_gpu_modules "$LSPCI")"
MEMKB="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
ZRAM_SIZE="$(zram_size "$MEMKB")"
if [[ "${SWAP}" == "hibernate" ]]; then
  SWAPFILE_SIZE="${HIBERNATE_SWAP_SIZE:-$(hibernate_swap_size "$MEMKB")}"
else
  SWAPFILE_SIZE="(none)"
fi

# Without answers (manual run), mount every profile.sh data disk that's here.
if [[ -z "$ANSWERS" ]]; then
  DATA_MOUNTS_TSV=""
  while IFS=$'\t' read -r uuid path; do
    [[ -n "$uuid" ]] || continue
    DATA_MOUNTS_TSV+="$uuid"$'\t'"${path/#\~//home/$USERNAME}"$'\n'
  done < <(data_disk_defaults "$(blkid -s UUID -o value)" "${DATA_DISKS[@]}")
  DATA_MOUNTS_TSV="${DATA_MOUNTS_TSV%$'\n'}"
fi

cat <<EOF

  kernel         : ${KERNEL} ${KERNEL_VER} (minimum ${MIN_KERNEL})
  microcode      : ${UCODE}
  GPU packages   : ${GPU_PKGS:-(none - generic)}
  GPU cmdline    : ${GPU_CMDLINE:-(none)}
  GPU modules    : ${GPU_MODULES:-(none)}
  RAM            : $(( MEMKB / 1024 )) MiB
  zram swap      : ${ZRAM_SIZE} MiB
  hibernate swap : ${SWAPFILE_SIZE}$( [[ "$SWAPFILE_SIZE" != "(none)" ]] && echo " MiB (btrfs swapfile)" )
  hostname       : ${HOSTNAME:-(will prompt)}
  keyboard       : ${XKB_LAYOUT}${XKB_VARIANT:+ (${XKB_VARIANT})}
  data disks     : $(grep -c . <<<"$DATA_MOUNTS_TSV" || true) to mount permanently
  storage wipes  : $(grep -c . <<<"$DATA_WIPES_TSV" || true) drive(s)
EOF

progress_stage disk "Partition & encrypt"
########################################################################
rule "Target disk"
########################################################################
if [[ -n "$ANSWERS" ]]; then
  [[ -b "$DISK" ]] || die "answers DISK is not a block device: $DISK"
  DISK_KNAME="$(realpath "$DISK")"
  DISK_TRAN="$(lsblk -dno TRAN "$DISK_KNAME")"
else
  mapfile -t DISKS < <(list_disks)
  (( ${#DISKS[@]} > 0 )) || die "no candidate disks found"

  echo "Candidate disks:"
  i=0
  for d in "${DISKS[@]}"; do
    printf '  [%d] %s\n' "$i" "$d"
    i=$(( i + 1 ))
  done
  read -rp "Select target disk number (its ENTIRE contents will be destroyed): " idx
  [[ "$idx" =~ ^[0-9]+$ && "$idx" -lt "${#DISKS[@]}" ]] || die "invalid selection"

  DISK_KNAME="$(awk '{print $1}' <<<"${DISKS[$idx]}")"           # /dev/nvme1n1
  DISK_TRAN="$(awk '{print $NF}' <<<"${DISKS[$idx]}")"           # nvme|sata|usb|...
  DISK="$(disk_by_id "$DISK_KNAME")"
fi
DISK_MODEL="$(lsblk -dno MODEL "$DISK_KNAME" | sed 's/[[:space:]]*$//')"

# guards
if findmnt -rno SOURCE | grep -qE "^${DISK_KNAME}([0-9p]|$)"; then
  die "$DISK_KNAME has a mounted partition - refusing"
fi
root_src="$(findmnt -nvo SOURCE / || true)"
[[ "$(lsblk -no PKNAME "$root_src" 2>/dev/null)" == "${DISK_KNAME##*/}" ]] \
  && die "$DISK_KNAME backs the live / - refusing"
if [[ "$DISK_TRAN" == "usb" && $ALLOW_USB -eq 0 ]]; then
  die "$DISK_KNAME is a USB device - pass --allow-usb if you really mean it"
fi
# Data disks are mounted, never formatted: one on the disk about to be erased
# would vanish. The UI hides those; this catches manual runs and bad answers.
while IFS=$'\t' read -r uuid _; do
  [[ -n "$uuid" ]] || continue
  dev="$(blkid -U "$uuid" 2>/dev/null)" || die "data disk $uuid isn't on this machine"
  if [[ "$dev" == "$DISK_KNAME" || "$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1)" == "${DISK_KNAME##*/}" ]]; then
    die "data disk $uuid is on $DISK_KNAME, the disk about to be erased"
  fi
done <<<"$DATA_MOUNTS_TSV"

# Drives to wipe into storage. Same refusals as the target, plus: nothing the
# install keeps may live on one, and its label must stay unique. The UI
# enforces all of this; the answers file is the last word.
WIPE_DISKS=()
declare -A _wipe_seen=()
while IFS=$'\t' read -r wdisk wpath wlabel; do
  [[ -n "$wdisk" ]] || continue
  [[ -b "$wdisk" ]] || die "wipe drive is not a block device: $wdisk"
  wk="$(realpath "$wdisk")"
  [[ "$(lsblk -dno TYPE "$wk" 2>/dev/null)" == disk ]] || die "wipe drive $wdisk is not a whole disk"
  [[ "$wk" != "$DISK_KNAME" ]] || die "wipe drive $wdisk is the install target"
  [[ "$(lsblk -no PKNAME "$root_src" 2>/dev/null)" == "${wk##*/}" ]] && die "wipe drive $wdisk backs the live / - refusing"
  reason="$(busy_reason "$(lsblk -rno TYPE,MOUNTPOINT "$wk" | tail -n +2)")"
  [[ -z "$reason" ]] || die "wipe drive $wdisk is in use ($reason) - refusing"
  while IFS=$'\t' read -r uuid mpath; do
    [[ -n "$uuid" ]] || continue
    dev="$(blkid -U "$uuid" 2>/dev/null || true)"
    [[ -n "$dev" && "$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1)" == "${wk##*/}" ]] \
      && die "data disk $uuid is on $wdisk, a drive to wipe"
    [[ "$mpath" != "$wpath" ]] || die "folder $wpath is used by both a mounted disk and a wiped drive"
  done <<<"$DATA_MOUNTS_TSV"
  WIPE_DISKS+=("$wk"); _wipe_seen["$wk"]=1
done <<<"$DATA_WIPES_TSV"
if (( ${#WIPE_DISKS[@]} )); then
  live_root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n1)"
  kept_labels=""
  while read -r d; do
    [[ -n "$d" && "$d" != "$DISK_KNAME" && -z "${_wipe_seen[$d]:-}" && "${d##*/}" != "$live_root_disk" ]] || continue
    kept_labels+="$(lsblk -rno LABEL "$d")"$'\n'
  done < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}')
  kept_labels="$(sed 's/\\x20/ /g' <<<"$kept_labels" | tr 'A-Z' 'a-z')"   # lsblk -r escapes spaces
  while IFS=$'\t' read -r _ _ wlabel; do
    [[ -n "$wlabel" ]] || continue
    grep -qxF -- "${wlabel,,}" <<<"$kept_labels" && die "another drive is already called $wlabel"
  done <<<"$DATA_WIPES_TSV"
fi

echo
echo "Target: $DISK"
echo "  model : ${DISK_MODEL:-(unknown)}"
echo "  size  : $(lsblk -dno SIZE "$DISK_KNAME")"
echo "  transport: ${DISK_TRAN}"
echo "  current layout:"
sgdisk -p "$DISK_KNAME" 2>/dev/null | sed 's/^/    /' || echo "    (no GPT / unreadable)"
echo
if [[ "${DISK_CONFIRMED:-}" != yes ]]; then
  read -rp "Type the disk MODEL exactly to confirm [${DISK_MODEL}]: " typed
  [[ "$typed" == "$DISK_MODEL" ]] || die "model string did not match - aborting"
  read -rp "Last chance. Type YES to DESTROY $DISK_KNAME: " last
  [[ "$last" == "YES" ]] || die "aborted"
fi

########################################################################
rule "Passphrases"
########################################################################
if [[ -z "$ANSWERS" ]]; then
  read -rsp "New user (${USERNAME}) password: " USER_PASSWORD; echo
  read -rsp "Confirm user password: "                p2;      echo
  [[ "$USER_PASSWORD" == "$p2" && -n "$USER_PASSWORD" ]] || die "user passwords differ/empty"
  read -rsp "New root password: " ROOT_PASSWORD; echo
  read -rsp "Confirm root password: " p2;        echo
  [[ "$ROOT_PASSWORD" == "$p2" && -n "$ROOT_PASSWORD" ]] || die "root passwords differ/empty"
fi

########################################################################
rule "Partitioning + encryption + filesystems"
########################################################################
# Every partition GUID on a drive about to be erased, for the boot-entry
# pruning after the bootloader stage.
mapfile -t ERASED_GUIDS < <(lsblk -rno PARTUUID "$DISK_KNAME" "${WIPE_DISKS[@]}" | grep . || true)

WIPED_UUIDS=()
if [[ -n "$DATA_WIPES_TSV" ]]; then
  rule "Storage drives"
  while IFS=$'\t' read -r wdisk wpath wlabel; do
    [[ -n "$wdisk" ]] || continue
    wuuid="$(format_data_disk "$wdisk" "$wlabel")" || die "couldn't wipe $wdisk"
    DATA_MOUNTS_TSV+="${DATA_MOUNTS_TSV:+$'\n'}$wuuid"$'\t'"$wpath"
    WIPED_UUIDS+=("$wuuid")
  done <<<"$DATA_WIPES_TSV"
fi

partition_disk "$DISK"
luks_format_open "$LUKS_PART"          # LUKS_PASSPHRASE from answers, else prompts x2
make_filesystems
make_swapfile

progress_stage base "Base system"
########################################################################
rule "pacstrap"
########################################################################
pkgs=(
  base "${KERNEL}" "${KERNEL}-headers" linux-firmware
  btrfs-progs cryptsetup mkinitcpio
  "${UCODE}"
  networkmanager sudo git openssh vim
  plymouth
  zram-generator
  limine limine-mkinitcpio-hook efibootmgr
  # From the live ISO's [cachyos] repo, so always current; chroot-setup.sh
  # points the target's pacman.conf at them.
  cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist
)
if [[ -n "$GPU_PKGS" ]]; then
  read -ra gpu_arr <<<"$GPU_PKGS"
  pkgs+=("${gpu_arr[@]}")
fi
echo "Packages: ${pkgs[*]}"
# A single slow file (mirror timeout over Wi-Fi) fails the whole transaction.
# Retry with fresh databases; packages already fetched stay in the target's
# cache, and re-initialising the keyring with -K is idempotent.
for attempt in 1 2 3; do
  pacstrap -K /mnt "${pkgs[@]}" && break
  (( attempt < 3 )) || die "pacstrap failed 3 times - check the network and the log above"
  warn "pacstrap failed (attempt $attempt/3); refreshing package databases and retrying in 10s"
  sleep 10
  pacman -Syy --noconfirm || true
done

progress_stage config "Configure"
########################################################################
rule "fstab"
########################################################################
genfstab -U /mnt >> /mnt/etc/fstab
if [[ "${SWAP}" == "hibernate" ]]; then
  grep -q '^/swap/swapfile ' /mnt/etc/fstab \
    || printf '/swap/swapfile none swap defaults 0 0\n' >> /mnt/etc/fstab
fi

########################################################################
rule "System configuration (chroot)"
########################################################################
install -Dm755 "$HERE/lib/chroot-setup.sh" /mnt/root/chroot-setup.sh
install -Dm644 "$HERE/lib/bootloader.sh"   /mnt/root/bootloader.sh
install -Dm644 "$HERE/lib/cachyos-repos.sh" /mnt/root/cachyos-repos.sh

# Vendored Plymouth theme (graphical boot splash + LUKS prompt). Not stow-
# managed - Plymouth reads themes from a system path. chroot-setup.sh selects it.
rm -rf /mnt/usr/share/plymouth/themes/fledge
install -d /mnt/usr/share/plymouth/themes
cp -r "$HERE/../plymouth-theme/fledge" /mnt/usr/share/plymouth/themes/fledge

arch-chroot /mnt env \
  TIMEZONE="$TIMEZONE" LOCALE="$LOCALE" \
  KEYMAP="$(console_keymap "$XKB_LAYOUT" "$XKB_VARIANT")" XKB_LAYOUT="$XKB_LAYOUT" XKB_VARIANT="$XKB_VARIANT" \
  FLEDGE_PROGRESS="${FLEDGE_PROGRESS:-}" \
  USERNAME="$USERNAME" HOSTNAME="$HOSTNAME" KERNEL="$KERNEL" SWAP="$SWAP" \
  LUKS_NAME="$LUKS_NAME" LUKS_PARTUUID="$LUKS_PARTUUID" \
  EXTRA_CMDLINE="$EXTRA_CMDLINE" GPU_CMDLINE="$GPU_CMDLINE" GPU_MODULES="$GPU_MODULES" \
  ZRAM_SIZE="$ZRAM_SIZE" RESUME_OFFSET="${RESUME_OFFSET:-}" \
  USER_PASSWORD="$USER_PASSWORD" ROOT_PASSWORD="$ROOT_PASSWORD" \
  bash /root/chroot-setup.sh
# The Bootloader marker is printed inside the chroot, so this script's own
# stage must follow it, or a failure in the rest of that stage reports `fail config`.
# shellcheck disable=SC2034  # read by progress_fail in the EXIT trap
FLEDGE_STAGE=boot

rm -f /mnt/root/chroot-setup.sh /mnt/root/bootloader.sh /mnt/root/cachyos-repos.sh

# Firmware entries naming a partition we just erased point at nothing; some
# firmware lists or even tries them first. Entries on kept drives and ones
# without a disk path stay. A failure only warns: the system boots either way.
prune_boot_entries() {
  local efi n new_guid order
  efi="$(efibootmgr -v)" || return 1
  for n in $(stale_boot_entries "$efi" "${ERASED_GUIDS[@]}"); do
    efibootmgr -b "$n" -B >/dev/null || return 1
    echo "removed stale boot entry Boot$n"
  done
  efi="$(efibootmgr -v)" || return 1
  new_guid="$(blkid -s PARTUUID -o value "$ESP_PART")"
  n="$(boot_entry_for "$efi" "$new_guid")"
  [[ -n "$n" ]] || return 0
  order="$(awk '/^BootOrder:/{print $2}' <<<"$efi")"
  efibootmgr -o "$(order_first "$order" "$n")" >/dev/null || return 1
}
prune_boot_entries || warn "couldn't tidy the firmware boot entries; check efibootmgr after the first boot"

add_data_mounts
own_wiped_roots
seed_user_settings "$USERNAME" "$XKB_LAYOUT" "$XKB_VARIANT" \
  "$(arch-chroot /mnt id -u "$USERNAME")" "$(arch-chroot /mnt id -g "$USERNAME")"
# Before the Desktop stage, not inside it: a --desktop-only retry can't know
# the disk passphrase, and must keep what this wrote.
write_autologin "$USERNAME" "$USER_PASSWORD" "$LUKS_PASSPHRASE"

########################################################################
rule "Staging repo + first-boot bootstrap"
########################################################################
# Copy this checkout into the installed system so bootstrap.sh (and the docs)
# are present offline after reboot with no re-staging.
target_home="/mnt/home/${USERNAME}"
mkdir -p "${target_home}/proj"
rm -rf "${target_home}/proj/fledge"
cp -r "$REPO_ROOT" "${target_home}/proj/fledge"

# First-boot service, the fallback: the Desktop stage below runs bootstrap.sh
# before the reboot and disables this on success. If that stage didn't finish,
# firstboot runs bootstrap.sh as the user, unattended, on TTY1, then starts
# SDDM - so a failed bootstrap leaves a TTY + log instead of a broken greeter.
install -Dm755 "$HERE/firstboot/fledge-firstboot.sh"      /mnt/usr/local/sbin/fledge-firstboot.sh
sed -i "s/@USERNAME@/${USERNAME}/g"                        /mnt/usr/local/sbin/fledge-firstboot.sh
install -Dm644 "$HERE/firstboot/fledge-firstboot.service" /mnt/etc/systemd/system/fledge-firstboot.service

arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/proj"
arch-chroot /mnt systemctl enable fledge-firstboot.service

# Networks the live session joined (the installer's Wi-Fi picker saves NM
# keyfiles), so first boot is online on a laptop.
copy_nm_profiles /etc/NetworkManager/system-connections /mnt/etc/NetworkManager/system-connections

desktop_and_finish
cat <<EOF

Install complete. On reboot, unlock the disk; the desktop starts by itself when
the disk and login passwords are the same, otherwise log in.
If anything in the desktop layer is missing, its log is /var/log/fledge-install.log.

EOF
if [[ -z "$ANSWERS" ]]; then
  read -rp "Reboot now? [y/N] " r
  [[ "$r" == [yY] ]] && reboot
fi
