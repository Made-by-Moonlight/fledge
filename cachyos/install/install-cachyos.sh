#!/usr/bin/env bash
# Hardware-adaptive CachyOS installer. Run as root in the stock CachyOS live ISO.
#   sudo /path/to/cachyos/install/install-cachyos.sh [--allow-usb] [--answers FILE]
#
# See ./README.md and ../../docs/superpowers/specs/2026-08-28-bare-metal-install-design.md
set -euo pipefail

HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"     # the slievr-cachy checkout being run from
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

die()  { printf '\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\e[33mWARN:\e[0m  %s\n' "$*" >&2; }
rule() { printf '\n\e[1m== %s ==\e[0m\n' "$*"; }

ALLOW_USB=0
ANSWERS=""
while (( $# )); do
  case "$1" in
    --allow-usb) ALLOW_USB=1 ;;
    --answers)   ANSWERS="${2:?--answers needs a file}"; shift ;;
    *)           die "unknown argument: $1" ;;
  esac
  shift
done
if [[ -n "$ANSWERS" ]]; then
  load_answers "$ANSWERS" || die "unusable answers file: $ANSWERS"
  for k in DISK HOSTNAME USER_PASSWORD LUKS_PASSPHRASE; do
    [[ -n "${!k:-}" ]] || die "answers file is missing $k"
  done
  if [[ -n "${TIMEZONE:-}" ]]; then
    [[ "$TIMEZONE" != *..* && -f "/usr/share/zoneinfo/$TIMEZONE" ]] \
      || die "answers TIMEZONE is not a valid zone: $TIMEZONE"
  fi
  ROOT_PASSWORD="${ROOT_PASSWORD:-}"     # empty -> root locked (chroot-setup.sh)
  # USERNAME is optional (profile.sh has the default) but always re-checked:
  # it reaches useradd, paths and a sed expression.
  valid_username "$USERNAME" || die "answers USERNAME is not a valid login name: $USERNAME"
fi

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

mapfile -t KEEP_FSTAB < <(filter_fstab_entries "$(blkid -s UUID -o value)" "${EXTRA_FSTAB_ENTRIES[@]}")

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
  data disks     : ${#KEEP_FSTAB[@]} of ${#EXTRA_FSTAB_ENTRIES[@]} fstab entries present on this machine
EOF

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
partition_disk "$DISK"
luks_format_open "$LUKS_PART"          # LUKS_PASSPHRASE from answers, else prompts x2
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
  plymouth
  zram-generator
  limine limine-mkinitcpio-hook efibootmgr
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

########################################################################
rule "fstab"
########################################################################
genfstab -U /mnt >> /mnt/etc/fstab
for e in "${KEEP_FSTAB[@]}"; do
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

# Vendored Plymouth theme (graphical boot splash + LUKS prompt). Not stow-
# managed - Plymouth reads themes from a system path. chroot-setup.sh selects it.
rm -rf /mnt/usr/share/plymouth/themes/slievr-cachy
install -d /mnt/usr/share/plymouth/themes
cp -r "$HERE/../plymouth-theme/slievr-cachy" /mnt/usr/share/plymouth/themes/slievr-cachy

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
rule "Staging repo + first-boot bootstrap"
########################################################################
# Copy this checkout into the installed system so bootstrap.sh (and the docs)
# are present offline after reboot with no re-staging.
target_home="/mnt/home/${USERNAME}"
mkdir -p "${target_home}/proj"
rm -rf "${target_home}/proj/slievr-cachy"
cp -r "$REPO_ROOT" "${target_home}/proj/slievr-cachy"

# First-boot service: runs bootstrap.sh as the user, unattended, on TTY1, then
# starts SDDM. install-cachyos.sh does NOT enable sddm - firstboot does, so a
# failed bootstrap leaves a TTY + log instead of a broken greeter.
install -Dm755 "$HERE/firstboot/slievr-firstboot.sh"      /mnt/usr/local/sbin/slievr-firstboot.sh
sed -i "s/@USERNAME@/${USERNAME}/g"                        /mnt/usr/local/sbin/slievr-firstboot.sh
install -Dm644 "$HERE/firstboot/slievr-firstboot.service" /mnt/etc/systemd/system/slievr-firstboot.service

arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/proj"
arch-chroot /mnt systemctl enable slievr-firstboot.service

# Wi-Fi the live ISO joined (iwd) -> NetworkManager keyfiles, so first boot is
# online on a laptop. Wired machines have nothing in /var/lib/iwd.
install_wifi_profiles /var/lib/iwd /mnt/etc/NetworkManager/system-connections

########################################################################
rule "Done"
########################################################################
umount -R /mnt
cryptsetup close "$LUKS_NAME"
cat <<EOF

Install complete.

On reboot: unlock the disk, then slievr-firstboot runs bootstrap.sh
automatically on TTY1 (log: /var/log/slievr-firstboot.log) and starts SDDM
when it finishes. No manual step. If bootstrap fails you land at a TTY with
the repo at /home/${USERNAME}/proj/slievr-cachy and instructions on screen.

EOF
if [[ -z "$ANSWERS" ]]; then
  read -rp "Reboot now? [y/N] " r
  [[ "$r" == [yY] ]] && reboot
fi
