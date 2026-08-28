#!/usr/bin/env bash
# Hardware-adaptive CachyOS installer. Run as root in the stock CachyOS live ISO.
#   sudo /path/to/cachyos/install/install-cachyos.sh [--allow-usb]
#
# See ./README.md and ../../docs/superpowers/specs/2026-08-28-bare-metal-install-design.md
set -euo pipefail

HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
MIRROR_CHECK_HOST="mirror.cachyos.org"

# shellcheck source=profile.sh
source "$HERE/profile.sh"
# shellcheck source=lib/detect.sh
source "$HERE/lib/detect.sh"
# shellcheck source=lib/disk.sh
source "$HERE/lib/disk.sh"

ALLOW_USB=0
[[ "${1:-}" == "--allow-usb" ]] && ALLOW_USB=1

die()  { printf '\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\e[33mWARN:\e[0m  %s\n' "$*" >&2; }
rule() { printf '\n\e[1m== %s ==\e[0m\n' "$*"; }

########################################################################
rule "Preflight"
########################################################################
[[ $EUID -eq 0 ]]        || die "must run as root"
[[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode (no /sys/firmware/efi)"

missing=()
for c in pacstrap genfstab arch-chroot cryptsetup sgdisk wipefs partprobe \
         mkfs.btrfs mkfs.fat efibootmgr blkid lsblk findmnt lspci; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
(( ${#missing[@]} == 0 )) || die "missing tools in the live env: ${missing[*]}"

grep -qiE 'archiso|cachyos|miso' /proc/cmdline \
  || warn "this doesn't look like a live ISO ( /proc/cmdline has no archiso/cachyos )"
ping -c1 -W2 "$MIRROR_CHECK_HOST" >/dev/null 2>&1 \
  || warn "can't reach $MIRROR_CHECK_HOST - pacstrap will fail without network"

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

cat <<EOF

  microcode      : ${UCODE}
  GPU packages   : ${GPU_PKGS:-(none - generic)}
  GPU cmdline    : ${GPU_CMDLINE:-(none)}
  GPU modules    : ${GPU_MODULES:-(none)}
  RAM            : $(( MEMKB / 1024 )) MiB
  zram swap      : ${ZRAM_SIZE} MiB
  hibernate swap : ${SWAPFILE_SIZE}$( [[ "$SWAPFILE_SIZE" != "(none)" ]] && echo " MiB (btrfs swapfile)" )
  hostname       : ${HOSTNAME:-(will prompt)}
EOF

########################################################################
rule "Target disk"
########################################################################
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
DISK_MODEL="$(lsblk -dno MODEL "$DISK_KNAME" | sed 's/[[:space:]]*$//')"

# resolve to a stable by-id path (prefer nvme-/ata-, never wwn-/eui-/-part)
DISK=""
for link in /dev/disk/by-id/*; do
  [[ -e "$link" ]] || continue
  [[ "$link" == *-part* ]] && continue
  case "${link##*/}" in wwn-*|*eui.*) continue ;; esac
  if [[ "$(realpath "$link")" == "$DISK_KNAME" ]]; then DISK="$link"; break; fi
done
[[ -n "$DISK" ]] || DISK="$DISK_KNAME"

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

echo
echo "Target: $DISK"
echo "  model : ${DISK_MODEL:-(unknown)}"
echo "  size  : $(lsblk -dno SIZE "$DISK_KNAME")"
echo "  transport: ${DISK_TRAN}"
echo "  current layout:"
sgdisk -p "$DISK_KNAME" 2>/dev/null | sed 's/^/    /' || echo "    (no GPT / unreadable)"
echo
read -rp "Type the disk MODEL exactly to confirm [${DISK_MODEL}]: " typed
[[ "$typed" == "$DISK_MODEL" ]] || die "model string did not match - aborting"
read -rp "Last chance. Type YES to DESTROY $DISK_KNAME: " last
[[ "$last" == "YES" ]] || die "aborted"

########################################################################
rule "Passphrases"
########################################################################
read -rsp "New user (${USERNAME}) password: " USER_PASSWORD; echo
read -rsp "Confirm user password: "                p2;      echo
[[ "$USER_PASSWORD" == "$p2" && -n "$USER_PASSWORD" ]] || die "user passwords differ/empty"
read -rsp "New root password: " ROOT_PASSWORD; echo
read -rsp "Confirm root password: " p2;        echo
[[ "$ROOT_PASSWORD" == "$p2" && -n "$ROOT_PASSWORD" ]] || die "root passwords differ/empty"

########################################################################
rule "Partitioning + encryption + filesystems"
########################################################################
partition_disk "$DISK"
luks_format_open "$LUKS_PART"          # prompts for the LUKS passphrase x2
make_filesystems
make_swapfile

########################################################################
rule "pacstrap"
########################################################################
pkgs=(
  base "${KERNEL}" "${KERNEL}-headers" linux-firmware
  btrfs-progs cryptsetup mkinitcpio
  "${UCODE}"
  networkmanager sudo git openssh vim
  curl tar
  zram-generator
  limine limine-mkinitcpio-hook efibootmgr
)
if [[ -n "$GPU_PKGS" ]]; then
  read -ra gpu_arr <<<"$GPU_PKGS"
  pkgs+=("${gpu_arr[@]}")
fi
echo "Packages: ${pkgs[*]}"
pacstrap -K /mnt "${pkgs[@]}"

########################################################################
rule "fstab"
########################################################################
genfstab -U /mnt >> /mnt/etc/fstab
for e in "${EXTRA_FSTAB_ENTRIES[@]}"; do
  printf '%s\n' "$e" >> /mnt/etc/fstab
done
if [[ "${SWAP}" == "hibernate" ]]; then
  grep -q '^/swap/swapfile ' /mnt/etc/fstab \
    || printf '/swap/swapfile none swap defaults 0 0\n' >> /mnt/etc/fstab
fi

########################################################################
rule "System configuration (chroot)"
########################################################################
install -Dm755 "$HERE/lib/chroot-setup.sh" /mnt/root/chroot-setup.sh
install -Dm644 "$HERE/lib/bootloader.sh"   /mnt/root/bootloader.sh

arch-chroot /mnt env \
  TIMEZONE="$TIMEZONE" LOCALE="$LOCALE" KEYMAP="$KEYMAP" \
  USERNAME="$USERNAME" HOSTNAME="$HOSTNAME" KERNEL="$KERNEL" SWAP="$SWAP" \
  LUKS_NAME="$LUKS_NAME" LUKS_PARTUUID="$LUKS_PARTUUID" \
  EXTRA_CMDLINE="$EXTRA_CMDLINE" GPU_CMDLINE="$GPU_CMDLINE" GPU_MODULES="$GPU_MODULES" \
  ZRAM_SIZE="$ZRAM_SIZE" RESUME_OFFSET="${RESUME_OFFSET:-}" \
  USER_PASSWORD="$USER_PASSWORD" ROOT_PASSWORD="$ROOT_PASSWORD" \
  bash /root/chroot-setup.sh

rm -f /mnt/root/chroot-setup.sh /mnt/root/bootloader.sh

########################################################################
rule "Done"
########################################################################
umount -R /mnt
cryptsetup close "$LUKS_NAME"
cat <<EOF

Install complete.

Next: reboot, unlock the disk, log in as ${USERNAME}, then from the staged repo:
    ~/proj/slievr-cachy/cachyos/bootstrap.sh

EOF
read -rp "Reboot now? [y/N] " r
[[ "$r" == [yY] ]] && reboot
