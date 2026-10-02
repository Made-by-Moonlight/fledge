# shellcheck shell=bash
# Hardware detection. Pure functions where possible: they take their input
# source as an argument so test-detect.sh can feed fixtures. The live-only
# helpers (list_disks) are exercised in the VM and with stubs.

# detect_ucode <cpuinfo_path>  ->  amd-ucode | intel-ucode
detect_ucode() {
  local f="${1:-/proc/cpuinfo}"
  if grep -qm1 'AuthenticAMD' "$f"; then
    echo "amd-ucode"
  elif grep -qm1 'GenuineIntel' "$f"; then
    echo "intel-ucode"
  else
    echo "amd-ucode"  # sane default; warn upstream
    return 1
  fi
}

# _gpu_vendors <lspci_text>  ->  newline list of nvidia|amd|intel seen on a
# display-class device (VGA / 3D / Display controller)
_gpu_vendors() {
  local line
  while IFS= read -r line; do
    case "$line" in
      *"VGA compatible controller"*|*"3D controller"*|*"Display controller"*) ;;
      *) continue ;;
    esac
    case "$line" in
      *NVIDIA*|*"nVidia"*)                          echo nvidia ;;
    esac
    case "$line" in
      *"Advanced Micro Devices"*|*"[AMD/ATI]"*|*" ATI "*) echo amd ;;
    esac
    case "$line" in
      *"Intel Corporation"*)                        echo intel ;;
    esac
  done <<<"$1"
}

# detect_gpu_pkgs <lspci_text>  ->  space-separated pacman package list
detect_gpu_pkgs() {
  local v pkgs=() seen
  seen="$(_gpu_vendors "$1" | sort -u)"
  for v in $seen; do
    case "$v" in
      nvidia) pkgs+=(linux-cachyos-nvidia nvidia-utils lib32-nvidia-utils) ;;
      amd)    pkgs+=(vulkan-radeon lib32-vulkan-radeon) ;;
      intel)  pkgs+=(vulkan-intel) ;;
    esac
  done
  echo "${pkgs[*]-}"
}

# detect_gpu_cmdline <lspci_text>  ->  nvidia_drm.modeset=1 | (empty)
detect_gpu_cmdline() {
  if _gpu_vendors "$1" | grep -qx nvidia; then
    echo "nvidia_drm.modeset=1"
  fi
}

# detect_gpu_modules <lspci_text>  ->  mkinitcpio MODULES for the GPU | (empty)
detect_gpu_modules() {
  if _gpu_vendors "$1" | grep -qx nvidia; then
    echo "nvidia nvidia_modeset nvidia_uvm nvidia_drm"
  fi
}

# part_suffix <disk_basename>  ->  p (nvme/mmcblk/loop) | (empty)
part_suffix() {
  case "$1" in
    nvme*|mmcblk*|loop*) echo p ;;
    *) echo "" ;;
  esac
}

# zram_size <memtotal_kB>  ->  MiB, min(RAM/2, 8192)
zram_size() {
  local mib=$(( $1 / 1024 / 2 ))
  (( mib > 8192 )) && mib=8192
  echo "$mib"
}

# hibernate_swap_size <memtotal_kB>  ->  MiB, ceil(RAM to GiB)*1024 + 2048
hibernate_swap_size() {
  local gib=$(( ($1 + 1048576 - 1) / 1048576 ))
  echo "$(( gib * 1024 + 2048 ))"
}

# filter_fstab_entries <present_uuids> <entry>...  ->  the entries whose
# UUID= source is in present_uuids (newline-separated, as printed by
# `blkid -s UUID -o value`), one per line, in order. Entries that don't start
# with UUID= pass through. Lets one profile.sh list every machine's data disks.
filter_fstab_entries() {
  local present="$1" entry; shift
  for entry in "$@"; do
    if [[ "$entry" =~ ^UUID=([^[:space:]]+) ]]; then
      grep -qxF -- "${BASH_REMATCH[1]}" <<<"$present" || continue
    fi
    printf '%s\n' "$entry"
  done
}

# list_disks  ->  lines: NAME<TAB>SIZE<TAB>MODEL<TAB>TRAN
# Whole disks only, excluding the live-media disk (when it can be identified)
# and, unless the caller allows them, USB devices. Tested with stubbed
# findmnt/lsblk in test-detect.sh.
list_disks() {
  local livesrc lminusb
  # disk backing the live media, if any
  livesrc="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null \
    || findmnt -no SOURCE /run/archiso/cowspace 2>/dev/null || true)"
  # Under Ventoy the source is a device-mapper node lsblk can't always resolve;
  # a failed lookup must not abort the listing in callers running set -e.
  lminusb=""
  if [[ -n "$livesrc" ]]; then
    lminusb="$({ lsblk -no PKNAME "$livesrc" 2>/dev/null || true; } | head -n1)"
  fi
  lsblk -dpno NAME,SIZE,MODEL,TRAN,TYPE | awk -v live="/dev/$lminusb" '
    $NF == "disk" {
      name=$1; $NF=""; sub(/[ \t]+$/, "")
      if (name == live) next
      # zram / ramdisks report TYPE=disk but are not install targets
      if (name ~ /\/(zram|ram)[0-9]+$/) next
      # rebuild: NAME SIZE MODEL... TRAN
      printf "%s\n", $0
    }'
}

# disk_by_id <kname> [byid_dir]  ->  stable by-id path for a whole disk, or
# kname when there is none (e.g. virtio). Skips -partN, wwn-* and eui links,
# which are either partitions or opaque.
disk_by_id() {
  local kname="$1" dir="${2:-/dev/disk/by-id}" link want
  want="$(realpath "$kname")"
  for link in "$dir"/*; do
    [[ -e "$link" ]] || continue
    [[ "$link" == *-part* ]] && continue
    case "${link##*/}" in wwn-*|*eui.*) continue ;; esac
    if [[ "$(realpath "$link")" == "$want" ]]; then
      echo "$link"; return 0
    fi
  done
  echo "$kname"
}
